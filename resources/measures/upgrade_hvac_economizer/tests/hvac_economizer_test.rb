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

# dependencies
require 'openstudio'
require 'openstudio-standards'
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'
require 'minitest/autorun'
require_relative '../measure.rb'
require_relative '../../../../test/helpers/minitest_helper'

class HVACEconomizer_Test < Minitest::Test

  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # create an instance of the measure
    measure = HVACEconomizer.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # Get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(1, arguments.size)
    assert_equal('apply_measure', arguments[0].name)
  end

  # return file paths to test models in test directory
  def models_for_tests
    paths = Dir.glob(File.join(File.dirname(__FILE__), '../../../tests/models/*.osm'))
    paths = paths.map { |path| File.expand_path(path) }
    return paths
  end

  # return file paths to epw files in test directory
  def epws_for_tests
    paths = Dir.glob(File.join(File.dirname(__FILE__), '../../../tests/weather/*.epw'))
    paths = paths.map { |path| File.expand_path(path) }
    return paths
  end

  def load_model(osm_path)
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(OpenStudio::Path.new(osm_path))
    assert(!model.empty?)
    model = model.get
    return model
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    return "#{File.dirname(__FILE__)}/output/#{test_name}"
  end

  def model_output_path(test_name)
    return "#{run_dir(test_name)}/#{test_name}.osm"
  end

  def sql_path(test_name)
    return "#{run_dir(test_name)}/run/eplusout.sql"
  end

  def report_path(test_name)
    return "#{run_dir(test_name)}/reports/eplustbl.html"
  end

  # applies the measure and then runs the model
  def apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false)
    assert(File.exist?(osm_path))
    assert(File.exist?(epw_path))

    # create run directory if it does not exist
    if !File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert(File.exist?(run_dir(test_name)))

    # change into run directory for tests
    start_dir = Dir.pwd
    Dir.chdir run_dir(test_name)

    # remove prior runs if they exist
    if File.exist?(model_output_path(test_name))
      FileUtils.rm(model_output_path(test_name))
    end
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end

    # copy the osm and epw to the test directory
    new_osm_path = "#{run_dir(test_name)}/#{File.basename(osm_path)}"
    FileUtils.cp(osm_path, new_osm_path)
    new_epw_path = "#{run_dir(test_name)}/#{File.basename(epw_path)}"
    FileUtils.cp(epw_path, new_epw_path)
    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # load the test model
    model = load_model(new_osm_path)

    # set model weather file
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(new_epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
    assert(model.weatherFile.is_initialized)

    # run the measure
    puts "\nAPPLYING MEASURE..."
    measure.run(model, runner, argument_map)
    result = runner.result
    result_success = result.value.valueName == 'Success'

    # show the output
    show_output(result)

    # save model
    model.save(model_output_path(test_name), true)

    if run_model && result_success
      puts "\nRUNNING MODEL..."

      std = Standard.build('ComStock DEER 2020')
      std.model_run_simulation_and_log_errors(model, run_dir(test_name))

      # check that the model ran successfully
      assert(File.exist?(sql_path(test_name)))
    end

    # change back directory
    Dir.chdir(start_dir)

    return result
  end

  def get_design_oa_flow_rates(model)
    hash_oa_design_rates = {}
    # get OA design rates prior to measure implementation
    model.getControllerOutdoorAirs.each do |ctrloa|

      # get related airloophvac
      name_ctrloa = ctrloa.name.to_s

      # get design OA flow rate
      min_oa_rate = nil
      if ctrloa.autosizedMinimumOutdoorAirFlowRate.is_initialized
        min_oa_rate = ctrloa.autosizedMinimumOutdoorAirFlowRate.get
      elsif ctrloa.minimumOutdoorAirFlowRate.is_initialized
        min_oa_rate = ctrloa.minimumOutdoorAirFlowRate.get
      else
        raise 'no design OA flow rate found'
      end
      if min_oa_rate == 0.0
        puts("### DEBUGGING: min_oa_rate is zero so skipping this outdoor air system for comparison.")
      else
        puts("### DEBUGGING: name_ctrloa = #{name_ctrloa} | min_oa_rate = #{min_oa_rate}")
        # add key (airloop name) and value (design OA rate)
        hash_oa_design_rates[name_ctrloa] = min_oa_rate.round(6)
      end

    end

    return hash_oa_design_rates
  end

  def economizer_available(model)
    economizer_availability = []
    model.getAirLoopHVACs.each do |air_loop_hvac|
      # get airLoopHVACOutdoorAirSystem
      oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
      if oa_sys.is_initialized
        oa_sys = oa_sys.get
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.Model', "#{air_loop.name} is required to have an economizer, but it has no OA system.")
        next
      end
      # get controller:outdoorair
      oa_control = oa_sys.getControllerOutdoorAir
      # change/check settings: control type
      if oa_control.getEconomizerControlType != 'NoEconomizer'
        economizer_availability << true
      else
        economizer_availability << false
      end
    end
    return economizer_availability
  end

  def models_to_test_design_oa_rates
    test_sets = []
    # test_sets << { model: 'PVAV_gas_heat_electric_reheat_4A', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'PSZ-AC_with_gas_coil_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    test_sets << { model: '361_Warehouse_PVAV_2a', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'LargeOffice_VAV_chiller_boiler', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'LargeOffice_VAV_district_chw_hw', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'Outpatient_VAV_chiller_PFP_boxes', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'Retail_PVAV_gas_ht_elec_rht', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'VAV_chiller_boiler_4A', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'VAV_with_reheat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    return test_sets
  end

  def test_design_oa_rates
    # Define test name
    test_name = 'test_design_oa_rates'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # loop through each model from models_to_test_design_oa_rates and conduct test
    models_to_test_design_oa_rates.each do |set|
      instance_test_name = set[:model]
      puts "instance test name: #{instance_test_name}"
      osm_path = models_for_tests.select { |x| set[:model] == File.basename(x, '.osm') }
      epw_path = epws_for_tests.select { |x| set[:weather] == File.basename(x, '.epw') }
      assert(!osm_path.empty?)
      assert(!epw_path.empty?)
      osm_path = osm_path[0]
      epw_path = epw_path[0]

      # Initialize hash
      oa_design_rates_before = {}
      oa_design_rates_after = {}

      # Create an instance of the measure
      measure = HVACEconomizer.new

      # Load the model; only used here for populating arguments
      model = load_model(osm_path)
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure::OSArgumentMap.new
      apply_measure = arguments[0].clone
      assert(apply_measure.setValue(true))
      argument_map['apply_measure'] = apply_measure

      # Set weather
      epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(epw_path))
      OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)

      # Hardsize model
      puts("### DEBUGGING: first hardsize")
      standard = Standard.build('ComStock DOE Ref Pre-1980')
      if standard.model_run_sizing_run(model, "#{File.dirname(__FILE__)}/output/#{instance_test_name}/SR1") == false
        puts("Sizing run for Hardsize model failed, cannot hard-size model.")
        return false
      end
      model.applySizingValues

      # Check economizer availability and see if original model does not include economizer
      economizer_availability_before = economizer_available(model)
      puts("### DEBUGGING: economizer available before measure = #{economizer_availability_before}")
      assert(economizer_availability_before.include?(false))

      # Get OA rates before applying measure
      oa_design_rates_before = get_design_oa_flow_rates(model)

      # Apply the measure to the model and optionally run the model
      result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)
      model = load_model(model_output_path(instance_test_name))
      puts("### DEBUGGING: result = #{result}")

      # Hardsize model
      puts("### DEBUGGING: second hardsize")
      standard = Standard.build('ComStock DOE Ref Pre-1980')
      if standard.model_run_sizing_run(model, "#{File.dirname(__FILE__)}/output/#{instance_test_name}/SR2") == false
        puts("Sizing run for Hardsize model failed, cannot hard-size model.")
        return false
      end
      model.applySizingValues

      # Check economizer availability and see if updated model includes economizer
      economizer_availability_after = economizer_available(model)
      puts("### DEBUGGING: economizer available after measure = #{economizer_availability_after}")
      assert(economizer_availability_after.include?(true))

      # Get OA rates after applying measure
      oa_design_rates_after = get_design_oa_flow_rates(model)
      puts("### DEBUGGING: oa_design_rates_before = #{oa_design_rates_before}")
      puts("### DEBUGGING: oa_design_rates_after = #{oa_design_rates_after}")

      # Check if OA rates are the same before and after the measure implementation
      assert(oa_design_rates_before == oa_design_rates_after)
    end
  end

  # create an array of hashes with model name, weather, and expected result
  def models_to_test
    test_sets = []
    test_sets << { model: 'PVAV_gas_heat_electric_reheat_4A', weather: 'VA_MANASSAS_724036_12', result: 'Success' }
    test_sets << { model: 'Baseboard_electric_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'NA' }
    test_sets << { model: 'PSZ-AC_with_gas_coil_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    test_sets << { model: 'Residential_AC_with_electric_baseboard_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'NA' }
    test_sets << { model: 'Residential_heat_pump_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'NA' }
    test_sets << { model: 'DOAS_wshp_gshp_3A', weather: 'GA_ROBINS_AFB_722175_12', result: 'NA' }
    return test_sets
  end

  def test_models
    test_name = 'test_models'
    puts "\n######\nTEST:#{test_name}\n######\n"

    models_to_test.each do |set|
      instance_test_name = set[:model]
      puts "instance test name: #{instance_test_name}"
      osm_path = models_for_tests.select { |x| set[:model] == File.basename(x, '.osm') }
      epw_path = epws_for_tests.select { |x| set[:weather] == File.basename(x, '.epw') }
      assert(!osm_path.empty?)
      assert(!epw_path.empty?)
      osm_path = osm_path[0]
      epw_path = epw_path[0]

      # create an instance of the measure
      measure = HVACEconomizer.new

      # load the model; only used here for populating arguments
      model = load_model(osm_path)

      # set arguments here; will vary by measure
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure::OSArgumentMap.new

      # set arguments: choice of economizer
      apply_measure = arguments[0].clone
      assert(apply_measure.setValue(true))
      argument_map['apply_measure'] = apply_measure

      # apply the measure to the model and optionally run the model
      result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

      # check the measure result; result values will equal Success, Fail, or Not Applicable
      # also check the amount of warnings, info, and error messages
      # use if or case statements to change expected assertion depending on model characteristics
      assert(result.value.valueName == set[:result])
    end
  end
end
