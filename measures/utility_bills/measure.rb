# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

require 'csv'
require 'date'
require 'json'
require 'open3'


#start the measure
class UtilityBills < OpenStudio::Measure::ReportingMeasure
  # human readable name
  def name
    return "Utility Bills"
  end

  # human readable description
  def description
    return "Calculates utility bills for the model based on location."
  end

  # human readable description of modeling approach
  def modeler_description
    return "Calculates utility bills using the PySAM API and commercial rates from the NREL Utility Rate Database or EIA data."
  end

  # define the arguments that the user will input
  def arguments(model = nil)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    result = OpenStudio::IdfObjectVector.new

    # Request hourly data for fuel types with hourly bill calculations
    fuel_types = ['Electricity'] # 'NaturalGas', 'DistrictCooling', 'DistrictHeating', 'FuelOilNo2', 'Propane'
    fuel_types.each do |fuel_type|
      result << OpenStudio::IdfObject.load("Output:Meter,#{fuel_type}:Facility,Hourly;").get
    end

    return result
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # Get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError("Could not load last OpenStudio model, cannot apply measure.")
      return false
    end
    model = model.get

    sql = runner.lastEnergyPlusSqlFile
    if sql.empty?
      runner.registerError("Cannot find last sql file.")
      return false
    end
    sql = sql.get
    model.setSqlFile(sql)

    # Define run directory location
    run_dir_typical = File.absolute_path(File.join(Dir.pwd, 'run'))
    run_dir_comstock = File.absolute_path(File.join(Dir.pwd, '..'))
    if File.exist?(run_dir_typical)
      run_dir = run_dir_typical
    elsif File.exist?(run_dir_comstock)
      run_dir = run_dir_comstock
    else
      runner.registerError("Could not find directory with EnergyPlus output, cannot extract timeseries results")
      return false
    end

    # Determine the model year
    year_object = model.getYearDescription
    if year_object.calendarYear.is_initialized
      year = year_object.calendarYear.get
    else
      year = 2009
    end

    # Get the weather file run period
    ann_env_pd = nil
    sql.availableEnvPeriods.each do |env_pd|
      env_type = sql.environmentType(env_pd)
      if env_type.is_initialized
        if env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod')
          ann_env_pd = env_pd
        end
      end
    end
    if ann_env_pd == false
      runner.registerError("Can't find a weather runperiod, make sure you ran an annual simulation, not just the design days.")
      return false
    end

    # Electricity Bill

    # Get hourly electricity values
    env_period_ix_query = "SELECT EnvironmentPeriodIndex FROM EnvironmentPeriods WHERE EnvironmentName='#{ann_env_pd}'"
    env_period_ix = sql.execAndReturnFirstInt(env_period_ix_query).get
    electricity_query = "SELECT VariableValue FROM ReportMeterData WHERE ReportMeterDataDictionaryIndex IN (SELECT ReportMeterDataDictionaryIndex FROM ReportMeterDataDictionary WHERE VariableTYpe='Sum' AND VariableName='Electricity:Facility' AND ReportingFrequency='Hourly' AND VariableUnits='J') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
    hourly_electricity_kwh = []
    unless sql.execAndReturnVectorOfDouble(electricity_query).get.empty?
      values = sql.execAndReturnVectorOfDouble(electricity_query).get
      values.each do |val|
        hourly_electricity_kwh << OpenStudio.convert(val, 'J', 'kWh').get # hourly data
      end
    end
    # Get min and peak demand for rates with qualifiers
    tot_elec_kwh = hourly_electricity_kwh.sum.round
    min_kw = hourly_electricity_kwh.min.round
    max_kw = hourly_electricity_kwh.max.round

    # Get the census tract
    census_tract = model.getBuilding.additionalProperties.getFeatureAsString('nhgis_tract_gisjoin')
    if census_tract.empty?
      runner.registerError('Cannot find nhgis_tract_gisjoin for building, cannot calculate electricity bills.')
      return false
    end
    census_tract = census_tract.get

    # Get the state abbreviation
    state_abbreviation = model.getBuilding.additionalProperties.getFeatureAsString('state_abbreviation')
    if state_abbreviation.empty?
      runner.registerError('Cannot find state_abbreviation for building, cannot calculate electricity bills.')
      return false
    end
    state_abbreviation = state_abbreviation.get

    # Load the tract to electric utility EIA ID mapping
    tract_to_elec_util_path = File.join(File.dirname(__FILE__), 'resources', 'tract_to_elec_util.csv')
    tract_to_elec_util = {}
    CSV.foreach(tract_to_elec_util_path) do |row|
      tract_to_elec_util[row[0]] = row[1]
    end

    # Look up the utility EIA ID based on the census tract
    elec_eia_id = tract_to_elec_util[census_tract]
    unless elec_eia_id.nil?
      runner.registerValue('electricity_utility_eia_id', elec_eia_id)
    else
      runner.registerWarning("No electric utility for census tract #{census_tract}, using EIA average electric price.")
    end

    # Find all the electric rates for this utility
    all_rates = Dir.glob(File.join(File.dirname(__FILE__), "resources/elec_rates/#{elec_eia_id}/*.json"))
    if all_rates.size > 0
      runner.registerInfo("Found #{all_rates.size} URDB electric rates for EIA utility #{elec_eia_id}.")
      use_urdb_rates = true
    else
      unless elec_eia_id.nil?
        runner.registerWarning("No URDB electric rates found for EIA utility #{elec_eia_id}, using EIA average electric price.")
        use_urdb_rates = false
      end
    end

    # Downselect to applicable rates based on kW and kWh limits
    applicable_rates = []
    all_rates.each_with_index do |rate_path, i|
      # Load the rate data
      rate = JSON.parse(File.read(rate_path))
      rate_name = rate['name']
      rate_id = rate['label']

      if rate.has_key?('peakkwcapacitymin')
        if min_kw < rate['peakkwcapacitymin']
          runner.registerInfo("Rate #{rate_name} is not applicable because the building min demand of #{min_kw} kW is below minimum threshold of #{rate['peakkwcapacitymin']} kW.")
          next
        end
      end

      if rate.has_key?('peakkwcapacitymax')
        if max_kw > rate['peakkwcapacitymax']
          runner.registerInfo("Rate #{rate_name} is not applicable because the building max demand of #{max_kw} kW is above maximum threshold of #{rate['peakkwcapacitymax']} kW.")
          next
        end
      end

      if rate.has_key?('peakkwhusagemin')
        if tot_elec_kwh < rate['peakkwhusagemin']
          runner.registerInfo("Rate #{rate_name} is not applicable because the building annual energy #{tot_elec_kwh} kWh is below minimum threshold of #{rate['peakkwhusagemin']} kWh.")
          next
        end
      end

      if rate.has_key?('peakkwhusagemax')
        if tot_elec_kwh > rate['peakkwhusagemax']
          runner.registerInfo("Rate #{rate_name} is not applicable because the building annual energy #{max} kWh is above maximum threshold of #{rate['peakkwhusagemax']} kWh.")
          next
        end
      end

      # Rate is applicable to this building
      runner.registerInfo("Rate #{rate_name} is applicable.")
      applicable_rates << File.expand_path(rate_path)
    end

    # Ensure at least one rate is applicable to this building
    if all_rates.size > 0 && applicable_rates.size.zero?
      use_urdb_rates = false
      runner.registerWarning("No URDB electric rates were applicable to this building, using EIA average electric price.")
    end

    # Calculate bills using either URDB rates or EIA average price
    elec_bills = []
    if use_urdb_rates
      # Write the hourly kWh to CSV
      elec_csv_path = File.expand_path("#{run_dir}/electricity_hourly.csv")
      CSV.open(elec_csv_path, "wb") do |csv|
        hourly_electricity_kwh.each do |kwh|
          csv << [kwh.round(3)]
        end
      end

      # Get the average annual electric rate increase from 2013 to 2022 to attempt to make rates more current
      elec_ann_incr_path = File.join(File.dirname(__FILE__), 'resources', 'eia_com_elec_avg_yrly_rate_increase.json')
      elec_ann_incr = JSON.parse(File.read(elec_ann_incr_path))[state_abbreviation]

      # Calculate the bills for each applicable electric rate using the PySAM API via python
      calc_elec_bill_py_path = File.join(File.dirname(__FILE__), 'resources', 'calc_elec_bill.py')
      applicable_rates.each_with_index do |rate_path, i|
        # Load the rate data
        rate = JSON.parse(File.read(rate_path))
        rate_name = rate['name']
        rate_start_date = rate['startdate']
        if rate_start_date
          rate_start_year = Time.at(1318996912).utc.to_datetime.to_date.year
        else
          rate_start_year = 2013
          runner.registerWarning("#{rate_name} listed no start date, assuming #{rate_start_year}")
        end

        runner.registerInfo("Calculating bills for #{rate_name}")

        # Call calc_elec_bill.py
        command = "python #{calc_elec_bill_py_path} #{elec_csv_path} #{rate_path}"
        stdout_str, stderr_str, status = Open3.capture3(command)
        if status.success?
          pysam_out = JSON.parse(stdout_str)
          # Adjust the rate for price increases using state averages
          n_yr = 2022 - rate_start_year
          pct_inc = n_yr * elec_ann_incr
          total_utility_bill_dollars_base_yr = pysam_out['total_utility_bill_dollars'].round.to_i
          total_utility_bill_dollars_2022 = (total_utility_bill_dollars_base_yr * (1.0 + pct_inc)).round.to_i
          # runner.registerInfo("Adjusting bill from #{rate_name} from #{rate_start_year} to 2022 assuming #{pct_inc} increase.")
          # Register the resulting bill and associated rate name
          runner.registerValue("electricity_rate_#{i+1}_name", rate_name)
          runner.registerValue("electricity_rate_#{i+1}_bill_dollars", total_utility_bill_dollars_2022)
          elec_bills << total_utility_bill_dollars_2022
        else
          runner.registerError("Error running PySAM: #{command}")
          runner.registerError("stdout: #{stdout_str}")
          runner.registerError("stderr: #{stderr_str}")
          return false
        end
      end

      # TODO check for outliers

      # TODO report start or end date or latest revision date of each rate

      # TODO if there are many rates, use newer rates only
    else
      elec_prices_path = File.join(File.dirname(__FILE__), 'resources', 'eia_com_elec_prices_dol_per_kwh_2022.json')
      elec_rate_dollars_per_kwh = JSON.parse(File.read(elec_prices_path))[state_abbreviation]
      total_elec_utility_bill_dollars = (tot_elec_kwh * elec_rate_dollars_per_kwh).round.to_i
      runner.registerValue("electricity_rate_1_name", "EIA 2022 Average Commercial Electric Price for #{state_abbreviation}")
      runner.registerValue("electricity_rate_1_bill_dollars", total_elec_utility_bill_dollars)
      elec_bills << total_elec_utility_bill_dollars
    end

    # Calculate the average annual bill across all applicable electric rates
    avg_elec_bill = (elec_bills.sum(0.0) / elec_bills.size).round.to_i
    runner.registerValue('electricity_average_bill_dollars', avg_elec_bill)

    # Natural Gas Bill
    if sql.naturalGasTotalEndUses.is_initialized
      tot_kbtu = OpenStudio.convert(sql.naturalGasTotalEndUses.get, 'GJ', 'kBtu').get
      if tot_kbtu > 0
        prices_path = File.join(File.dirname(__FILE__), 'resources', 'eia_com_gas_prices_dol_per_kbtu_2022.json')
        dollars_per_kbtu = JSON.parse(File.read(prices_path))[state_abbreviation]
        utility_bill_dollars = (tot_kbtu * dollars_per_kbtu).round.to_i
        runner.registerValue("natural_gas_rate_1_name", "EIA 2022 Average Commercial Natural Gas Price for #{state_abbreviation}")
        runner.registerValue("natural_gas_rate_1_bill_dollars", utility_bill_dollars)
      end
    end

    # Propane Bill
    if sql.propaneTotalEndUses.is_initialized
      tot_kbtu = OpenStudio.convert(sql.propaneTotalEndUses.get, 'GJ', 'kBtu').get
      if tot_kbtu > 0
        prices_path = File.join(File.dirname(__FILE__), 'resources', 'eia_res_propane_prices_dol_per_kbtu_2022.json')
        dollars_per_kbtu = JSON.parse(File.read(prices_path))[state_abbreviation]
        utility_bill_dollars = (tot_kbtu * dollars_per_kbtu).round.to_i
        runner.registerValue("propane_rate_1_name", "EIA 2022 Average Residential Propane Price for #{state_abbreviation}")
        runner.registerValue("propane_rate_1_bill_dollars", utility_bill_dollars)
      end
    end

    # Fuel Oil Bill
    if sql.fuelOilNo2TotalEndUses.is_initialized
      tot_kbtu = OpenStudio.convert(sql.fuelOilNo2TotalEndUses.get, 'GJ', 'kBtu').get
      if tot_kbtu > 0
        prices_path = File.join(File.dirname(__FILE__), 'resources', 'eia_res_fuel_oil_prices_dol_per_kbtu_2022.json')
        dollars_per_kbtu = JSON.parse(File.read(prices_path))[state_abbreviation]
        utility_bill_dollars = (tot_kbtu * dollars_per_kbtu).round.to_i
        runner.registerValue("fuel_oil_rate_1_name", "EIA 2022 Average Residential Fuel Oil Price for #{state_abbreviation}")
        runner.registerValue("fuel_oil_rate_1_bill_dollars", utility_bill_dollars)
      end
    end

    # District Heating Bills
    # TODO have not found any source of rates beyond data for individual utilities
    if sql.districtHeatingTotalEndUses.is_initialized
      tot_kbtu = OpenStudio.convert(sql.districtHeatingTotalEndUses.get, 'GJ', 'kBtu').get
      if tot_kbtu > 0
        runner.registerWarning('District heating utility bills are not yet calculated.')
      end
    end

    # District Cooling Bills
    # TODO have not found any source of rates beyond data for individual utilities
    if sql.districtCoolingTotalEndUses.is_initialized
      tot_kbtu = OpenStudio.convert(sql.districtCoolingTotalEndUses.get, 'GJ', 'kBtu').get
      if tot_kbtu > 0
        runner.registerWarning('District cooling utility bills are not yet calculated.')
      end
    end


    return true
  end

end

# register the measure to be used by the application
UtilityBills.new.registerWithApplication
