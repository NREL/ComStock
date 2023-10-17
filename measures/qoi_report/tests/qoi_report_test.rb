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
require 'openstudio/ruleset/ShowRunnerOutput'
require 'minitest/autorun'
require_relative '../measure.rb'
require 'fileutils'
require 'openstudio-standards'

class QOIReportTest < MiniTest::Test
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

  def run_test(test_name, osm_path, epw_path)
    # create run directory if it does not exist
    unless File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert(File.exist?(run_dir(test_name)))

    # change into run directory for tests
    start_dir = Dir.pwd
    Dir.chdir run_dir(test_name)

    # create an instance of the measure
    measure = QOIReport.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments()
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

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
    model.addObjects(request_model.objects)
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

    # delete the output if it exists
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end
    assert(!File.exist?(report_path(test_name)))

    # run the measure
    puts "\nRUNNING MEASURE RUN FOR #{test_name}..."
    measure.run(runner, argument_map)
    result = runner.result
    show_output(result)
    assert_equal('Success', result.value.valueName)

    # change back directory
    Dir.chdir(start_dir)
    return true
  end

  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # create an instance of the measure
    measure = QOIReport.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments()
    assert_equal(0, arguments.size)
  end

  def test_average_daily_use_base
    # create an instance of the measure
    measure = QOIReport.new

    temperature, total_site_electricity_kw = _setup_test
    timeseries = { 'temperature' => temperature, 'total_site_electricity_kw' => total_site_electricity_kw }

    actual_val = measure.average_daily_use(timeseries, measure.seasons['winter'], 'min')
    assert_in_epsilon(5.0, actual_val, 0.001) # average of 0 and 10

    actual_val = measure.average_daily_use(timeseries, measure.seasons['summer'], 'min')
    assert_in_epsilon(9.0, actual_val, 0.001) # average of 8 and 10

    actual_val = measure.average_daily_use(timeseries, measure.seasons['shoulder'], 'min')
    assert_in_epsilon(7.5, actual_val, 0.001) # average of 5 and 10
  end

  def test_average_daily_use_peak
    # create an instance of the measure
    measure = QOIReport.new

    temperature, total_site_electricity_kw = _setup_test
    timeseries = { 'temperature' => temperature, 'total_site_electricity_kw' => total_site_electricity_kw }

    actual_val = measure.average_daily_use(timeseries, measure.seasons['winter'], 'max')
    assert_in_epsilon(11.0, actual_val, 0.001) # average of 10 and 12

    actual_val = measure.average_daily_use(timeseries, measure.seasons['summer'], 'max')
    assert_in_epsilon(13.0, actual_val, 0.001) # average of 10 and 16

    actual_val = measure.average_daily_use(timeseries, measure.seasons['shoulder'], 'max')
    assert_in_epsilon(14.5, actual_val, 0.001) # average of 10 and 19
  end

  def test_average_daily_timing_base
    # create an instance of the measure
    measure = QOIReport.new

    temperature, total_site_electricity_kw = _setup_test
    timeseries = { 'temperature' => temperature, 'total_site_electricity_kw' => total_site_electricity_kw }

    actual_val = measure.average_daily_timing(timeseries, measure.seasons['winter'], 'min')
    assert_in_epsilon(0.0, actual_val, 0.001) # average of 0 and 0

    actual_val = measure.average_daily_timing(timeseries, measure.seasons['summer'], 'min')
    assert_in_epsilon(1.5, actual_val, 0.001) # average of 3 and 0

    actual_val = measure.average_daily_timing(timeseries, measure.seasons['shoulder'], 'min')
    assert_in_epsilon(5.0, actual_val, 0.001) # average of 10 and 0
  end

  def test_average_daily_timing_peak
    # create an instance of the measure
    measure = QOIReport.new

    temperature, total_site_electricity_kw = _setup_test
    timeseries = { 'temperature' => temperature, 'total_site_electricity_kw' => total_site_electricity_kw }

    actual_val = measure.average_daily_timing(timeseries, measure.seasons['winter'], 'max')
    assert_in_epsilon(2.5, actual_val, 0.001) # average of 1 and 4

    actual_val = measure.average_daily_timing(timeseries, measure.seasons['summer'], 'max')
    assert_in_epsilon(6.5, actual_val, 0.001) # average of 0 and 13

    actual_val = measure.average_daily_timing(timeseries, measure.seasons['shoulder'], 'max')
    assert_in_epsilon(10.0, actual_val, 0.001) # average of 0 and 20
  end

  def test_no_heating_temperatures
    # create an instance of the measure
    measure = QOIReport.new

    temperature, total_site_electricity_kw = _setup_test
    temperature[0..48] = _daily_cooling_temperatures * 2 # no heating temperatures
    timeseries = { 'temperature' => temperature, 'total_site_electricity_kw' => total_site_electricity_kw }

    actual_val = measure.average_daily_use(timeseries, measure.seasons['winter'], 'min')
    assert actual_val.nil?

    actual_val = measure.average_daily_use(timeseries, measure.seasons['summer'], 'min')
    assert_in_epsilon(7.0, actual_val, 0.001) # average of 0, 10, 8, and 10

    actual_val = measure.average_daily_use(timeseries, measure.seasons['shoulder'], 'min')
    assert_in_epsilon(7.5, actual_val, 0.001) # average of 5 and 10
  end

  def _setup_test
    temperature = []
    temperature += _daily_heating_temperatures * 2 # two days of random heating temperatures
    temperature += _daily_cooling_temperatures * 2 # two days of random cooling temperatures
    temperature += _daily_overlap_temperatures * 2 # two days of random overlap temperatures

    total_site_electricity_kw = [] # six days of total site electricity kw
    total_site_electricity_kw += [0, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10]
    total_site_electricity_kw += [10, 10, 10, 10, 12, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10]
    total_site_electricity_kw += [10, 10, 10, 8, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10]
    total_site_electricity_kw += [10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 16, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10]
    total_site_electricity_kw += [10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 5, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10]
    total_site_electricity_kw += [10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 19, 10, 10, 10]

    return temperature, total_site_electricity_kw
  end

  def _daily_heating_temperatures
    # create an instance of the measure
    measure = QOIReport.new

    lower = 0
    upper = measure.seasons['winter'][1].to_i
    return (lower..upper).to_a.sample(24) # random 24 hours of heating temperatures
  end

  def _daily_cooling_temperatures
    # create an instance of the measure
    measure = QOIReport.new

    lower = measure.seasons['summer'][0].to_i
    upper = 100
    return (lower..upper).to_a.sample(24) # random 24 hours of cooling temperatures
  end

  def _daily_overlap_temperatures
    # create an instance of the measure
    measure = QOIReport.new

    lower = measure.seasons['shoulder'][0].to_i
    upper = measure.seasons['shoulder'][1].to_i
    return (lower..upper).to_a.sample(24) # random 24 hours of overlap temperatures
  end

  def test_bldg_retail_resforcedair
    test_name = 'test_bldg_retail_resforcedair'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/retail_2010.osm'
    epw_path = File.dirname(__FILE__) + '/USA_MI_Detroit.City.725375_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_bldg_cold_climate
    test_name = 'test_bldg_cold_climate'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/cold_climate.osm'
    epw_path = File.dirname(__FILE__) + '/cold_climate.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end
end
