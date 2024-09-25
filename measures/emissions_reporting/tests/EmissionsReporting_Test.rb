# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2021, Alliance for Sustainable Energy, LLC.
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
require 'minitest/autorun'
require_relative '../measure.rb'
require 'fileutils'
require 'openstudio-standards'
require_relative '../../../test/helpers/minitest_helper'

class EmissionsReporting_Test < Minitest::Test
  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs
    test_name = "test_number_of_arguments_and_argument_names"
    puts "\n######\nTEST:#{test_name}\n######\n"

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

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    return "#{File.dirname(__FILE__)}/output/#{test_name}"
  end

  def model_output_path(test_name)
    return "#{run_dir(test_name)}/#{test_name}.osm"
  end

  def workspace_path(test_name)
    return "#{run_dir(test_name)}/run/in.idf"
  end

  def sql_path(test_name)
    return "#{run_dir(test_name)}/run/eplusout.sql"
  end

  def report_path(test_name)
    return "#{run_dir(test_name)}/reports/eplustbl.html"
  end

  def print_step_values(result_h)
    require 'csv'
    CSV.open(File.join(run_dir('test_all_scenarios'),'step_vals.csv'), "w") do |csv|
      result_h["step_values"].each do |h|
        csv << [h["name"]]
      end
    end
  end

  def print_column_definitions(result_h, test_name)
    # print output names for column definitions
    regex = /annual_?(.*)_(electricity|natural_gas|fuel_oil|propane)_ghg_emissions_?(.*)_kg/
    result = ""
    result_h['step_values'].each do |h|
      result_string = "\nresults.csv,emissions_reporting."
      value_name = h["name"]
      # make new col name
      result_string << "#{value_name},out.emissions"
      captures = value_name.scan(regex).flatten
      next if captures.empty?
      captures.each_with_index do |c,i|
        if i == 2 && !c.empty?
          if c.match?(/aer_/)
            result_string << ".#{c}_from_2023"
          elsif c.match?(/lrmer_/)
            if c.match?(/_start_/)
              result_string << ".#{c}"
            else
             result_string << ".#{c}_2023_start"
            end
          else result_string << ".#{c}"
          end
        else
          result_string << ".#{c}" unless c.empty?
        end

      end
      # full_metadata, basic_metadata, data_type, original_units, new_units
      result_string << ",TRUE,TRUE,float,co2e_kg,co2e_kg"

      # process fuel string
      if captures[0].empty?
        fuel_str = "total on-site #{captures[1].gsub("_"," ")}"
      else
        fuel_str = "#{captures[1].gsub("_"," ")}"
      end

      # process emissions case string
      case
      when captures[2].include?('egrid')
        case_str = "#{captures[2].gsub('_',' ').gsub('egrid','eGRID')} emissions intensities"
      when captures[2].include?('aer')
        case_str = "Cambium 2022 #{captures[2].gsub('_',' ').gsub('aer', 'Average Emissions Rate').gsub('re','renewable energy').gsub('95','95%%')} non-levelized emissions intensity values from 2023"
      when captures[2].include?('lrmer')
        case_str = "Cambium 2022 #{captures[2].gsub('_',' ').gsub('lrmer', 'Long-Range Marginal Emissions Rate').gsub('re','renewable energy').gsub('95','95%%').gsub(/\s\d{2}$/,'')} emissions intensity values, "
        if captures[2].match?(/_\d{2}_\d{4}_/)
          matches = captures[2].scan(/_(\d{2})_(\d{4})_start/).flatten
          case_str << "levelized over #{matches[0]} years starting in #{matches[1]}"
        else
          matches = captures[2].scan(/_\w{4}_(\d{2})/).flatten
          case_str << "levelized over #{matches[0]} years starting in 2023"
        end
      end

      # end-use string
      end_use_str = "on-site #{captures[0]}"

      # construct field_description
      if captures[0].empty? && captures[2].empty?
        # total non-electric fuel
        result_string << ",annual greenhouse gas emissions from #{fuel_str} use"
      elsif captures[0].empty?
        # total electricity with case
        result_string << ",annual greenhouse gas emissions from #{fuel_str} use, using #{case_str}"
      elsif captures[2].empty?
        # non-elec fuel with end-use
        result_string << ",annual greenhouse gas emissions from #{end_use_str} #{fuel_str} use"
      else
        # electricty end-use with case
        result_string << ",annual greenhouse gas emissions from #{end_use_str} #{fuel_str} use, using #{case_str}"
      end

      result << result_string
    end

    require 'csv'
    CSV.open(File.join(run_dir(test_name),'emissions_columns.csv'), "w") do |csv|
      result.split("\n").each do |row|
        csv << row.split(',')
      end
    end
  end

  def run_test(test_name, osm_path, epw_path, argument_map)
    # create run directory if it does not exist
    unless File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert(File.exist?(run_dir(test_name)))

    # change into run directory for tests
    start_dir = Dir.pwd
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
    request_model.objects.each{|o| model.addObject(o)}
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

    # change back directory
    Dir.chdir(start_dir)
    return result
  end

  def test_timeseries_lrmer
    test_name = 'test_timeseries_lrmer'

    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/office.osm'
    epw_path = File.dirname(__FILE__) + '/FortCollins2016.epw'

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

    assert(run_test(test_name, osm_path, epw_path, argument_map))
  end

  def test_all_scenarios
    test_name = 'test_all_scenarios'

    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/smalloffice.osm'
    epw_path = File.dirname(__FILE__) + '/FortCollins2016.epw'

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

    result = run_test(test_name, osm_path, epw_path, argument_map)
    assert(result)
    require 'json'
    result_h = JSON.parse(result.to_s)
    # test that runperiod totals same as summed hourly
    assert_in_delta(3384.63, result_h['step_values'].select{|v| v["name"] == "annual_natural_gas_ghg_emissions_kg"}.first["value"], 0.1)

    # test that all electricity emissions are > 0
    result_h['step_values'].select{ |v| v["name"].include?('cooling_electricity')}.each do |result|
      assert(result['value'] > 0, "Result for #{result['name']} is zero")
    end

    # print_step_values(result_h)
    print_column_definitions(result_h, test_name)
  end

  def test_hawaii
    test_name = 'test_hawaii'

    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/smalloffice.osm'
    epw_path = File.dirname(__FILE__) + '/FortCollins2016.epw'

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

    assert(run_test(test_name, osm_path, epw_path, argument_map))
  end
end
