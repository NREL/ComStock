# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
require 'json'
require 'csv'

require "#{File.dirname(__FILE__)}/resources/os_lib_heat_transfer"
require "#{File.dirname(__FILE__)}/resources/os_lib_scout_hvac"
require "#{File.dirname(__FILE__)}/resources/os_lib_scout_meters"
require "#{File.dirname(__FILE__)}/resources/os_lib_scout_buildingmeters"

# start the measure
class ScoutLoadsSummary < OpenStudio::Measure::ReportingMeasure
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return "Scout Loads Summary"
  end

  # human readable description
  def description
    return "Breaks the demand (heat gains and losses) down by sub-end-use (walls, windows, roof, etc.) and supply (things in building consuming energy) down by sub-end-use (hot water pumps, chilled water pumps, etc.) for use in Scout."
  end

  # human readable description of modeling approach
  def modeler_description
    return "Uses zone- and surface- level output variables to break heat gains/losses down by building component.  Uses a series of custom meters to disaggregate the EnergyPlus end uses into sub-end-uses.  Warning: resulting sql files will very large because of the number of output variables and meters.  Measure will output results on a timestep basis if requested."
  end

  # define the arguments that the user will input
  def arguments(model = nil)
    args = OpenStudio::Measure::OSArgumentVector.new

    report_timeseries_data = OpenStudio::Measure::OSArgument.makeBoolArgument('report_timeseries_data', true)
    report_timeseries_data.setDisplayName('Report timeseries data to csv file')
    report_timeseries_data.setDefaultValue(false)
    args << report_timeseries_data

    enable_supply_side_reporting = OpenStudio::Measure::OSArgument.makeBoolArgument('enable_supply_side_reporting', true)
    enable_supply_side_reporting.setDisplayName('Enable/disable supply side reporting')
    enable_supply_side_reporting.setDefaultValue(false)
    args << enable_supply_side_reporting

    debug_mode = OpenStudio::Measure::OSArgument.makeBoolArgument('debug_mode', true)
    debug_mode.setDisplayName('Enable extra variables for debugging zone loads')
    debug_mode.setDefaultValue(false)
    args << debug_mode

    return args
  end

  # add any outout variable requests here
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    result = OpenStudio::IdfObjectVector.new

    freq = 'timestep'

    # heat transfer outputs
    runner.registerInfo("Requesting output variables for heat transfer")
    OsLib_HeatTransfer.heat_transfer_outputs.each do |output|
      var = "Output:Variable,,#{output},#{freq};"
      # runner.registerInfo(var)
      result << OpenStudio::IdfObject.load(var).get
    end

    # Get model
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Cannot find last model in energyPlusOutputRequests, cannot request outputs for HVAC equipment.')
      return result
    end
    model = model.get

    # Request the unique set of outputs
    runner.registerInfo("Requesting custom meters for HVAC and other end uses")
    bldg_meters = OsLib::Scout::BuildingMeters::BuildingMeterSet.new(num_ts=1) # initialize values to a 1-item array for speed
    bldg_meters.populate_supply_meter_details(model)
    bldg_meters.all_supply_meter_idf_objects(model).each do |meter_idf|
      result << meter_idf
    end

    result
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # Get the last model
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Cannot find last model.')
      return false
    end
    model = model.get

    # Get the last sql file
    sql = runner.lastEnergyPlusSqlFile
    if sql.empty?
      runner.registerError('Cannot find last sql file.')
      return false
    end
    sql = sql.get
    model.setSqlFile(sql)

    # Get input arguments
    report_timeseries_data = runner.getBoolArgumentValue('report_timeseries_data', user_arguments)
    enable_supply_side_reporting = runner.getBoolArgumentValue('enable_supply_side_reporting', user_arguments)
    debug_mode = runner.getBoolArgumentValue('debug_mode', user_arguments)

    # Define variables
    joules = 'J'
    watts = 'W'
    celsius = 'C'

    # Set the frequency for analysis.
    # Must match frequency requested in energyPlusOutputRequests.
    freq = 'Zone Timestep'

    # Get the annual run period
    ann_env_pd = nil
    sql.availableEnvPeriods.each do |env_pd|
      env_type = sql.environmentType(env_pd)
      if env_type.is_initialized
        if env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod')
          ann_env_pd = env_pd
        end
      end
    end
    unless ann_env_pd
      runner.registerError('An annual simulation was not run. Cannot get annual timeseries data')
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
      runner.registerError('An annual simulation was not run. Cannot summarize annual heat transfer for Scout.')
      return false
    end

    # Determine the number of timesteps
    num_ts = hrs_sim * steps_per_hour
    runner.registerInfo("Getting data from #{hrs_sim} hrs at #{steps_per_hour} steps/hr = #{num_ts} timesteps")

    # Get the model year
    year = model.yearDescription.get.assumedYear
    start_dt = Time.new(year, 1, 1)

    # Read the custom meters for the Scout supply side sub-end-uses from sql file
    bldg_meters = OsLib::Scout::BuildingMeters::BuildingMeterSet.new(num_ts)
    bldg_meters.populate_supply_meter_details(model)
    bldg_meters.populate_supply_meter_timeseries(runner, sql, ann_env_pd, freq, num_ts, joules)

    # Get the annual heating & cooling timeseries total per fuel type
    tot_tses = {
        'heating' => Vector.elements(Array.new(num_ts, 0.0)),
        'cooling' => Vector.elements(Array.new(num_ts, 0.0))
    }
    fuel_type_tses = {
        ['heating', 'electricity'] => Vector.elements(Array.new(num_ts, 0.0)),
        ['heating', 'natural_gas'] => Vector.elements(Array.new(num_ts, 0.0)),
        ['heating', 'district_heating'] => Vector.elements(Array.new(num_ts, 0.0)),
        ['heating', 'district_cooling'] => Vector.elements(Array.new(num_ts, 0.0)),
        ['cooling', 'electricity'] => Vector.elements(Array.new(num_ts, 0.0)),
        ['cooling', 'natural_gas'] => Vector.elements(Array.new(num_ts, 0.0)),
        ['cooling', 'district_heating'] => Vector.elements(Array.new(num_ts, 0.0)),
        ['cooling', 'district_cooling'] => Vector.elements(Array.new(num_ts, 0.0))
    }
    ['heating', 'cooling'].each do |end_use|
      ['electricity', 'natural_gas', 'district_heating', 'district_cooling'].each do |fuel_type|
        bldg_meters.end_use.supply(end_use).sub_end_use.each do |meter|
          tot_tses[end_use] += Vector.elements(meter.vals)
          fuel_type_tses[[end_use, meter.fuel_type]] += Vector.elements(meter.vals)
        end
      end
    end

    # Calculate heating & cooling timeseries percentage by fuel type
    fuel_type_pct_tses = {}
    fuel_type_tses.each_pair do |end_use_fuel_type, fuel_type_ts|
      end_use = end_use_fuel_type[0]
      ann_pcts = []
      fuel_type_ts.to_a.zip(tot_tses[end_use].to_a).each do |ft_val, tot_val|
        if tot_val.zero?
          ann_pcts << 0.0
        else
          ann_pcts << ft_val / tot_val
        end
      end
      fuel_type_pct_tses[end_use_fuel_type] = ann_pcts
    end

    # Get Scout demand side totals, which are heating/cooling demand by component (walls, roofs, etc.)
    debug_bldg_heat_transfer_vectors = []
    total_building_calculated_energy_balance = Vector.elements(Array.new(num_ts, 0.0))
    total_building_true_energy_balance = Vector.elements(Array.new(num_ts, 0.0))
    model.getThermalZones.each do |zone|
      # Get the heat transfer broken out by component
      heat_transfer_vectors = OsLib_HeatTransfer.thermal_zone_heat_transfer_vectors(runner, zone, sql, freq, debug_mode)

      # Save zone level heat transfer vectors for debugging
      heat_transfer_vectors.each do |vector_name, vector_vals|
        debug_bldg_heat_transfer_vectors << ["#{zone.name.get}|#{vector_name}"] + vector_vals.to_a if vector_vals.kind_of?(Vector)
      end

      # Sum energy balance for validation
      total_building_calculated_energy_balance += heat_transfer_vectors['Calc Energy Balance']
      total_building_true_energy_balance += heat_transfer_vectors['True Energy Balance']

      # Scout heating/cooling supply and demand breakdown
      zone_meters = OsLib::Scout::Meters::MeterSet.new(num_ts)
      hvac_transfer_vals = heat_transfer_vectors['HVAC (All) Heat Transfer Energy'].to_a
      hvac_transfer_vals.each_with_index do |hvac_energy_transfer, i|
        if hvac_energy_transfer > 0 # heating
          # during heating, all heat gains are "reducing" the heating that the HVAC needs to provide, so reverse sign
          zone_meters.end_use.demand('heating').sub_end_use('people_gain').first.vals[i] = -1.0 * (heat_transfer_vectors['Zone People Convective Heating Energy'].to_a[i] + heat_transfer_vectors['Zone People Delayed Convective Heating Energy'].to_a[i])
          zone_meters.end_use.demand('heating').sub_end_use('lighting_gain').first.vals[i] = -1.0 * (heat_transfer_vectors['Zone Lights Convective Heating Energy'].to_a[i] + heat_transfer_vectors['Zone Lights Delayed Convective Heating Energy'].to_a[i])
          zone_meters.end_use.demand('heating').sub_end_use('equipment_gain').first.vals[i] = -1.0 * (heat_transfer_vectors['Zone Equipment Instantaneous Convective Internal Gains'].to_a[i] + heat_transfer_vectors['Zone Equipment Delayed Convective Internal Gains'].to_a[i])
          zone_meters.end_use.demand('heating').sub_end_use('wall').first.vals[i] = -1.0 * heat_transfer_vectors['Zone Exterior Wall Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('heating').sub_end_use('foundation_wall').first.vals[i] = -1.0 * heat_transfer_vectors['Zone Exterior Foundation Wall Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('heating').sub_end_use('roof').first.vals[i] = -1.0 * heat_transfer_vectors['Zone Exterior Roof Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('heating').sub_end_use('floor').first.vals[i] = -1.0 * heat_transfer_vectors['Zone Exterior Floor Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('heating').sub_end_use('ground').first.vals[i] = -1.0 * heat_transfer_vectors['Zone Exterior Ground Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('heating').sub_end_use('windows_conduction').first.vals[i] = -1.0 * heat_transfer_vectors['Zone Exterior Window Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('heating').sub_end_use('doors_conduction').first.vals[i] = -1.0 * heat_transfer_vectors['Zone Exterior Door Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('heating').sub_end_use('windows_solar').first.vals[i] = -1.0 * heat_transfer_vectors['Zone Windows Radiation Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('heating').sub_end_use('infiltration').first.vals[i] = -1.0 * heat_transfer_vectors['Zone Infiltration Gains'].to_a[i]
          zone_meters.end_use.demand('heating').sub_end_use('ventilation').first.vals[i] = -1.0 * heat_transfer_vectors['Zone Ventilation Gains'].to_a[i]
        elsif hvac_energy_transfer < 0 # cooling
          # during cooling, all heat gains are "increasing" the cooling that the HVAC needs to provide, so sign matches convention
          zone_meters.end_use.demand('cooling').sub_end_use('people_gain').first.vals[i] = heat_transfer_vectors['Zone People Convective Heating Energy'].to_a[i] + heat_transfer_vectors['Zone People Delayed Convective Heating Energy'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('lighting_gain').first.vals[i] = heat_transfer_vectors['Zone Lights Convective Heating Energy'].to_a[i] + heat_transfer_vectors['Zone Lights Delayed Convective Heating Energy'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('equipment_gain').first.vals[i] = heat_transfer_vectors['Zone Equipment Instantaneous Convective Internal Gains'].to_a[i] + heat_transfer_vectors['Zone Equipment Delayed Convective Internal Gains'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('wall').first.vals[i] = heat_transfer_vectors['Zone Exterior Wall Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('foundation_wall').first.vals[i] = heat_transfer_vectors['Zone Exterior Foundation Wall Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('roof').first.vals[i] = heat_transfer_vectors['Zone Exterior Roof Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('floor').first.vals[i] = heat_transfer_vectors['Zone Exterior Floor Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('ground').first.vals[i] = heat_transfer_vectors['Zone Exterior Ground Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('windows_conduction').first.vals[i] = heat_transfer_vectors['Zone Exterior Window Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('doors_conduction').first.vals[i] = heat_transfer_vectors['Zone Exterior Door Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('windows_solar').first.vals[i] = heat_transfer_vectors['Zone Windows Radiation Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('infiltration').first.vals[i] = heat_transfer_vectors['Zone Infiltration Gains'].to_a[i]
          zone_meters.end_use.demand('cooling').sub_end_use('ventilation').first.vals[i] = heat_transfer_vectors['Zone Ventilation Gains'].to_a[i]
        else # hvac_energy_transfer == 0, floating
          # Heat transfer into/out of the zone at this time is not accounted for by HVAC energy
          # Track total energy in and out to see how much load occurs during deadband times
          zone_meters.end_use.demand('floating').sub_end_use('people_gain').first.vals[i] = heat_transfer_vectors['Zone People Convective Heating Energy'].to_a[i] + heat_transfer_vectors['Zone People Delayed Convective Heating Energy'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('lighting_gain').first.vals[i] = heat_transfer_vectors['Zone Lights Convective Heating Energy'].to_a[i] + heat_transfer_vectors['Zone Lights Delayed Convective Heating Energy'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('equipment_gain').first.vals[i] = heat_transfer_vectors['Zone Equipment Instantaneous Convective Internal Gains'].to_a[i] + heat_transfer_vectors['Zone Equipment Delayed Convective Internal Gains'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('wall').first.vals[i] = heat_transfer_vectors['Zone Exterior Wall Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('foundation_wall').first.vals[i] = heat_transfer_vectors['Zone Exterior Foundation Wall Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('roof').first.vals[i] = heat_transfer_vectors['Zone Exterior Roof Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('floor').first.vals[i] = heat_transfer_vectors['Zone Exterior Floor Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('ground').first.vals[i] = heat_transfer_vectors['Zone Exterior Ground Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('windows_conduction').first.vals[i] = heat_transfer_vectors['Zone Exterior Window Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('doors_conduction').first.vals[i] = heat_transfer_vectors['Zone Exterior Door Convection Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('windows_solar').first.vals[i] = heat_transfer_vectors['Zone Windows Radiation Heat Transfer Energy'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('infiltration').first.vals[i] = heat_transfer_vectors['Zone Infiltration Gains'].to_a[i]
          zone_meters.end_use.demand('floating').sub_end_use('ventilation').first.vals[i] = heat_transfer_vectors['Zone Ventilation Gains'].to_a[i]
        end
      end

      # Add all of the heat transfer components for this zone to the whole building totals
      zone_meters.end_use.demand.each do |demand_end_use|
        demand_end_use.sub_end_use.each do |sub_end_use_meter|
          eu = sub_end_use_meter.end_use
          seu = sub_end_use_meter.sub_end_use
          vals = sub_end_use_meter.vals
          # Apportion each of the end uses between all fuel types
          fuel_type_pct_tses.each_pair do |end_use_fuel_type, ann_pcts|
            fuel_type = end_use_fuel_type[1]
            new_vals = []
            vals.zip(ann_pcts).each do |val, pct|
              new_vals << val * pct
            end
            bldg_meters.end_use.demand(eu).add_vals_to_sub_end_use(seu, fuel_type, new_vals)
          end
        end
      end
    end

    # Report out total building load energy balance error metrics
    debug_bldg_heat_transfer_vectors << ['Total Building Calculated Energy Balance'] + total_building_calculated_energy_balance.to_a
    debug_bldg_heat_transfer_vectors << ['Total Building True Energy Balance'] + total_building_true_energy_balance.to_a
    total_building_energy_balance_error = OsLib_HeatTransfer.ts_error_between_vectors(total_building_calculated_energy_balance, -1 * total_building_true_energy_balance, 4) # Reverse sign of one before comparing
    total_building_energy_balance_annual_gain_error = OsLib_HeatTransfer.annual_heat_gain_error_between_vectors(total_building_calculated_energy_balance, -1 * total_building_true_energy_balance, 4) # Reverse sign of one before comparing
    total_building_energy_balance_annual_loss_error = OsLib_HeatTransfer.annual_heat_loss_error_between_vectors(total_building_calculated_energy_balance, -1 * total_building_true_energy_balance, 4) # Reverse sign of one before comparing
    runner.registerInfo("Building Annual Energy Balance Gain Error is #{total_building_energy_balance_annual_gain_error * 100}%, Annual Energy Balance Loss Error is #{total_building_energy_balance_annual_loss_error * 100}%")
    runner.registerValue('building_annual_energy_balance_gain_error_pct', total_building_energy_balance_annual_gain_error * 100)
    runner.registerValue('building_annual_energy_balance_loss_error_pct', total_building_energy_balance_annual_loss_error * 100)

    # Report supply side sub-end-use totals
    if enable_supply_side_reporting
      runner.registerInfo("Supply Side Annual Totals")
      bldg_meters.end_use.supply.each do |end_use|
        end_use.sub_end_use.each do |mtr|
          runner.registerValue(mtr.register_value_name, mtr.sum_vals('GJ'), 'GJ')
        end
      end
    else
      runner.registerInfo("Supply side reporting was not requested, therefore will not be outputted.")
    end

    # Report demand side sub-end-use totals
    runner.registerInfo("Demand Side Annual Totals")
    bldg_meters.end_use.demand.each do |end_use|
      end_use.sub_end_use.each do |mtr|
        runner.registerValue(mtr.register_value_name, mtr.sum_vals('GJ'), 'GJ')
      end
    end

    # Write timeseries sub end use supply and demand data if requested
    if report_timeseries_data
      runner.registerInfo("Writing Requested Timeseries Data")
      ts_data = []

      # Supply side sub-end-use timeseries
      if enable_supply_side_reporting
        bldg_meters.end_use.supply.each do |end_use|
          end_use.sub_end_use.each do |mtr|
            ts_data << [mtr.register_value_name] + mtr.vals
          end
        end
      else
        runner.registerInfo("Supply side reporting was not requested, therefore will not be outputted.")
      end

      # Demand side sub-end-use totals
      bldg_meters.end_use.demand.each do |end_use|
        end_use.sub_end_use.each do |mtr|
          ts_data << [mtr.register_value_name] + mtr.vals
        end
      end

      # Write to file
      CSV.open('./scout_timeseries.csv', 'w') do |csv|
        ts_data.transpose.each do |row|
          csv << row
        end
      end

      # Write zone vectors to file
      CSV.open('./zone_timeseries_with_datetime_index.csv', 'w') do |csv|
        debug_bldg_heat_transfer_vectors.transpose.each_with_index do |row,i|
          i == 0 ? idx = 'datetime_index' : idx = start_dt + 3600.0 * (24.0 + (i.to_f/4))
          row = row.unshift(idx)
          csv << row
        end
      end
    else
      runner.registerInfo("Timeseries data .csvs not requested.")
    end

    # Close the sql file
    sql.close

    return true
  end
end

# this allows the measure to be use by the application
ScoutLoadsSummary.new.registerWithApplication
