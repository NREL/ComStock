# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# Reopen the OpenStudio class to add methods to apply standards to this object
class OpenStudio::Model::AirLoopHVAC
  # This method creates a schedule where the value is zero when
  # the overall occupancy for all zones on the airloop is below
  # the specified threshold, and one when the overall occupancy is
  # greater than or equal to the threshold.  This method is designed
  # to use the total number of people on the airloop, so if there is
  # a zone that is continuously occupied by a few people, but other
  # zones that are intermittently occupied by many people, the
  # first zone doesn't drive the entire system.
  #
  # @param occupied_percentage_threshold [Double] the minimum fraction (0 to 1) that counts as occupied
  # @return [ScheduleRuleset] a ScheduleRuleset where 0 = unoccupied, 1 = occupied
  # @todo Speed up this method.  Bottleneck is ScheduleRule.getDaySchedules
  def get_occupancy_schedule(occupied_percentage_threshold = 0.05)
    # Get all the occupancy schedules in every space in every zone
    # served by this airloop.  Include people added via the SpaceType
    # in addition to people hard-assigned to the Space itself.
    occ_schedules_num_occ = {}
    max_occ_on_airloop = 0
    thermalZones.each do |zone|
      # Get the people objects
      zone.spaces.each do |space|
        # From the space type
        if space.spaceType.is_initialized
          space.spaceType.get.people.each do |people|
            num_ppl_sch = people.numberofPeopleSchedule
            if num_ppl_sch.is_initialized
              num_ppl_sch = num_ppl_sch.get
              num_ppl_sch = num_ppl_sch.to_ScheduleRuleset
              next if num_ppl_sch.empty? # Skip non-ruleset schedules
              num_ppl_sch = num_ppl_sch.get
              num_ppl = people.getNumberOfPeople(space.floorArea)
              if occ_schedules_num_occ[num_ppl_sch].nil?
                occ_schedules_num_occ[num_ppl_sch] = num_ppl
                max_occ_on_airloop += num_ppl
              else
                occ_schedules_num_occ[num_ppl_sch] += num_ppl
                max_occ_on_airloop += num_ppl
              end
            end
          end
        end
        # From the space
        space.people.each do |people|
          num_ppl_sch = people.numberofPeopleSchedule
          if num_ppl_sch.is_initialized
            num_ppl_sch = num_ppl_sch.get
            num_ppl_sch = num_ppl_sch.to_ScheduleRuleset
            next if num_ppl_sch.empty? # Skip non-ruleset schedules
            num_ppl_sch = num_ppl_sch.get
            num_ppl = people.getNumberOfPeople(space.floorArea)
            if occ_schedules_num_occ[num_ppl_sch].nil?
              occ_schedules_num_occ[num_ppl_sch] = num_ppl
              max_occ_on_airloop += num_ppl
            else
              occ_schedules_num_occ[num_ppl_sch] += num_ppl
              max_occ_on_airloop += num_ppl
            end
          end
        end
      end
    end

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirLoopHVAC', "#{name} has #{occ_schedules_num_occ.size} unique occ schedules.")
    occ_schedules_num_occ.each do |occ_sch, num_occ|
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirLoopHVAC', "   #{occ_sch.name} - #{num_occ.round} people")
    end
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirLoopHVAC', "   Total #{max_occ_on_airloop.round} people on #{name}")

    # For each day of the year, determine
    # time_value_pairs = []
    year = model.getYearDescription
    yearly_data = []
    yearly_times = OpenStudio::DateTimeVector.new
    yearly_values = []
    for i in 1..365

      times_on_this_day = []
      os_date = year.makeDate(i)
      day_of_week = os_date.dayOfWeek.valueName

      # Get the unique time indices and corresponding day schedules
      occ_schedules_day_schs = {}
      day_sch_num_occ = {}
      occ_schedules_num_occ.each do |occ_sch, num_occ|
        # Get the day schedules for this day
        # (there should only be one)
        day_schs = occ_sch.getDaySchedules(os_date, os_date)
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirLoopHVAC', "Schedule #{occ_sch.name} has #{day_schs.size} day schs") unless day_schs.size == 1
        day_schs[0].times.each do |time|
          times_on_this_day << time.toString
        end
        day_sch_num_occ[day_schs[0]] = num_occ
      end

      # Determine the total fraction for the airloop at each time
      daily_times = []
      daily_os_times = []
      daily_values = []
      daily_occs = []
      times_on_this_day.uniq.sort.each do |time|
        os_time = OpenStudio::Time.new(time)
        os_date_time = OpenStudio::DateTime.new(os_date, os_time)
        # Total number of people at each time
        tot_occ_at_time = 0
        day_sch_num_occ.each do |day_sch, num_occ|
          occ_frac = day_sch.getValue(os_time)
          tot_occ_at_time += occ_frac * num_occ
        end

        # Total fraction for the airloop at each time
        air_loop_occ_frac = tot_occ_at_time / max_occ_on_airloop
        occ_status = 0 # unoccupied
        if air_loop_occ_frac >= occupied_percentage_threshold
          occ_status = 1
        end

        # Add this data to the daily arrays
        daily_times << time
        daily_os_times << os_time
        daily_values << occ_status
        daily_occs << air_loop_occ_frac.round(2)
      end

      # OpenStudio::logFree(OpenStudio::Debug, "openstudio.standards.AirLoopHVAC", "#{daily_times.join(', ')}                  #{daily_values.join(', ')}")

      # Simplify the daily times to eliminate intermediate
      # points with the same value as the following point.
      simple_daily_times = []
      simple_daily_os_times = []
      simple_daily_values = []
      simple_daily_occs = []
      daily_values.each_with_index do |value, i|
        next if value == daily_values[i + 1]
        simple_daily_times << daily_times[i]
        simple_daily_os_times << daily_os_times[i]
        simple_daily_values << daily_values[i]
        simple_daily_occs << daily_occs[i]
      end

      # OpenStudio::logFree(OpenStudio::Debug, "openstudio.standards.AirLoopHVAC", "#{simple_daily_times.join(', ')}                  {simple_daily_values.join(', ')}")

      # Store the daily values
      yearly_data << { 'date' => os_date, 'day_of_week' => day_of_week, 'times' => simple_daily_times, 'values' => simple_daily_values, 'daily_os_times' => simple_daily_os_times, 'daily_occs' => simple_daily_occs }

    end

    # Create a TimeSeries from the data
    # time_series = OpenStudio::TimeSeries.new(times, values, 'unitless')

    # Make a schedule ruleset
    sch_name = "#{name} Occ Sch"
    sch_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
    sch_ruleset.setName(sch_name.to_s)

    # Default - All Occupied
    day_sch = sch_ruleset.defaultDaySchedule
    day_sch.setName("#{sch_name} Default")
    day_sch.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1)

    # Winter Design Day - All Occupied
    day_sch = OpenStudio::Model::ScheduleDay.new(model)
    sch_ruleset.setWinterDesignDaySchedule(day_sch)
    day_sch = sch_ruleset.winterDesignDaySchedule
    day_sch.setName("#{sch_name} Winter Design Day")
    day_sch.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1)

    # Summer Design Day - All Occupied
    day_sch = OpenStudio::Model::ScheduleDay.new(model)
    sch_ruleset.setSummerDesignDaySchedule(day_sch)
    day_sch = sch_ruleset.summerDesignDaySchedule
    day_sch.setName("#{sch_name} Summer Design Day")
    day_sch.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1)

    # Create ruleset schedules, attempting to create
    # the minimum number of unique rules.
    ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'].each do |day_of_week|
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirLoopHVAC', day_of_week.to_s)
      end_of_prev_rule = yearly_data[0]['date']
      yearly_data.each_with_index do |daily_data, i|
        # Skip unless it is the day of week
        # currently under inspection
        day = daily_data['day_of_week']
        next unless day == day_of_week
        date = daily_data['date']
        times = daily_data['times']
        values = daily_data['values']
        daily_occs = daily_data['daily_occs']

        # If the next (Monday, Tuesday, etc.)
        # is the same as today, keep going.
        # If the next is different, or if
        # we've reached the end of the year,
        # create a new rule
        if !yearly_data[i + 7].nil?
          next_day_times = yearly_data[i + 7]['times']
          next_day_values = yearly_data[i + 7]['values']
          next if times == next_day_times && values == next_day_values
        end

        daily_os_times = daily_data['daily_os_times']
        daily_occs = daily_data['daily_occs']

        # If here, we need to make a rule to cover from the previous
        # rule to today
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirLoopHVAC', "Making a new rule for #{day_of_week} from #{end_of_prev_rule} to #{date}")
        sch_rule = OpenStudio::Model::ScheduleRule.new(sch_ruleset)
        sch_rule.setName("#{sch_name} #{day_of_week} Rule")
        day_sch = sch_rule.daySchedule
        day_sch.setName("#{sch_name} #{day_of_week}")
        daily_os_times.each_with_index do |time, i|
          value = values[i]
          next if value == values[i + 1] # Don't add breaks if same value
          day_sch.addValue(time, value)
          OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirLoopHVAC', "   Adding value #{time}, #{value}")
        end

        # Set the dates when the rule applies
        sch_rule.setStartDate(end_of_prev_rule)
        sch_rule.setEndDate(date)

        # Individual Days
        sch_rule.setApplyMonday(true) if day_of_week == 'Monday'
        sch_rule.setApplyTuesday(true) if day_of_week == 'Tuesday'
        sch_rule.setApplyWednesday(true) if day_of_week == 'Wednesday'
        sch_rule.setApplyThursday(true) if day_of_week == 'Thursday'
        sch_rule.setApplyFriday(true) if day_of_week == 'Friday'
        sch_rule.setApplySaturday(true) if day_of_week == 'Saturday'
        sch_rule.setApplySunday(true) if day_of_week == 'Sunday'

        # Reset the previous rule end date
        end_of_prev_rule = date + OpenStudio::Time.new(0, 24, 0, 0)
      end
    end

    return sch_ruleset
  end
end
