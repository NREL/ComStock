# frozen_string_literal: true

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
require_relative '../measure'
require_relative '../../../../test/helpers/minitest_helper'

class AddHeatPumpRtuTest < Minitest::Test
  # return file paths to test models in test directory
  def models_for_tests
    paths = Dir.glob(File.join(File.dirname(__FILE__), '../../../tests/models/*.osm'))
    paths.map { |path| File.expand_path(path) }
  end

  # return file paths to epw files in test directory
  def epws_for_tests
    paths = Dir.glob(File.join(File.dirname(__FILE__), '../../../tests/weather/*.epw'))
    paths.map { |path| File.expand_path(path) }
  end

  def load_model(osm_path)
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(OpenStudio::Path.new(osm_path))
    assert(!model.empty?)
    model.get
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    "#{File.dirname(__FILE__)}/output/#{test_name}"
  end

  def model_input_path(osm_name)
    # return models_for_tests.select { |x| set[:model] == osm_name }
    File.join(File.dirname(__FILE__), '../../../tests/models', osm_name)
  end

  def epw_input_path(epw_name)
    File.join(File.dirname(__FILE__), '../../../tests/weather', epw_name)
  end

  def model_output_path(test_name)
    "#{run_dir(test_name)}/#{test_name}.osm"
  end

  def sql_path(test_name)
    "#{run_dir(test_name)}/run/eplusout.sql"
  end

  def report_path(test_name)
    "#{run_dir(test_name)}/reports/eplustbl.html"
  end

  # applies the measure and then runs the model
  def apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false, model: nil)
    assert(File.exist?(osm_path))
    assert(File.exist?(epw_path))

    # create run directory if it does not exist
    FileUtils.mkdir_p(run_dir(test_name)) unless File.exist?(run_dir(test_name))
    assert(File.exist?(run_dir(test_name)))

    # change into run directory for tests
    start_dir = Dir.pwd
    Dir.chdir run_dir(test_name)

    # remove prior runs if they exist
    FileUtils.rm(model_output_path(test_name)) if File.exist?(model_output_path(test_name))
    FileUtils.rm(report_path(test_name)) if File.exist?(report_path(test_name))

    # copy the osm and epw to the test directory
    new_osm_path = "#{run_dir(test_name)}/#{File.basename(osm_path)}"
    FileUtils.cp(osm_path, new_osm_path)
    new_epw_path = "#{run_dir(test_name)}/#{File.basename(epw_path)}"
    FileUtils.cp(epw_path, new_epw_path)
    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # load the test model
    model = load_model(new_osm_path) if model.nil?

    # set model weather file
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(new_epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
    assert(model.weatherFile.is_initialized)

    # run the measure
    puts "\nAPPLYING MEASURE..."
    measure.run(model, runner, argument_map)
    result = runner.result
    result_success = result.value.valueName == 'Success'

    # Show the output
    show_output(result)

    # Save model
    model.save(model_output_path(test_name), true)

    if run_model && result_success
      puts "\nRUNNING MODEL..."

      std = Standard.build('90.1-2013')
      std.model_run_simulation_and_log_errors(model, run_dir(test_name))

      # Check that the model ran successfully
      assert(File.exist?(sql_path(test_name)))
    end

    # change back directory
    Dir.chdir(start_dir)

    result
  end

  def test_number_of_arguments_and_argument_names
    # This test ensures that the current test is matched to the measure inputs
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Make an empty model
    model = OpenStudio::Model::Model.new

    # Get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(10, arguments.size)
    assert_equal('backup_ht_fuel_scheme', arguments[0].name)
    assert_equal('performance_oversizing_factor', arguments[1].name)
    assert_equal('htg_sizing_option', arguments[2].name)
    assert_equal('clg_oversizing_estimate', arguments[3].name)
    assert_equal('htg_to_clg_hp_ratio', arguments[4].name)
    assert_equal('hp_min_comp_lockout_temp_f', arguments[5].name)
    assert_equal('std_perf', arguments[6].name)
    assert_equal('hr', arguments[7].name)
    assert_equal('dcv', arguments[8].name)
    assert_equal('econ', arguments[9].name)
  end

  def calc_cfm_per_ton_singlespdcoil_heating(model, cfm_per_ton_min, cfm_per_ton_max)
    # get relevant heating coils
    coils_heating = model.getCoilHeatingDXSingleSpeeds

    # check if there is at least one coil
    refute_equal(coils_heating.size, 0)

    # calc cfm/ton
    coils_heating.each do |heating_coil|
      # get coil specs
      if heating_coil.ratedTotalHeatingCapacity.is_initialized
        rated_capacity_w = heating_coil.ratedTotalHeatingCapacity.get
      end
      rated_airflow_m_3_per_sec = heating_coil.ratedAirFlowRate.get if heating_coil.ratedAirFlowRate.is_initialized

      # calc relevant metrics
      rated_capacity_ton = OpenStudio.convert(rated_capacity_w, 'W', 'ton').get
      rated_airflow_cfm = OpenStudio.convert(rated_airflow_m_3_per_sec, 'm^3/s', 'cfm').get
      cfm_per_ton = rated_airflow_cfm / rated_capacity_ton
      # puts('### DEBUGGING: ---------------------------------------------------------')
      # puts("### DEBUGGING: heating_coil = #{heating_coil.name}")
      # puts("### DEBUGGING: rated_airflow_cfm = #{rated_airflow_cfm.round(0)} cfm")
      # puts("### DEBUGGING: rated_capacity_ton = #{rated_capacity_ton.round(2)} ton")
      # puts("### DEBUGGING: cfm/ton = #{cfm_per_ton.round(2)} cfm/ton")

      # check if resultant cfm/ton is violating min/max bounds
      assert_equal(cfm_per_ton.round(0) >= cfm_per_ton_min, true)
      assert_equal(cfm_per_ton.round(0) <= cfm_per_ton_max, true)
    end
  end

  def calc_cfm_per_ton_multispdcoil_heating(model, cfm_per_ton_min, cfm_per_ton_max)
    # get relevant heating coils
    coils_heating = model.getCoilHeatingDXMultiSpeedStageDatas

    # check if there is at least one coil
    refute_equal(coils_heating.size, 0)

    # calc cfm/ton
    coils_heating.each do |heating_coil|
      # get coil specs
      if heating_coil.grossRatedHeatingCapacity.is_initialized
        rated_capacity_w = heating_coil.grossRatedHeatingCapacity.get
      end
      rated_airflow_m_3_per_sec = heating_coil.ratedAirFlowRate.get if heating_coil.ratedAirFlowRate.is_initialized

      # calc relevant metrics
      rated_capacity_ton = OpenStudio.convert(rated_capacity_w, 'W', 'ton').get
      rated_airflow_cfm = OpenStudio.convert(rated_airflow_m_3_per_sec, 'm^3/s', 'cfm').get
      cfm_per_ton = rated_airflow_cfm / rated_capacity_ton
      # puts('### DEBUGGING: ---------------------------------------------------------')
      # puts("### DEBUGGING: heating_coil = #{heating_coil.name}")
      # puts("### DEBUGGING: rated_airflow_cfm = #{rated_airflow_cfm.round(0)} cfm")
      # puts("### DEBUGGING: rated_capacity_ton = #{rated_capacity_ton.round(2)} ton")
      # puts("### DEBUGGING: cfm/ton = #{cfm_per_ton.round(2)} cfm/ton")

      # check if resultant cfm/ton is violating min/max bounds
      assert_equal(cfm_per_ton.round(0) >= cfm_per_ton_min, true)
      assert_equal(cfm_per_ton.round(0) <= cfm_per_ton_max, true)
    end
  end

  def calc_cfm_per_ton_multispdcoil_cooling(model, cfm_per_ton_min, cfm_per_ton_max)
    # get cooling coils
    coils_cooling = model.getCoilCoolingDXMultiSpeedStageDatas

    # check if there is at least one coil
    refute_equal(coils_cooling.size, 0)

    # calc cfm/ton
    coils_cooling.each do |cooling_coil|
      # get coil specs
      if cooling_coil.grossRatedTotalCoolingCapacity.is_initialized
        rated_capacity_w = cooling_coil.grossRatedTotalCoolingCapacity.get
      end
      rated_airflow_m_3_per_sec = cooling_coil.ratedAirFlowRate.get if cooling_coil.ratedAirFlowRate.is_initialized

      # calc relevant metrics
      rated_capacity_ton = OpenStudio.convert(rated_capacity_w, 'W', 'ton').get
      rated_airflow_cfm = OpenStudio.convert(rated_airflow_m_3_per_sec, 'm^3/s', 'cfm').get
      cfm_per_ton = rated_airflow_cfm / rated_capacity_ton
      # puts('### DEBUGGING: ---------------------------------------------------------')
      # puts("### DEBUGGING: cooling_coil = #{cooling_coil.name}")
      # puts("### DEBUGGING: rated_airflow_cfm = #{rated_airflow_cfm.round(0)} cfm")
      # puts("### DEBUGGING: rated_capacity_ton = #{rated_capacity_ton.round(2)} ton")
      # puts("### DEBUGGING: cfm/ton = #{cfm_per_ton.round(2)} cfm/ton")

      # check if resultant cfm/ton is violating min/max bounds
      assert_equal(cfm_per_ton.round(0) >= cfm_per_ton_min, true)
      assert_equal(cfm_per_ton.round(0) <= cfm_per_ton_max, true)
    end
  end

  def verify_cfm_per_ton(model, result)
    # define min and max limits of cfm/ton
    cfm_per_ton_min = 300
    cfm_per_ton_max = 450

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # initialize parameters
    performance_category = nil

    # check performance category
    result.stepValues.each do |input_arg|
      next unless input_arg.name == 'std_perf'

      performance_category = if input_arg.valueAsBoolean == true
                               'standard'
                             else
                               'advanced'
                             end
    end
    # puts("### DEBUGGING: performance_category = #{performance_category}")
    refute_equal(performance_category, nil)

    # loop through coils and check cfm/ton values
    if performance_category.include?('advanced')

      calc_cfm_per_ton_multispdcoil_cooling(model, cfm_per_ton_min, cfm_per_ton_max)
      calc_cfm_per_ton_multispdcoil_heating(model, cfm_per_ton_min, cfm_per_ton_max)

    elsif performance_category.include?('standard')

      calc_cfm_per_ton_multispdcoil_cooling(model, cfm_per_ton_min, cfm_per_ton_max)
      calc_cfm_per_ton_singlespdcoil_heating(model, cfm_per_ton_min, cfm_per_ton_max)

    end
  end

  def verify_hp_rtu(test_name, model, measure, argument_map, osm_path, epw_path)
    # get initial gas heating coils
    li_gas_htg_coils_initial = model.getCoilHeatingGass

    # get initial number of applicable air loops
    li_unitary_sys_initial = model.getAirLoopHVACUnitarySystems

    # get initial unitary system schedules for outdoor air and general operation
    # these will be compared against applied HP-RTU system
    dict_oa_sched_min_initial = {}
    dict_min_oa_initial = {}
    dict_max_oa_initial = {}
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
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(test_name))

    # get final gas heating coils
    li_gas_htg_coils_final = model.getCoilHeatingGass

    # assert gas heating coils have been removed
    assert_equal(li_gas_htg_coils_final.size, 0)

    # get list of final unitary systems
    li_unitary_sys_final = model.getAirLoopHVACUnitarySystems

    # assert same number of unitary systems as initial
    assert_equal(li_unitary_sys_initial.size, li_unitary_sys_final.size)

    # get final unitary system schedules for outdoor air and general operation
    # these will be compared against original system
    dict_oa_sched_min_final = {}
    dict_min_oa_final = {}
    dict_max_oa_final = {}
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
      assert_in_delta(htg_dsn_flowrate.to_f, htg_coil_spd4.ratedAirFlowRate.get, 0.000001)

      # assert flow rate reduces for lower speeds
      htg_coil_spd3 = htg_coil.stages[2]
      htg_coil_spd2 = htg_coil.stages[1]
      htg_coil_spd1 = htg_coil.stages[0]
      assert(htg_coil_spd4.ratedAirFlowRate.get > htg_coil_spd3.ratedAirFlowRate.get)
      assert(htg_coil_spd3.ratedAirFlowRate.get > htg_coil_spd2.ratedAirFlowRate.get)
      assert(htg_coil_spd2.ratedAirFlowRate.get > htg_coil_spd1.ratedAirFlowRate.get)

      # assert capacity reduces for lower speeds
      assert(htg_coil_spd4.grossRatedHeatingCapacity.get > htg_coil_spd3.grossRatedHeatingCapacity.get)
      assert(htg_coil_spd3.grossRatedHeatingCapacity.get > htg_coil_spd2.grossRatedHeatingCapacity.get)
      assert(htg_coil_spd2.grossRatedHeatingCapacity.get > htg_coil_spd1.grossRatedHeatingCapacity.get)

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
      assert_in_delta(clg_dsn_flowrate.to_f, clg_coil_spd4.ratedAirFlowRate.get, 0.000001)

      # assert flow rate reduces for lower speeds
      clg_coil_spd3 = clg_coil.stages[2]
      clg_coil_spd2 = clg_coil.stages[1]
      clg_coil_spd1 = clg_coil.stages[0]
      assert(clg_coil_spd4.ratedAirFlowRate.get > clg_coil_spd3.ratedAirFlowRate.get)
      assert(clg_coil_spd3.ratedAirFlowRate.get > clg_coil_spd2.ratedAirFlowRate.get)
      assert(clg_coil_spd2.ratedAirFlowRate.get > clg_coil_spd1.ratedAirFlowRate.get)

      # assert capacity reduces for lower speeds
      assert(clg_coil_spd4.grossRatedTotalCoolingCapacity.get > clg_coil_spd3.grossRatedTotalCoolingCapacity.get)
      assert(clg_coil_spd3.grossRatedTotalCoolingCapacity.get > clg_coil_spd2.grossRatedTotalCoolingCapacity.get)
      assert(clg_coil_spd2.grossRatedTotalCoolingCapacity.get > clg_coil_spd1.grossRatedTotalCoolingCapacity.get)
    end
    nil
  end

  # ##This section tests proper application of measure on fully applicable models
  # tests include:
  # 1) running model to ensure succesful completion
  # 2) checking user-specified electric backup heating is applied
  # 3) checking that all gas heating couls have been removed from model
  # 4) all air loops contain multispeed heating coil
  # 5) coil speeds capacities and flow rates are ascending
  # 6) coil speeds fall within E+ specified cfm/ton ranges

  def test_370_Small_Office_PSZ_Gas_2A
    osm_name = '370_small_office_psz_gas_2A.osm'
    epw_name = 'SC_Columbia_Metro_723100_12.epw'

    test_name = 'test_370_Small_Office_PSZ_Gas_2A'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      argument_map[arg.name] = temp_arg_var
    end

    test_result = verify_hp_rtu(test_name, model, measure, argument_map, osm_path, epw_path)
  end

  def test_370_small_office_psz_gas_coil_7A
    osm_name = '370_small_office_psz_gas_coil_7A.osm'
    epw_name = 'NE_Kearney_Muni_725526_16.epw'

    test_name = 'test_370_small_office_psz_gas_coil_7A'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      argument_map[arg.name] = temp_arg_var
    end

    test_result = verify_hp_rtu(test_name, model, measure, argument_map, osm_path, epw_path)
  end

  def test_370_warehouse_psz_gas_6A
    osm_name = '370_warehouse_psz_gas_6A.osm'
    epw_name = 'MI_DETROIT_725375_12.epw'

    test_name = 'test_370_warehouse_psz_gas_6A'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      argument_map[arg.name] = temp_arg_var
    end

    test_result = verify_hp_rtu(test_name, model, measure, argument_map, osm_path, epw_path)
  end

  def test_370_retail_psz_gas_6B
    osm_name = '370_retail_psz_gas_6B.osm'
    epw_name = 'NE_Kearney_Muni_725526_16.epw'

    test_name = 'test_370_retail_psz_gas_6B'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      argument_map[arg.name] = temp_arg_var
    end

    test_result = verify_hp_rtu(test_name, model, measure, argument_map, osm_path, epw_path)
  end

  ###########################################################################
  ###This section tests proper classification of partially-applicable building types
  def test_370_full_service_restaurant_psz_gas_coil
    osm_name = '370_full_service_restaurant_psz_gas_coil.osm'
    epw_name = 'GA_ROBINS_AFB_722175_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      argument_map[arg.name] = temp_arg_var
    end

    # get initial number of applicable air loops
    li_unitary_sys_initial = model.getAirLoopHVACUnitarySystems

    # determine air loops with/without kitchens
    tz_kitchens = []
    kitchen_htg_coils = []
    tz_all_other = []
    nonkitchen_htg_coils = []
    model.getAirLoopHVACUnitarySystems.sort.each do |unitary_sys|
      # skip kitchen spaces
      thermal_zone_names_to_exclude = %w[
        Kitchen
        kitchen
        KITCHEN
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
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    # get heating coils from final model for kitchen and non kitchen spaces
    tz_kitchens_final = []
    kitchen_htg_coils_final = []
    tz_all_other_final = []
    nonkitchen_htg_coils_final = []
    model.getAirLoopHVACUnitarySystems.sort.each do |unitary_sys|
      # skip kitchen spaces
      thermal_zone_names_to_exclude = %w[
        Kitchen
        kitchen
        KITCHEN
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
      assert(htg_coil.to_CoilHeatingDXMultiSpeed.is_initialized)
    end

    # assert kitchen spaces still contain gas coils
    kitchen_htg_coils_final.each do |htg_coil|
      assert(htg_coil.to_CoilHeatingGas.is_initialized)
    end

    # assert cfm/ton violation
    verify_cfm_per_ton(model, result)
  end

  ###########################################################################
  ###This test is for cfm/ton check for standard performance unit
  def test_370_full_service_restaurant_psz_gas_coil_std_perf
    osm_name = '370_full_service_restaurant_psz_gas_coil.osm'
    epw_name = 'GA_ROBINS_AFB_722175_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      if arg.name == 'std_perf'
        std_perf = arguments[idx].clone
        std_perf.setValue(true) # override std_perf arg
        argument_map[arg.name] = std_perf
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    # assert cfm/ton violation
    verify_cfm_per_ton(model, result)
  end

  ###########################################################################
  ###This test is for cfm/ton check for upsized unit
  def test_370_full_service_restaurant_psz_gas_coil_upsizing
    osm_name = '370_full_service_restaurant_psz_gas_coil.osm'
    epw_name = 'GA_ROBINS_AFB_722175_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      if arg.name == 'performance_oversizing_factor'
        performance_oversizing_factor = arguments[idx].clone
        performance_oversizing_factor.setValue(0.25) # override performance_oversizing_factor arg
        argument_map[arg.name] = performance_oversizing_factor
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    # assert cfm/ton violation
    verify_cfm_per_ton(model, result)
  end

  ###########################################################################
  # ###This section tests proper classification of non applicable HVAC systems

  # assert that non applicable HVAC system registers as NA
  def test_370_StripMall_Residential_AC_with_residential_forced_air_furnace_2A
    # this makes sure measure registers an na for non applicable model
    osm_name = '370_StripMall_Residential AC with residential forced air furnace_2A.osm'
    epw_name = 'TN_KNOXVILLE_723260_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      argument_map[arg.name] = temp_arg_var
    end

    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    assert_equal('NA', result.value.valueName)
  end

  # assert that non applicable HVAC system registers as NA
  def test_370_warehouse_pvav_gas_boiler_reheat_2A
    # this makes sure measure registers an na for non applicable model
    osm_name = '370_warehouse_pvav_gas_boiler_reheat_2A.osm'
    epw_name = 'TN_KNOXVILLE_723260_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      argument_map[arg.name] = temp_arg_var
    end

    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    assert_equal('NA', result.value.valueName)
  end

  # assert that non applicable HVAC system registers as NA
  def test_370_medium_office_doas_fan_coil_acc_boiler_3A
    # this makes sure measure registers an na for non applicable model
    osm_name = '370_medium_office_doas_fan_coil_acc_boiler_3A.osm'
    epw_name = 'TN_KNOXVILLE_723260_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      argument_map[arg.name] = temp_arg_var
    end

    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    assert_equal('NA', result.value.valueName)
  end

  # test that ERVs do no impact existing ERVs when ERV argument is NOT toggled
  def test_370_full_service_restaurant_psz_gas_coil_single_erv_3A
    # this makes sure measure registers an na for non applicable model
    osm_name = '370_full_service_restaurant_psz_gas_coil_single_erv_3A.osm'
    epw_name = 'SC_Columbia_Metro_723100_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      argument_map[arg.name] = temp_arg_var
    end

    # get baseline ERVs
    ervs_baseline = model.getHeatExchangerAirToAirSensibleAndLatents

    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    # assert no difference in ERVs in upgrade model
    ervs_upgrade = model.getHeatExchangerAirToAirSensibleAndLatents
    assert_equal(ervs_baseline, ervs_upgrade)
  end

  # test that ERVs do no impact non-applicable building types
  def test_370_full_service_restaurant_psz_gas_coil_single_erv_3A_na
    # this makes sure measure registers an na for non applicable model
    osm_name = '370_full_service_restaurant_psz_gas_coil_single_erv_3A.osm'
    epw_name = 'SC_Columbia_Metro_723100_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      argument_map[arg.name] = temp_arg_var
    end

    # get baseline ERVs
    ervs_baseline = model.getHeatExchangerAirToAirSensibleAndLatents

    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    # assert no difference in ERVs in upgrade model
    ervs_upgrade = model.getHeatExchangerAirToAirSensibleAndLatents
    assert_equal(ervs_baseline, ervs_upgrade)
  end
end
