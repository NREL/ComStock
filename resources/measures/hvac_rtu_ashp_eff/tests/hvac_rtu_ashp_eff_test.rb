# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
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
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'
require 'minitest/autorun'
require_relative '../measure.rb'

class HVACRTUASHPEfficiency_Test < Minitest::Test
  # all tests are a sub definition of this class, e.g.:
  # def test_new_kind_of_test
  #   # test content
  # end

  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # create an instance of the measure
    measure = HVACRTUASHPEfficiency.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(1, arguments.size)
    assert_equal('target_efficiency_level', arguments[0].name)
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

  # Convert from EER to COP
  # @ref [References::USDOEPrototypeBuildings] If capacity is not supplied, use DOE Prototype Building method.
  # @ref [References::ASHRAE9012013] If capacity is supplied, use the 90.1-2013 method
  #
  # @param eer [Double] Energy Efficiency Ratio (EER)
  # @param capacity_w [Double] the heating capacity at AHRI rating conditions, in W
  # @return [Double] Coefficient of Performance (COP)
  def eer_to_cop(eer, capacity_w = nil)
    if capacity_w.nil?
      # The PNNL Method.
      # r is the ratio of supply fan power to total equipment power at the rating condition,
      # assumed to be 0.12 for the reference buildings per PNNL.
      r = 0.12
      cop = (eer / 3.413 + r) / (1 - r)
    else
      # The 90.1-2013 method
      # Convert the capacity to Btu/hr
      capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
      cop = 7.84E-8 * eer * capacity_btu_per_hr + 0.338 * eer
    end

    return cop
  end

  # create an array of hashes with model name, weather, and expected result
  def models_to_test
    test_sets = []
    test_sets << { model: 'PVAV_gas_heat_electric_reheat_4A', weather: 'VA_MANASSAS_724036_12', result: 'NA' }
    test_sets << { model: 'Baseboard_electric_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'NA' }
    test_sets << { model: 'PSZ-AC_with_gas_coil_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'NA' }
    test_sets << { model: 'PSZ-HP_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    test_sets << { model: 'Residential_AC_with_electric_baseboard_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'NA' }
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
      measure = HVACRTUASHPEfficiency.new

      # load the model; only used here for populating arguments
      model = load_model(osm_path)

      # set arguments here; will vary by measure
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure::OSArgumentMap.new
      target_efficiency_level = arguments[0].clone
      assert(target_efficiency_level.setValue('IEER 15.0'))
      argument_map['target_efficiency_level'] = target_efficiency_level

      # apply the measure to the model and optionally run the model
      result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

      # check the measure result; result values will equal Success, Fail, or Not Applicable
      # also check the amount of warnings, info, and error messages
      # use if or case statements to change expected assertion depending on model characteristics
      assert(result.value.valueName == set[:result])

      # to check that something changed in the model, load the model and the check the objects match expected new value
      if result.value.valueName == 'Success'
        model = load_model(model_output_path(instance_test_name))
        air_loop_hvacs = model.getAirLoopHVACs
        air_loop_hvac = air_loop_hvacs[0]
        model_heating_cop = 0
        model_cooling_cop = 0
        capacity_w = 0
        air_loop_hvac.supplyComponents.each do |component|
          # CoilHeatingDXSingleSpeed
          if component.to_CoilHeatingDXSingleSpeed.is_initialized
            model_heating_cop = component.to_CoilHeatingDXSingleSpeed.get.ratedCOP
          # CoilCoolingDXSingleSpeed
          elsif component.to_CoilCoolingDXSingleSpeed.is_initialized
            cooling_coil = component.to_CoilCoolingDXSingleSpeed.get
            model_cooling_cop = cooling_coil.ratedCOP.get
            if cooling_coil.ratedTotalCoolingCapacity.is_initialized
              capacity_w = cooling_coil.ratedTotalCoolingCapacity.get
            elsif cooling_coil.autosizedRatedTotalCoolingCapacity.is_initialized
              capacity_w = cooling_coil.autosizedRatedTotalCoolingCapacity.get
            end
          # CoilCoolingDXTwoSpeed
          elsif component.to_CoilCoolingDXTwoSpeed.is_initialized
            cooling_coil = component.to_CoilCoolingDXTwoSpeed.get
            model_cooling_cop = cooling_coil.ratedHighSpeedCOP.get
            if cooling_coil.ratedHighSpeedTotalCoolingCapacity.is_initialized
              capacity_w = cooling_coil.ratedHighSpeedTotalCoolingCapacity.get
            elsif cooling_coil.autosizedRatedHighSpeedTotalCoolingCapacity.is_initialized
              capacity_w = cooling_coil.autosizedRatedHighSpeedTotalCoolingCapacity.get
            end
          end
        end
        expected_cooling_cop = eer_to_cop(13.82)
        expected_heating_cop = eer_to_cop(13.82)
        assert((expected_heating_cop - model_heating_cop)**2 < 0.01, "expected heating cop '#{expected_heating_cop}' and model heating cop '#{model_heating_cop}' on air loop #{air_loop_hvac.name} with cooling capacity #{capacity_w} W")
        assert((expected_cooling_cop - model_cooling_cop)**2 < 0.01, "expected cooling cop '#{expected_cooling_cop}' and model cooling cop '#{model_cooling_cop}' on air loop #{air_loop_hvac.name} with cooling capacity #{capacity_w} W")
      end
    end
  end
end
