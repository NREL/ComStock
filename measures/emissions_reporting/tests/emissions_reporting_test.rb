# ComStock™, Copyright (c) 2024 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# dependencies
require 'fileutils'
require 'minitest/autorun'
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'openstudio-standards'
require_relative '../measure'

class EmissionsReportingTest < Minitest::Test
  def load_model(osm_path)
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(OpenStudio::Path.new(osm_path))
    assert(!model.empty?)
    model = model.get
    return model
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    return "#{__dir__}/output/#{test_name}"
  end

  def model_output_path(test_name)
    return "#{run_dir(test_name)}/out.osm"
  end

  def sql_path(test_name)
    return "#{run_dir(test_name)}/run/eplusout.sql"
  end

  def workspace_path(test_name)
    "#{run_dir(test_name)}/run/in.idf"
  end

  def report_path(test_name)
    return "#{run_dir(test_name)}/reports/eplustbl.html"
  end

  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs
    puts "\n######\nTEST:#{__method__}\n######\n"

    # create an instance of the measure
    measure = EmissionsReporting.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(3, arguments.size)
    assert_equal('grid_region', arguments[0].name)
    assert_equal('grid_state', arguments[1].name)
    assert_equal('emissions_scenario', arguments[2].name)
  end

  def print_column_definitions(result_h)
    # print output names for column definitions
    regex = /annual_(.*)_(electricity|natural_gas|fuel_oil|propane)_ghg_emissions_?(.*)_kg/
    result = ''
    result_h['step_values'].each do |h|
      result_string = "\nresults.csv,emissions_reporting."
      value_name = h['name']
      result_string << "#{value_name},out.emissions"
      # puts value_name
      captures = value_name.scan(regex).flatten
      next if captures.empty?

      # puts captures
      captures.each_with_index do |c, i|
        if i == 2 && !c.empty?
          result_string << if c.match?(/aer_/)
                             ".#{c}_from_2023"
                           elsif c.match?(/lrmer_/)
                             if c.match?(/_start_/)
                               ".#{c}"
                             else
                               ".#{c}_2023_start"
                             end
                           else
                             ".#{c}"
                           end
        else
          result_string << ".#{c}" unless c.empty?
        end
      end
      result_string << ',TRUE,TRUE,float,co2e_kg,co2e_kg'
      if captures[2].include?('egrid')
        result_string << ",\"annual greehouse gas emissions from #{captures[0].gsub('_',
                                                                                    ' ')} #{captures[1].gsub('_',
                                                                                                             ' ')} use, using #{captures[2].gsub(
                                                                                                               '_', ' '
                                                                                                             )} emissions intensity\""
      elsif captures[2].include?('aer')
        result_string << ",\"annual greehouse gas emissions from #{captures[0].gsub('_',
                                                                                    ' ')} #{captures[1].gsub('_',
                                                                                                             ' ')} use, using Cambium 2022 #{captures[2]} non-levelized values from 2023\""
      elsif captures[2].include?('lrmer')
        if captures[2].match?(/_\d{2}_\d{4}_/)
          matches = captures[2].scan(/_(\d{2})_(\d{4})_start/).flatten
          result_string << ",\"annual greehouse gas emissions from #{captures[0].gsub('_',
                                                                                      ' ')} #{captures[1].gsub('_',
                                                                                                               ' ')} use, using Cambium 2022 #{captures[2]} levelized over #{matches[0]} years starting in #{matches[1]}\""
        else
          matches = captures[2].scan(/_\w{4}_(\d{2})/).flatten
          result_string << ",\"annual greehouse gas emissions from #{captures[0].gsub('_',
                                                                                      ' ')} #{captures[1].gsub('_',
                                                                                                               ' ')} use, using Cambium 2022 #{captures[2]} levelized over #{matches[0]} years starting in 2023\""
        end
      else
        result_string << ",\"annual greenhouse gas emissions from on site #{captures[0].gsub('_',
                                                                                             ' ')} #{captures[1].gsub(
                                                                                               '_', ' '
                                                                                             )} use\""
      end
      result << result_string
    end
    puts result
  end

  def run_test(test_name, osm_path, epw_path, argument_map)
    # create run directory if it does not exist
    FileUtils.mkdir_p(run_dir(test_name))
    assert(File.exist?(run_dir(test_name)))

    # change into run directory for tests
    start_dir = Dir.pwd
    begin
      Dir.chdir run_dir(test_name)

      # create an instance of the measure
      measure = EmissionsReporting.new

      # create an instance of a runner
      runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

      # Load the input model to set up runner, this will happen automatically when measure is run in PAT or OpenStudio
      translator = OpenStudio::OSVersion::VersionTranslator.new
      model = translator.loadModel(osm_path)
      assert(model.is_initialized)
      model = model.get
      runner.setLastOpenStudioModel(model)

      # get the energyplus output requests, this will be done automatically by OS App and PAT
      idf_output_requests = measure.energyPlusOutputRequests(runner, argument_map)

      # convert output requests to OSM for testing, OS App and PAT will add these to the E+ Idf
      workspace = OpenStudio::Workspace.new('Draft'.to_StrictnessLevel, 'EnergyPlus'.to_IddFileType)
      workspace.addObjects(idf_output_requests)
      rt = OpenStudio::EnergyPlus::ReverseTranslator.new
      request_model = rt.translateWorkspace(workspace)

      # load the test model and add output requests
      translator = OpenStudio::OSVersion::VersionTranslator.new
      model = translator.loadModel(OpenStudio::Path.new(osm_path))
      assert(!model.empty?)
      model = model.get
      request_model.objects.each { |o| model.addObject(o) }
      # model.addObjects(request_model.objects)
      model.save(model_output_path(test_name), true)

      # set model weather file
      assert(File.exist?(epw_path))
      epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(epw_path))
      OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
      assert(model.weatherFile.is_initialized)

      # run the simulation if necessary
      unless File.exist?(sql_path(test_name))
        puts "\nRUNNING ANNUAL RUN FOR #{test_name}..."

        std = Standard.build('90.1-2013')
        std.model_run_simulation_and_log_errors(model, run_dir(test_name))
      end
      assert(File.exist?(model_output_path(test_name)))
      assert(File.exist?(sql_path(test_name)))

      # set up runner, this will happen automatically when measure is run in PAT or OpenStudio
      runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_output_path(test_name)))
      runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path(test_name)))
      runner.setLastEpwFilePath(epw_path)
      runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

      # run the measure
      puts "\nRUNNING MEASURE RUN FOR #{test_name}..."
      measure.run(runner, argument_map)
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)
    ensure
      # change back directory
      Dir.chdir(start_dir)
    end
    result
  end

  def test_timeseries_lrmer
    puts "\n######\nTEST:#{__method__}\n######\n"

    osm_path = "#{__dir__}/office.osm"
    epw_path = "#{__dir__}/FortCollins2016.epw"

    # create an instance of the measure
    measure = EmissionsReporting.new

    # set arguments
    arguments = measure.arguments(OpenStudio::Model::Model.new)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)
    grid_region = arguments[0].clone
    grid_state = arguments[1].clone
    emissions_scenario = arguments[2].clone
    assert(grid_region.setValue('Lookup from model'))
    assert(grid_state.setValue('Lookup from model'))
    assert(emissions_scenario.setValue('LRMER_MidCase_15'))
    argument_map['grid_region'] = grid_region
    argument_map['grid_state'] = grid_state
    argument_map['emissions_scenario'] = emissions_scenario

    assert(run_test(__method__, osm_path, epw_path, argument_map))
  end

  def test_all_scenarios
    puts "\n######\nTEST:#{__method__}\n######\n"

    osm_path = "#{__dir__}/office.osm"
    epw_path = "#{__dir__}/FortCollins2016.epw"

    # create an instance of the measure
    measure = EmissionsReporting.new

    # set arguments
    arguments = measure.arguments(OpenStudio::Model::Model.new)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)
    grid_region = arguments[0].clone
    grid_state = arguments[1].clone
    emissions_scenario = arguments[2].clone
    assert(grid_region.setValue('RMPAc'))
    assert(grid_state.setValue('Lookup from model'))
    assert(emissions_scenario.setValue('All'))
    argument_map['grid_region'] = grid_region
    argument_map['grid_state'] = grid_state
    argument_map['emissions_scenario'] = emissions_scenario

    result = run_test(__method__, osm_path, epw_path, argument_map)
    assert(result)
    require 'json'
    result_h = JSON.parse(result.to_s)
    # test that runperiod totals same as summed hourly
    assert_in_delta(8613.9, result_h['step_values'].select do |v|
      v['name'] == 'annual_natural_gas_ghg_emissions_kg'
    end.first['value'], 0.1)

    # print_column_definitions(result_h)
  end

  def test_hawaii
    puts "\n######\nTEST:#{__method__}\n######\n"

    osm_path = "#{__dir__}/office.osm"
    epw_path = "#{__dir__}/FortCollins2016.epw"

    # create an instance of the measure
    measure = EmissionsReporting.new

    # set arguments
    arguments = measure.arguments(OpenStudio::Model::Model.new)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)
    grid_region = arguments[0].clone
    grid_state = arguments[1].clone
    emissions_scenario = arguments[2].clone
    assert(grid_region.setValue('HIMS'))
    assert(grid_state.setValue('Lookup from model'))
    assert(emissions_scenario.setValue('LRMER_MidCase_15'))
    argument_map['grid_region'] = grid_region
    argument_map['grid_state'] = grid_state
    argument_map['emissions_scenario'] = emissions_scenario

    assert(run_test(__method__, osm_path, epw_path, argument_map))
  end
end
