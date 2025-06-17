# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

require 'erb'
require 'json'

# start the measure
class LoadsSummary < OpenStudio::Measure::ReportingMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'loads_summary'
  end

  # human readable description
  def description
    return ''
  end

  # human readable description of modeling approach
  def modeler_description
    return ''
  end

  # define the arguments that the user will input
  def arguments(model = nil)
    args = OpenStudio::Measure::OSArgumentVector.new

    report_timeseries_data = OpenStudio::Measure::OSArgument.makeBoolArgument('report_timeseries_data', true)
    report_timeseries_data.setDisplayName('Report timeseries data to csv file')
    report_timeseries_data.setDefaultValue(false)
    args << report_timeseries_data

    debug_mode = OpenStudio::Measure::OSArgument.makeBoolArgument('debug_mode', true)
    debug_mode.setDisplayName('Enable extra variables for debugging zone loads')
    debug_mode.setDefaultValue(false)
    args << debug_mode

    return args
  end

  # define the outputs that the measure will create
  def outputs
    outs = OpenStudio::Measure::OSOutputVector.new

    # this measure does not produce machine readable outputs with registerValue, return an empty list

    return outs
  end

  def components
    [
    'people_gain',
    'light_gain',
    'equip_gain',
    'win_sol',
    'ext_wall',
    'fnd_wall',
    'roof',
    'ext_flr',
    'gnd_flr',
    'win_cond',
    'door',
    'infil',
    'vent'
    ]
  end

  def modes
    [
      'htg',
      'clg',
      'flt'
    ]
  end

  def variables_names
    [
      'Zone Air Heat Balance System Air Transfer Rate',
      'Zone Air Heat Balance System Convective Heat Gain Rate',
      'Zone People Convective Heating Energy',
      'Zone People Radiant Heating Energy',
      'Zone Lights Convective Heating Energy',
      'Zone Lights Radiant Heating Energy',
      'Zone Electric Equipment Convective Heating Energy',
      'Zone Electric Equipment Radiant Heating Energy',
      'Zone Gas Equipment Convective Heating Energy',
      'Zone Gas Equipment Radiant Heating Energy',
      'Zone Hot Water Equipment Convective Heating Energy',
      'Zone Hot Water Equipment Radiant Heating Energy',
      'Zone Other Equipment Convective Heating Energy',
      'Zone Other Equipment Radiant Heating Energy',
      'Enclosure Windows Total Transmitted Solar Radiation Energy',
      'Surface Window Inside Face Glazing Net Infrared Heat Transfer Rate',
      'Surface Window Inside Face Shade Net Infrared Heat Transfer Rate',
      'Surface Window Inside Face Gap between Shade and Glazing Zone Convection Heat Gain Rate',
      'Surface Inside Face Convection Heat Gain Energy',
      'Zone Infiltration Sensible Heat Gain Energy',
      'Zone Infiltration Sensible Heat Loss Energy',
      'Zone Mechanical Ventilation Heating Load Increase Energy',
      'Zone Mechanical Ventilation Heating Load Decrease Energy',
      'Zone Mechanical Ventilation Cooling Load Increase Energy',
      'Zone Mechanical Ventilation Cooling Load Decrease Energy',
    ]
  end

  def debug_vars
    [
      'people_conv',
      'people_delayed',
      'light_conv',
      'light_delayed',
      'equip_conv',
      'equip_delayed',
      'total_delayed',
      'win_sol_delayed',
      'window_ir_delayed',
      'int_surf_conv',
      'attributable_ext_surf_conv',
      'ext_wall_conv',
      'ext_roof_conv',
      'ext_gnd_flr_conv',
      'ext_win_conv',
      'infil',
      'vent'
    ]
  end

  # add any outout variable requests here
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

  end

  def get_timeseries_array(runner, sql, env_period, timestep, variable_name, key_value, num_timesteps, expected_units = nil, desired_units = nil)
    time_series_array = []
    time_series = sql.timeSeries(env_period, timestep, variable_name, key_value)
    if time_series.is_initialized #checks to see if time_series exists
      time_series = time_series.get
      # Check the units
      unless expected_units.nil?
        unless time_series.units == expected_units
          runner.registerError("Expected units of #{expected_units} but got #{time_series.units} for #{variable_name}")
        end

        # Convert the units if desired
        if !desired_units.nil? && time_series.units != desired_units
          begin
            conversion = OpenStudio.convert(1.0, time_series.units, desired_units).get
            time_series = time_series * conversion
          rescue StandardError => e
            runner.registerError("Failed to convert units from #{time_series.units} to #{desired_units} for #{variable_name}: #{e.message}")
            return Array.new(num_timesteps, 0.0)
          end
        end
      end

      time_series_array = time_series.values.to_a
    else
      # Query is not valid.
      time_series_array = Array.new(num_timesteps, 0.0)
      runner.registerWarning("Timeseries query: '#{variable_name}' for '#{key_value}' at '#{timestep}' not found, returning array of zeros")
    end

    return time_series_array
  end
 
  def get_runperiod_variable_value(runner, sql, env_period, key_value, desired_units = nil)
    query = %{
    SELECT rvd.VariableValue
    FROM ReportVariableData AS rvd
    JOIN ReportVariableDataDictionary AS rvdd
      ON rvd.ReportVariableDataDictionaryIndex = rvdd.ReportVariableDataDictionaryIndex
    JOIN Time AS t
      ON rvd.TimeIndex = t.TimeIndex
    WHERE rvdd.KeyValue = '#{key_value}'
    AND rvdd.VariableName = 'PythonPlugin:OutputVariable'
    AND rvdd.ReportingFrequency = 'Run Period'
    AND t.IntervalType = 4;
    }

    result = sql.execAndReturnFirstDouble(query)
    if result.empty?
      runner.registerError('Cannot find run period variable value for ' + key_value)
      return false
    else
      result = result.get
    end

    return desired_units ? OpenStudio.convert(result, 'J', desired_units).get : result
  end  

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Cannot find last model.')
      return false
    end
    model = model.get

    # use the built-in error checking (need model)
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # get measure arguments
    report_timeseries_data = runner.getBoolArgumentValue('report_timeseries_data', user_arguments)
    debug_mode = runner.getBoolArgumentValue('debug_mode', user_arguments)

    # load sql file
    sql_file = runner.lastEnergyPlusSqlFile
    if sql_file.empty?
      runner.registerError('Cannot find last sql file.')
      return false
    end
    sql_file = sql_file.get
    model.setSqlFile(sql_file)

    # get the weather file run period (as opposed to design day run period)
    ann_env_pd = nil
    sql_file.availableEnvPeriods.each do |env_pd|
      env_type = sql_file.environmentType(env_pd)
      if env_type.is_initialized
        if env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod')
          ann_env_pd = env_pd
          break
        end
      end
    end

    # Get the timestep length
    steps_per_hour = if model.getSimulationControl.timestep.is_initialized
                       model.getSimulationControl.timestep.get.numberOfTimestepsPerHour
                     else
                       6 # default OpenStudio timestep if none specified
                     end

    # Get the annual hours simulated
    hrs_sim = 0
    if sql_file.hoursSimulated.is_initialized
      hrs_sim = sql_file.hoursSimulated.get
    else
      runner.registerError('An annual simulation was not run. Cannot summarize annual heat transfer for Scout.')
      return false
    end

    # Determine the number of timesteps
    num_ts = hrs_sim * steps_per_hour

    # query the component outputs and register values
    components.each do |component|
      modes.each do |mode|
        # ts = get_timeseries_array(runner, sql_file, ann_env_pd, 'Zone Timestep', 'PythonPlugin:OutputVariable', "#{component}_#{mode}", num_ts, 'J', 'GJ')
        # runner.registerValue("#{component}_#{mode}", ts.sum, 'GJ')
        value = get_runperiod_variable_value(runner, sql_file, ann_env_pd, "#{component}_#{mode}", 'GJ')
        runner.registerValue("#{component}_#{mode}", value, 'GJ')

      end
    end

    # close the sql file
    sql_file.close

    return true
  end
end

# register the measure to be used by the application
LoadsSummary.new.registerWithApplication
