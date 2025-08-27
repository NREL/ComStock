# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# start the measure
class SimulationSettings < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Simulation Settings'
  end

  # human readable description
  def description
    return 'Sets timestep, daylight savings, calendar year, and run period.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Sets timestep, daylight savings, calendar year, and run period.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Timestep
    timesteps_per_hr = OpenStudio::Measure::OSArgument.makeIntegerArgument('timesteps_per_hr', true)
    timesteps_per_hr.setDisplayName('Simulation Timestep')
    timesteps_per_hr.setDescription('Simulation timesteps per hr')
    timesteps_per_hr.setDefaultValue(4)
    args << timesteps_per_hr

    # Daylight Savings Time
    enable_dst = OpenStudio::Measure::OSArgument.makeBoolArgument('enable_dst', true)
    enable_dst.setDisplayName('Enable Daylight Savings')
    enable_dst.setDescription('Set to true to make model schedules observe daylight savings. Set to false if in a location where DST is not observed.')
    enable_dst.setDefaultValue(true)
    args << enable_dst

    # DST start date
    dst_start = OpenStudio::Ruleset::OSArgument.makeStringArgument('dst_start', true)
    dst_start.setDisplayName('Daylight Savings Starts')
    dst_start.setDescription('Only used if Enable Daylight Savings is true')
    dst_start.setDefaultValue('2nd Sunday in March')
    args << dst_start

    # DST end date
    dst_end = OpenStudio::Ruleset::OSArgument.makeStringArgument('dst_end', true)
    dst_end.setDisplayName('Daylight Savings Starts')
    dst_end.setDescription('Only used if Enable Daylight Savings is true')
    dst_end.setDefaultValue('1st Sunday in November')
    args << dst_end

    # Year
    calendar_year = OpenStudio::Measure::OSArgument.makeIntegerArgument('calendar_year', true)
    calendar_year.setDisplayName('Calendar Year')
    calendar_year.setDefaultValue(0)
    calendar_year.setDescription('This will impact the day of the week the simulation starts on. An input value of 0 will leave the year un-altered')
    args << calendar_year

    # Day of week that Jan 1st falls on
    jan_first_day_of_wk = OpenStudio::Ruleset::OSArgument.makeStringArgument('jan_first_day_of_wk', true)
    jan_first_day_of_wk.setDisplayName('Day of Week that Jan 1st falls on')
    jan_first_day_of_wk.setDescription('Only used if Calendar Year = 0.  If Calendar Year specified, use correct start day for that year.')
    jan_first_day_of_wk.setDefaultValue('Thursday') # Matches OpenStudio default year of 2009
    args << jan_first_day_of_wk

    # Begin month of simulation
    begin_month = OpenStudio::Ruleset::OSArgument.makeIntegerArgument('begin_month', true)
    begin_month.setDisplayName('Begin Month')
    begin_month.setDescription('First month of simulation')
    begin_month.setDefaultValue(1)
    args << begin_month

    # Begin day of simulation
    begin_day = OpenStudio::Ruleset::OSArgument.makeIntegerArgument('begin_day', true)
    begin_day.setDisplayName('Begin Day')
    begin_day.setDescription('First day of simulation')
    begin_day.setDefaultValue(1)
    args << begin_day

    # Last month of simulation
    end_month = OpenStudio::Ruleset::OSArgument.makeIntegerArgument('end_month', true)
    end_month.setDisplayName('End Month')
    end_month.setDescription('Last month of simulation')
    end_month.setDefaultValue(12)
    args << end_month

    # Last day of simulation
    end_day = OpenStudio::Ruleset::OSArgument.makeIntegerArgument('end_day', true)
    end_day.setDisplayName('End Day')
    end_day.setDescription('Last day of simulation')
    end_day.setDefaultValue(31)
    args << end_day

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Assign the user inputs to variables
    timesteps_per_hr = runner.getIntegerArgumentValue('timesteps_per_hr', user_arguments)
    enable_dst = runner.getBoolArgumentValue('enable_dst', user_arguments)
    dst_start = runner.getStringArgumentValue('dst_start', user_arguments)
    dst_end = runner.getStringArgumentValue('dst_end', user_arguments)
    calendar_year = runner.getIntegerArgumentValue('calendar_year', user_arguments)
    jan_first_day_of_wk = runner.getStringArgumentValue('jan_first_day_of_wk', user_arguments)
    begin_month = runner.getIntegerArgumentValue('begin_month', user_arguments)
    begin_day = runner.getIntegerArgumentValue('begin_day', user_arguments)
    end_month = runner.getIntegerArgumentValue('end_month', user_arguments)
    end_day = runner.getIntegerArgumentValue('end_day', user_arguments)

    # Daylight savings
    if enable_dst
      dst_control = model.getRunPeriodControlDaylightSavingTime
      dst_control.setStartDate(dst_start)
      dst_control.setEndDate(dst_end)
      runner.registerInfo("Daylight savings enabled from #{dst_control.getString(1)} to #{dst_control.getString(2)}.")
    else
      dst_control = model.getRunPeriodControlDaylightSavingTime.remove
      model.getRunPeriod.setUseWeatherFileDaylightSavings(false)
      runner.registerInfo('Daylight savings disabled.')
    end

    # Timestep
    timestep = model.getTimestep
    timestep.setNumberOfTimestepsPerHour(timesteps_per_hr)
    runner.registerInfo("Timestep set to #{timestep.numberOfTimestepsPerHour} timesteps/hr.")

    # Run period
    run_period = model.getRunPeriod
    run_period.setBeginMonth(begin_month)
    run_period.setBeginDayOfMonth(begin_day)
    run_period.setEndMonth(end_month)
    run_period.setEndDayOfMonth(end_day)
    runner.registerInfo("Run period set from #{run_period.getBeginMonth}/#{run_period.getBeginDayOfMonth} to #{run_period.getEndMonth}/#{run_period.getEndDayOfMonth}.")

    # Year
    yr_desc = model.getYearDescription
    if calendar_year > 0
      yr_desc.setCalendarYear(calendar_year)
      fwd_translator_first_day = yr_desc.makeDate(run_period.getBeginMonth, run_period.getBeginDayOfMonth).dayOfWeek.valueName
      runner.registerInfo("Calendar year set to #{yr_desc.calendarYear.get}, start day of week in IDF will be set to #{fwd_translator_first_day} for #{run_period.getBeginMonth}/#{run_period.getBeginDayOfMonth}/#{yr_desc.calendarYear.get} during OSM to IDF translation.")
    else
      yr_desc.resetDayofWeekforStartDay
      yr_desc.resetCalendarYear
      yr_desc.setDayofWeekforStartDay(jan_first_day_of_wk)
      runner.registerInfo("Reset calendar year and set Jan 1st day of week to #{yr_desc.dayofWeekforStartDay}. Calendar year assumed to be #{yr_desc.assumedYear}.")
    end

    return true
  end
end

# register the measure to be used by the application
SimulationSettings.new.registerWithApplication
