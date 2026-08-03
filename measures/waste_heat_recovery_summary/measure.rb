# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'erb'
require 'json'
require 'fileutils'

# start the measure
class WasteHeatRecoverySummary < OpenStudio::Measure::ReportingMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Waste Heat Recovery Summary'
  end

  # timestep for timeseries data processing
  def timeseries_timestep
    return 'Hourly'
  end

  # human readable description
  def description
    return 'This measure reports the amount of simultaneous heating and cooling that occurs in the building, as well as heat flows for potential heat recovery.'
  end

  # human readable description of modeling approach
  def modeler_description
    return "This measure depends on HVAC timeseries data, and can take a while to run."
  end

  # define the arguments that the user will input
  def arguments(model = nil)
    args = OpenStudio::Measure::OSArgumentVector.new

    timeseries_output = OpenStudio::Measure::OSArgument.makeBoolArgument('timeseries_output', true)
    timeseries_output.setDisplayName('Output Timeseries')
    timeseries_output.setDescription('If true, the measure will output timeseries data. If false, only run period totals.')
    timeseries_output.setDefaultValue(false)
    args << timeseries_output

    return args
  end

  # define the outputs that the measure will create
  def outputs
    outs = OpenStudio::Measure::OSOutputVector.new
    # this measure does not produce machine readable outputs with registerValue, return an empty list
    return outs
  end

  # This method is called on all reporting measures immediately before the translation to E+ IDF
  def modelOutputRequests(model, runner, user_arguments)
    timeseries_output = runner.getBoolArgumentValue('timeseries_output', user_arguments)

    # Get all heating and cooling coil names
    heating_coil_names = []
    cooling_coil_names = []
    water_equipment_names = []

    # Collect all hydronic coils directly from the model.
    # This captures zone reheat coils and airloop coils that were missed by the prior traversal.
    model.getCoilHeatingWaters.each do |coil|
      heating_coil_names << coil.name.get
    end

    model.getCoilCoolingWaters.each do |coil|
      cooling_coil_names << coil.name.get
    end

    # De-duplicate while preserving stable ordering for predictable plugin output.
    heating_coil_names = heating_coil_names.uniq.sort
    cooling_coil_names = cooling_coil_names.uniq.sort

    # Get all water use equipment names
    model.getWaterUseEquipments.each do |equipment|
      water_equipment_names << equipment.name.get
    end

    # Debug: log found equipment
    runner.registerInfo("Found #{heating_coil_names.size} heating coils: #{heating_coil_names.inspect}")
    runner.registerInfo("Found #{cooling_coil_names.size} cooling coils: #{cooling_coil_names.inspect}")
    runner.registerInfo("Found #{water_equipment_names.size} water equipment: #{water_equipment_names.inspect}")
    if heating_coil_names.empty? && cooling_coil_names.empty?
      runner.registerWarning('No hydronic heating or cooling coils were found in the model; coil energy outputs will be zero.')
    end

    # Create hashes for template rendering
    equipment_hash = {
      'heating_coils' => heating_coil_names,
      'cooling_coils' => cooling_coil_names,
      'water_equipment' => water_equipment_names
    }
    equipment_json = JSON.pretty_generate(equipment_hash)

    # python plugin variables for aggregated outputs
    heating_coil_var = OpenStudio::Model::PythonPluginVariable.new(model)
    heating_coil_var.setName('total_heating_coil_energy_glob')

    cooling_coil_var = OpenStudio::Model::PythonPluginVariable.new(model)
    cooling_coil_var.setName('total_cooling_coil_energy_glob')

    simultaneous_energy_var = OpenStudio::Model::PythonPluginVariable.new(model)
    simultaneous_energy_var.setName('simultaneous_energy_glob')

    hot_water_vol_var = OpenStudio::Model::PythonPluginVariable.new(model)
    hot_water_vol_var.setName('total_hot_water_volume_glob')

    drain_temp_var = OpenStudio::Model::PythonPluginVariable.new(model)
    drain_temp_var.setName('avg_drain_temperature_glob')

    # python plugin output variables
    heating_out_var = OpenStudio::Model::PythonPluginOutputVariable.new(heating_coil_var)
    heating_out_var.setName('total_heating_coil_energy')
    heating_out_var.setTypeofDatainVariable('Summed')
    heating_out_var.setUpdateFrequency('ZoneTimestep')
    heating_out_var.setUnits('J')

    cooling_out_var = OpenStudio::Model::PythonPluginOutputVariable.new(cooling_coil_var)
    cooling_out_var.setName('total_cooling_coil_energy')
    cooling_out_var.setTypeofDatainVariable('Summed')
    cooling_out_var.setUpdateFrequency('ZoneTimestep')
    cooling_out_var.setUnits('J')

    hot_water_out_var = OpenStudio::Model::PythonPluginOutputVariable.new(hot_water_vol_var)
    hot_water_out_var.setName('total_hot_water_volume')
    hot_water_out_var.setTypeofDatainVariable('Summed')
    hot_water_out_var.setUpdateFrequency('ZoneTimestep')
    hot_water_out_var.setUnits('m3')

    drain_temp_out_var = OpenStudio::Model::PythonPluginOutputVariable.new(drain_temp_var)
    drain_temp_out_var.setName('avg_drain_temperature')
    drain_temp_out_var.setTypeofDatainVariable('Average')
    drain_temp_out_var.setUpdateFrequency('ZoneTimestep')
    drain_temp_out_var.setUnits('C')

    simultaneous_out_var = OpenStudio::Model::PythonPluginOutputVariable.new(simultaneous_energy_var)
    simultaneous_out_var.setName('simultaneous_energy')
    simultaneous_out_var.setTypeofDatainVariable('Summed')
    simultaneous_out_var.setUpdateFrequency('ZoneTimestep')
    simultaneous_out_var.setUnits('J')

    # add regular output variables that reference the python plugin outputs
    # Note: Python plugin outputs are always requested at Timestep frequency for aggregation in run method
    out_vars = [
      'total_heating_coil_energy',
      'total_cooling_coil_energy',
      'total_hot_water_volume',
      'avg_drain_temperature',
      'simultaneous_energy'
    ]

    out_vars.each do |var_name|
      out_var = OpenStudio::Model::OutputVariable.new('PythonPlugin:OutputVariable', model)
      out_var.setKeyValue(var_name)
      out_var.setReportingFrequency('Timestep')
    end

    # add simulation output variables needed for the plugin for each coil and equipment
    heating_coil_names.each do |coil_name|
      out_var = OpenStudio::Model::OutputVariable.new('Heating Coil Heating Energy', model)
      out_var.setKeyValue(coil_name)
      out_var.setReportingFrequency('Timestep')
    end

    cooling_coil_names.each do |coil_name|
      out_var = OpenStudio::Model::OutputVariable.new('Cooling Coil Total Cooling Energy', model)
      out_var.setKeyValue(coil_name)
      out_var.setReportingFrequency('Timestep')
    end

    water_equipment_names.each do |equip_name|
      out_var = OpenStudio::Model::OutputVariable.new('Water Use Equipment Drain Water Temperature', model)
      out_var.setKeyValue(equip_name)
      out_var.setReportingFrequency('Timestep')

      out_var = OpenStudio::Model::OutputVariable.new('Water Use Equipment Total Volume', model)
      out_var.setKeyValue(equip_name)
      out_var.setReportingFrequency('Timestep')
    end

    # read in the template
    rsrcs = "#{File.dirname(__FILE__)}/resources"
    temp_path = "#{rsrcs}/python_plugin.py.erb"

    template = ''
    File.open(temp_path, 'r') do |file|
      template = file.read
    end

    # configure template with variable values
    renderer = ERB.new(template)
    py_out = renderer.result(binding)

    # write the python plugin file to resources dir
    plugin_dir = File.join(Dir.pwd, 'python_EMS')
    FileUtils.mkdir_p(plugin_dir) unless File.exist?(plugin_dir)
    plugin_path = File.join(plugin_dir, 'in.py')
    File.write(plugin_path, py_out)

    external_file = OpenStudio::Model::ExternalFile.getExternalFile(model, plugin_path)
    external_file = external_file.get

    # python plugin instance
    python_plugin_instance = OpenStudio::Model::PythonPluginInstance.new(external_file, 'WasteHeatRecoverySummary')
    python_plugin_instance.setName('Waste Heat Recovery Summary')
    python_plugin_instance.setRunDuringWarmupDays(true)

    return true
  end

  def get_timeseries_array(runner, sql, env_period, timestep, variable_name, key_value, num_timesteps, expected_units = nil, desired_units = nil)
    time_series_array = []
    time_series = sql.timeSeries(env_period, timestep, variable_name, key_value)
    if time_series.is_initialized
      time_series = time_series.get
      # Check the units
      unless expected_units.nil?
        unless time_series.units == expected_units
          runner.registerWarning("Expected units of #{expected_units} but got #{time_series.units} for #{variable_name}")
        end

        # Convert the units if desired
        if !desired_units.nil? && time_series.units != desired_units
          begin
            conversion = OpenStudio.convert(1.0, time_series.units, desired_units).get
            time_series = time_series * conversion
          rescue StandardError => e
            runner.registerWarning("Failed to convert units from #{time_series.units} to #{desired_units} for #{variable_name}: #{e.message}")
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

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments, user_arguments)
      return false
    end

    timeseries_output = runner.getBoolArgumentValue('timeseries_output', user_arguments)

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

    # get the weather file run period (as opposed to design day run period)
    ann_env_pd = nil
    sql.availableEnvPeriods.each do |env_pd|
      env_type = sql.environmentType(env_pd)
      if env_type.is_initialized && (env_type.get == (OpenStudio::EnvironmentType.new('WeatherRunPeriod')))
        ann_env_pd = env_pd
      end
    end

    if (ann_env_pd.nil?) || (ann_env_pd == false)
      runner.registerError('Cannot find a weather runperiod. Make sure you ran an annual simulation, not just the design days.')
      return false
    end

    # Get the timestep length
    steps_per_hour = if model.getSimulationControl.timestep.is_initialized
                       model.getSimulationControl.timestep.get.numberOfTimestepsPerHour
                     else
                       6 # default OpenStudio timestep if none specified
                     end

    # Get the annual hours simulated
    hrs_sim = 0
    if sql.hoursSimulated.is_initialized
      hrs_sim = sql.hoursSimulated.get
    else
      runner.registerError('An annual simulation was not run. Cannot summarize waste heat recovery.')
      return false
    end

    # Determine the number of timesteps
    num_ts = hrs_sim * steps_per_hour
    timestep_seconds = 3600.0 / steps_per_hour

    # Get timeseries data for heating, cooling, and simultaneous energy
    heating_ts = get_timeseries_array(runner, sql, ann_env_pd, 'Zone Timestep', 'PythonPlugin:OutputVariable', 'total_heating_coil_energy', num_ts, 'J', 'GJ')
    cooling_ts = get_timeseries_array(runner, sql, ann_env_pd, 'Zone Timestep', 'PythonPlugin:OutputVariable', 'total_cooling_coil_energy', num_ts, 'J', 'GJ')
    simultaneous_ts = get_timeseries_array(runner, sql, ann_env_pd, 'Zone Timestep', 'PythonPlugin:OutputVariable', 'simultaneous_energy', num_ts, 'J', 'GJ')
    waste_water_vol_ts = get_timeseries_array(runner, sql, ann_env_pd, 'Zone Timestep', 'PythonPlugin:OutputVariable', 'total_hot_water_volume', num_ts, 'm3')
    drain_temp_ts = get_timeseries_array(runner, sql, ann_env_pd, 'Zone Timestep', 'PythonPlugin:OutputVariable', 'avg_drain_temperature', num_ts, 'C')

    # Debug: log non-zero values
    runner.registerInfo("Heating timeseries non-zero values: #{heating_ts.count { |v| v != 0 }}")
    runner.registerInfo("Cooling timeseries non-zero values: #{cooling_ts.count { |v| v != 0 }}")
    runner.registerInfo("Simultaneous timeseries non-zero values: #{simultaneous_ts.count { |v| v != 0 }}")
    runner.registerInfo("Water volume timeseries non-zero values: #{waste_water_vol_ts.count { |v| v != 0 }}")
    runner.registerInfo("Drain temp timeseries non-zero values: #{drain_temp_ts.count { |v| v != 0 }}")

    # Calculate annual totals
    annual_heating_energy_gj = heating_ts.sum
    annual_cooling_energy_gj = cooling_ts.sum
    annual_simultaneous_energy_gj = simultaneous_ts.sum
    annual_waste_water_volume = waste_water_vol_ts.sum

    # Convert per-timestep energy to instantaneous capacity using the timestep duration.
    peak_heating_capacity_w = heating_ts.max.to_f * 1_000_000_000.0 / timestep_seconds
    peak_cooling_capacity_w = cooling_ts.max.to_f * 1_000_000_000.0 / timestep_seconds
    peak_simultaneous_capacity_w = simultaneous_ts.max.to_f * 1_000_000_000.0 / timestep_seconds
    
    # Calculate volume-weighted average drain temperature
    avg_drain_temp_weighted = 0.0
    if annual_waste_water_volume > 0
      weighted_temp_sum = waste_water_vol_ts.zip(drain_temp_ts).map { |vol, temp| vol * temp }.sum
      avg_drain_temp_weighted = weighted_temp_sum / annual_waste_water_volume
    end
    
    # Calculate recoverable heat (assuming 5C temperature difference and water heat capacity of 4.18 kJ/kg·K)
    # Volume in m3 * 1000 kg/m3 * 4.18 kJ/kg·K * 5K = Volume * 20.9 GJ
    temp_diff_k = 5.0
    water_density_kg_m3 = 1000.0
    water_heat_capacity_kj_kg_k = 4.18
    recoverable_heat_gj = annual_waste_water_volume * water_density_kg_m3 * water_heat_capacity_kj_kg_k * temp_diff_k / 1_000_000

    # Calculate percentages
    heating_simultaneous_pct = annual_heating_energy_gj > 0 ? (annual_simultaneous_energy_gj / annual_heating_energy_gj) * 100 : 0
    cooling_simultaneous_pct = annual_cooling_energy_gj > 0 ? (annual_simultaneous_energy_gj / annual_cooling_energy_gj) * 100 : 0

    # Register values
    runner.registerValue('annual_heating_coil_energy_gj', annual_heating_energy_gj, 'GJ')
    runner.registerValue('annual_cooling_coil_energy_gj', annual_cooling_energy_gj, 'GJ')
    runner.registerValue('annual_simultaneous_energy_gj', annual_simultaneous_energy_gj, 'GJ')
    runner.registerValue('simultaneous_percent_of_total_heating', heating_simultaneous_pct, '%')
    runner.registerValue('simultaneous_percent_of_total_cooling', cooling_simultaneous_pct, '%')
    runner.registerValue('peak_heating_capacity_w', peak_heating_capacity_w, 'W')
    runner.registerValue('peak_cooling_capacity_w', peak_cooling_capacity_w, 'W')
    runner.registerValue('peak_simultaneous_capacity_w', peak_simultaneous_capacity_w, 'W')
    runner.registerValue('annual_waste_water_volume_m3', annual_waste_water_volume, 'm3')
    runner.registerValue('annual_avg_drain_temperature_c', avg_drain_temp_weighted, 'C')
    runner.registerValue('annual_recoverable_drain_heat_gj', recoverable_heat_gj, 'GJ')

    # Report summary message
    summary_text = "
    WASTE HEAT RECOVERY SUMMARY
    ==========================
    Annual Heating Coil Energy: #{annual_heating_energy_gj.round(2)} GJ
    Annual Cooling Coil Energy: #{annual_cooling_energy_gj.round(2)} GJ
    Annual Simultaneous Energy: #{annual_simultaneous_energy_gj.round(2)} GJ

    Peak Heating Capacity: #{peak_heating_capacity_w.round(0)} W
    Peak Cooling Capacity: #{peak_cooling_capacity_w.round(0)} W
    Peak Simultaneous Capacity: #{peak_simultaneous_capacity_w.round(0)} W
    
    Simultaneous as % of Heating: #{heating_simultaneous_pct.round(2)}%
    Simultaneous as % of Cooling: #{cooling_simultaneous_pct.round(2)}%
    
    Annual Waste Water Volume: #{annual_waste_water_volume.round(2)} m3
    Annual Avg Drain Temperature (Volume-Weighted): #{avg_drain_temp_weighted.round(2)} C
    
    Recoverable Heat Potential (5C differential): #{recoverable_heat_gj.round(2)} GJ
    "
    runner.registerInfo(summary_text)

    # close the sql file
    sql.close

    return true
  end
end

# register the measure to be used by the application
WasteHeatRecoverySummary.new.registerWithApplication
