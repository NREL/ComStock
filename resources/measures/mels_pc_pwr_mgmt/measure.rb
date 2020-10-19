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

# start the measure
class MelsPcPowerManagement < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'PC Power Management'
  end

  # human readable description
  def description
    return 'Screen savers were necessary to prevent image burn-in in older CRT monitors.  However, screen savers are not necessary on modern LCD monitors. Disabling screen savers on these monitors drastically reduces their energy consumption when not in use.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Find all of the office electric equipment schedules in the building, and reduce their fractional values to a user-specified level (default 25%) between user specified times (default 6pm-9am). The default value for this measure is not well supported as plug loads are not broken into discrete categories in the prototype buildings.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Argument to run measure
    run_measure = OpenStudio::Measure::OSArgument.makeBoolArgument('run_measure', true)
    run_measure.setDisplayName('Run Measure')
    run_measure.setDescription('Argument to run measure.')
    run_measure.setDefaultValue(true)
    args << run_measure

    # Choice argument to select which devices to reduce energy consumption
    choice = OpenStudio::StringVector.new
    choice << 'ScreenSaver'
    choice << 'Desktop'
    choice << 'Display'
    choice = OpenStudio::Measure::OSArgument.makeChoiceArgument('choice', choice, true)
    choice.setDisplayName('PC Component')
    choice.setDefaultValue('ScreenSaver')
    args << choice

    return args
  end

  # method to reduce the values in a day schedule to a give number before and after a given time
  def mels_reduce_schedule(day_sch, before_hour, before_min, before_value, after_hour, after_min, after_value)
    before_time = OpenStudio::Time.new(0, before_hour, before_min, 0)
    after_time = OpenStudio::Time.new(0, after_hour, after_min, 0)
    day_end_time = OpenStudio::Time.new(0, 24, 0, 0)

    # Special situation for when start time and end time are equal,
    # meaning that a 24hr reduction is desired
    if before_time == after_time
      day_sch.clearValues
      day_sch.addValue(day_end_time, after_value)
      return
    end

    original_value_at_after_time = day_sch.getValue(after_time)
    day_sch.addValue(before_time, before_value)
    day_sch.addValue(after_time, original_value_at_after_time)
    times = day_sch.times
    values = day_sch.values
    day_sch.clearValues

    new_times = []
    new_values = []
    for i in 0..(values.length - 1)
      if times[i] >= before_time && times[i] <= after_time
        new_times << times[i]
        new_values << values[i]
      end
    end

    # add the value for the time period from after time to end of the day
    new_times << day_end_time
    new_values << after_value

    for i in 0..(new_values.length - 1)
      day_sch.addValue(new_times[i], new_values[i])
    end
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    unless runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Return not applicable if not selected to run
    run_measure = runner.getBoolArgumentValue('run_measure', user_arguments)
    unless run_measure
      runner.registerAsNotApplicable("Run measure is #{run_measure}.")
      return false
    end

    # Assign the user inputs to variables
    choice = runner.getStringArgumentValue('choice', user_arguments)
    
    if choice == 'ScreenSaver' || choice == 'Display'
      fraction_value = 0.25
    elsif choice == 'Desktop'
      fraction_value = 0.10
    end
    apply_weekday = true
    start_weekday = 18.0
    end_weekday = 8.0
    apply_saturday = true
    start_saturday = 16.0
    end_saturday = 9.0
    apply_sunday = true
    start_sunday = 18.0
    end_sunday = 18.0

    # http://www.nrel.gov/docs/fy13osti/57730.pdf

    # check the fraction for reasonableness
    if !(fraction_value >= 0 && fraction_value <= 1)
      runner.registerError('Fractional value needs to be between or equal to 0 and 1.')
      return false
    end

    # check start_weekday for reasonableness and round to 15 minutes
    if !(start_weekday >= 0 && start_weekday <= 24)
      runner.registerError('Time in hours needs to be between or equal to 0 and 24')
      return false
    else
      rounded_start_weekday = (start_weekday * 4).round / 4.0
      if start_weekday != rounded_start_weekday
        runner.registerInfo("Weekday start time rounded to nearest 15 minutes: #{rounded_start_weekday}")
      end
      wk_after_hour = rounded_start_weekday.truncate
      wk_after_min = (rounded_start_weekday - wk_after_hour) * 60
      wk_after_min = wk_after_min.to_i
    end

    # check end_weekday for reasonableness and round to 15 minutes
    if !(end_weekday >= 0 && end_weekday <= 24)
      runner.registerError('Time in hours needs to be between or equal to 0 and 24.')
      return false
    elsif end_weekday > start_weekday
      runner.registerError('Please enter an end time earlier in the day than start time.')
      return false
    else
      rounded_end_weekday = (end_weekday * 4).round / 4.0
      if end_weekday != rounded_end_weekday
        runner.registerInfo("Weekday end time rounded to nearest 15 minutes: #{rounded_end_weekday}")
      end
      wk_before_hour = rounded_end_weekday.truncate
      wk_before_min = (rounded_end_weekday - wk_before_hour) * 60
      wk_before_min = wk_before_min.to_i
    end

    # check start_saturday for reasonableness and round to 15 minutes
    if !(start_saturday >= 0 && start_saturday <= 24)
      runner.registerError('Time in hours needs to be between or equal to 0 and 24.')
      return false
    else
      rounded_start_saturday = (start_saturday * 4).round / 4.0
      if start_saturday != rounded_start_saturday
        runner.registerInfo("Saturday start time rounded to nearest 15 minutes: #{rounded_start_saturday}")
      end
      sat_after_hour = rounded_start_saturday.truncate
      sat_after_min = (rounded_start_saturday - sat_after_hour) * 60
      sat_after_min = sat_after_min.to_i
    end

    # check end_saturday for reasonableness and round to 15 minutes
    if !(end_saturday >= 0 && end_saturday <= 24)
      runner.registerError('Time in hours needs to be between or equal to 0 and 24.')
      return false
    elsif end_saturday > start_saturday
      runner.registerError('Please enter an end time earlier in the day than start time.')
      return false
    else
      rounded_end_saturday = (end_saturday * 4).round / 4.0
      if end_saturday != rounded_end_saturday
        runner.registerInfo("Saturday end time rounded to nearest 15 minutes: #{rounded_end_saturday}")
      end
      sat_before_hour = rounded_end_saturday.truncate
      sat_before_min = (rounded_end_saturday - sat_before_hour) * 60
      sat_before_min = sat_before_min.to_i
    end

    # check start_sunday for reasonableness and round to 15 minutes
    if !(start_sunday >= 0 && start_sunday <= 24)
      runner.registerError('Time in hours needs to be between or equal to 0 and 24.')
      return false
    else
      rounded_start_sunday = (start_sunday * 4).round / 4.0
      if start_sunday != rounded_start_sunday
        runner.registerInfo("Sunday start time rounded to nearest 15 minutes: #{rounded_start_sunday}")
      end
      sun_after_hour = rounded_start_sunday.truncate
      sun_after_min = (rounded_start_sunday - sun_after_hour) * 60
      sun_after_min = sun_after_min.to_i
    end

    # check end_sunday for reasonableness and round to 15 minutes
    if !(end_sunday >= 0 && end_sunday <= 24)
      runner.registerError('Time in hours needs to be between or equal to 0 and 24.')
      return false
    elsif end_sunday > start_sunday
      runner.registerError('Please enter an end time earlier in the day than start time.')
      return false
    else
      rounded_end_sunday = (end_sunday * 4).round / 4.0
      if end_sunday != rounded_end_sunday
        runner.registerInfo("Sunday end time rounded to nearest 15 minutes: #{rounded_end_sunday}")
      end
      sun_before_hour = rounded_end_sunday.truncate
      sun_before_min = (rounded_end_sunday - sun_before_hour) * 60
      sun_before_min = sun_before_min.to_i
    end

    # Uniform reduction for all times
    wk_before_value = fraction_value
    wk_after_value = fraction_value
    sat_before_value = fraction_value
    sat_after_value = fraction_value
    sun_before_value = fraction_value
    sun_after_value = fraction_value

    # populate rules hash
    rules = []
    rules << ['Asm', 'OfficeGeneral']
    rules << ['ECC', 'CompRoomClassRm']
    rules << ['ECC', 'OfficeGeneral']
    rules << ['ESe', 'CompRoomClassRm']
    rules << ['EUn', 'CompRoomClassRm']
    rules << ['EUn', 'OfficeGeneral']
    rules << ['Gro', 'OfficeGeneral']
    rules << ['Hsp', 'OfficeGeneral']
    rules << ['Htl', 'OfficeGeneral']
    rules << ['MBT', 'OfficeOpen']
    rules << ['Mtl', 'OfficeGeneral']
    rules << ['Nrs', 'OfficeGeneral']
    rules << ['OfL', 'OfficeSmall']
    rules << ['OfL', 'OfficeOpen']
    rules << ['OfS', 'OfficeSmall']
    rules << ['RtL', 'OfficeGeneral']
    rules << ['WRf', 'OfficeGeneral']

    # Add DOE buildings
    rules << ['Courthouse', 'Office']
    rules << ['SecondarySchool', 'Office']
    rules << ['SecondarySchool', 'Library']
    rules << ['SuperMarket', 'Office']
    rules << ['Hospital', 'Office']
    rules << ['Outpatient', 'Office']
    rules << ['Outpatient', 'Reception']
    rules << ['Outpatient', 'Conference']
    rules << ['Outpatient', 'IT_Room']
    rules << ['SmallHotel', 'Office']
    rules << ['SmallOffice', 'SmallOffice - ClosedOffice']
    rules << ['SmallOffice', 'SmallOffice - OpenOffice']
    rules << ['SmallOffice', 'SmallOffice - Conference']
    rules << ['MediumOffice', 'MediumOffice - ClosedOffice']
    rules << ['MediumOffice', 'MediumOffice - OpenOffice']
    rules << ['MediumOffice', 'MediumOffice - Conference']
    rules << ['LargeOffice', 'ClosedOffice']
    rules << ['LargeOffice', 'OpenOffice']
    rules << ['LargeOffice', 'Conference']
    rules << ['RetailStandalone', 'Point_of_Sale']
    rules << ['Retail', 'Point_of_Sale']
    rules << ['Warehouse', 'Office']
    rules << ['PrimarySchool', 'Office']
    rules << ['Office', 'OpenOffice']
    rules << ['Office', 'ClosedOffice']
    rules << ['Office', 'SmallOffice - ClosedOffice']
    rules << ['Office', 'SmallOffice - OpenOffice']
    rules << ['Office', 'SmallOffice - Conference']
    rules << ['Office', 'MediumOffice - ClosedOffice']
    rules << ['Office', 'MediumOffice - OpenOffice']
    rules << ['Office', 'MediumOffice - Conference']
    rules << ['Office', 'WholeBuilding - Md Office']
    rules << ['Office', 'WholeBuilding - Sm Office']
    rules << ['Office', 'WholeBuilding - Lg Office']

    original_equip_schs = []
    selected_elec_equip_instances = []
    # loop through space types
    model.getSpaceTypes.each do |space_type|
      # skip if not used in model
      next if space_type.spaces.empty?

      # confirm space type maps to a recognized standards type
      next unless space_type.standardsBuildingType.is_initialized
      next unless space_type.standardsSpaceType.is_initialized
      standards_building_type = space_type.standardsBuildingType.get
      standards_space_type = space_type.standardsSpaceType.get
      space_type_hash = {}
      space_type_hash[space_type] = [standards_building_type, standards_space_type]
      unless rules.include? space_type_hash[space_type]
        runner.registerInfo("#{space_type.name} does not have a standards office space type. Plug load levels for this space type will not be altered.")
        next
      end

      # Get schedules from all electric equipment in office-related space types
      space_type.electricEquipment.each do |equip|
        selected_elec_equip_instances << equip
        if equip.schedule.is_initialized
          equip_sch = equip.schedule.get
          original_equip_schs << equip_sch
        end
      end
    end

    # return not applicable if the model has no office space types
    if original_equip_schs.empty?
      runner.registerAsNotApplicable('There are no office space types in the model, so we assume 0 PCs. No electric equipment schedules were altered.')
      return false
    end

    # loop through the unique list of equip schedules, cloning and reducing schedule fraction before and after the specified times
    original_equip_new_schs = {}
    original_equip_schs.uniq.each do |equip_sch|
      # guard clause for ScheduleRulesets
      unless equip_sch.to_ScheduleRuleset.is_initialized
        runner.registerWarning("Schedule '#{equip_sch.name}' isn't a ScheduleRuleset object and won't be altered by this measure.")
        next
      end

      # guard clause for already altered schedules
      if original_equip_new_schs.key?(equip_sch)
        next
      end

      new_equip_sch = equip_sch.clone(model).to_ScheduleRuleset.get
      new_equip_sch.setName("#{equip_sch.name} with PC Power Management")
      original_equip_new_schs[equip_sch] = new_equip_sch
      new_equip_sch = new_equip_sch.to_ScheduleRuleset.get

      # reduce default day schedules
      if new_equip_sch.scheduleRules.empty?
        runner.registerWarning("Schedule '#{new_equip_sch.name}' applies to all days.  It has been treated as a Weekday schedule.")
      end
      mels_reduce_schedule(new_equip_sch.defaultDaySchedule, wk_before_hour, wk_before_min, wk_before_value, wk_after_hour, wk_after_min, wk_after_value)

      # reduce weekdays
      new_equip_sch.scheduleRules.each do |sch_rule|
        if apply_weekday
          if sch_rule.applyMonday || sch_rule.applyTuesday || sch_rule.applyWednesday || sch_rule.applyThursday || sch_rule.applyFriday
            mels_reduce_schedule(sch_rule.daySchedule, wk_before_hour, wk_before_min, wk_before_value, wk_after_hour, wk_after_min, wk_after_value)
          end
        end
      end

      # reduce saturdays
      new_equip_sch.scheduleRules.each do |sch_rule|
        if apply_saturday && sch_rule.applySaturday
          if sch_rule.applyMonday || sch_rule.applyTuesday || sch_rule.applyWednesday || sch_rule.applyThursday || sch_rule.applyFriday
            runner.registerWarning("Rule '#{sch_rule.name}' for schedule '#{new_equip_sch.name}' applies to both Saturdays and Weekdays.  It has been treated as a Weekday schedule.")
          else
            mels_reduce_schedule(sch_rule.daySchedule, sat_before_hour, sat_before_min, sat_before_value, sat_after_hour, sat_after_min, sat_after_value)
          end
        end
      end

      # reduce sundays
      new_equip_sch.scheduleRules.each do |sch_rule|
        if apply_sunday && sch_rule.applySunday
          if sch_rule.applyMonday || sch_rule.applyTuesday || sch_rule.applyWednesday || sch_rule.applyThursday || sch_rule.applyFriday
            runner.registerWarning("Rule '#{sch_rule.name}' for schedule '#{new_equip_sch.name}' applies to both Sundays and Weekdays.  It has been  treated as a Weekday schedule.")
          elsif sch_rule.applySaturday
            runner.registerWarning("Rule '#{sch_rule.name}' for schedule '#{new_equip_sch.name}' applies to both Saturdays and Sundays.  It has been treated as a Saturday schedule.")
          else
            mels_reduce_schedule(sch_rule.daySchedule, sun_before_hour, sun_before_min, sun_before_value, sun_after_hour, sun_after_min, sun_after_value)
          end
        end
      end
    end

    # loop through all electric equipment instances, replacing old equip schedules with the reduced schedules
    selected_elec_equip_instances.each do |equip|
      if equip.schedule.empty?
        runner.registerWarning("There was no schedule assigned for the electric equipment object named '#{equip.name}. No schedule was added.'")
      else
        old_equip_sch = equip.schedule.get
        equip.setSchedule(original_equip_new_schs[old_equip_sch])
        runner.registerInfo("Schedule for the electric equipment object named '#{equip.name}' was reduced to simulate the application of PC Power Management.")
      end
    end

    # Get the total number of occupants in office spaces
    total_space_occupancy = 0
    model.getSpaceTypes.each do |space_type|
      next unless space_type.standardsSpaceType.is_initialized
      case space_type.standardsSpaceType.get.to_s
      when 'OfficeOpen', 'OfficeGeneral', 'OfficeSmall', 'CompRoomClassRm', 'Conference', 'Point_of_Sale', 'SmallOffice - OpenOffice', 'SmallOffice - ClosedOffice', 'MediumOffice - OpenOffice', 'MediumOffice - ClosedOffice', 'OpenOffice', 'ClosedOffice', 'Point_of_Sale', 'Library', 'Reception', 'IT_Room', 'Office', 'SmallOffice - Conference', 'MediumOffice - Conference', 'WholeBuilding - Md Office', 'WholeBuilding - Sm Office', 'WholeBuilding - Lg Office'
        total_space_occupancy += space_type.getNumberOfPeople(space_type.floorArea)
      end
    end

    # Register as not applicable is there are no occupants in office space types in the model
    if total_space_occupancy == 0
      runner.registerAsNotApplicable('There are no occupants in office space types in the model.  This measure is not applicable.')
    end

    num_computers = total_space_occupancy.round
    # Reporting final condition of model
    runner.registerValue('mels_pc_pwr_mgmt_num_computers', num_computers)
    runner.registerFinalCondition("There are #{total_space_occupancy.round} occupants in office space types in the model, therefore we assume PC power management can be installed on #{num_computers} PCs. #{original_equip_schs.uniq.size} schedule(s) were edited to reflect the addition of PC Power Management to the plug loads in the building.")
    return true
  end
end

# register the measure to be used by the application
MelsPcPowerManagement.new.registerWithApplication
