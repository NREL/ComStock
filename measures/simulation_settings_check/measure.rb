# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'erb'

# start the measure
class SimulationSettingsCheck < OpenStudio::Measure::ReportingMeasure
  # human readable name
  def name
    'Simulation Settings Check'
  end

  # human readable description
  def description
    'Checks year, start day of week, daylight savings, leap year, and timestep inputs and outputs'
  end

  # human readable description of modeling approach
  def modeler_description
    'Checks year, start day of week, daylight savings, leap year, and timestep inputs and outputs'
  end

  # define the arguments that the user will input
  def arguments(_model = nil)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument to toggle QAQC
    run_sim_settings_checks = OpenStudio::Measure::OSArgument.makeBoolArgument('run_sim_settings_checks', true)
    run_sim_settings_checks.setDisplayName('Run Checks')
    run_sim_settings_checks.setDescription('If set to true, will run the measure, which adds output variables and increases runtime.')
    run_sim_settings_checks.setDefaultValue(false)
    args << run_sim_settings_checks
    args
  end

  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    result = OpenStudio::IdfObjectVector.new

    run_sim_settings_checks = runner.getBoolArgumentValue('run_sim_settings_checks', user_arguments)
    return result unless run_sim_settings_checks

    result << OpenStudio::IdfObject.load('Output:Variable,*,Site Day Type Index,Hourly;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Site Daylight Saving Time Status,hourly;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Site Outdoor Air Drybulb Temperature,timestep;').get

    result
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking
    return false unless runner.validateUserArguments(arguments, user_arguments)

    run_sim_settings_checks = runner.getBoolArgumentValue('run_sim_settings_checks', user_arguments)
    return true unless run_sim_settings_checks

    # get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Cannot find last model.')
      return false
    end
    model = model.get

    sql = runner.lastEnergyPlusSqlFile
    if sql.empty?
      runner.registerError('Cannot find last sql file.')
      return false
    end
    sql = sql.get
    model.setSqlFile(sql)

    # Get the weather file run period (as opposed to design day run period)
    ann_env_pd = nil
    sql.availableEnvPeriods.each do |env_pd|
      env_type = sql.environmentType(env_pd)
      if env_type.is_initialized && (env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod'))
        ann_env_pd = env_pd
        break
      end
    end

    # Make sure an annual simulation was run
    if ann_env_pd.nil?
      runner.registerError('No annual environment period found, cannot perform checks.')
      return false
    end

    # Get the day type timeseries.
    day_types = nil
    day_types_ts = sql.timeSeries(ann_env_pd, 'Hourly', 'Site Day Type Index', 'Environment')
    if day_types_ts.is_initialized
      # Put values into array
      day_types = []
      vals = day_types_ts.get.values
      for i in 0..(vals.size - 1)
        day_types << vals[i]
      end
    else
      runner.registerError('Site Day Type Index at Hourly timestep could not be found, cannot perform checks.')
      return false
    end

    # Get the daylight savings status timeseries
    daylt_svgs = nil
    daylt_svgs_ts = sql.timeSeries(ann_env_pd, 'Hourly', 'Site Daylight Saving Time Status', 'Environment')
    if daylt_svgs_ts.is_initialized
      # Put values into array
      daylt_svgs = []
      vals = daylt_svgs_ts.get.values
      for i in 0..(vals.size - 1)
        daylt_svgs << vals[i]
      end
    else
      runner.registerError('Site Daylight Saving Time Status at Hourly timestep could not be found, cannot perform checks.')
      return false
    end

    # Get the outdoor air temp timeseries
    oa_temps = nil
    oa_temps_ts = sql.timeSeries(ann_env_pd, 'Zone Timestep', 'Site Outdoor Air Drybulb Temperature', 'Environment')
    if oa_temps_ts.is_initialized
      # Put values into array
      oa_temps = []
      vals = oa_temps_ts.get.values
      for i in 0..(vals.size - 1)
        oa_temps << vals[i]
      end
    else
      runner.registerError('Site Outdoor Air Drybulb Temperature at Zone Timestep timestep could not be found, cannot perform checks.')
      return false
    end

    # Get the year from the sql file directly
    yr_query = if model.version < OpenStudio::VersionString.new('3.0.0')
                 'SELECT year FROM time WHERE TimeIndex == 1'
               else
                 'SELECT year FROM time LIMIT 1'
               end
    sql_yr = sql.execAndReturnFirstInt(yr_query)
    if sql_yr.empty?
      runner.registerError('Could not determine simulation year from sql file times, cannot perform checks.')
      return false
    end
    sql_yr = sql_yr.get

    # Check daylight savings inputs
    # If DST object is present in the model, that takes precedence.
    # If no DST object is present, EnergyPlus falls back on the
    # 'Use Weather File Daylight Saving Period' field in the RunPeriod object.
    run_period_daylt_svgs_objs = model.getObjectsByType('OS:RunPeriodControl:DaylightSavingTime'.to_IddObjectType)
    run_period = model.getRunPeriod
    if run_period_daylt_svgs_objs.empty?
      if run_period.getUseWeatherFileDaylightSavings
        daylt_svgs_input_status = "No RunPeriodControl:DaylightSavingTime so E+ falls back on RunPeriod 'Use Weather File Daylight Saving Period', which is set to TRUE (use DST specified in weather file)."
      else
        daylt_svgs_input_status = "No RunPeriodControl:DaylightSavingTime so E+ falls back on RunPeriod 'Use Weather File Daylight Saving Period', which is set to FALSE (don't use DST specified in weather file)."
      end
    elsif run_period_daylt_svgs_objs.size == 1
      run_period_ctrl = run_period_daylt_svgs_objs[0]
      start_dst = run_period_ctrl.getString(1)
      end_dst = run_period_ctrl.getString(2)
      daylt_svgs_input_status = "RunPeriodControl:DaylightSavingTime starts #{start_dst}, ends #{end_dst}."
    else
      runner.registerError('Multiple RunPeriodControl:DaylightSavingTime objects in model, cannot perform checks.')
      return false
    end

    # Check daylight savings outputs
    num_hrs_daylt_svgs = daylt_svgs.inject(:+)
    daylt_svgs_output_status = "Daylight savings observed for #{num_hrs_daylt_svgs.round} of #{daylt_svgs.size} hrs simulated."

    # Check hours simulated input
    input_begin_month = run_period.getBeginMonth
    input_begin_day = run_period.getBeginDayOfMonth
    input_end_month = run_period.getEndMonth
    input_end_day = run_period.getEndDayOfMonth
    hrs_simulated_input_status = "Run from #{input_begin_month}/#{input_begin_day} to #{input_end_month}/#{input_end_day}."

    # Check hours simulated via output
    hrs_simulated = sql.hoursSimulated
    if hrs_simulated.is_initialized
      hrs_simulated = hrs_simulated.get
      hrs_simulated_output_status = "Simulation was #{hrs_simulated} hrs."
    else
      runner.registerError('Could not determine number of hours simulated from sql file, cannot perform checks.')
      return false
    end

    # Warn if other than 8760 hrs simulated
    unless hrs_simulated == 8760.0
      hrs_simulated_warning = 'Expected 8760 for annual simulation.'
      runner.registerWarning(hrs_simulated_warning)
    end

    # Check timestep input
    sim_ctrl = model.getSimulationControl
    step = sim_ctrl.timestep
    if step.is_initialized
      step = step.get
      input_steps_per_hr = step.numberOfTimestepsPerHour
      timestep_input_status = "TimeStep object set to #{input_steps_per_hr} steps/hr."
    else
      runner.registerError('No TimeStep object in model, cannot perform checks.')
      return false
    end

    # Check the timestep output
    output_num_timesteps = oa_temps_ts.get.values.size
    output_steps_per_hr = output_num_timesteps / hrs_simulated
    timestep_output_status = "E+ timeseries shows #{output_steps_per_hr} steps/hr."

    # Warn if input and output timestep lengths don't match
    unless input_steps_per_hr.to_f == output_steps_per_hr.to_f
      timestep_warning = "Timestep input and output don't match."
    end

    # Check the start day of week inputs
    yr_desc = model.getYearDescription
    input_start_day = yr_desc.dayofWeekforStartDay
    if yr_desc.calendarYear.is_initialized
      yr = yr_desc.calendarYear.get
      input_start_day = yr_desc.makeDate(run_period.getBeginMonth, run_period.getBeginDayOfMonth).dayOfWeek.valueName
      start_day_input_status = "Year set to #{yr}. Simulation start day of #{run_period.getBeginMonth}/#{run_period.getBeginDayOfMonth}/#{yr} is a #{input_start_day}."
    else
      yr = yr_desc.assumedYear
      input_start_day = yr_desc.makeDate(run_period.getBeginMonth, run_period.getBeginDayOfMonth).dayOfWeek.valueName
      start_day_input_status = "Year not specified. OpenStudio assumed #{yr}. Simulation start day of #{run_period.getBeginMonth}/#{run_period.getBeginDayOfMonth}/#{yr} is a #{input_start_day}."
    end

    # Get the day of week of the first timestep
    day_type_to_name = {
      1 => 'Sunday',
      2 => 'Monday',
      3 => 'Tuesday',
      4 => 'Wednesday',
      5 => 'Thursday',
      6 => 'Friday',
      7 => 'Saturday',
      8 => 'Holiday',
      9 => 'SummerDesignDay',
      10 => 'WinterDesignDay',
      11 => 'CustomDay1',
      12 => 'CustomDay2'
    }
    puts "day_types[0] = #{day_types[0].to_i}"
    output_start_day = day_type_to_name[day_types[0].to_i]
    puts "output_start_day = #{output_start_day}"
    start_day_output_status = "E+ output first day of the simulation is a #{output_start_day}."

    # Warn if different input and output start days don't match
    unless input_start_day.downcase == output_start_day.downcase
      start_day_warning = "The input file lists a start day of #{input_start_day}, while the EnergyPlus outputs indicate a start day of #{output_start_day}."
      runner.registerWarning(start_day_warning)
    end

    # Check leap year input
    input_is_leap_yr = yr_desc.isLeapYear
    leap_year_input_status = if input_is_leap_yr
                               "Year is set to #{yr}, which IS a leap year."
                             else
                               "Year is set to #{yr}, which is NOT a leap year."
                             end

    # Check leap year via output
    output_is_leap_yr = false
    day_types_ts.get.dateTimes.each do |date_time|
      date = date_time.date
      ### workaround ###
      # TODO: remove once https://github.com/NREL/OpenStudio/issues/817 is fixed
      # OS always assumes 2009 in sql timeseries results,
      # so make a Date for the same day of the year, but
      # using the year extracted directly from the sql file.
      day_of_year = date.dayOfYear
      date = OpenStudio::Date.fromDayOfYear(day_of_year, sql_yr)
      ### workaround ###
      next unless date.monthOfYear.value == 2 # February
      next unless date.dayOfMonth == 29 # Feb 29

      output_is_leap_yr = true
      break
    end
    leap_year_output_status = if output_is_leap_yr
                                'E+ output DOES have values for February 29th, so it IS running as a leap year.'
                              else
                                'E+ output does NOT have values for February 29th, so it is NOT running as a leap year.'
                              end

    # Warn if different input and output leap year info doesn't match
    unless input_is_leap_yr == output_is_leap_yr
      leap_year_warning = "The input says leap year = #{input_is_leap_yr}, while the EnergyPlus outputs indicate leap year = #{output_is_leap_yr}."
      runner.registerWarning(leap_year_warning)
    end

    # read in template
    html_in_path = "#{File.dirname(__FILE__)}/resources/report.html.erb"
    html_in_path = "#{File.dirname(__FILE__)}/report.html.erb" unless File.exist?(html_in_path)

    html_in = ''
    File.open(html_in_path, 'r') do |file|
      html_in = file.read
    end

    # configure template with variable values
    web_asset_path = OpenStudio.getSharedResourcesPath / OpenStudio::Path.new('web_assets')
    renderer = ERB.new(html_in)
    html_out = renderer.result(binding)

    # write html file
    html_out_path = './report.html'
    File.open(html_out_path, 'w') do |file|
      file << html_out
      # make sure data is written to the disk one way or the other
      begin
        file.fsync
      rescue StandardError
        file.flush
      end
    end

    # closing the sql file
    sql.close

    # reporting final condition
    runner.registerFinalCondition("Generated #{html_out_path}.")

    true
  end
end

# register the measure to be used by the application
SimulationSettingsCheck.new.registerWithApplication
