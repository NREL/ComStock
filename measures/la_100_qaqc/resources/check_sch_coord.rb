# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

module OsLib_QAQC
  # Determine the hour when the schedule first exceeds the starting value and when
  # it goes back down to the ending value at the end of the day.
  # This method only works for ScheduleRuleset schedules.
  def get_start_and_end_times(schedule_ruleset)
    # Ensure that this is a ScheduleRuleset
    schedule_ruleset = schedule_ruleset.to_ScheduleRuleset
    return [nil, nil] if schedule_ruleset.empty?
    schedule_ruleset = schedule_ruleset.get

    # Define the start and end date
    if schedule_ruleset.model.yearDescription.is_initialized
      year_description = schedule_ruleset.model.yearDescription.get
      year = year_description.assumedYear
      year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, year)
      year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, year)
    else
      year_start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('January'), 1, 2009)
      year_end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, 2009)
    end

    # Get the ordered list of all the day schedules that are used by this schedule ruleset
    day_schs = schedule_ruleset.getDaySchedules(year_start_date, year_end_date)

    # Get a 365-value array of which schedule is used on each day of the year,
    day_schs_used_each_day = schedule_ruleset.getActiveRuleIndices(year_start_date, year_end_date)

    # Create a map that shows how many days each schedule is used
    day_sch_freq = day_schs_used_each_day.group_by { |n| n }
    day_sch_freq = day_sch_freq.sort_by { |freq| freq[1].size }
    common_day_freq = day_sch_freq.last

    # Build a hash that maps schedule day index to schedule day
    schedule_index_to_day = {}
    day_schs.each_with_index do |day_sch, i|
      schedule_index_to_day[day_schs_used_each_day[i]] = day_sch
    end

    # Get the most common day schedule
    sch_index = common_day_freq[0]
    number_of_days_sch_used = common_day_freq[1].size

    # Get the day schedule at this index
    day_sch = if sch_index == -1 # If index = -1, this day uses the default day schedule (not a rule)
                schedule_ruleset.defaultDaySchedule
              else
                schedule_index_to_day[sch_index]
              end

    # Determine the full load hours for just one day
    values = []
    times = []
    day_sch.times.each_with_index do |time, i|
      times << day_sch.times[i]
      values << day_sch.values[i]
    end

    # Get the minimum value
    start_val = values.first
    end_val = values.last

    # Get the start time (first time value goes above minimum)
    start_time = nil
    values.each_with_index do |val, i|
      break if i == values.size - 1 # Stop if we reach end of array
      if val == start_val && values[i + 1] > start_val
        start_time = times[i + 1]
        break
      end
    end

    # Get the end time (first time value goes back down to minimum)
    end_time = nil
    values.each_with_index do |val, i|
      if i < values.size - 1
        if val > end_val && values[i + 1] == end_val
          end_time = times[i]
          break
        end
      else
        if val > end_val && values[0] == start_val # Check first hour of day for schedules that end at midnight
          end_time = OpenStudio::Time.new(0, 24, 0, 0)
          break
        end
      end
    end

    return [start_time, end_time]
  end

# Check that the lighting, equipment, and HVAC setpoint schedules coordinate with the occupancy schedules.
# This is defined as having start and end times within the specified number of hours away from the occupancy schedule.

# @param target_standard [Standard] target standard, Class Standard from openstudio-standards
# @param max_hrs [Double] threshold for throwing an error for schedule coordination
  def check_sch_coord(category, target_standard, max_hrs: 2.0, name_only: false)
    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Schedule Coordination')
    check_elems << OpenStudio::Attribute.new('category', category)
    check_elems << OpenStudio::Attribute.new('description', 'Check that lighting, equipment, and HVAC schedules coordinate with occupancy.')

    # stop here if only name is requested this is used to populate display name for arguments
    if name_only == true
      results = []
      check_elems.each do |elem|
        results << elem.valueAsString
      end
      return results
    end

    std = Standard.build(target_standard)

    begin
      # Convert max hr limit to OpenStudio Time
    max_hrs = OpenStudio::Time.new(0, max_hrs.to_i, 0, 0)

      # Check schedules in each space
      @model.getSpaces.sort.each do |space|
        # Occupancy, Lighting, and Equipment Schedules
        coord_schs = []
        occ_schs = []
        # Get the space type (optional)
        space_type = space.spaceType

        # Occupancy
        occs = []
        occs += space.people # From space directly
        occs += space_type.get.people if space_type.is_initialized # Inherited from space type
        occs.each do |occ|
          occ_schs << occ.numberofPeopleSchedule.get if occ.numberofPeopleSchedule.is_initialized
        end

        # Lights
        lts = []
        lts += space.lights # From space directly
        lts += space_type.get.lights if space_type.is_initialized # Inherited from space type
        lts.each do |lt|
          coord_schs << lt.schedule.get if lt.schedule.is_initialized
        end

        # Equip
        plugs = []
        plugs += space.electricEquipment # From space directly
        plugs += space_type.get.electricEquipment if space_type.is_initialized # Inherited from space type
        plugs.each do |plug|
          coord_schs << plug.schedule.get if plug.schedule.is_initialized
        end

        # HVAC Schedule (airloop-served zones only)
        if space.thermalZone.is_initialized
          zone = space.thermalZone.get
          if zone.airLoopHVAC.is_initialized
            coord_schs << zone.airLoopHVAC.get.availabilitySchedule
          end
        end

        # Cannot check spaces with no occupancy schedule to compare against
        next if occ_schs.empty?

        # Get start and end occupancy times from the first occupancy schedule
        occ_start_time, occ_end_time = get_start_and_end_times(occ_schs[0])

        # Cannot check a space where the occupancy start time or end time cannot be determined
        next if occ_start_time.nil? || occ_end_time.nil?

        # Check all schedules against occupancy

        # Lights should have a start and end within X hrs of the occupancy start and end
        coord_schs.each do |coord_sch|
          # Get start and end time of load/HVAC schedule
          start_time, end_time = get_start_and_end_times(coord_sch)
          if start_time.nil?
            check_elems << OpenStudio::Attribute.new('flag', "Could not determine start time of a schedule called #{coord_sch.name}, cannot determine if schedule coordinates with occupancy schedule.")
            next
          elsif end_time.nil?
            check_elems << OpenStudio::Attribute.new('flag', "Could not determine end time of a schedule called #{coord_sch.name}, cannot determine if schedule coordinates with occupancy schedule.")
            next
          end

          # Check start time
          if (occ_start_time - start_time) > max_hrs || (start_time - occ_start_time) > max_hrs
            check_elems << OpenStudio::Attribute.new('flag', "The start time of #{coord_sch.name} is #{start_time}, which is more than #{max_hrs} away from the occupancy schedule start time of #{occ_start_time} for #{occ_schs[0].name} in #{space.name}.  Schedules do not coordinate.")
          end

          # Check end time
          if (occ_end_time - end_time) > max_hrs || (end_time - occ_end_time) > max_hrs
            check_elems << OpenStudio::Attribute.new('flag', "The end time of #{coord_sch.name} is #{end_time}, which is more than #{max_hrs} away from the occupancy schedule end time of #{occ_end_time} for #{occ_schs[0].name} in #{space.name}.  Schedules do not coordinate.")
          end
        end
      end
    rescue StandardError => e
      # brief description of ruby error
      check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

      # backtrace of ruby error for diagnostic use
      if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
    end

    # add check_elms to new attribute
    check_elem = OpenStudio::Attribute.new('check', check_elems)

    return check_elem
    # note: registerWarning and registerValue will be added for checks downstream using os_lib_reporting_qaqc.rb
  end
end
