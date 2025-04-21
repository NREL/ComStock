# ComStock™, Copyright (c) 2024 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# dependencies
require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require_relative '../measure'

class UtilityBillsTest < Minitest::Test
  def epw_path_default
    # make sure we have a weather data location
    epw = nil
    epw = OpenStudio::Path.new("#{__dir__}/USA_CO_Golden-NREL.724666_TMY3.epw")
    assert(File.exist?(epw.to_s))
    return epw.to_s
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    "#{__dir__}/output/#{test_name}/run"
  end

  def model_out_path(test_name)
    "#{run_dir(test_name)}/TestOutput.osm"
  end

  def workspace_path(test_name)
    return "#{run_dir(test_name)}/run/in.idf"
  end

  def sql_path(test_name)
    return "#{run_dir(test_name)}/run/eplusout.sql"
  end

  def report_path(test_name)
    "#{run_dir(test_name)}/run/enduse_timeseries.csv"
  end

  # Run the test simulation
  def run_test_simulation(test_name, epw_path)
    if !File.exist?(sql_path(test_name))
      osw_path = File.join(run_dir(test_name), 'in.osw')
      osw_path = File.absolute_path(osw_path)

      workflow = OpenStudio::WorkflowJSON.new
      workflow.setSeedFile(File.absolute_path(model_out_path(test_name)))
      workflow.setWeatherFile(File.absolute_path(epw_path))
      workflow.saveAs(osw_path)

      cli_path = OpenStudio.getOpenStudioCLI
      cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""

      # blank out bundler and gem path modifications, will be re-setup by new call
      new_env = {}
      new_env['BUNDLER_ORIG_MANPATH'] = nil
      new_env['BUNDLER_ORIG_PATH'] = nil
      new_env['BUNDLER_VERSION'] = nil
      new_env['BUNDLE_BIN_PATH'] = nil
      new_env['RUBYLIB'] = nil
      new_env['RUBYOPT'] = nil
      new_env['GEM_PATH'] = nil
      new_env['GEM_HOME'] = nil
      new_env['BUNDLE_GEMFILE'] = nil
      new_env['BUNDLE_PATH'] = nil
      new_env['BUNDLE_WITHOUT'] = nil

      stdout_str, stderr_str, status = Open3.capture3(new_env, cmd)

      unless status.success?
        puts("Error running command: '#{cmd}'")
        puts("stdout: #{stdout_str}")
        puts("stderr: #{stderr_str}")
        cmd2 = "\"#{cli_path}\" gem_list"
        stdout_str_2, stderr_str_2, status_2 = Open3.capture3(new_env, cmd2)
        puts("Gems available to openstudio cli according to (openstudio gem_list): \n #{stdout_str_2}")
      end
    end

    return true
  end

  def get_utility_for_tract(tract)
    tract_to_elec_util_path = File.join(File.dirname(__FILE__), '..', 'resources', 'tract_to_elec_util.csv')
    tract_to_elec_util = {}
    CSV.foreach(tract_to_elec_util_path) do |row|
      tract_to_elec_util[row[0]] = row[1]
    end
    return tract_to_elec_util[tract]
  end

  # create test files if they do not exist when the test first runs
  def setup_test(test_name, idf_output_requests, sampling_region, census_tract, state_abbrev, start_year, model_in_path, epw_path = epw_path_default)
    FileUtils.mkdir_p(run_dir(test_name))

    assert(File.exist?(run_dir(test_name)))


    FileUtils.rm_f(report_path(test_name))


    assert(File.exist?(model_in_path))


    FileUtils.rm_f(model_out_path(test_name))


    # convert output requests to OSM for testing, OS App and PAT will add these to the E+ Idf
    workspace = OpenStudio::Workspace.new('Draft'.to_StrictnessLevel, 'EnergyPlus'.to_IddFileType)
    workspace.addObjects(idf_output_requests)
    rt = OpenStudio::EnergyPlus::ReverseTranslator.new
    request_model = rt.translateWorkspace(workspace)

    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(model_in_path)
    assert(!model.empty?)
    model = model.get
    model.addObjects(request_model.objects)
    model.getBuilding.additionalProperties.setFeature('sampling_region', sampling_region)
    model.getBuilding.additionalProperties.setFeature('nhgis_tract_gisjoin', census_tract)
    model.getBuilding.additionalProperties.setFeature('state_abbreviation', state_abbrev)
    model.getYearDescription.setCalendarYear(start_year)
    model.save(model_out_path(test_name), true)

    if ENV['OPENSTUDIO_TEST_NO_CACHE_SQLFILE']

      FileUtils.rm_f(sql_path(test_name))

    end

    run_test_simulation(test_name, epw_path)
  end

  # Test when the building is in a tract with no EIA utility ID assigned
  def test_sm_hotel_no_utility_for_tract
    test_name = 'sm_hotel_no_urdb_rates'
    model_in_path = "#{__dir__}/1004_SmallHotel_a.osm"
    # This census tract has no EIA utility ID assigned
    sampling_region = '0'
    census_tract = 'G0100470957000'
    state_abbreviation = 'AL'
    year = 1999

    # create an instance of the measure
    measure = UtilityBills.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new), argument_map)
    assert(!idf_output_requests.empty?, 'Expected IDF output requests, but none were found')

    # mimic the process of running this measure in OS App or PAT
    epw_path = epw_path_default
    setup_test(test_name, idf_output_requests, sampling_region, census_tract, state_abbreviation, year, model_in_path)

    assert(File.exist?(model_out_path(test_name)))
    assert(File.exist?(sql_path(test_name)), "Could not find sql file at #{sql_path(test_name)}")

    # Set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(test_name)))
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path(test_name)))
    runner.setLastEpwFilePath('')
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # Temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(test_name))
      # run the measure
      measure.run(runner, argument_map)
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)
    ensure
      Dir.chdir(start_dir)
    end

    # Check that electric bills are being calculated
    puts '***Machine-Readable Attributes**'
    rvs = {}
    result.stepValues.each do |value|
      name_val = JSON.parse(value.string)
      rvs[name_val['name']] = name_val['value']
    end

    elec_util_from_file = get_utility_for_tract(census_tract)
    # check that no utility is found for the given census tract
    assert(elec_util_from_file.nil?)

    # check that nothing is found for this tract in bill results
    utility_id_regexp = /\|([^:]+)/
    refute_includes(rvs['electricity_utility_bill_results'].scan(utility_id_regexp).flatten, elec_util_from_file)

    # check that state average result has value
    state_avg_regexp = /\|([^:]+)/
    assert_includes(rvs['state_avg_electricity_cost_results'].scan(state_avg_regexp).flatten, state_abbreviation)
    
  end

  # Test when the building is assigned a utility with no rates from URDB
  def test_sm_hotel_no_urdb_rates
    test_name = 'sm_hotel_no_urdb_rates'
    model_in_path = "#{__dir__}/1004_SmallHotel_a.osm"
    # This census tract is assigned to EIA utility 17683,
    # which has no valid rates in URDB
    sampling_region = '0'
    census_tract = 'G2800630950101'
    state_abbreviation = 'MS'
    year = 1999

    # create an instance of the measure
    measure = UtilityBills.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new), argument_map)
    assert(!idf_output_requests.empty?, 'Expected IDF output requests, but none were found')

    # mimic the process of running this measure in OS App or PAT
    epw_path = epw_path_default
    setup_test(test_name, idf_output_requests, sampling_region, census_tract, state_abbreviation, year, model_in_path)

    assert(File.exist?(model_out_path(test_name)))
    assert(File.exist?(sql_path(test_name)), "Could not find sql file at #{sql_path(test_name)}")

    # Set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(test_name)))
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path(test_name)))
    runner.setLastEpwFilePath('')
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # Temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(test_name))
      # run the measure
      measure.run(runner, argument_map)
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)
    ensure
      Dir.chdir(start_dir)
    end

    # Check that electric bills are being calculated
    puts '***Machine-Readable Attributes**'
    rvs = {}
    result.stepValues.each do |value|
      name_val = JSON.parse(value.string)
      rvs[name_val['name']] = name_val['value']
    end

    elec_util_from_file = get_utility_for_tract(census_tract)
    # check that utility is found
    assert(elec_util_from_file)

    # check that nothing is found for this tract in bill results
    utility_id_regexp = /\|([^:]+)/
    refute_includes(rvs['electricity_utility_bill_results'].scan(utility_id_regexp).flatten, elec_util_from_file)

    # check that state average result has value
    state_avg_regexp = /\|([^:]+)/
    assert_includes(rvs['state_avg_electricity_cost_results'].scan(state_avg_regexp).flatten, state_abbreviation)
    

    # Check for a warning about no rates found
    found_warn = false
    result.stepWarnings.each do |msg|
      found_warn = true if msg.include?("No URDB electric rates found for EIA utility #{elec_util_from_file}")
    end
    assert(found_warn)
  end

  # Test when the building is assigned a utility with many rates from URDB
  def test_sm_hotel_many_urdb_rates
    test_name = 'sm_hotel_many_urdb_rates'
    model_in_path = "#{__dir__}/1004_SmallHotel_a.osm"
    # Set census tract: G0600010400200 which matches
    # utility ID: 14328 (Pacific Gas & Electric Co.) with lots of rates
    sampling_region = '101'
    census_tract = 'G0600010400200'
    state_abbreviation = 'CA'
    year = 1999

    # create an instance of the measure
    measure = UtilityBills.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new), argument_map)
    assert(!idf_output_requests.empty?, 'Expected IDF output requests, but none were found')

    # mimic the process of running this measure in OS App or PAT
    epw_path = epw_path_default
    setup_test(test_name, idf_output_requests, sampling_region, census_tract, state_abbreviation, year, model_in_path)

    assert(File.exist?(model_out_path(test_name)))
    assert(File.exist?(sql_path(test_name)), "Could not find sql file at #{sql_path(test_name)}")

    # Set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(test_name)))
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path(test_name)))
    runner.setLastEpwFilePath('')
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # Temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(test_name))
      # run the measure
      measure.run(runner, argument_map)
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)
    ensure
      Dir.chdir(start_dir)
    end

    # Check that electric bills are being calculated
    puts '***Machine-Readable Attributes**'
    rvs = {}
    result.stepValues.each do |value|
      name_val = JSON.parse(value.string)
      rvs[name_val['name']] = name_val['value']
    end

    elec_util_from_file = get_utility_for_tract(census_tract)
    # check that utility is found
    assert(elec_util_from_file)

    # check that something is found for this tract in bill results
    utility_id_regexp = /\|([^:]+)/
    assert_includes(rvs['electricity_utility_bill_results'].scan(utility_id_regexp).flatten, elec_util_from_file)

    # Parse the string
    keys_stats = [
      'eia_id', 'total_min_value', 'total_min_key', 'total_max_value', 'total_max_key',
      'total_median_low_value', 'total_median_low_key', 'total_median_high_value', 'total_median_high_key',
      'total_mean_value', 'dc_flat_min_value', 'dc_flat_min_key', 'dc_flat_max_value', 'dc_flat_max_key',
      'dc_flat_median_low_value', 'dc_flat_median_low_key', 'dc_flat_median_high_value', 'dc_flat_median_high_key',
      'dc_flat_mean_value', 'dc_tou_min_value', 'dc_tou_min_key', 'dc_tou_max_value', 'dc_tou_max_key',
      'dc_tou_median_low_value', 'dc_tou_median_low_key', 'dc_tou_median_high_value', 'dc_tou_median_high_key',
      'dc_tou_mean_value', 'ec_min_value', 'ec_min_key', 'ec_max_value', 'ec_max_key',
      'ec_median_low_value', 'ec_median_low_key', 'ec_median_high_value', 'ec_median_high_key',
      'ec_mean_value', 'fixed_min_value', 'fixed_min_key', 'fixed_max_value', 'fixed_max_key',
      'fixed_median_low_value', 'fixed_median_low_key', 'fixed_median_high_value', 'fixed_median_high_key',
      'fixed_mean_value', 'total_bill_counts'
    ]
    bill_vals_stats = rvs['electricity_utility_bill_results'].split('|').reject(&:empty?).map do |stat_set|
      values = stat_set.split(':')
      Hash[keys_stats.zip(values)]
    end

    # Check reasonableness of statistics
    bill_vals_stats.each do |bill_val|
      assert_equal(47, bill_val.size)

      assert(bill_val['total_max_value'].to_i > bill_val['total_min_value'].to_i)
      assert(bill_val['total_min_value'].to_i <= bill_val['total_median_low_value'].to_i)
      assert(bill_val['total_min_value'].to_i <= bill_val['total_median_high_value'].to_i)
      assert(bill_val['total_min_value'].to_i <= bill_val['total_mean_value'].to_i)
      assert(bill_val['total_max_value'].to_i >= bill_val['total_median_low_value'].to_i)
      assert(bill_val['total_max_value'].to_i >= bill_val['total_median_high_value'].to_i)
      assert(bill_val['total_max_value'].to_i >= bill_val['total_mean_value'].to_i)

      assert(bill_val['dc_flat_max_value'].to_i >= bill_val['dc_flat_min_value'].to_i)
      assert(bill_val['dc_flat_min_value'].to_i <= bill_val['dc_flat_median_low_value'].to_i)
      assert(bill_val['dc_flat_min_value'].to_i <= bill_val['dc_flat_median_high_value'].to_i)
      assert(bill_val['dc_flat_min_value'].to_i <= bill_val['dc_flat_mean_value'].to_i)
      assert(bill_val['dc_flat_max_value'].to_i >= bill_val['dc_flat_median_low_value'].to_i)
      assert(bill_val['dc_flat_max_value'].to_i >= bill_val['dc_flat_median_high_value'].to_i)
      assert(bill_val['dc_flat_max_value'].to_i >= bill_val['dc_flat_mean_value'].to_i)

      assert(bill_val['dc_tou_max_value'].to_i >= bill_val['dc_tou_min_value'].to_i)
      assert(bill_val['dc_tou_min_value'].to_i <= bill_val['dc_tou_median_low_value'].to_i)
      assert(bill_val['dc_tou_min_value'].to_i <= bill_val['dc_tou_median_high_value'].to_i)
      assert(bill_val['dc_tou_min_value'].to_i <= bill_val['dc_tou_mean_value'].to_i)
      assert(bill_val['dc_tou_max_value'].to_i >= bill_val['dc_tou_median_low_value'].to_i)
      assert(bill_val['dc_tou_max_value'].to_i >= bill_val['dc_tou_median_high_value'].to_i)
      assert(bill_val['dc_tou_max_value'].to_i >= bill_val['dc_tou_mean_value'].to_i)

      assert(bill_val['ec_max_value'].to_i >= bill_val['ec_min_value'].to_i)
      assert(bill_val['ec_min_value'].to_i <= bill_val['ec_median_low_value'].to_i)
      assert(bill_val['ec_min_value'].to_i <= bill_val['ec_median_high_value'].to_i)
      assert(bill_val['ec_min_value'].to_i <= bill_val['ec_mean_value'].to_i)
      assert(bill_val['ec_max_value'].to_i >= bill_val['ec_median_low_value'].to_i)
      assert(bill_val['ec_max_value'].to_i >= bill_val['ec_median_high_value'].to_i)
      assert(bill_val['ec_max_value'].to_i >= bill_val['ec_mean_value'].to_i)

      assert(bill_val['fixed_max_value'].to_i >= bill_val['fixed_min_value'].to_i)
      assert(bill_val['fixed_min_value'].to_i <= bill_val['fixed_median_low_value'].to_i)
      assert(bill_val['fixed_min_value'].to_i <= bill_val['fixed_median_high_value'].to_i)
      assert(bill_val['fixed_min_value'].to_i <= bill_val['fixed_mean_value'].to_i)
      assert(bill_val['fixed_max_value'].to_i >= bill_val['fixed_median_low_value'].to_i)
      assert(bill_val['fixed_max_value'].to_i >= bill_val['fixed_median_high_value'].to_i)
      assert(bill_val['fixed_max_value'].to_i >= bill_val['fixed_mean_value'].to_i)
    end

    # spot checks against hard-coded values
    hard_coded_rates = [
      {
        'eia_id' => '14328',
        'type' => 'total',
        'statistics' => 'min',
        'key' => '5cef09e25457a3f767f60fe4',
        'value' => 9999,
      },
      {
        'eia_id' => '16612',
        'type' => 'dc_flat',
        'statistics' => 'max',
        'key' => '5a382b1a5457a34b37d2dd7f',
        'value' => 9999,
      },
      {
        'eia_id' => '14328',
        'type' => 'dc_tou',
        'statistics' => 'min',
        'key' => '5cef09e25457a3f767f60fe4',
        'value' => 9999,
      },
      {
        'eia_id' => '207',
        'type' => 'ec',
        'statistics' => 'max',
        'key' => '53fb55435257a335346c0e61', # https://apps.openei.org/USURDB/rate/view/53fb55435257a335346c0e61#3__Energy
        'value' => 112253,
      },
      {
        'eia_id' => '207',
        'type' => 'fixed',
        'statistics' => 'min',
        'key' => '53fb57595257a352326c0e61', # https://apps.openei.org/IURDB/rate/view/53fb57595257a352326c0e61#4__Fixed_Charges
        'value' => 60,
      }
    ]
    hard_coded_rates.each do |test_set|
      constructed_key = test_set['type'] + "_" + test_set['statistics'] + "_value"
      bill_vals_stats.each do |stats_eia|
        next if stats_eia['eia_id'] != test_set['eia_id']
        assert_equal(test_set['value'], stats_eia[constructed_key].to_i, "Expected value for #{test_set['type']} with key #{test_set['key']} to be #{test_set['value']} but got #{stats_eia[constructed_key]}")
      end
    end

    # check that state average result has value
    state_avg_regexp = /\|([^:]+)/
    assert_includes(rvs['state_avg_electricity_cost_results'].scan(state_avg_regexp).flatten, state_abbreviation)
  
    # Check that more than one rates are applicable
    num_appl_rates = 0
    shift_msgs = 0
    result.stepInfo.each do |msg|
      num_appl_rates += 1 if msg.include?('is applicable')
      shift_msgs += 1 if msg.include?('Shifting electric timeseries to Monday start')
    end
    assert(num_appl_rates > 0)
    assert(shift_msgs > 0)
  end

  # Test when the building is assigned a utility with many rates from URDB
  def test_sm_hotel_many_urdb_rates_monday_start
    test_name = 'sm_hotel_many_urdb_rates_monday_start'
    model_in_path = "#{__dir__}/1004_SmallHotel_a.osm"
    # Set census tract: G0600010400200 which matches
    # utility ID: 14328 (Pacific Gas & Electric Co.) with lots of rates
    sampling_region = '101'
    census_tract = 'G0600010400200'
    state_abbreviation = 'CA'
    year = 2018

    # create an instance of the measure
    measure = UtilityBills.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new), argument_map)
    assert(!idf_output_requests.empty?, 'Expected IDF output requests, but none were found')

    # mimic the process of running this measure in OS App or PAT
    epw_path = epw_path_default
    setup_test(test_name, idf_output_requests, sampling_region, census_tract, state_abbreviation, year, model_in_path)

    assert(File.exist?(model_out_path(test_name)))
    assert(File.exist?(sql_path(test_name)), "Could not find sql file at #{sql_path(test_name)}")

    # Set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(test_name)))
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path(test_name)))
    runner.setLastEpwFilePath('')
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # Temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(test_name))
      # run the measure
      measure.run(runner, argument_map)
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)
    ensure
      Dir.chdir(start_dir)
    end

    # Check that electric bills are being calculated
    puts '***Machine-Readable Attributes**'
    rvs = {}
    result.stepValues.each do |value|
      name_val = JSON.parse(value.string)
      rvs[name_val['name']] = name_val['value']
    end

    elec_util_from_file = get_utility_for_tract(census_tract)
    # check that utility is found
    assert(elec_util_from_file)

    # check that something is found for this tract in bill results
    utility_id_regexp = /\|([^:]+)/
    assert_includes(rvs['electricity_utility_bill_results'].scan(utility_id_regexp).flatten, elec_util_from_file)

    # check that all results are populated with min, max, mean, med, num
    results_regexp = "/\|#{elec_util_from_file}:(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?)\|/"
    bill_vals = rvs['electricity_utility_bill_results'].match(results_regexp).captures.map(&:to_i)
    assert_equal(10, bill_vals.size)
    keys = [
      'min_dollars',
      'min_label',
      'max_dollars',
      'max_label',
      'median_low_dollars',
      'median_low_label',
      'median_high_dollars',
      'median_high_label',
      'mean_dollars',
      'num_rates'
    ]
    results_hash = Hash[keys.zip(bill_vals)]

    assert(results_hash['max_dollars'] > results_hash['min_dollars'])
    assert(results_hash['min_dollars'] <= results_hash['median_low_dollars'])
    assert(results_hash['min_dollars'] <= results_hash['median_high_dollars'])
    assert(results_hash['min_dollars'] <= results_hash['mean_dollars'])
    assert(results_hash['max_dollars'] >= results_hash['median_low_dollars'])
    assert(results_hash['max_dollars'] >= results_hash['median_high_dollars'])
    assert(results_hash['max_dollars'] >= results_hash['mean_dollars'])

    # check that state average result has value
    state_avg_regexp = /\|([^:]+)/
    assert_includes(rvs['state_avg_electricity_cost_results'].scan(state_avg_regexp).flatten, state_abbreviation)
  
    # Check that more than one rates are applicable
    # and that there is no message about shifting the timeseries to Monday start
    # because 2018 starts on a Monday
    num_appl_rates = 0
    shift_msgs = 0
    result.stepInfo.each do |msg|
      num_appl_rates += 1 if msg.include?('is applicable')
      shift_msgs += 1 if msg.include?('Shifting electric timeseries to Monday start')
    end
    assert(num_appl_rates > 0)
    assert(shift_msgs.zero?)
  end

  # Test when the building is a utility with rates with PySAM warning
  def test_sm_hotel_pysam_warn_rates
    test_name = 'sm_hotel_pysam_warn_rates'
    model_in_path = "#{__dir__}/1004_SmallHotel_a.osm"
    # Set census tract: G0900110693300 which matches
    # utility ID: 2089 (Bozrah Light & Power Company) with lots of rates
    sampling_region = '10'
    census_tract = 'G0900110693300'
    state_abbreviation = 'CT'
    year = 1999

    # create an instance of the measure
    measure = UtilityBills.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new), argument_map)
    assert(!idf_output_requests.empty?, 'Expected IDF output requests, but none were found')

    # mimic the process of running this measure in OS App or PAT
    epw_path = epw_path_default
    setup_test(test_name, idf_output_requests, sampling_region, census_tract, state_abbreviation, year, model_in_path)

    assert(File.exist?(model_out_path(test_name)))
    assert(File.exist?(sql_path(test_name)), "Could not find sql file at #{sql_path(test_name)}")

    # Set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(test_name)))
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path(test_name)))
    runner.setLastEpwFilePath('')
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # Temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(test_name))
      # run the measure
      measure.run(runner, argument_map)
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)
    ensure
      Dir.chdir(start_dir)
    end

    # Check that electric bills are being calculated
    puts '***Machine-Readable Attributes**'
    rvs = {}
    result.stepValues.each do |value|
      name_val = JSON.parse(value.string)
      rvs[name_val['name']] = name_val['value']
    end

    elec_util_from_file = get_utility_for_tract(census_tract)
    # check that utility is found
    assert(elec_util_from_file)

    # check that something is found for this tract in bill results
    utility_id_regexp = /\|([^:]+)/
    assert_includes(rvs['electricity_utility_bill_results'].scan(utility_id_regexp).flatten, elec_util_from_file)

    # check that all results are populated with min, max, mean, med, num
    results_regexp = "/\|#{elec_util_from_file}:(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?):(.+?)\|/"
    bill_vals = rvs['electricity_utility_bill_results'].match(results_regexp).captures.map(&:to_i)
    assert_equal(10, bill_vals.size)
    keys = [
      'min_dollars',
      'min_label',
      'max_dollars',
      'max_label',
      'median_low_dollars',
      'median_low_label',
      'median_high_dollars',
      'median_high_label',
      'mean_dollars',
      'num_rates'
    ]
    results_hash = Hash[keys.zip(bill_vals)]

    assert(results_hash['max_dollars'] > results_hash['min_dollars'])
    assert(results_hash['min_dollars'] <= results_hash['median_low_dollars'])
    assert(results_hash['min_dollars'] <= results_hash['median_high_dollars'])
    assert(results_hash['min_dollars'] <= results_hash['mean_dollars'])
    assert(results_hash['max_dollars'] >= results_hash['median_low_dollars'])
    assert(results_hash['max_dollars'] >= results_hash['median_high_dollars'])
    assert(results_hash['max_dollars'] >= results_hash['mean_dollars'])

    # check that state average result has value
    state_avg_regexp = /\|([^:]+)/
    assert_includes(rvs['state_avg_electricity_cost_results'].scan(state_avg_regexp).flatten, state_abbreviation)
  
    # Check that more than one rates are applicable
    # and messages about shifting the timeseries to Monday start
    # because 1999 starts on a Friday
    num_appl_rates = 0
    shift_msgs = 0
    result.stepInfo.each do |msg|
      num_appl_rates += 1 if msg.include?('is applicable')
      shift_msgs += 1 if msg.include?('Shifting electric timeseries to Monday start')
    end
    assert(num_appl_rates > 0)
    assert(shift_msgs > 0)
  end

  # Test that all of the rate .json files can successfully be evaluated through PySAM
  def dont_test_all_rates_through_pysam
    elec_csv_path = File.expand_path(File.join(__dir__, 'test_electricity_hourly.csv'))
    calc_elec_bill_path = File.expand_path(File.join(__dir__, '..', 'resources', 'calc_elec_bill.py'))

    # Find all the electric rates
    all_elec_rates = Dir.glob(File.join(__dir__, '..', 'resources/elec_rates/**/*.json'))
    rates_per_min = 5.0 * 60
    mins_est = all_elec_rates.size / rates_per_min
    puts("There are #{all_elec_rates.size} electric rates to check, test will take ~#{mins_est} minutes")

    # Call calc_elec_bill.py on every rate
    all_elec_rates.sort.each_with_index do |rate_path, i|
      rate_path = File.expand_path(rate_path)
      # puts("Testing electricity rate #{i+1}: #{rate_path}")
      command = "python #{calc_elec_bill_path} #{elec_csv_path} #{rate_path}"
      stdout_str, stderr_str, status = Open3.capture3(command)
      # Remove the warning string from the PySAM output if necessary
      rate_warn_a = 'Billing Demand Notice.'
      rate_warn_b = 'This rate includes billing demand adjustments and/or demand ratchets that may not be accurately reflected in the data downloaded from the URDB. Please check the information in the Description under Description and Applicability and review the rate sheet to be sure the billing demand inputs are correct.'
      stdout_str = stdout_str.gsub(rate_warn_a, '')
      stdout_str = stdout_str.gsub(rate_warn_b, '')
      stdout_str = stdout_str.strip
      if status.success?
        # Register the resulting bill and associated rate name
        msg = "#{i} rate_path: #{rate_path}, stdout: #{stdout_str}, stderr: #{stderr_str}"
        begin
          pysam_out = JSON.parse(stdout_str)
        rescue StandardError
          puts(msg)
        end
        assert(!pysam_out.nil?, msg)
        # Check that a bill was calculated
        assert(pysam_out['total_utility_bill_dollars'] > 0.0, msg)
        # Check blended rates. Some places in AK and HI appear to have rates > ~$1.40/kWh!!!
        assert(pysam_out['average_rate_dollars_per_kwh'] >= 0.01, msg)
        assert(pysam_out['average_rate_dollars_per_kwh'] <= 1.50, msg)
      else
        puts("Error running PySAM: #{command}")
        puts("stdout: #{stdout_str}")
        puts("stderr: #{stderr_str}")
      end
      assert(status.success?, "Rate #{rate_path} failed: stdout: #{stdout_str}, stderr: #{stderr_str}")
    end

    broken_rate_paths.each do |brp|
      puts brp
    end
  end
end
