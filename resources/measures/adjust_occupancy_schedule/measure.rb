# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# TODO: Replace these methods with calls to OpenstudioStandards::Schedules

# Returns the ScheduleRuleset minimum and maximum values.
# This method does not include summer and winter design day values.
# By default the method reports values from all component day schedules even if unused,
# but can optionally report values encountered only during the run period.
#
# @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
# @param only_run_period_values [Bool] check values encountered only during the run period
#   Default to false. This will ignore ScheduleRules or the DefaultDaySchedule if never used.
# @return [Hash] returns a hash with 'min' and 'max' values
def schedule_ruleset_get_min_max(schedule_ruleset, only_run_period_values: false)
  # validate schedule
  unless schedule_ruleset.to_ScheduleRuleset.is_initialized
    OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Schedules.Information', "Method schedule_ruleset_get_min_max() failed because object #{schedule_ruleset} is not a ScheduleRuleset.")
    return nil
  end

  # day schedules
  day_schedules = []

  # check only day schedules in the run period
  if only_run_period_values
    # get year
    if schedule_ruleset.model.yearDescription.is_initialized
      year_description = schedule_ruleset.model.yearDescription.get
      year = year_description.assumedYear
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Schedules.Information', 'Year description is not specified. Full load hours calculation will assume 2009, the default year OS uses.')
      year = 2009
    end

    # get start and end month and day
    run_period = schedule_ruleset.model.getRunPeriod
    start_month = run_period.getBeginMonth
    start_day = run_period.getBeginDayOfMonth
    end_month = run_period.getEndMonth
    end_day = run_period.getEndDayOfMonth

    # set the start and end date
    start_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new(start_month), start_day, year)
    end_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new(end_month), end_day, year)

    # Get the ordered list of all the day schedules
    day_schs = schedule_ruleset.getDaySchedules(start_date, end_date)

    # Get the array of which schedule is used on each day of the year
    day_schs_used_each_day = schedule_ruleset.getActiveRuleIndices(start_date, end_date)

    # Create a map that shows how many days each schedule is used
    day_sch_freq = day_schs_used_each_day.group_by { |n| n }

    # Build a hash that maps schedule day index to schedule day
    schedule_index_to_day = {}
    day_schs.each_with_index do |day_sch, i|
      schedule_index_to_day[day_schs_used_each_day[i]] = day_sch
    end

    # Loop through each of the schedules and record which ones are used
    day_sch_freq.each do |freq|
      sch_index = freq[0]
      number_of_days_sch_used = freq[1].size
      next unless number_of_days_sch_used > 0

      # Get the day schedule at this index
      day_sch = nil
      if sch_index == -1 # If index = -1, this day uses the default day schedule (not a rule)
        day_sch = schedule_ruleset.defaultDaySchedule
      else
        day_sch = schedule_index_to_day[sch_index]
      end

      # add day schedule to array
      day_schedules << day_sch
    end
  else
    # use all day schedules
    day_schedules << schedule_ruleset.defaultDaySchedule
    schedule_ruleset.scheduleRules.each { |rule| day_schedules << rule.daySchedule }
  end

  # get min and max from day schedules array
  min = nil
  max = nil
  day_schedules.each do |day_schedule|
    day_schedule.values.each do |value|
      if min.nil?
        min = value
      else
        if min > value then min = value end
      end
      if max.nil?
        max = value
      else
        if max < value then max = value end
      end
    end
  end
  result = { 'min' => min, 'max' => max }

  return result
end

# Increase/decrease by percentage or static value
#
# @param schedule_ruleset [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
# @param value [Double] Hash of name and time value pairs
# @param modification_type [String] Options are 'Multiplier', which multiples by the value,
#   and 'Sum' which adds by the value
# @return [OpenStudio::Model::ScheduleRuleset] OpenStudio ScheduleRuleset object
# @todo add in design day adjustments, maybe as an optional argument
# @todo provide option to clone existing schedule
def schedule_ruleset_simple_value_adjust(schedule_ruleset, value, modification_type = 'Multiplier')
  # gather profiles
  profiles = []
  default_profile = schedule_ruleset.to_ScheduleRuleset.get.defaultDaySchedule
  profiles << default_profile
  rules = schedule_ruleset.scheduleRules
  rules.each do |rule|
    profiles << rule.daySchedule
  end

  # alter profiles
  profiles.each do |profile|
    times = profile.times
    i = 0
    profile.values.each do |sch_value|
      case modification_type
      when 'Multiplier', 'Percentage'
        # percentage was used early on but Multiplier is preferable
        profile.addValue(times[i], sch_value * value)
      when 'Sum', 'Value'
        # value was used early on but Sum is preferable
        profile.addValue(times[i], sch_value + value)
      end
      i += 1
    end
  end

  return schedule_ruleset
