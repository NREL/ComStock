# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'
require 'open3'

require_relative '../measure.rb'
require 'minitest/autorun'

class UtilityBills_Test < Minitest::Test
  def model_in_path_default
    return "#{File.dirname(__FILE__)}/ExampleModel.osm"
  end

  def epw_path_default
    # make sure we have a weather data location
    epw = nil
    epw = OpenStudio::Path.new("#{File.dirname(__FILE__)}/USA_CO_Golden-NREL.724666_TMY3.epw")
    assert(File.exist?(epw.to_s))
    return epw.to_s
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    "#{File.dirname(__FILE__)}/output/#{test_name}/run"
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

  # create test files if they do not exist when the test first runs
  def setup_test(test_name, idf_output_requests, census_tract, state_abbrev, model_in_path = model_in_path_default, epw_path = epw_path_default)
    if !File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert(File.exist?(run_dir(test_name)))

    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end

    assert(File.exist?(model_in_path))

    if File.exist?(model_out_path(test_name))
      FileUtils.rm(model_out_path(test_name))
    end

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
    model.getBuilding.additionalProperties.setFeature('nhgis_tract_gisjoin', census_tract)
    model.getBuilding.additionalProperties.setFeature('state_abbreviation', state_abbrev)
    model.save(model_out_path(test_name), true)

    if ENV['OPENSTUDIO_TEST_NO_CACHE_SQLFILE']
      if File.exist?(sql_path(test_name))
        FileUtils.rm_f(sql_path(test_name))
      end
    end

    run_test_simulation(test_name, epw_path)
  end

  # Test when the building is in a tract with no EIA utility ID assigned
  def dont_testsm_hotel_no_utility_for_tract
    test_name = 'sm_hotel_no_urdb_rates'
    model_in_path = "#{File.dirname(__FILE__)}/1004_SmallHotel_a.osm"
    # This census tract has no EIA utility ID assigned
    census_tract = 'G0100470957000'
    state_abbreviation ='AL'

    # create an instance of the measure
    measure = UtilityBills.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new), argument_map)
    assert(idf_output_requests.size > 0, 'Expected IDF output requests, but none were found')

    # mimic the process of running this measure in OS App or PAT
    epw_path = epw_path_default
    setup_test(test_name, idf_output_requests, census_tract, state_abbreviation, model_in_path)

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
    register_values = {}
    result.stepValues.each do |value|
      name_val = JSON.parse(value.string)
      register_values[name_val['name']] = name_val['value']
    end
    assert(register_values.has_key?('electricity_rate_1_name'))
    assert(register_values.has_key?('electricity_rate_1_bill_dollars'))
    assert(register_values.has_key?('electricity_average_bill_dollars'))

    # Check for a warning about missing utility
    found_warn = false
    result.stepWarnings.each do |msg|
      found_warn = true if msg.include?('No electric utility for census tract')
    end
    assert(found_warn)
  end

  # Test when the building is assigned a utility with no rates from URDB
  def dont_testsm_hotel_no_urdb_rates
    test_name = 'sm_hotel_no_urdb_rates'
    model_in_path = "#{File.dirname(__FILE__)}/1004_SmallHotel_a.osm"
    # This census tract is assigned to EIA utility 17683,
    # which has no valid rates in URDB
    census_tract = 'G2800630950100'
    state_abbreviation ='MS'

    # create an instance of the measure
    measure = UtilityBills.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new), argument_map)
    assert(idf_output_requests.size > 0, 'Expected IDF output requests, but none were found')

    # mimic the process of running this measure in OS App or PAT
    epw_path = epw_path_default
    setup_test(test_name, idf_output_requests, census_tract, state_abbreviation, model_in_path)

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
    register_values = {}
    result.stepValues.each do |value|
      name_val = JSON.parse(value.string)
      register_values[name_val['name']] = name_val['value']
    end
    assert(register_values.has_key?('electricity_rate_1_name'))
    assert(register_values.has_key?('electricity_rate_1_bill_dollars'))
    assert(register_values.has_key?('electricity_average_bill_dollars'))

    # Check for a warning about no rates found
    found_warn = false
    result.stepWarnings.each do |msg|
      found_warn = true if msg.include?('No URDB electric rates found for EIA utility')
    end
    assert(found_warn)
  end

  # Test when the building is assigned a utility with many rates from URDB
  def test_sm_hotel_many_urdb_rates
    test_name = 'sm_hotel_many_urdb_rates'
    model_in_path = "#{File.dirname(__FILE__)}/1004_SmallHotel_a.osm"
    # Set census tract: G2000030953600 which matches
    # utility ID: 10000 with lots of rates
    census_tract = 'G2000030953600'
    state_abbreviation ='KS'

    # create an instance of the measure
    measure = UtilityBills.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new), argument_map)
    assert(idf_output_requests.size > 0, 'Expected IDF output requests, but none were found')

    # mimic the process of running this measure in OS App or PAT
    epw_path = epw_path_default
    setup_test(test_name, idf_output_requests, census_tract, state_abbreviation, model_in_path)

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
    register_values = {}
    result.stepValues.each do |value|
      name_val = JSON.parse(value.string)
      register_values[name_val['name']] = name_val['value']
    end
    assert(register_values.has_key?('electricity_rate_1_name'))
    assert(register_values.has_key?('electricity_rate_1_bill_dollars'))
    assert(register_values.has_key?('electricity_average_bill_dollars'))

    # Check for a warning about no rates found
    num_appl_rates = 0
    result.stepInfo.each do |msg|
      num_appl_rates += 1 if msg.include?('is applicable')
    end
    assert(num_appl_rates > 0)
  end

  # Test that all of the rate .json files can successfully be evaluated through PySAM
  def dont_test_all_rates_through_pysam
    elec_csv_path = File.expand_path(File.join(File.dirname(__FILE__), 'test_electricity_hourly.csv'))
    calc_elec_bill_path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'resources', 'calc_elec_bill.py'))

    # Find all the electric rates
    all_elec_rates = Dir.glob(File.join(File.dirname(__FILE__), '..', "resources/elec_rates/**/*.json"))
    rates_per_min = 5.0 * 60
    mins_est = all_elec_rates.size / rates_per_min
    puts("There are #{all_elec_rates.size} electric rates to check, test will take ~#{mins_est} minutes")

    # Call calc_elec_bill.py on every rate
    all_elec_rates.sort.each_with_index do |rate_path, i|
      # next unless i >= 0
      rate_path = File.expand_path(rate_path)
      # puts("Testing electricity rate #{i+1}: #{rate_path}")
      command = "python #{calc_elec_bill_path} #{elec_csv_path} #{rate_path}"
      stdout_str, stderr_str, status = Open3.capture3(command)
      if status.success?
        # Register the resulting bill and associated rate name
        msg = "stdout: #{stdout_str}, stderr: #{stderr_str}"
        begin
          pysam_out = JSON.parse(stdout_str)
        rescue
          puts(msg)
        end
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
  end
end