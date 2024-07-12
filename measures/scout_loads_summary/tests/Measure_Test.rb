# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'minitest/autorun'
require 'open3'

require_relative '../measure.rb'
require_relative '../../../test/helpers/minitest_helper'

require 'fileutils'

class ScoutLoadsSummary_Test < Minitest::Test
  def epw_path_default
    # make sure we have a weather data location
    epw = nil
    epw = OpenStudio::Path.new("#{__dir__}/USA_CO_Golden-NREL.724666_TMY3.epw")
    assert(File.exist?(epw.to_s))
    return epw.to_s
  end

  def debug
    return true
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    "#{__dir__}/output/#{test_name}"
  end

  def model_in_path(model_in_name)
    "#{__dir__}/#{model_in_name}"
  end

  def model_out_path(test_name)
    "#{run_dir(test_name)}/TestOutput.osm"
  end

  def workspace_path(test_name)
    "#{run_dir(test_name)}/run/in.idf"
  end

  def sql_path(test_name)
    "#{run_dir(test_name)}/run/eplusout.sql"
  end

  def report_path(test_name)
    "#{run_dir(test_name)}/report.csv"
  end

  def get_run_env()
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

    return new_env
  end

  # create test files if they do not exist when the test first runs
  def run_measure(test_name, test_model_path, args_hash, epw_path = epw_path_default)

    # Check that the input model exists
    assert(File.exist?(test_model_path))

    # Check that the epw file exists
    assert(File.exist?(epw_path))

    # Make the run directory for this test
    FileUtils.mkdir_p(run_dir(test_name)) unless File.exist?(run_dir(test_name))
    assert(File.exist?(run_dir(test_name)))

    # Remove the previous output report
    FileUtils.rm(report_path(test_name)) if File.exist?(report_path(test_name))

    # Remove the previous output model
    FileUtils.rm(model_out_path(test_name)) if File.exist?(model_out_path(test_name))

    # Load the input model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(test_model_path)
    assert(model.is_initialized)
    model = model.get

    # Create an instance of the measure
    measure = ScoutLoadsSummary.new

    # Create a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    runner.setLastOpenStudioModel(model)

    # Populate arguments with testing value, if provided
    args = measure.arguments(model)
    argument_map = OpenStudio::Measure::convertOSArgumentVectorToMap(args)
    args.each do |arg|
      temp_arg_var = arg.clone
      if args_hash[arg.name]
        assert(temp_arg_var.setValue(args_hash[arg.name]), "Could not set #{arg.name} to #{args_hash[arg.name]}")
      end
      argument_map[arg.name] = temp_arg_var
    end

    # Get the EnergyPlus output requests and add to the input model.
    # This will be done automatically by OS App and PAT.
    idf_output_requests = measure.energyPlusOutputRequests(runner, argument_map)
    assert(idf_output_requests.size > 0, "There should be at least one IDF output request, but there were zero.")
    workspace = OpenStudio::Workspace.new("Draft".to_StrictnessLevel, "EnergyPlus".to_IddFileType)
    # Load each object individually so that failure to load is easier to debug during testing
    idf_output_requests.each do |idf_obj|
      single_object = OpenStudio::IdfObjectVector.new
      single_object << idf_obj
      bef = workspace.objects.size
      workspace.addObjects(single_object)
      aft = workspace.objects.size
      assert(aft > bef, "Failed to add #{idf_obj} from energyPlusOutputRequests to workspace")
    end
    rt = OpenStudio::EnergyPlus::ReverseTranslator.new
    request_model = rt.translateWorkspace(workspace)
    model.addObjects(request_model.objects)
    model.save(model_out_path(test_name), true)

    # Run the simulation if sql file is missing
    if !File.exist?(sql_path(test_name))
      osw_path = File.join(run_dir(test_name), 'in.osw')
      osw_path = File.absolute_path(osw_path)

      workflow = OpenStudio::WorkflowJSON.new
      workflow.setSeedFile(File.absolute_path(model_out_path(test_name)))
      workflow.setWeatherFile(File.absolute_path(epw_path))
      workflow.saveAs(osw_path)

      cli_path = OpenStudio.getOpenStudioCLI
      command = "\"#{cli_path}\" run -w \"#{osw_path}\""
      stdout_str, stderr_str, status = Open3.capture3(get_run_env(), command)

      if status.success?
        puts "Successfully ran command: '#{command}'"
      else
        puts "Error running command: '#{command}'"
        puts "stdout: #{stdout_str}"
        puts "stderr: #{stderr_str}"
      end
    end

    # Check that the model output and sql file exist
    assert(File.exist?(model_out_path(test_name)))
    assert(File.exist?(sql_path(test_name)))

    # Set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(test_name)))
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path(test_name)))
    runner.setLastEpwFilePath(epw_path)
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # Temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(test_name))
      $stdout.reopen('test_output.txt', 'w')
      $stdout.sync = true
      # run the measure
      measure.run(runner, argument_map)
      result = runner.result
      show_output(result)


      assert_equal('Success', result.value.valueName)

      $stdout = STDOUT

    ensure
      Dir.chdir(start_dir)
    end

    return model
  end

  def test_large_office
    test_name = 'test_large_office'
    test_model_name = 'large_office_pthp.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => true,
        'enable_supply_side_reporting' => false,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_large_office_vav
    test_name = 'test_large_office_vav'
    test_model_name = 'LargeOffice-90.1-2013-ASHRAE 169-2013-4A.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => false,
        'enable_supply_side_reporting' => true,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_medium_office
    test_name = 'test_medium_office'
    test_model_name = 'medium_office.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => true,
        'enable_supply_side_reporting' => true,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_small_office
    test_name = 'test_small_office'
    test_model_name = 'small_office_pthp.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => true,
        'enable_supply_side_reporting' => true,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_small_office_high_loads
    test_name = 'test_small_office_high_loads'
    test_model_name = 'small_office_pthp_high_loads.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => true,
        'enable_supply_side_reporting' => true,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_small_office_no_windows
    test_name = 'test_small_office_no_windows'
    test_model_name = 'small_office_pthp_no_windows.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => true,
        'enable_supply_side_reporting' => true,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  # no windows
  # no internal mass
  # no infiltration
  # constant thermostat setpoints
  def test_small_office_basic
    test_name = 'test_small_office_basic'
    test_model_name = 'small_office_pthp_basic.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => true,
        'enable_supply_side_reporting' => true,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_restaurant
    test_name = 'test_restaurant'
    test_model_name = 'full_restaurant_psz.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => true,
        'enable_supply_side_reporting' => true,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_simple_restaurant
    test_name = 'test_simple_restaurant'
    test_model_name = 'Restaurant_5B.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => true,
        'enable_supply_side_reporting' => false,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_prototype_restaurant
    test_name = 'test_prototype_restaurant'
    test_model_name = 'prototype_restaurant.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => true,
        'enable_supply_side_reporting' => false,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_prototype_restaurant_no_exhaust
    test_name = 'test_prototype_restaurant_no_exhaust'
    test_model_name = 'prototype_restaurant_no_exhaust.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => true,
        'enable_supply_side_reporting' => false,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_secondary_school
    test_name = 'test_secondary_school'
    test_model_name = 'SecondarySchool-90.1-2013-ASHRAE 169-2013-4A.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => false,
        'enable_supply_side_reporting' => false,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_warehouse
    test_name = 'test_warehouse'
    test_model_name = 'Warehouse_ComStock_90.1-2007_7A.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => true,
        'enable_supply_side_reporting' => true,
        'debug_mode' => debug
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_mfm
    test_name = 'test_mfm'
    test_model_name = 'MFm.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => false,
        'enable_supply_side_reporting' => false,
        'debug_mode' => false
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_scn
    test_name = 'test_scn'
    test_model_name = 'SCn.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => false,
        'enable_supply_side_reporting' => false,
        'debug_mode' => false
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_district_heating
    test_name = 'test_district_heating'
    test_model_name = 'district_heating.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => false,
        'enable_supply_side_reporting' => false,
        'debug_mode' => false
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_district_cooling
    test_name = 'test_district_cooling'
    test_model_name = 'district_cooling.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => false,
        'enable_supply_side_reporting' => false,
        'debug_mode' => false
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_baseboard_electric
    test_name = 'test_baseboard_electric'
    test_model_name = 'baseboard_electric.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => false,
        'enable_supply_side_reporting' => false,
        'debug_mode' => false
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_doas_with_vrf
    test_name = 'test_doas_with_vrf'
    test_model_name = 'doas_with_vrf.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => false,
        'enable_supply_side_reporting' => false,
        'debug_mode' => false
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end

  def test_research_special
    test_name = 'test_research_special'
    test_model_name = 'research_special.osm'
    test_model_path = "#{__dir__}/#{test_model_name}"

    # Set the arguments to test
    args_hash = {
        'report_timeseries_data' => false,
        'enable_supply_side_reporting' => false,
        'debug_mode' => false
    }

    # Run the measure
    model = run_measure(test_name, test_model_path, args_hash)

    return true
  end
end