end

# start the measure
class AdjustOccupancySchedule < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'adjust_occupancy_schedule'
  end

  # human readable description
  def description
    return 'Adjusts People occupancy schedules to change total occupant count'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Adjusts People schedule so that peak occupancy is a user-input fraction of existing schedule values'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument for peak occupancy fraction
    peak_occ_frac = OpenStudio::Measure::OSArgument.makeDoubleArgument('peak_occ_frac', true)
    peak_occ_frac.setDisplayName('Peak Occupancy Fraction')
    peak_occ_frac.setDefaultValue(0.6)
    args << peak_occ_frac

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign argument to variables
    peak_occ_frac = runner.getDoubleArgumentValue('peak_occ_frac', user_arguments)

    total_occ = 0
    all_sch_info = []

    # get schedules from all people loads
    model.getPeoples.each do |ppl|
      # gather schedule info
      sch_info = { area: 0, ppl_nom: 0 }
      num_sch = ppl.numberofPeopleSchedule.get.to_ScheduleRuleset.get
      load_def = ppl.peopleDefinition
      sch_info[:sch] = num_sch
      sch_info[:name] = num_sch.name.get
      sch_info[:area] += load_def.floorArea
      sch_info[:ppl_nom] += load_def.getNumberOfPeople(load_def.floorArea)
      sch_info.merge!(schedule_ruleset_get_min_max(num_sch).transform_keys(&:to_sym))
      all_sch_info << sch_info
    end

    # get unique schedule names
    sch_names = all_sch_info.map { |hash| hash.select { |k, _| k == :name } }.uniq

    # calculate total nominal and schedule-adjusted occupancy
    tot_ppl_nom = all_sch_info.inject(0) { |sum, h| sum + h[:ppl_nom] }
    tot_ppl_adj = all_sch_info.inject(0) { |sum, h| sum + (h[:ppl_nom] * h[:max]) }

    # report initial occupancy values
    runner.registerInitialCondition("#{sch_names.size} Unique occupancy schedules found. Initial total nominal occupancy: #{tot_ppl_nom}, initial peak schedule-adjusted occupancy: #{tot_ppl_adj}.")

    # loop through people schedules and apply adjustment
    runner.registerInfo("Reducing occupancy schedule values by #{peak_occ_frac.round(2) * 100}%. Design sizing schedule values will remain unchanged.")

    sch_names.each do |h|
      sch_name = h[:name]
      schedule = model.getScheduleRulesetByName(sch_name).get
      # append reduced percentage to schedule name
      schedule.setName(sch_name + " reduced by #{peak_occ_frac.round(2) * 100}%")
      # apply reduction
      schedule = schedule_ruleset_simple_value_adjust(schedule, peak_occ_frac, 'Multiplier')
    end

    # report final peak occupancy
    final_info = []
    model.getPeoples.each do |ppl|
      sch_info = {}
      sch_info.merge!(schedule_ruleset_get_min_max(ppl.numberofPeopleSchedule.get.to_ScheduleRuleset.get).transform_keys(&:to_sym))
      sch_info[:ppl_nom] = ppl.peopleDefinition.getNumberOfPeople(ppl.peopleDefinition.floorArea)
      final_info << sch_info
    end

    final_ppl_nom = final_info.inject(0) { |sum, h| sum + h[:ppl_nom] }
    final_ppl_adj = final_info.inject(0) { |sum, h| sum + (h[:ppl_nom] * h[:max]) }

    runner.registerFinalCondition("Final total nominal occupancy: #{final_ppl_nom}; final peak schedule-adjusted occupancy: #{final_ppl_adj}.")

    return true
  end
end

# register the measure to be used by the application
AdjustOccupancySchedule.new.registerWithApplication
