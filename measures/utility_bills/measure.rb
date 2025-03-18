# ComStock™, Copyright (c) 2024 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'csv'
require 'date'
require 'json'
require 'open3'

# start the measure
class UtilityBills < OpenStudio::Measure::ReportingMeasure
  def os
    @os ||= begin
      host_os = RbConfig::CONFIG['host_os']
      case host_os
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
        :windows
      when /darwin|mac os/
        :macosx
      when /linux/
        :linux
      when /solaris|bsd/
        :unix
      else
        raise Error::WebDriverError, "unknown os: #{host_os.inspect}"
      end
    end
  end

  # human readable name
  def name
    return 'Utility Bills'
  end

  # human readable description
  def description
    return 'Calculates utility bills for the model based on location.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Calculates utility bills using the PySAM API and commercial rates from the NREL Utility Rate Database or EIA data.'
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
    result << OpenStudio::IdfObject.load('Output:Meter,Electricity:Facility,Hourly;').get

    return result
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # Get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Could not load last OpenStudio model, cannot apply measure.')
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

    # Define run directory location
    run_dir_typical = File.absolute_path(File.join(Dir.pwd, 'run'))
    run_dir_comstock = File.absolute_path(File.join(Dir.pwd, '..'))
    if File.exist?(run_dir_typical)
      run_dir = run_dir_typical
    elsif File.exist?(run_dir_comstock)
      run_dir = run_dir_comstock
    else
      runner.registerError('Could not find directory with EnergyPlus output, cannot extract timeseries results')
      return false
    end

    # Determine the model year and start day of year
    rp = model.getRunPeriod
    year_object = model.getYearDescription
    if year_object.calendarYear.is_initialized
      year = year_object.calendarYear.get
      yr = year_object.calendarYear.get
      year_start_day = year_object.makeDate(rp.getBeginMonth, rp.getBeginDayOfMonth).dayOfWeek.valueName
      runner.registerInfo("Year set to #{yr}. Simulation start day of #{rp.getBeginMonth}/#{rp.getBeginDayOfMonth}/#{yr} is a #{year_start_day}.")
    else
      yr = year_object.assumedYear
      year_start_day = year_object.makeDate(rp.getBeginMonth, rp.getBeginDayOfMonth).dayOfWeek.valueName
      runner.registerInfo("Year not specified. OpenStudio assumed #{yr}. Simulation start day of #{rp.getBeginMonth}/#{rp.getBeginDayOfMonth}/#{yr} is a #{year_start_day}.")
    end

    # Get the weather file run period
    ann_env_pd = nil
    sql.availableEnvPeriods.each do |env_pd|
      env_type = sql.environmentType(env_pd)
      if env_type.is_initialized && (env_type.get == (OpenStudio::EnvironmentType.new('WeatherRunPeriod')))
        ann_env_pd = env_pd
      end
    end
    if ann_env_pd == false
      runner.registerError("Can't find a weather runperiod, make sure you ran an annual simulation, not just the design days.")
      return false
    end

    # Electricity Bill

    # Get hourly electricity timeseries
    elec_ts = sql.timeSeries(ann_env_pd, 'Hourly', 'Electricity:Facility', '')
    if elec_ts.empty?
      runner.registerError('Could not get hourly electricity consumption, cannot calculate electricity bill')
      return false
    end
    elec_ts = elec_ts.get

    # PySAM 4.2.0 assumes that Jan 1 is a Monday per https://github.com/NREL/ssc/issues/195
    # Shift timeseries electricity data to match that assumption
    # so that the weekday/weekend rates apply to the correct energy consumption

    # Find the first Monday timestamp
    first_monday_i = nil
    elec_ts.dateTimes.each_with_index do |date_time, i|
      # runner.registerInfo("timestamp index: #{i}, #{date_time.date.dayOfWeek.valueName} ,#{date_time}")
      if date_time.date.dayOfWeek.valueName == 'Monday'
        # E+ timestamps are hour-ending, so a 00:00 timestamp represents 11-12pm the day prior
        if date_time.time.hours.zero?
          first_monday_i = i + 1
        else
          first_monday_i = i
        end
        runner.registerInfo("First monday timestamp index: #{first_monday_i}")
        break
      end
    end

    # Convert the timeseries vectors to Ruby arrays
    orig_dts = elec_ts.dateTimes.map { |dt| dt }
    orig_vals = []
    elec_ts.values.each { |val| orig_vals << val }

    # Shift values if necessary
    runner.registerInfo("Raw electric timeseries dates #{orig_dts[0]} to #{orig_dts[-1]}")
    if first_monday_i.zero?
      # No shift required
      shifted_dts = orig_dts
      shifted_vals = orig_vals
    else
      # First monday through the end of the year, then first few pre-Monday days
      runner.registerInfo('Shifting electric timeseries to Monday start for PySAM')
      shifted_dts = orig_dts[first_monday_i..] + orig_dts[0..first_monday_i - 1]
      shifted_vals = orig_vals[first_monday_i..] + orig_vals[0..first_monday_i - 1]
      runner.registerInfo("Shifted electric timeseries dates #{shifted_dts[0]} to #{shifted_dts[-1]}")
    end

    # Check that the size is the same
    unless shifted_vals.size == elec_ts.values.size
      runner.registerError("Error shifting values to Monday start, started with #{elec_ts.values.size}, ended with #{shifted_vals.size}")
      return false
    end

    # Check that the total energy is the same
    unless shifted_vals.sum == elec_ts.values.sum
      runner.registerError("Error shifting values to Monday start, started with #{elec_ts.values.sum}, ended with #{shifted_vals.sum}")
      return false
    end

    # Convert electricity to kWh
    hourly_electricity_kwh = shifted_vals.map do |val|
      OpenStudio.convert(val, 'J', 'kWh').get # hourly data
    end

    # Get min and peak demand for rates with qualifiers
    tot_elec_kwh = hourly_electricity_kwh.sum.round
    min_kw = hourly_electricity_kwh.min.round
    max_kw = hourly_electricity_kwh.max.round

    # Write the hourly kWh to CSV
    elec_csv_path = File.expand_path("#{run_dir}/electricity_hourly.csv")
    if !File.exist? elec_csv_path
      CSV.open(elec_csv_path, 'wb') do |csv|
        hourly_electricity_kwh.each do |kwh|
          csv << [kwh.round(3)]
        end
      end
    end

    # Get the sampling region
    sampling_region = model.getBuilding.additionalProperties.getFeatureAsString('sampling_region')
    if sampling_region.empty?
      runner.registerError('Cannot find sampling_region for building, cannot calculate electricity bills.')
      return false
    end
    sampling_region = sampling_region.get

    # load sampling region to tract map
    region_to_tract_map_path = File.join(File.dirname(__FILE__), 'resources', 'sampling_region_to_tracts.json')
    region_to_tract_map = JSON.parse(File.read(region_to_tract_map_path))

    potential_tracts = region_to_tract_map[sampling_region]
    runner.registerInfo("For sampling region #{sampling_region}, there are #{potential_tracts.size} potential tracts")

    state_fips_from_tract = ->(gisjoin) { gisjoin[1, 2] }

    potential_state_fips = potential_tracts.map { |tract| state_fips_from_tract.call(tract) }.uniq
    state_abbrev_to_fips = JSON.parse(File.read(File.join(File.dirname(__FILE__), 'resources', 'state_abbrev_to_fips.json')))
    potential_state_abbrevs = potential_state_fips.map { |f| state_abbrev_to_fips.key(f) }

    runner.registerInfo("For sampling region #{sampling_region}, potential states are #{potential_state_abbrevs}")

    # Load the tract to electric utility EIA ID mapping
    tract_to_elec_util_path = File.join(File.dirname(__FILE__), 'resources', 'tract_to_elec_util.csv')
    tract_to_elec_util = {}
    CSV.foreach(tract_to_elec_util_path) do |row|
      tract_to_elec_util[row[0]] = row[1]
    end

    # Look up the utility EIA IDs based on the potential census tracts for the sampling region
    state_eia_map = Hash.new { |h, k| h[k] = [] }
    elec_eia_ids = []
    potential_tracts.each do |tract|
      state_abbrev = state_abbrev_to_fips.key(state_fips_from_tract.call(tract))
      elec_util_id = tract_to_elec_util[tract]
      state_eia_map[state_abbrev] << elec_util_id unless state_eia_map[state_abbrev].include?(elec_util_id) || elec_util_id.nil?
    end

    # load files
    # Get the average annual electric rate increase from 2013 to 2022 to attempt to make rates more current
    elec_ann_incr_path = File.join(File.dirname(__FILE__), 'resources', 'eia_com_elec_avg_yrly_rate_increase.json')
    elec_ann_incr = JSON.parse(File.read(elec_ann_incr_path))

    # state average rate info
    # electricity
    elec_prices_path = File.join(File.dirname(__FILE__), 'resources', 'eia_com_elec_prices_dol_per_kwh_2022.json')
    elec_prices = JSON.parse(File.read(elec_prices_path))

    # natural gas
    tot_ng_kbtu = nil
    ng_prices = nil
    if sql.naturalGasTotalEndUses.is_initialized
      tot_ng_kbtu = OpenStudio.convert(sql.naturalGasTotalEndUses.get, 'GJ', 'kBtu').get
      if tot_ng_kbtu > 0
        prices_path = File.join(File.dirname(__FILE__), 'resources', 'eia_com_gas_prices_dol_per_kbtu_2022.json')
        ng_prices = JSON.parse(File.read(prices_path))
      end
    end

    # propane
    tot_propane_kbtu = nil
    propane_prices = nil
    if sql.propaneTotalEndUses.is_initialized
      tot_propane_kbtu = OpenStudio.convert(sql.propaneTotalEndUses.get, 'GJ', 'kBtu').get
      if tot_propane_kbtu > 0
        prices_path = File.join(File.dirname(__FILE__), 'resources', 'eia_res_propane_prices_dol_per_kbtu_2022.json')
        propane_prices = JSON.parse(File.read(prices_path))
      end
    end

    # fuel oil
    tot_fueloil_kbtu = nil
    fueloil_prices = nil
    if sql.fuelOilNo2TotalEndUses.is_initialized
      tot_fueloil_kbtu = OpenStudio.convert(sql.fuelOilNo2TotalEndUses.get, 'GJ', 'kBtu').get
      if tot_fueloil_kbtu > 0
        prices_path = File.join(File.dirname(__FILE__), 'resources', 'eia_res_fuel_oil_prices_dol_per_kbtu_2022.json')
        fueloil_prices = JSON.parse(File.read(prices_path))
      end
    end

    # concatenated output strings
    electricity_bill_results = ''
    state_avg_elec_results = ''
    state_avg_ng_results = ''
    state_avg_propane_results = ''
    state_avg_fueloil_results = ''


    state_eia_map.keys.each do |state_abbreviation|
      elec_eia_ids = state_eia_map[state_abbreviation]

      if elec_eia_ids.empty?
        runner.registerWarning("No EIA Utility IDs found for potential tracts in #{state_abbreviation}. Only state averages will be calculated.")
      end

      elec_eia_ids.each do |elec_eia_id|
        # Find all the electric rates for this utility
        all_rates = Dir.glob(File.join(File.dirname(__FILE__), "resources/elec_rates/#{elec_eia_id}/*.json"))
        if all_rates.empty?
          unless elec_eia_id.nil?
            runner.registerWarning("No URDB electric rates found for EIA utility #{elec_eia_id}, using EIA average electric price.")
            use_urdb_rates = false
          end
        else
          runner.registerInfo("Found #{all_rates.size} URDB electric rates for EIA utility #{elec_eia_id}.")
          use_urdb_rates = true
        end

        # Downselect to applicable rates based on kW and kWh limits
        applicable_rates = []
        all_rates.each_with_index do |rate_path, i|
          # Load the rate data
          rate = JSON.parse(File.read(rate_path))
          rate_name = rate['name']
          rate_id = rate['label']

          if rate.key?('peakkwcapacitymin') && (min_kw < (rate['peakkwcapacitymin']))
            runner.registerInfo("Rate #{rate_name} is not applicable because the building min demand of #{min_kw} kW is below minimum threshold of #{rate['peakkwcapacitymin']} kW.")
            next
          end

          if rate.key?('peakkwcapacitymax') && (max_kw > (rate['peakkwcapacitymax']))
            runner.registerInfo("Rate #{rate_name} is not applicable because the building max demand of #{max_kw} kW is above maximum threshold of #{rate['peakkwcapacitymax']} kW.")
            next
          end

          if rate.key?('peakkwhusagemin') && (tot_elec_kwh < (rate['peakkwhusagemin']))
            runner.registerInfo("Rate #{rate_name} is not applicable because the building annual energy #{tot_elec_kwh} kWh is below minimum threshold of #{rate['peakkwhusagemin']} kWh.")
            next
          end

          if rate.key?('peakkwhusagemax') && (tot_elec_kwh > (rate['peakkwhusagemax']))
            runner.registerInfo("Rate #{rate_name} is not applicable because the building annual energy #{tot_elec_kwh} kWh is above maximum threshold of #{rate['peakkwhusagemax']} kWh.")
            next
          end

          # Rate is applicable to this building
          runner.registerInfo("Rate #{rate_name} is applicable.")
          applicable_rates << File.expand_path(rate_path)
        end

        # Ensure at least one rate is applicable to this building
        if !all_rates.empty? && applicable_rates.empty?
          use_urdb_rates = false
          runner.registerWarning("No URDB electric rates were applicable to this building for utility #{elec_eia_id} in #{state_abbreviation}, using EIA average electric price.")
        end

        # Calculate bills using URDB rates
        if use_urdb_rates

          electricity_bill_results += "|#{elec_eia_id}:"

          elec_bills = {}
          # get annual percent increase for state
          state_elec_ann_incr = elec_ann_incr[state_abbreviation]

          # Calculate the bills for each applicable electric rate using the PySAM API via python
          rate_results = {}
          calc_elec_bill_py_path = File.join(File.dirname(__FILE__), 'resources', 'calc_elec_bill.py')
          applicable_rates.each_with_index do |rate_path, i|
            # Load the rate data
            rate = JSON.parse(File.read(rate_path))
            rate_name = rate['name']
            rate_label = rate['label']
            rate_start_date = rate['startdate']
            if rate_start_date
              rate_start_year = Time.at(rate_start_date).utc.to_datetime.to_date.year
            else
              rate_start_year = 2013
              runner.registerWarning("#{rate_name} listed no start date, assuming #{rate_start_year}")
            end

            # Call calc_elec_bill.py
            py = if os == :windows || os == :macosx
                   'python' # Assumes running buildstockbatch from a Conda shell
                 # 'conda run -n pysam python' # for local testing
                 elsif os == :linux
                   'python3.11' # Assumes running buildstockbatch from ComStock docker image
                 else
                   runner.registerError("Could not find python command for #{os}")
                   return false
                 end

            command = "#{py} #{calc_elec_bill_py_path} #{elec_csv_path} #{rate_path}"
            stdout_str, stderr_str, status = Open3.capture3(command)
            # Remove the warning string from the PySAM output if necessary.
            # The bills are typically reasonable despite this warning.
            rate_warn_a = 'Billing Demand Notice.'
            rate_warn_b = 'This rate includes billing demand adjustments and/or demand ratchets that may not be accurately reflected in the data downloaded from the URDB. Please check the information in the Description under Description and Applicability and review the rate sheet to be sure the billing demand inputs are correct.'
            stdout_str = stdout_str.gsub(rate_warn_a, '')
            stdout_str = stdout_str.gsub(rate_warn_b, '')
            stdout_str = stdout_str.strip
            if status.success?
              begin
                pysam_out = JSON.parse(stdout_str)
              rescue JSON::ParserError
                runner.registerError("Error running PySAM: #{command}")
                runner.registerError("stdout: #{stdout_str}")
                return false
              end
              # Adjust the rate for price increases using state averages
              pct_inc = ((2022 - rate_start_year) * state_elec_ann_incr).round(3)
              total_utility_bill_dollars_base_yr = pysam_out['total_utility_bill_dollars'].round.to_i
              total_utility_bill_dollars_2022 = (total_utility_bill_dollars_base_yr * (1.0 + pct_inc)).round.to_i
              rate_results[rate_label] = total_utility_bill_dollars_2022
              runner.registerInfo("Bill for #{rate_name}: $#{total_utility_bill_dollars_2022}, adjusted from #{rate_start_year} to 2022 assuming #{pct_inc} increase.")
            else
              runner.registerError("Error running PySAM: #{command}")
              runner.registerError("stdout: #{stdout_str}")
              runner.registerError("stderr: #{stderr_str}")
              return false
            end
          end

          # Report bills for reasonable rates where: 0.25x_median < bill < 2x_median
          bills_sorted = rate_results.values.sort
          median_bill = bills_sorted[(bills_sorted.length - 1) / 2] + (bills_sorted[bills_sorted.length / 2] / 2.0)
          i = 1
          rate_results.each do |rate_label, bill|
            if bill < 0.25 * median_bill
              runner.registerInfo("Removing #{rate_label}, because bill #{bill} < 0.25 x median #{median_bill}")
            elsif bill > 2.0 * median_bill
              runner.registerInfo("Removing #{rate_label}, because bill #{bill} > 2.0 x median #{median_bill}")
            else
              # include the bill result in bill result statistics
              elec_bills[rate_label] = bill
              i += 1
            end
          end

          # Report bill statistics across all applicable electric rates
          elec_bill_values = elec_bills.values
          elec_bill_values = elec_bill_values.sort
          runner.registerInfo("Bills sorted: #{elec_bill_values}")
          min_bill = elec_bill_values.min
          max_bill = elec_bill_values.max
          mean_bill = (elec_bill_values.sum.to_f / elec_bill_values.length).round.to_i
          lo_i = (elec_bill_values.length - 1) / 2
          hi_i = elec_bill_values.length / 2
          median_bill = ((elec_bill_values[lo_i] + elec_bill_values[hi_i]) / 2.0).round.to_i
          n_bills = elec_bills.length

          electricity_bill_results += "#{min_bill.round.to_i}:#{elec_bills.key(min_bill)}:"
          electricity_bill_results += "#{max_bill.round.to_i}:#{elec_bills.key(max_bill)}:"
          electricity_bill_results += "#{elec_bill_values[lo_i].round.to_i}:#{elec_bills.key(elec_bill_values[lo_i])}:"
          electricity_bill_results += "#{elec_bill_values[hi_i].round.to_i}:#{elec_bills.key(elec_bill_values[hi_i])}:"
          electricity_bill_results += "#{mean_bill}:"
          # electricity_bill_results += "#{median_bill}:"
          electricity_bill_results += n_bills.to_s
        end
      end

      # calculate state averages
      # Electricity bill
      state_avg_elec_results += "|#{state_abbreviation}:"
      elec_rate_dollars_per_kwh = elec_prices[state_abbreviation]
      total_elec_utility_bill_dollars = (tot_elec_kwh * elec_rate_dollars_per_kwh).round.to_i
      state_avg_elec_results += total_elec_utility_bill_dollars.to_s

      # Natural Gas Bill
      unless tot_ng_kbtu.zero?
        state_avg_ng_results += "|#{state_abbreviation}:"
        ng_dollars_per_kbtu = ng_prices[state_abbreviation]
        ng_bill_dollars = (tot_ng_kbtu * ng_dollars_per_kbtu).round.to_i
        state_avg_ng_results += ng_bill_dollars.to_s
      end

      # Propane Bill
      unless tot_propane_kbtu.zero?
        state_avg_propane_results += "|#{state_abbreviation}:"
        propane_dollars_per_kbtu = propane_prices[state_abbreviation]
        propane_bill_dollars = (tot_propane_kbtu * propane_dollars_per_kbtu).round.to_i
        state_avg_propane_results += propane_bill_dollars.to_s
      end

      # fuel oil bill
      unless tot_fueloil_kbtu.zero?
        state_avg_fueloil_results += "|#{state_abbreviation}:"
        fo_dollars_per_kbtu = fueloil_prices[state_abbreviation]
        fo_dollars = (tot_fueloil_kbtu * fo_dollars_per_kbtu).round.to_i
        state_avg_fueloil_results += fo_dollars.to_s
      end
    end

    runner.registerValue('electricity_utility_bill_results', "#{electricity_bill_results}|")
    runner.registerValue('state_avg_electricity_cost_results', "#{state_avg_elec_results}|")
    runner.registerValue('state_avg_naturalgas_cost_results', "#{state_avg_ng_results}|")
    runner.registerValue('state_avg_propane_cost_results', "#{state_avg_propane_results}|")
    runner.registerValue('state_avg_fueloil_cost_results', "#{state_avg_fueloil_results}|")

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

    # Close the sql file
    sql.close

    return true
  end
end

# register the measure to be used by the application
UtilityBills.new.registerWithApplication
