# insert your copyright here

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'minitest/autorun'
require 'fileutils'
require 'open3'

require_relative '../measure'
require_relative '../../../test/helpers/minitest_helper'

class LoadsSummaryTest < Minitest::Test
  def debug
    # return true
    return false
  end

  def timeseries
    # return true
    return true
  end

  def script_version
    # return true
    return 2  # change this to the version of the script you are testing
  end

  def teardown
    $stdout = STDOUT
  end

  def model_in_path_default
    return "#{File.dirname(__FILE__)}/example_model.osm"
  end

  def epw_path_default
    # make sure we have a weather data location
    epw = File.expand_path("#{File.dirname(__FILE__)}/USA_CO_Golden-NREL.724666_TMY3.epw")
    assert_path_exists(epw.to_s)
    return epw.to_s
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    return "#{File.dirname(__FILE__)}/output/#{test_name}"
  end

  def model_out_path(test_name)
    return "#{run_dir(test_name)}/example_model.osm"
  end

  def sql_path(test_name)
    return "#{run_dir(test_name)}/run/eplusout.sql"
  end

  def report_path(test_name)
    return "#{run_dir(test_name)}/report.html"
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

  def run_in_workflow(test_name, test_model_path, args_hash, epw_path = epw_path_default)
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

    osw_path = File.join(run_dir(test_name), 'in.osw')
    osw_path = File.absolute_path(osw_path)
    
    workflow = OpenStudio::WorkflowJSON.new
    workflow.setSeedFile(File.absolute_path(test_model_path))
    workflow.setWeatherFile(File.absolute_path(epw_path))
    # puts File.absolute_path(File.join(File.dirname(__FILE__), '../../loads_summary'))
    # step = OpenStudio::MeasureStep.new(File.absolute_path(File.join(File.dirname(__FILE__), '../../measure.rb')))
    workflow.addMeasurePath(File.absolute_path(File.join(File.dirname(__FILE__), '../../')))
    step = OpenStudio::MeasureStep.new('loads_summary')
    args_hash.each do |key, value|
      step.setArgument(key, value)
    end

    check = workflow.setMeasureSteps(OpenStudio::MeasureType.new("ReportingMeasure"), [step])

    # # try not translating spaces
    # fto = OpenStudio::ForwardTranslatorOptions.new
    # fto.setExcludeSpaceTranslation(true)
    # fto.setExcludeLCCObjects(true)
    # ro = OpenStudio::RunOptions.new
    # ro.setSkipEnergyPlusPreprocess(true)
    # ro.setForwardTranslatorOptions(fto)
    # workflow.setRunOptions(ro)

    puts workflow

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

    # Check that the model output and sql file exist
    assert(File.exist?(sql_path(test_name)))
  end

  # create test files if they do not exist when the test first runs
  def setup_test(test_name, idf_output_requests, model_in_path = model_in_path_default, epw_path = epw_path_default)
    if !File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert_path_exists(run_dir(test_name))

    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end

    assert_path_exists(model_in_path)

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
    refute_empty(model)
    model = model.get
    model.addObjects(request_model.objects)
    model.save(model_out_path(test_name), true)

    if ENV['OPENSTUDIO_TEST_NO_CACHE_SQLFILE']
      if File.exist?(sql_path(test_name))
        FileUtils.rm_f(sql_path(test_name))
      end
    end

    osw_path = File.join(run_dir(test_name), 'in.osw')
    osw_path = File.absolute_path(osw_path)

    workflow = OpenStudio::WorkflowJSON.new
    workflow.setSeedFile(File.absolute_path(model_out_path(test_name)))
    workflow.setWeatherFile(File.absolute_path(epw_path))
    workflow.saveAs(osw_path)

    cli_path = OpenStudio.getOpenStudioCLI
    cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""
    puts cmd
    system(cmd)

  end

  # def test_simple_model
  #   test_name = __method__.to_s
  #   test_model_name = 'simple_test.osm'
  #   test_model_path = "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/test.epw"

  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug,
  #     'script_version' => script_version
  #   }

  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)
  # end

  
  # def test_cz1A_warehouse
  #   test_name = 'test_cz1A_warehouse'
  #   test_model_name = 'CZ1A_warehouse_10001_25000_PTHP.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G1200860.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug,
  #     'script_version' => script_version
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz2A_warehouse
  #   test_name = 'test_cz2A_warehouse'
  #   test_model_name = 'CZ2A_warehouse_10001_25000_PSZ-AC with electric coil.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G1200210.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug,
  #     'script_version' => script_version
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz2B_full_service_restaurant
  #   test_name = 'test_cz2B_full_service_restaurant'
  #   test_model_name = 'CZ2B_full_service_restaurant_10001_25000_PSZ-AC with electric coil.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G0400130.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'script_version' => script_version,
  #     'debug_mode' => debug
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz3A_strip_mall
  #   test_name = 'test_cz3A_strip_mall'
  #   test_model_name = 'CZ3A_strip_mall_10001_25000_PVAV with gas boiler reheat.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G4801810.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug,
  #     'script_version' => script_version
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz3B_warehouse
  #   test_name = 'test_cz3B_warehouse'
  #   test_model_name = 'CZ3B_warehouse_200001_500000_PVAV with gas boiler reheat.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G0600710.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug,
  #     'script_version' => script_version
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  def test_cz3C_small_office
    test_name = "test_cz3C_small_office_#{script_version}"
    test_model_name = 'CZ3C_small_office_10001_25000_PTHP.osm'
    test_model_path =  "#{__dir__}/#{test_model_name}"
    epw_path = "#{__dir__}/G0600530.epw"

    # set the arguments to test
    args_hash = {
      'report_timeseries_data' => timeseries,
      'debug_mode' => debug,
      'script_version' => script_version
    }

    # run the measure
    run_in_workflow(test_name, test_model_path, args_hash, epw_path)

    return true
  end

  # def test_cz4A_outpatient
  #   test_name = 'test_cz4A_outpatient'
  #   test_model_name = 'CZ4A_outpatient_25001_50000_PSZ-AC with gas boiler.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G2405100.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz4B_retail
  #   test_name = 'test_cz4B_retail'
  #   test_model_name = 'CZ4B_retail_10001_25000_PSZ-AC with gas coil.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G3500010.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz4C_warehouse
  #   test_name = 'test_cz4C_warehouse'
  #   test_model_name = 'CZ4C_warehouse_100001_200000_PVAV with PFP boxes.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G5300670.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz5A_outpatient
  #   test_name = 'test_cz5A_outpatient'
  #   test_model_name = 'CZ5A_outpatient_5001_10000_PSZ-AC with gas boiler.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G4200970.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz5B_strip_mall
  #   test_name = 'test_cz5B_strip_mall'
  #   test_model_name = 'CZ5B_strip_mall_5001_10000_PVAV with PFP boxes.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G0800310.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz6B_strip_mall
  #   test_name = 'test_cz6B_strip_mall'
  #   test_model_name = 'CZ6B_strip_mall_50001_100000_PSZ-AC with gas coil.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G3000410.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz7_secondary_school
  #   test_name = 'test_cz7_secondary_school'
  #   test_model_name = 'CZ7_secondary_school_10001_25000_PVAV with district hot water reheat.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G0200130.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz7A_strip_mall
  #   test_name = 'test_cz7A_strip_mall'
  #   test_model_name = 'CZ7A_strip_mall_25001_50000_PVAV with gas boiler reheat.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G3800170.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz7B_secondary_school
  #   test_name = 'test_cz7B_secondary_school'
  #   test_model_name = 'CZ7B_secondary_school_10001_25000_VAV air-cooled chiller with gas boiler reheat.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G0801050.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

  # def test_cz8_large_office
  #   test_name = 'test_cz8_large_office'
  #   test_model_name = 'CZ8_large_office_10001_25000_VAV chiller with gas boiler reheat.osm'
  #   test_model_path =  "#{__dir__}/#{test_model_name}"
  #   epw_path = "#{__dir__}/G0200900.epw"

  #   # set the arguments to test
  #   args_hash = {
  #     'report_timeseries_data' => timeseries,
  #     'debug_mode' => debug
  #   }

  #   # run the measure
  #   run_in_workflow(test_name, test_model_path, args_hash, epw_path)

  #   return true
  # end

end

