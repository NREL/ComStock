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
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'
require 'minitest/autorun'
require_relative '../measure.rb'

# only necessary to include here if annual simulation request and the measure doesn't require openstudio-standards
require 'openstudio-standards'

class AddHeatPumpRtu_Test < Minitest::Test
  # all tests are a sub definition of this class, e.g.:
  # def test_new_kind_of_test
  #   # test content
  # end

  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # create an instance of the measure
    measure = AddHeatPumpRtu.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(9, arguments.size)
    assert_equal('backup_ht_fuel_scheme', arguments[0].name)
    assert_equal('performance_oversizing_factor', arguments[1].name)
    assert_equal('htg_sizing_option', arguments[2].name)
    assert_equal('clg_oversizing_estimate', arguments[3].name)
    assert_equal('htg_to_clg_hp_ratio', arguments[4].name)
    assert_equal('std_perf', arguments[5].name)
    assert_equal('hr', arguments[6].name)
    assert_equal('dcv', arguments[7].name)
    assert_equal('econ', arguments[8].name)
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

  # create an array of hashes with model name, weather, and expected result
  def models_to_test
    test_sets = []

    test_sets << {model: 'Small_Office_psz_gas_3a', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success',
      arg_hash: {
        'backup_ht_fuel_scheme' => 'electric_resistance_backup',
        'performance_oversizing_factor' => 0,
        'htg_sizing_option' => '0F',
        'clg_oversizing_estimate' => 1,
        'htg_to_clg_hp_ratio' => 1,
        'std_perf' => false,
        'hr' => true,
        'dcv' => false,
        'econ' => false
      }
    }

    test_sets << {model: 'Retail_PSZ-AC', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success',
      arg_hash: {
        'backup_ht_fuel_scheme' => 'electric_resistance_backup',
        'performance_oversizing_factor' => 0,
        'htg_sizing_option' => '0F',
        'clg_oversizing_estimate' => 1,
        'htg_to_clg_hp_ratio' => 1,
        'std_perf' => false,
        'hr' => true,
        'dcv' => false,
        'econ' => false
      }
    }

    test_sets << {model: 'Warehouse_economizer_test', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success',
      arg_hash: {
        'backup_ht_fuel_scheme' => 'electric_resistance_backup',
        'performance_oversizing_factor' => 0,
        'htg_sizing_option' => '0F',
        'clg_oversizing_estimate' => 1,
        'htg_to_clg_hp_ratio' => 1,
        'std_perf' => false,
        'hr' => true,
        'dcv' => false,
        'econ' => false
      }
    }

    test_sets << {model: 'Residential_forced_air_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'NA',
      arg_hash: {
        'backup_ht_fuel_scheme' => 'electric_resistance_backup',
        'performance_oversizing_factor' => 0,
        'htg_sizing_option' => '0F',
        'clg_oversizing_estimate' => 1,
        'htg_to_clg_hp_ratio' => 1,
        'std_perf' => false,
        'hr' => true,
        'dcv' => false,
        'econ' => false
      }
    }

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
      measure = AddHeatPumpRtu.new

      # load the model; only used here for populating arguments
      model = load_model(osm_path)

      # set arguments here; will vary by measure
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure::OSArgumentMap.new

      # set default arguments
      arguments.each do |arg|
        temp_arg_var = arg.clone
        argument_map[arg.name] = temp_arg_var # Add argument to map with default value
      end

      # override with values from arg_hash
      args_hash = set[:arg_hash]
      args_hash.each do |arg_name, arg_value|
        arg = arguments.find { |a| a.name == arg_name }
        raise "Argument #{arg_name} not found" if arg.nil?
        assert(arg.setValue(arg_value)) # Override with value from arg_hash
        argument_map[arg_name] = arg
      end


      if instance_test_name.downcase.include?("restaurant")
        # get initial number of applicable air loops
        li_unitary_sys_initial = model.getAirLoopHVACUnitarySystems

        # determine air loops with/without kitchens
        tz_kitchens = []
        kitchen_htg_coils = []
        tz_all_other = []
        nonkitchen_htg_coils = []
        model.getAirLoopHVACUnitarySystems.sort.each do |unitary_sys|

          # skip kitchen spaces
          thermal_zone_names_to_exclude = [
            'Kitchen',
            'kitchen',
            'KITCHEN',
          ]
          if thermal_zone_names_to_exclude.any? { |word| (unitary_sys.name.to_s).include?(word) }
            tz_kitchens << unitary_sys

            # add kitchen heating coil to list
            kitchen_htg_coils << unitary_sys.heatingCoil.get

            next
          end

          # add non kitchen zone and heating coil to list
          tz_all_other << unitary_sys
          # add kitchen heating coil to list
          nonkitchen_htg_coils << unitary_sys.heatingCoil.get
        end

        # Apply the measure to the model and optionally run the model
        result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
        assert_equal(set[:result], result.value.valueName, "Failed for #{instance_test_name}")
        model = load_model(model_output_path(__method__))

        # get heating coils from final model for kitchen and non kitchen spaces
        tz_kitchens_final = []
        kitchen_htg_coils_final = []
        tz_all_other_final = []
        nonkitchen_htg_coils_final = []
        model.getAirLoopHVACUnitarySystems.sort.each do |unitary_sys|

          # skip kitchen spaces
          thermal_zone_names_to_exclude = [
            'Kitchen',
            'kitchen',
            'KITCHEN',
          ]
          if thermal_zone_names_to_exclude.any? { |word| (unitary_sys.name.to_s).include?(word) }
            tz_kitchens_final << unitary_sys

            # add kitchen heating coil to list
            kitchen_htg_coils_final << unitary_sys.heatingCoil.get

            next
          end

          # add non kitchen zone and heating coil to list
          tz_all_other_final << unitary_sys
          # add kitchen heating coil to list
          nonkitchen_htg_coils_final << unitary_sys.heatingCoil.get
        end

        # assert no changes to kitchen unitary systems
        assert_equal(tz_kitchens_final, tz_kitchens)

        # assert non kitchen spaces contain multispeed DX heating coils
        nonkitchen_htg_coils_final.each do |htg_coil|
          assert(htg_coil.to_CoilHeatingDXMultiSpeed.is_initialized, "Failed for #{instance_test_name}")
        end

        # assert kitchen spaces still contain gas coils
        kitchen_htg_coils_final.each do |htg_coil|
          assert(htg_coil.to_CoilHeatingGas.is_initialized, "Failed for #{instance_test_name}")
        end
      else
        # get initial gas heating coils
        li_gas_htg_coils_initial = model.getCoilHeatingGass

        # get initial number of applicable air loops
        li_unitary_sys_initial = model.getAirLoopHVACUnitarySystems

        # get initial unitary system schedules for outdoor air and general operation
        # these will be compared against applied HP-RTU system
        dict_oa_sched_min_initial={}
        dict_min_oa_initial={}
        dict_max_oa_initial={}
        model.getAirLoopHVACs.sort.each do |air_loop_hvac|

          # get thermal zone for dictionary mapping
          thermal_zone = air_loop_hvac.thermalZones[0]

          # get OA schedule from OA controller
          oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
          controller_oa = oa_system.getControllerOutdoorAir
          oa_schedule = controller_oa.minimumOutdoorAirSchedule.get
          dict_oa_sched_min_initial[thermal_zone] = oa_schedule

          # get min/max outdoor air flow rate
          min_oa = controller_oa.minimumOutdoorAirFlowRate
          max_oa = controller_oa.maximumOutdoorAirFlowRate
          dict_min_oa_initial[thermal_zone] = min_oa
          dict_max_oa_initial[thermal_zone] = max_oa
        end

        # Apply the measure to the model and optionally run the model
        result = apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false)
        assert_equal(set[:result], result.value.valueName, "Failed for #{instance_test_name}")
        model = load_model(model_output_path(test_name))

        # get final gas heating coils
        li_gas_htg_coils_final = model.getCoilHeatingGass

        # assert gas heating coils have been removed
        assert_equal(li_gas_htg_coils_final.size, 0, "Failed for #{instance_test_name}")

        # get list of final unitary systems
        li_unitary_sys_final = model.getAirLoopHVACUnitarySystems

        # assert same number of unitary systems as initial
        assert_equal(li_unitary_sys_initial.size, li_unitary_sys_final.size, "Failed for #{instance_test_name}")

        # get final unitary system schedules for outdoor air and general operation
        # these will be compared against original system
        dict_oa_sched_min_final={}
        dict_min_oa_final={}
        dict_max_oa_final={}
        model.getAirLoopHVACs.sort.each do |air_loop_hvac|

          # get thermal zone for dictionary mapping
          thermal_zone = air_loop_hvac.thermalZones[0]

          # get OA schedule from OA controller
          oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
          controller_oa = oa_system.getControllerOutdoorAir
          oa_schedule = controller_oa.minimumOutdoorAirSchedule.get
          dict_oa_sched_min_final[thermal_zone] = oa_schedule

          # get min/max outdoor air flow rate
          min_oa = controller_oa.minimumOutdoorAirFlowRate.get
          max_oa = controller_oa.maximumOutdoorAirFlowRate.get
          dict_min_oa_final[thermal_zone] = min_oa
          dict_max_oa_final[thermal_zone] = max_oa
        end

        # assert outdoor air values match between initial and new system
        model.getThermalZones.sort.each do |thermal_zone|
          assert_equal(dict_oa_sched_min_initial[thermal_zone], dict_oa_sched_min_final[thermal_zone])
          assert_in_delta(dict_min_oa_initial[thermal_zone].to_f, dict_min_oa_final[thermal_zone].to_f, 0.001)
          assert_in_delta(dict_max_oa_initial[thermal_zone].to_f, dict_max_oa_final[thermal_zone].to_f, 0.001)
        end

        # assert characteristics of new unitary systems
        li_unitary_sys_final.sort.each do |system|

          # assert new unitary systems all have variable speed fans
          fan = system.supplyFan.get
          assert(fan.to_FanVariableVolume.is_initialized)

          # ***heating***
          # assert new unitary systems all have multispeed DX heating coils
          htg_coil = system.heatingCoil.get
          assert(htg_coil.to_CoilHeatingDXMultiSpeed.is_initialized)
          htg_coil = htg_coil.to_CoilHeatingDXMultiSpeed.get

          # assert multispeed heating coil has 4 stages
          assert_equal(htg_coil.numberOfStages, 4)
          htg_coil_spd4 = htg_coil.stages[3]

          # assert speed 4 flowrate matches design flow rate
          htg_dsn_flowrate = system.supplyAirFlowRateDuringHeatingOperation
          assert_equal(htg_dsn_flowrate.to_f, htg_coil_spd4.ratedAirFlowRate.to_f)

          # assert flow rate reduces for lower speeds
          htg_coil_spd3 = htg_coil.stages[2]
          htg_coil_spd2 = htg_coil.stages[1]
          htg_coil_spd1 = htg_coil.stages[0]
          assert(htg_coil_spd4.ratedAirFlowRate.to_f > htg_coil_spd3.ratedAirFlowRate.to_f)
          assert(htg_coil_spd3.ratedAirFlowRate.to_f > htg_coil_spd2.ratedAirFlowRate.to_f)
          assert(htg_coil_spd2.ratedAirFlowRate.to_f > htg_coil_spd1.ratedAirFlowRate.to_f)

          # assert capacity reduces for lower speeds
          assert(htg_coil_spd4.grossRatedHeatingCapacity.to_f > htg_coil_spd3.grossRatedHeatingCapacity.to_f)
          assert(htg_coil_spd3.grossRatedHeatingCapacity.to_f > htg_coil_spd2.grossRatedHeatingCapacity.to_f)
          assert(htg_coil_spd2.grossRatedHeatingCapacity.to_f > htg_coil_spd1.grossRatedHeatingCapacity.to_f)

          # assert flow per capacity is within range for all stages; added 1% tolerance
          # min = 4.03e-05 m3/s/watt; max = 6.041e-05 m3/s/watt;
          min_flow_per_cap = 4.027e-05*0.99999
          max_flow_per_cap = 6.041e-05*1.000001
          htg_coil_spd4_cfm_per_ton = htg_coil_spd4.ratedAirFlowRate.to_f / htg_coil_spd4.grossRatedHeatingCapacity.to_f
          htg_coil_spd3_cfm_per_ton = htg_coil_spd3.ratedAirFlowRate.to_f / htg_coil_spd3.grossRatedHeatingCapacity.to_f
          htg_coil_spd2_cfm_per_ton = htg_coil_spd2.ratedAirFlowRate.to_f / htg_coil_spd2.grossRatedHeatingCapacity.to_f
          htg_coil_spd1_cfm_per_ton = htg_coil_spd1.ratedAirFlowRate.to_f / htg_coil_spd1.grossRatedHeatingCapacity.to_f
          assert((htg_coil_spd4_cfm_per_ton >= min_flow_per_cap) && (htg_coil_spd4_cfm_per_ton <= max_flow_per_cap))
          assert((htg_coil_spd3_cfm_per_ton >= min_flow_per_cap) && (htg_coil_spd3_cfm_per_ton <= max_flow_per_cap))
          assert((htg_coil_spd2_cfm_per_ton >= min_flow_per_cap) && (htg_coil_spd2_cfm_per_ton <= max_flow_per_cap))
          assert((htg_coil_spd1_cfm_per_ton >= min_flow_per_cap) && (htg_coil_spd1_cfm_per_ton <= max_flow_per_cap))

          # assert supplemental heating coil type matches user-specified electric resistance
          sup_htg_coil = system.supplementalHeatingCoil.get
          assert(sup_htg_coil.to_CoilHeatingElectric.is_initialized)

          # ***cooling***
          # assert new unitary systems all have multispeed DX cooling coils
          clg_coil = system.coolingCoil.get
          assert(clg_coil.to_CoilCoolingDXMultiSpeed.is_initialized)
          clg_coil = clg_coil.to_CoilCoolingDXMultiSpeed.get

          # assert multispeed heating coil has 4 stages
          assert_equal(clg_coil.numberOfStages, 4)
          clg_coil_spd4 = clg_coil.stages[3]

          # assert speed 4 flowrate matches design flow rate
          clg_dsn_flowrate = system.supplyAirFlowRateDuringCoolingOperation
          assert_equal(clg_dsn_flowrate.to_f, clg_coil_spd4.ratedAirFlowRate.to_f)

          # assert flow rate reduces for lower speeds
          clg_coil_spd3 = clg_coil.stages[2]
          clg_coil_spd2 = clg_coil.stages[1]
          clg_coil_spd1 = clg_coil.stages[0]
          assert(clg_coil_spd4.ratedAirFlowRate.to_f > clg_coil_spd3.ratedAirFlowRate.to_f)
          assert(clg_coil_spd3.ratedAirFlowRate.to_f > clg_coil_spd2.ratedAirFlowRate.to_f)
          assert(clg_coil_spd2.ratedAirFlowRate.to_f > clg_coil_spd1.ratedAirFlowRate.to_f)

          # assert capacity reduces for lower speeds
          assert(clg_coil_spd4.grossRatedTotalCoolingCapacity.to_f > clg_coil_spd3.grossRatedTotalCoolingCapacity.to_f)
          assert(clg_coil_spd3.grossRatedTotalCoolingCapacity.to_f > clg_coil_spd2.grossRatedTotalCoolingCapacity.to_f)
          assert(clg_coil_spd2.grossRatedTotalCoolingCapacity.to_f > clg_coil_spd1.grossRatedTotalCoolingCapacity.to_f)

          # assert flow per capacity is within range for all stages; added 1% tolerance
          # min = 4.03e-05 m3/s/watt; max = 6.041e-05 m3/s/watt;
          min_flow_per_cap = 4.03e-05*0.99999
          max_flow_per_cap = 6.041e-05*1.000001
          clg_coil_spd4_cfm_per_ton = clg_coil_spd4.ratedAirFlowRate.to_f / clg_coil_spd4.grossRatedTotalCoolingCapacity.to_f
          clg_coil_spd3_cfm_per_ton = clg_coil_spd3.ratedAirFlowRate.to_f / clg_coil_spd3.grossRatedTotalCoolingCapacity.to_f
          clg_coil_spd2_cfm_per_ton = clg_coil_spd2.ratedAirFlowRate.to_f / clg_coil_spd2.grossRatedTotalCoolingCapacity.to_f
          clg_coil_spd1_cfm_per_ton = clg_coil_spd1.ratedAirFlowRate.to_f / clg_coil_spd1.grossRatedTotalCoolingCapacity.to_f
          assert((clg_coil_spd4_cfm_per_ton >= min_flow_per_cap) && (clg_coil_spd4_cfm_per_ton <= max_flow_per_cap))
          assert((clg_coil_spd3_cfm_per_ton >= min_flow_per_cap) && (clg_coil_spd3_cfm_per_ton <= max_flow_per_cap))
          assert((clg_coil_spd2_cfm_per_ton >= min_flow_per_cap) && (clg_coil_spd2_cfm_per_ton <= max_flow_per_cap))
          assert((clg_coil_spd1_cfm_per_ton >= min_flow_per_cap) && (clg_coil_spd1_cfm_per_ton <= max_flow_per_cap))

        end
      end
    end
  end

end
