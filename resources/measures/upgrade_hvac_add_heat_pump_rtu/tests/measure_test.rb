# frozen_string_literal: true

# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
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
require 'json'

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
  def set_weather_and_apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false, model: nil, apply: true, expected_results: 'Success')
    assert(File.exist?(osm_path))
    assert(File.exist?(epw_path))
    ddy_path = "#{epw_path.gsub('.epw', '')}.ddy"

    # create run directory if it does not exist
    FileUtils.mkdir_p(run_dir(test_name))
    assert(File.exist?(run_dir(test_name)))

    # change into run directory for tests
    start_dir = Dir.pwd
    Dir.chdir run_dir(test_name)

    # remove prior runs if they exist
    FileUtils.rm_f(model_output_path(test_name))
    FileUtils.rm_f(report_path(test_name))

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

    # set design days
    if File.exist?(ddy_path)

      # remove all the Design Day objects that are in the file
      model.getObjectsByType('OS:SizingPeriod:DesignDay'.to_IddObjectType).each(&:remove)

      # load ddy
      ddy_model = OpenStudio::EnergyPlus.loadAndTranslateIdf(ddy_path).get

      ddy_model.getDesignDays.sort.each do |d|
        # grab only the ones that matter
        ddy_list = [
          /Htg 99.6. Condns DB/, # Annual heating 99.6%
          /Clg .4. Condns WB=>MDB/, # Annual humidity (for cooling towers and evap coolers)
          /Clg .4. Condns DB=>MWB/, # Annual cooling
          /August .4. Condns DB=>MCWB/, # Monthly cooling DB=>MCWB (to handle solar-gain-driven cooling)
          /September .4. Condns DB=>MCWB/,
          /October .4. Condns DB=>MCWB/
        ]
        ddy_list.each do |ddy_name_regex|
          if d.name.get.to_s.match?(ddy_name_regex)
            runner.registerInfo("Adding object #{d.name}")

            # add the object to the existing model
            model.addObject(d.clone)
            break
          end
        end
      end

      # assert
      assert_equal(false, model.getDesignDays.empty?)
    end

    if apply
      # run the measure
      puts "\nAPPLYING MEASURE..."
      measure.run(model, runner, argument_map)
      result = runner.result
      result_success = result.value.valueName == 'Success'
      assert_equal(expected_results, result.value.valueName)

      # Show the output
      show_output(result)
    end

    # adding output variables (for debugging)
    out_vars = [
      'Air System Mixed Air Mass Flow Rate',
      'Fan Air Mass Flow Rate',
      'Unitary System Predicted Sensible Load to Setpoint Heat Transfer Rate',
      'Cooling Coil Total Cooling Rate',
      'Cooling Coil Electricity Rate',
      'Cooling Coil Runtime Fraction',
      'Heating Coil Heating Rate',
      'Heating Coil Electricity Rate',
      'Heating Coil Runtime Fraction',
      'Heating Coil Defrost Electricity Rate',
      'Heating Coil NaturalGas Rate',
      'Unitary System DX Coil Cycling Ratio',
      'Unitary System DX Coil Speed Ratio',
      'Unitary System DX Coil Speed Level',
      'Unitary System Total Cooling Rate',
      'Unitary System Total Heating Rate',
      'Unitary System Electricity Rate',
      'HVAC System Solver Iteration Count',
      'Site Outdoor Air Drybulb Temperature',
      'Zone Air Temperature',
      'Zone Thermostat Heating Setpoint Temperature',
      'Zone Thermostat Cooling Setpoint Temperature'
    ]
    out_vars.each do |out_var_name|
      ov = OpenStudio::Model::OutputVariable.new('ov', model)
      ov.setKeyValue('*')
      ov.setReportingFrequency('Hourly')
      ov.setVariableName(out_var_name)
    end
    model.getOutputControlFiles.setOutputCSV(true)

    # set timestep to 1 hour
    model.getTimestep.setNumberOfTimestepsPerHour(1)

    # Save model
    model.save(model_output_path(test_name), true)

    if run_model
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
    assert_equal(16, arguments.size)
    assert_equal('backup_ht_fuel_scheme', arguments[0].name)
    assert_equal('performance_oversizing_factor', arguments[1].name)
    assert_equal('htg_sizing_option', arguments[2].name)
    assert_equal('clg_oversizing_estimate', arguments[3].name)
    assert_equal('htg_to_clg_hp_ratio', arguments[4].name)
    assert_equal('hp_min_comp_lockout_temp_f', arguments[5].name)
    assert_equal('hprtu_scenario', arguments[6].name)
    assert_equal('hr', arguments[7].name)
    assert_equal('dcv', arguments[8].name)
    assert_equal('econ', arguments[9].name)
    assert_equal('roof', arguments[10].name)
    assert_equal('window', arguments[11].name)
    assert_equal('sizing_run', arguments[12].name)
    assert_equal('debug_verbose', arguments[13].name)
    assert_equal('modify_setbacks', arguments[14].name)
    assert_equal('setback_value', arguments[15].name)
  end

  def data_point_ordering_check(lookup_table_in_hash)
    tables = lookup_table_in_hash[:tables][:curves][:table]

    tables.each do |table|
      next unless table[:form] == 'MultiVariableLookupTable'

      puts("--- checking table format: #{table[:name]}")

      # Extract and sort data_point keys numerically
      points = table.select { |k, _| k.to_s.match?(/^data_point\d+$/) }
                    .sort_by { |k, _| k.to_s.match(/\d+/)[0].to_i }
                    .map { |_, v| v.split(',').first(2).map(&:to_f) }

      # Now check if x2 varies first (should see repeated x1s for several rows)
      x1s, x2s = points.transpose

      # Build pairs and check how they vary
      last_x1, last_x2 = points[0]
      x1_first_changes = 0
      x2_first_changes = 0

      points.each_cons(2) do |(x1a, x2a), (x1b, x2b)|
        if x1a != x1b && x2a == x2b
          x1_first_changes += 1
        elsif x1a == x1b && x2a != x2b
          x2_first_changes += 1
        end
      end

      # If x1 changes more frequently while x2 is stable, the ordering is wrong
      assert(x2_first_changes >= x1_first_changes, 'Invalid data point order: x1 varies before x2 in some cases')
    end
  end

  def test_table_lookup_format
    # This test ensures the format of lookup tables
    test_name = 'test_lookup_table_format'
    puts "\n######\nTEST:#{test_name}\n######\n"

    path_to_jsons = "#{__dir__}/../resources/*.json"
    json_files = Dir.glob(path_to_jsons)
    json_files.each do |file_path|
      puts("### checking json file: #{file_path}")
      begin
        content = File.read(file_path)
        hash = JSON.parse(content, symbolize_names: true)
        puts("### checking json file: #{file_path}")

        # Now `hash` is your Ruby hash from JSON
        # You can insert your test logic here
        assert(hash[:tables], "Missing :tables key in #{file_path}")

        # check lookup table format
        data_point_ordering_check(hash)
      rescue JSON::ParserError => e
        flunk "JSON parsing failed for #{file_path}: #{e.message}"
      end
    end
  end

  def biquadratic_format_check(lookup_table_in_hash, file_path)
    tables = lookup_table_in_hash[:tables][:curves][:table]

    # Add the curve name and its related mode (heating or cooling)
    list_of_biquadratic_curves_to_check = {
      'cool_cap_ft1' => 'cooling',
      'cool_cap_ft2' => 'cooling',
      'cool_cap_ft3' => 'cooling',
      'cool_cap_ft4' => 'cooling',
      'cool_eir_ft1' => 'cooling',
      'cool_eir_ft2' => 'cooling',
      'cool_eir_ft3' => 'cooling',
      'cool_eir_ft4' => 'cooling',
      'defrost_eir' => 'heating',
      'heat_cap_ft1' => 'heating',
      'heat_cap_ft2' => 'heating',
      'heat_cap_ft3' => 'heating',
      'heat_cap_ft4' => 'heating',
      'heat_eir_ft1' => 'heating',
      'heat_eir_ft2' => 'heating',
      'heat_eir_ft3' => 'heating',
      'heat_eir_ft4' => 'heating'
    }

    tables.each do |table|
      next unless table[:form] == 'BiQuadratic'
      next unless list_of_biquadratic_curves_to_check.key?(table[:name])

      mode = list_of_biquadratic_curves_to_check[table[:name]]

      case mode
      when 'cooling'
        puts("--- checking biquadratic cooling curve format: #{table[:name]}")
        max_oat = table[:maximum_independent_variable_2]
        max_iat = table[:maximum_independent_variable_1]

        assert(
          max_oat > max_iat,
          "Maximum OAT (#{max_oat}) for cooling curve seems to be lower than " \
          "Maximum IAT (#{max_iat}). Check curve (#{table[:name]}) or " \
          "mode classification in list_of_biquadratic_curves_to_check. File: #{file_path}"
        )

      when 'heating'
        puts("--- checking biquadratic heating curve format: #{table[:name]}")
        min_oat = table[:minimum_independent_variable_2]
        min_iat = table[:minimum_independent_variable_1]

        assert(
          min_oat < min_iat,
          "Minimum OAT (#{min_oat}) for heating curve seems to be higher than " \
          "Minimum IAT (#{min_iat}). Check curve (#{table[:name]}) or " \
          "mode classification in list_of_biquadratic_curves_to_check. File: #{file_path}"
        )
      end
    end
  end

  def test_biquadratic_format
    # This test ensures the format of biquadratic curves used in DX units
    test_name = 'test_biquadratic_format'
    puts "\n######\nTEST: #{test_name}\n######\n"

    path_to_jsons = "#{__dir__}/../resources/*.json"
    json_files = Dir.glob(path_to_jsons)

    json_files.each do |file_path|
      content = File.read(file_path)
      hash = JSON.parse(content, symbolize_names: true)

      assert(hash[:tables], "Missing :tables key in #{file_path}")

      # Check lookup table format
      biquadratic_format_check(hash, file_path)
    rescue JSON::ParserError => e
      flunk "JSON parsing failed for #{file_path}: #{e.message}"
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
      next unless input_arg.name == 'hprtu_scenario'

      performance_category = input_arg.valueAsString

      puts performance_category
    end
    refute_equal(performance_category, nil)

    # loop through coils and check cfm/ton values
    if performance_category.include?('high_eff')

      calc_cfm_per_ton_multispdcoil_cooling(model, cfm_per_ton_min, cfm_per_ton_max)
      calc_cfm_per_ton_multispdcoil_heating(model, cfm_per_ton_min, cfm_per_ton_max)

    elsif performance_category.match?(/standard|dualfuel/)

      calc_cfm_per_ton_multispdcoil_cooling(model, cfm_per_ton_min, cfm_per_ton_max)
      calc_cfm_per_ton_singlespdcoil_heating(model, cfm_per_ton_min, cfm_per_ton_max)

    end
  end

  def _mimic_hardsize_model(model, test_dir)
    standard = Standard.build('ComStock DOE Ref Pre-1980')

    # Run a sizing run to determine equipment capacities and flow rates
    if standard.model_run_sizing_run(model, test_dir.to_s) == false
      puts('Sizing run for Hardsize model failed, cannot hard-size model.')
      return false
    end

    # APPLY
    model.applySizingValues

    # TODO: remove once this functionality is added to the OpenStudio C++ for hard sizing UnitarySystems
    model.getAirLoopHVACUnitarySystems.each do |unitary|
      if model.version < OpenStudio::VersionString.new('3.7.0')
        unitary.setSupplyAirFlowRateMethodDuringCoolingOperation('SupplyAirFlowRate')
        unitary.setSupplyAirFlowRateMethodDuringHeatingOperation('SupplyAirFlowRate')
      end
    end
    # TODO: remove once this functionality is added to the OpenStudio C++ for hard sizing Sizing:System
    model.getSizingSystems.each do |sizing_system|
      next if sizing_system.isDesignOutdoorAirFlowRateAutosized

      sizing_system.setSystemOutdoorAirMethod('ZoneSum')
    end

    return model
  end

  def verify_hp_rtu(test_name, measure, argument_map, osm_path, epw_path)
    # set weather file but not apply measure
    result = set_weather_and_apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false, apply: false)
    model = load_model(model_output_path(test_name))

    # hardsize model
    model = _mimic_hardsize_model(model, "#{run_dir(test_name)}/SR_before")

    # get initial gas heating coils
    li_gas_htg_coils_initial = model.getCoilHeatingGass

    # get initial number of applicable air loops
    li_unitary_sys_initial = model.getAirLoopHVACUnitarySystems

    # get initial unitary system schedules for outdoor air and general operation
    # these will be compared against applied HP-RTU system
    dict_oa_sched_min_initial = {}
    dict_min_oa_initial = {}
    model.getAirLoopHVACs.sort.each do |air_loop_hvac|
      # get thermal zone for dictionary mapping
      thermal_zone = air_loop_hvac.thermalZones[0]

      # get OA schedule from OA controller
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
      controller_oa = oa_system.getControllerOutdoorAir
      oa_schedule = controller_oa.minimumOutdoorAirSchedule.get
      dict_oa_sched_min_initial[thermal_zone.name.to_s] = oa_schedule

      # get min/max outdoor air flow rate
      min_oa = controller_oa.minimumOutdoorAirFlowRate.get
      max_oa = controller_oa.maximumOutdoorAirFlowRate.get
      dict_min_oa_initial[thermal_zone.name.to_s] = min_oa
    end

    # set weather file and apply measure
    result = set_weather_and_apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false, apply: true)
    model = load_model(model_output_path(test_name))

    # hardsize model
    model = _mimic_hardsize_model(model, "#{run_dir(test_name)}/SR_after")

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
      dict_oa_sched_min_final[thermal_zone.name.to_s] = oa_schedule

      # get min/max outdoor air flow rate
      min_oa = controller_oa.minimumOutdoorAirFlowRate.get
      max_oa = controller_oa.maximumOutdoorAirFlowRate.get
      dict_min_oa_final[thermal_zone.name.to_s] = min_oa
    end

    # assert outdoor air values match between initial and new system
    model.getThermalZones.sort.each do |thermal_zone|
      assert_equal(dict_oa_sched_min_initial[thermal_zone.name.to_s], dict_oa_sched_min_final[thermal_zone.name.to_s])
      assert_in_epsilon(dict_min_oa_initial[thermal_zone.name.to_s].to_f, dict_min_oa_final[thermal_zone.name.to_s].to_f, 0.001)
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
    result
  end

  def get_cooling_coil_capacity_and_cop(model, coil)
    capacity_w = 0.0
    coil_design_cop = 0.0

    if coil.to_CoilCoolingDXSingleSpeed.is_initialized
      coil = coil.to_CoilCoolingDXSingleSpeed.get

      # capacity
      if coil.ratedTotalCoolingCapacity.is_initialized
        capacity_w = coil.ratedTotalCoolingCapacity.get
      elsif coil.autosizedRatedTotalCoolingCapacity.is_initialized
        capacity_w = coil.autosizedRatedTotalCoolingCapacity.get
      else
        raise "Cooling coil capacity not available for coil '#{coil.name}'."
      end

      # cop
      if model.version > OpenStudio::VersionString.new('3.4.0')
        coil_design_cop = coil.ratedCOP
      else
        raise "'Rated COP' not available for DX coil '#{coil.name}'." unless coil.ratedCOP.is_initialized

        coil_design_cop = coil.ratedCOP.get



      end
    elsif coil.to_CoilCoolingDXTwoSpeed.is_initialized
      coil = coil.to_CoilCoolingDXTwoSpeed.get

      # capacity
      if coil.ratedHighSpeedTotalCoolingCapacity.is_initialized
        capacity_w = coil.ratedHighSpeedTotalCoolingCapacity.get
      elsif coil.autosizedRatedHighSpeedTotalCoolingCapacity.is_initialized
        capacity_w = coil.autosizedRatedHighSpeedTotalCoolingCapacity.get
      else
        raise "Cooling coil capacity not available for coil '#{coil.name}'."
      end

      # cop, use high speed cop
      if model.version > OpenStudio::VersionString.new('3.4.0')
        coil_design_cop = coil.ratedHighSpeedCOP
      else
        raise "'Rated High Speed COP' not available for DX coil '#{coil.name}'." unless coil.ratedHighSpeedCOP.is_initialized

        coil_design_cop = coil.ratedHighSpeedCOP.get



      end
    elsif coil.to_CoilCoolingDXMultiSpeed.is_initialized
      coil = coil.to_CoilCoolingDXMultiSpeed.get

      # capacity and cop, use cop at highest capacity
      temp_capacity_w = 0.0
      coil.stages.each do |stage|
        if stage.grossRatedTotalCoolingCapacity.is_initialized
          temp_capacity_w = stage.grossRatedTotalCoolingCapacity.get
        elsif stage.autosizedGrossRatedTotalCoolingCapacity.is_initialized
          temp_capacity_w = stage.autosizedGrossRatedTotalCoolingCapacity.get
        else
          raise "Cooling coil capacity not available for coil stage '#{stage.name}'."
        end

        # update cop if highest capacity
        temp_coil_design_cop = stage.grossRatedCoolingCOP
        coil_design_cop = temp_coil_design_cop if temp_capacity_w >= capacity_w

        # update if highest capacity
        capacity_w = temp_capacity_w if temp_capacity_w > capacity_w
      end
    elsif coil.to_CoilCoolingDXVariableSpeed.is_initialized
      coil = coil.to_CoilCoolingDXVariableSpeed.get

      # capacity and cop, use cop at highest capacity
      temp_capacity_w = 0.0
      coil.speeds.each do |speed|
        temp_capacity_w = speed.referenceUnitGrossRatedTotalCoolingCapacity

        # update cop if highest capacity
        temp_coil_design_cop = speed.referenceUnitGrossRatedCoolingCOP
        coil_design_cop = temp_coil_design_cop if temp_capacity_w >= capacity_w

        # update if highest capacity
        capacity_w = temp_capacity_w if temp_capacity_w > capacity_w
      end
    else
      raise 'Design capacity is only available for DX cooling coil types CoilCoolingDXSingleSpeed, CoilCoolingDXTwoSpeed, CoilCoolingDXMultiSpeed, CoilCoolingDXVariableSpeed.'
    end

    return capacity_w, coil_design_cop
  end

  def get_heating_coil_capacity_and_cop(model, coil)
    # get coil rated capacity and cop
    capacity_w = 0.0
    coil_design_cop = 0.0
    if coil.to_CoilHeatingDXSingleSpeed.is_initialized
      coil = coil.to_CoilHeatingDXSingleSpeed.get
      if coil.ratedTotalHeatingCapacity.is_initialized
        capacity_w = coil.ratedTotalHeatingCapacity.get
      elsif coil.autosizedRatedTotalHeatingCapacity.is_initialized
        capacity_w = coil.autosizedRatedTotalHeatingCapacity.get
      else
        raise "Heating coil capacity not available for coil '#{coil.name}'."
      end

      # get rated cop and cop at lower temperatures
      coil_design_cop = coil.ratedCOP
    elsif coil.to_CoilHeatingDXMultiSpeed.is_initialized
      coil = coil.to_CoilHeatingDXMultiSpeed.get
      temp_capacity_w = 0.0
      coil.stages.each do |stage|
        if stage.grossRatedHeatingCapacity.is_initialized
          temp_capacity_w = stage.grossRatedHeatingCapacity.get
        elsif stage.autosizedGrossRatedHeatingCapacity.is_initialized
          temp_capacity_w = stage.autosizedGrossRatedHeatingCapacity.get
        else
          raise "Heating coil capacity not available for coil stage '#{stage.name}'."
        end

        # get cop and cop at lower temperatures
        # pick cop at highest capacity
        temp_coil_design_cop = stage.grossRatedHeatingCOP
        coil_design_cop = temp_coil_design_cop if temp_capacity_w >= capacity_w

        # update if highest capacity
        capacity_w = temp_capacity_w if temp_capacity_w > capacity_w
      end
    elsif coil.to_CoilHeatingDXVariableSpeed.is_initialized
      coil = coil.to_CoilHeatingDXVariableSpeed.get
      coil.speeds.each do |speed|
        temp_capacity_w = speed.referenceUnitGrossRatedHeatingCapacity

        # get cop and cop at lower temperatures
        # pick cop at highest capacity
        temp_coil_design_cop = speed.referenceUnitGrossRatedHeatingCOP
        coil_design_cop = temp_coil_design_cop if temp_capacity_w >= capacity_w

        # update if highest capacity
        capacity_w = temp_capacity_w if temp_capacity_w > capacity_w
      end
    else
      raise 'Design COP and capacity for DX heating coil unavailable because of unrecognized coil type.'
    end

    return capacity_w, coil_design_cop
  end

  def get_sizing_summary(model)
    sizing_summary = {}
    sizing_summary['AirLoopHVACUnitarySystem'] = {}
    model.getAirLoopHVACUnitarySystems.each do |airloophvacunisys|
      name_obj = airloophvacunisys.name.to_s

      # get airflows
      sizing_summary['AirLoopHVACUnitarySystem'][name_obj] = {}
      sizing_summary['AirLoopHVACUnitarySystem'][name_obj]['supplyAirFlowRateDuringCoolingOperation'] = airloophvacunisys.supplyAirFlowRateDuringCoolingOperation.get
      sizing_summary['AirLoopHVACUnitarySystem'][name_obj]['supplyAirFlowRateDuringHeatingOperation'] = airloophvacunisys.supplyAirFlowRateDuringHeatingOperation.get

      # get coil capacity: cooling
      coil = airloophvacunisys.coolingCoil.get
      capacity_w, = get_cooling_coil_capacity_and_cop(model, coil)
      sizing_summary['AirLoopHVACUnitarySystem'][name_obj]['cooling_coil_capacity_w'] = capacity_w

      # get coil capacity: heating
      coil = airloophvacunisys.heatingCoil.get
      capacity_w, = get_heating_coil_capacity_and_cop(model, coil)
      sizing_summary['AirLoopHVACUnitarySystem'][name_obj]['heating_coil_capacity_w'] = capacity_w
    end
    sizing_summary['AirLoopHVAC'] = {}
    model.getAirLoopHVACs.each do |airloophvac|
      name_obj = airloophvac.name.to_s

      # get airflows
      sizing_summary['AirLoopHVAC'][name_obj] = {}
      sizing_summary['AirLoopHVAC'][name_obj]['designSupplyAirFlowRate'] = airloophvac.designSupplyAirFlowRate.get
    end
    sizing_summary['ControllerOutdoorAir'] = {}
    model.getControllerOutdoorAirs.each do |ctrloa|
      name_obj = ctrloa.name.to_s

      # get airflows
      sizing_summary['ControllerOutdoorAir'][name_obj] = {}
      sizing_summary['ControllerOutdoorAir'][name_obj]['maximumOutdoorAirFlowRate'] = ctrloa.maximumOutdoorAirFlowRate.get
    end
    sizing_summary
  end

  # this is checking parameters between regularly sized versus upsized model
  # but when upsizing does not make any impact on hotter region
  def check_sizing_results_no_upsizing(model, sizing_summary_reference)
    model.getAirLoopHVACUnitarySystems.each do |airloophvacunisys|
      name_obj = airloophvacunisys.name.to_s

      # check airflow: cooling
      value_before = sizing_summary_reference['AirLoopHVACUnitarySystem'][name_obj]['supplyAirFlowRateDuringCoolingOperation']
      value_after = airloophvacunisys.supplyAirFlowRateDuringCoolingOperation.get
      assert_in_epsilon(value_before, value_after, 0.000001, "values do not match: AirLoopHVACUnitarySystem | #{name_obj} | supplyAirFlowRateDuringCoolingOperation")

      # check airflow: heating
      value_before = sizing_summary_reference['AirLoopHVACUnitarySystem'][name_obj]['supplyAirFlowRateDuringHeatingOperation']
      value_after = airloophvacunisys.supplyAirFlowRateDuringHeatingOperation.get
      assert_in_epsilon(value_before, value_after, 0.000001, "values do not match: AirLoopHVACUnitarySystem | #{name_obj} | supplyAirFlowRateDuringHeatingOperation")

      # check capacity: cooling
      coil = airloophvacunisys.coolingCoil.get
      value_before = sizing_summary_reference['AirLoopHVACUnitarySystem'][name_obj]['cooling_coil_capacity_w']
      value_after, = get_cooling_coil_capacity_and_cop(model, coil)
      assert_in_epsilon(value_before, value_after, 0.000001, "values do not match: AirLoopHVACUnitarySystem | #{name_obj} | cooling_coil_capacity_w")

      # check capacity: heating
      coil = airloophvacunisys.heatingCoil.get
      value_before = sizing_summary_reference['AirLoopHVACUnitarySystem'][name_obj]['heating_coil_capacity_w']
      value_after, = get_heating_coil_capacity_and_cop(model, coil)
      assert_in_epsilon(value_before, value_after, 0.000001, "values do not match: AirLoopHVACUnitarySystem | #{name_obj} | heating_coil_capacity_w")
    end
    model.getAirLoopHVACs.each do |airloophvac|
      name_obj = airloophvac.name.to_s

      # check airflow
      value_before = sizing_summary_reference['AirLoopHVAC'][name_obj]['designSupplyAirFlowRate']
      value_after = airloophvac.designSupplyAirFlowRate.get
      assert_in_epsilon(value_before, value_after, 0.000001, "values do not match: AirLoopHVAC | #{name_obj} | designSupplyAirFlowRate")
    end
    model.getControllerOutdoorAirs.each do |ctrloa|
      name_obj = ctrloa.name.to_s

      # check airflow
      value_before = sizing_summary_reference['ControllerOutdoorAir'][name_obj]['maximumOutdoorAirFlowRate']
      value_after = ctrloa.maximumOutdoorAirFlowRate.get
      assert_in_epsilon(value_before, value_after, 0.000001, "values do not match: ControllerOutdoorAir | #{name_obj} | maximumOutdoorAirFlowRate")
    end
  end

  # this is checking parameters between regularly sized versus upsized model
  # and when upsizing does make an impact on colder region
  def check_sizing_results_upsizing(model, sizing_summary_reference)
    model.getAirLoopHVACUnitarySystems.each do |airloophvacunisys|
      name_obj = airloophvacunisys.name.to_s

      # check capacity: cooling
      coil = airloophvacunisys.coolingCoil.get
      value_before = sizing_summary_reference['AirLoopHVACUnitarySystem'][name_obj]['cooling_coil_capacity_w']
      value_after, = get_cooling_coil_capacity_and_cop(model, coil)
      relative_difference = (value_after - value_before) / value_before
      assert_in_epsilon(relative_difference, 0.25, 0.01, "values difference not close to threshold: AirLoopHVACUnitarySystem | #{name_obj} | cooling_coil_capacity_w")

      # check capacity: heating
      coil = airloophvacunisys.heatingCoil.get
      value_before = sizing_summary_reference['AirLoopHVACUnitarySystem'][name_obj]['heating_coil_capacity_w']
      value_after, = get_heating_coil_capacity_and_cop(model, coil)
      relative_difference = (value_after - value_before) / value_before
      assert_in_epsilon(relative_difference, 0.25, 0.01, "values difference not close to threshold: AirLoopHVACUnitarySystem | #{name_obj} | heating_coil_capacity_w")
    end
    model.getAirLoopHVACs.each do |airloophvac|
      name_obj = airloophvac.name.to_s

      # check airflow
      value_before = sizing_summary_reference['AirLoopHVAC'][name_obj]['designSupplyAirFlowRate']
      value_after = airloophvac.designSupplyAirFlowRate.get
      assert_in_epsilon(value_after, value_before, 0.01, "values difference not within threshold: AirLoopHVAC | #{name_obj} | designSupplyAirFlowRate")
    end
    model.getControllerOutdoorAirs.each do |ctrloa|
      name_obj = ctrloa.name.to_s

      # check airflow
      value_before = sizing_summary_reference['ControllerOutdoorAir'][name_obj]['maximumOutdoorAirFlowRate']
      value_after = ctrloa.maximumOutdoorAirFlowRate.get
      assert_in_epsilon(value_after, value_before, 0.01, "values difference not within threshold: AirLoopHVAC | #{name_obj} | maximumOutdoorAirFlowRate")
    end
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

      # puts("### checking coil")
      # puts("heating_coil.name = #{heating_coil.name}")
      # puts("rated_capacity_w = #{rated_capacity_w}")
      # puts("rated_airflow_cfm = #{rated_airflow_cfm}")
      # puts("cfm_per_ton = #{cfm_per_ton}")

      # check if resultant cfm/ton is violating min/max bounds
      assert_equal(cfm_per_ton.round(0) >= cfm_per_ton_min, true, "cfm_per_ton (#{cfm_per_ton}) is not larger than the threshold of cfm_per_ton_min (#{cfm_per_ton_min}) | heating_coil = #{heating_coil.name}")
      assert_equal(cfm_per_ton.round(0) <= cfm_per_ton_max, true, "cfm_per_ton (#{cfm_per_ton}) is not smaller than the threshold of cfm_per_ton_max (#{cfm_per_ton_max}) | heating_coil = #{heating_coil.name}")
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

      # check if resultant cfm/ton is violating min/max bounds
      assert_equal(cfm_per_ton.round(0) >= cfm_per_ton_min, true, "cfm_per_ton (#{cfm_per_ton}) is not larger than the threshold of cfm_per_ton_min (#{cfm_per_ton_min}) | heating_coil = #{heating_coil.name}")
      assert_equal(cfm_per_ton.round(0) <= cfm_per_ton_max, true, "cfm_per_ton (#{cfm_per_ton}) is not smaller than the threshold of cfm_per_ton_max (#{cfm_per_ton_max}) | heating_coil = #{heating_coil.name}")
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

      # puts("### checking coil")
      # puts("cooling_coil.name = #{cooling_coil.name}")
      # puts("rated_capacity_w = #{rated_capacity_w}")
      # puts("rated_airflow_cfm = #{rated_airflow_cfm}")
      # puts("cfm_per_ton = #{cfm_per_ton}")

      # check if resultant cfm/ton is violating min/max bounds
      assert_equal(cfm_per_ton.round(0) >= cfm_per_ton_min, true, "cfm_per_ton (#{cfm_per_ton}) is not larger than the threshold of cfm_per_ton_min (#{cfm_per_ton_min}) | cooling_coil = #{cooling_coil.name}")
      assert_equal(cfm_per_ton.round(0) <= cfm_per_ton_max, true, "cfm_per_ton (#{cfm_per_ton}) is not smaller than the threshold of cfm_per_ton_max (#{cfm_per_ton_max}) | cooling_coil = #{cooling_coil.name}")
    end
  end

  # ##########################################################################
  # # Single building result examples
  # def test_single_building_result_examples
  #   osm_epw_pair = {
  #     # '380_Small_Office_psz_gas_1zone_not_hard_sized.osm' => 'USA_AK_Fairbanks.Intl.AP.702610_TMY3.epw',
  #     '380_Small_Office_psz_gas_1zone_not_hard_sized.osm' => 'USA_GA_Atlanta-Hartsfield-Jackson.Intl.AP.722190_TMY3.epw',
  #     # '380_Small_Office_psz_gas_1zone_not_hard_sized.osm' => 'USA_HI_Honolulu.Intl.AP.911820_TMY3.epw',
  #   }

  #   test_name = 'test_single_building_result_examples'

  #   puts "\n######\nTEST:#{test_name}\n######\n"

  #   osm_epw_pair.each_with_index do |(osm_name, epw_name), idx_run|

  #     osm_path = model_input_path(osm_name)
  #     epw_path = epw_input_path(epw_name)

  #     # Create an instance of the measure
  #     measure = AddHeatPumpRtu.new

  #     # Load the model; only used here for populating arguments
  #     model = load_model(osm_path)

  #     # get arguments
  #     arguments = measure.arguments(model)
  #     argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

  #     # populate specific argument for testing
  #     arguments.each_with_index do |arg, idx|
  #       temp_arg_var = arg.clone
  #       case arg.name
  #       when 'sizing_run'
  #         sizing_run = arguments[idx].clone
  #         sizing_run.setValue(true)
  #         argument_map[arg.name] = sizing_run
  #       when 'hprtu_scenario'
  #         hprtu_scenario = arguments[idx].clone
  #         hprtu_scenario.setValue('two_speed_standard_eff') # variable_speed_high_eff, two_speed_standard_eff
  #         argument_map[arg.name] = hprtu_scenario
  #       when 'performance_oversizing_factor'
  #         performance_oversizing_factor = arguments[idx].clone
  #         performance_oversizing_factor.setValue(0.0)
  #         argument_map[arg.name] = performance_oversizing_factor
  #       when 'window'
  #         window = arguments[idx].clone
  #         window.setValue(true)
  #         argument_map[arg.name] = window
  #       when 'debug_verbose'
  #         debug_verbose = arguments[idx].clone
  #         debug_verbose.setValue(true)
  #         argument_map[arg.name] = debug_verbose
  #       else
  #         argument_map[arg.name] = temp_arg_var
  #       end
  #     end

  #     # Don't apply the measure to the model and run the model
  #     result = set_weather_and_apply_measure_and_run("#{test_name}_#{idx_run}_b", measure, argument_map, osm_path, epw_path, run_model: true, apply: false)
  #     model = load_model(model_output_path("#{test_name}_#{idx_run}_b"))

  #     # Apply the measure to the model and run the model
  #     result = set_weather_and_apply_measure_and_run("#{test_name}_#{idx_run}_u", measure, argument_map, osm_path, epw_path, run_model: true, apply: true)
  #     model = load_model(model_output_path("#{test_name}_#{idx_run}_u"))

  #   end
  # end

  # ##########################################################################
  # This section tests upsizing algorithm
  # tests compare:
  # 1) regularly sized model versus upsized model in cold region
  # 2) regularly sized model versus upsized model in hot region
  def test_sizing_model_in_alaska
    osm_name = 'small_office_psz_not_hard_sized.osm'
    epw_name = 'USA_AK_Fairbanks.Intl.AP.702610_TMY3.epw'

    test_name = 'test_sizing_model_in_alaska'

    lookup_table_test = {
      table_name: 'c_cap_high_T',
      ind1: 22.22,
      ind2: 29.44,
      dep: 1.1677
    }

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

    # populate specific argument for testing
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      case arg.name
      when 'sizing_run'
        sizing_run = arguments[idx].clone
        sizing_run.setValue(true)
        argument_map[arg.name] = sizing_run
      when 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('two_speed_standard_eff') # variable_speed_high_eff, two_speed_standard_eff
        argument_map[arg.name] = hprtu_scenario
      when 'performance_oversizing_factor'
        performance_oversizing_factor = arguments[idx].clone
        performance_oversizing_factor.setValue(0.0)
        argument_map[arg.name] = performance_oversizing_factor
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run("#{test_name}_b", measure, argument_map, osm_path, epw_path, run_model: false, apply: true)
    model = load_model(model_output_path("#{test_name}_b"))

    # get sizing info from regular sized model
    sizing_summary_reference = get_sizing_summary(model)

    # populate specific argument for testing: upsizing scenario
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      if arg.name == 'performance_oversizing_factor'
        performance_oversizing_factor = arguments[idx].clone
        performance_oversizing_factor.setValue(0.25)
        argument_map[arg.name] = performance_oversizing_factor
      end
    end

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run("#{test_name}_a", measure, argument_map, osm_path, epw_path, run_model: false, apply: true)
    model = load_model(model_output_path("#{test_name}_a"))

    # check performance category
    performance_category = nil
    result.stepValues.each do |input_arg|
      next unless input_arg.name == 'hprtu_scenario'

      performance_category = input_arg.valueAsString
    end

    # test lookup table values
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    if performance_category == 'two_speed_standard_eff'
      # Check if lookup table is available
      lookup_table_name = lookup_table_test[:table_name]
      # table_multivar_lookups = model.getTableMultiVariableLookups
      table_multivar_lookups = model.getTableLookups
      lookup_table = table_multivar_lookups.find { |table| table.name.to_s == lookup_table_name }
      refute_nil(lookup_table, "Cannot find table named #{lookup_table_name} from model.")

      # Compare table lookup value against hard-coded values
      dep_var_ref = lookup_table_test[:dep]
      dep_var = AddHeatPumpRtu.get_dep_var_from_lookup_table_with_interpolation(runner, lookup_table, lookup_table_test[:ind1], lookup_table_test[:ind2])
      # puts("### lookup table test")
      # puts("--- lookup_table_name = #{lookup_table_name}")
      # puts("--- input_var1 = #{lookup_table_test[:ind1]} | input_var2 = #{lookup_table_test[:ind2]}")
      # puts("--- dep_var reference = #{dep_var_ref} | dep_var from model = #{dep_var}")
      assert_in_epsilon(dep_var_ref, dep_var, 0.001, "Table lookup value test didn't pass: table name = #{lookup_table_name} | ind_var1 = #{lookup_table_test[:ind1]} | ind_var2 = #{lookup_table_test[:ind2]} | expected #{dep_var_ref} but got #{dep_var}")
    end

    # compare sizing summary of upsizing model with regular sized model
    check_sizing_results_upsizing(model, sizing_summary_reference)
  end

  def test_sizing_model_in_hawaii
    osm_name = 'small_office_psz_not_hard_sized.osm'
    epw_name = 'USA_HI_Honolulu.Intl.AP.911820_TMY3.epw'

    test_name = 'test_sizing_model_in_hawaii'

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

    # populate specific argument for testing
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      case arg.name
      when 'sizing_run'
        sizing_run = arguments[idx].clone
        sizing_run.setValue(true)
        argument_map[arg.name] = sizing_run
      when 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff') # variable_speed_high_eff, two_speed_standard_eff
        argument_map[arg.name] = hprtu_scenario
      when 'performance_oversizing_factor'
        performance_oversizing_factor = arguments[idx].clone
        performance_oversizing_factor.setValue(0.0)
        argument_map[arg.name] = performance_oversizing_factor
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run("#{test_name}_b", measure, argument_map, osm_path, epw_path, run_model: false, apply: true)
    model = load_model(model_output_path("#{test_name}_b"))

    # get sizing info from regular sized model
    sizing_summary_reference = get_sizing_summary(model)

    # populate specific argument for testing: upsizing scenario
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      if arg.name == 'performance_oversizing_factor'
        performance_oversizing_factor = arguments[idx].clone
        performance_oversizing_factor.setValue(0.25)
        argument_map[arg.name] = performance_oversizing_factor
      end
    end

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run("#{test_name}_a", measure, argument_map, osm_path, epw_path, run_model: false, apply: true)
    model = load_model(model_output_path("#{test_name}_a"))

    # compare sizing summary of upsizing model with regular sized model
    check_sizing_results_no_upsizing(model, sizing_summary_reference)
  end

  # ##########################################################################
  # This section tests proper application of measure on fully applicable models
  # tests include:
  # 1) running model to ensure succesful completion
  # 2) checking user-specified electric backup heating is applied
  # 3) checking that all gas heating couls have been removed from model
  # 4) all air loops contain multispeed heating coil
  # 5) coil speeds capacities and flow rates are ascending
  # 6) coil speeds fall within E+ specified cfm/ton ranges
  # 7) check roof/window measure related variables are saved or not saved in model

  def test_380_small_office_psz_gas_2a
    osm_name = '380_Small_Office_PSZ_Gas_2A.osm'
    epw_name = 'SC_Columbia_Metro_723100_12.epw'

    test_name = 'test_380_Small_Office_PSZ_Gas_2A'

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
      case arg.name
      when 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff') # override std_perf arg
        argument_map[arg.name] = hprtu_scenario
      when 'roof'
        roof = arguments[idx].clone
        roof.setValue(true)
        argument_map[arg.name] = roof
      when 'window'
        window = arguments[idx].clone
        window.setValue(true)
        argument_map[arg.name] = window
      else
        argument_map[arg.name] = temp_arg_var
      end
    end
    test_result = verify_hp_rtu(test_name, measure, argument_map, osm_path, epw_path)

    # check roof/window measure implementation
    roof_measure_implemented = false
    window_measure_implemented = false
    test_result = JSON.parse(test_result.to_s)
    test_result['step_values'].each do |step_value|
      # check if roof measure variable is available
      if step_value['name'] == 'env_roof_insul_roof_area_ft_2'
        roof_measure_implemented = true
      end

      # check if window measure variable is available
      if step_value['name'] == 'env_secondary_window_fen_area_ft_2'
        window_measure_implemented = true
      end
    end
    assert_equal(roof_measure_implemented, true, 'cannot find variable that was saved in roof upgrade measure via registerValue: env_roof_insul_roof_area_ft_2')
    assert_equal(window_measure_implemented, true, 'cannot find variable that was saved in window upgrade measure via registerValue: env_secondary_window_fen_area_ft_2')
  end

  def test_380_small_office_psz_gas_coil_7a
    osm_name = '380_small_office_psz_gas_coil_7A.osm'
    epw_name = 'NE_Kearney_Muni_725526_16.epw'

    test_name = 'test_380_small_office_psz_gas_coil_7A'

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
      if arg.name == 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff') # override std_perf arg
        argument_map[arg.name] = hprtu_scenario
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    test_result = verify_hp_rtu(test_name, measure, argument_map, osm_path, epw_path)

    # check roof/window measure implementation
    roof_measure_implemented = false
    window_measure_implemented = false
    test_result = JSON.parse(test_result.to_s)
    test_result['step_values'].each do |step_value|
      # check if roof measure variable is available
      if step_value['name'] == 'env_roof_insul_roof_area_ft_2'
        roof_measure_implemented = true
      end

      # check if window measure variable is available
      if step_value['name'] == 'env_secondary_window_fen_area_ft_2'
        window_measure_implemented = true
      end
    end
    assert_equal(roof_measure_implemented, false, 'cannot find variable that was saved in roof upgrade measure via registerValue: env_roof_insul_roof_area_ft_2')
    assert_equal(window_measure_implemented, false, 'cannot find variable that was saved in window upgrade measure via registerValue: env_secondary_window_fen_area_ft_2')
  end

  def test_small_office_psz_not_hard_sized
    osm_name = 'small_office_psz_not_hard_sized.osm'
    epw_name = 'USA_AK_Fairbanks.Intl.AP.702610_TMY3.epw'

    test_name = 'test_small_office_psz_not_hard_sized'

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
      if arg.name == 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff')
        argument_map[arg.name] = hprtu_scenario
      elsif arg.name == 'roof'
        roof = arguments[idx].clone
        roof.setValue(true)
        argument_map[arg.name] = roof
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    test_result = verify_hp_rtu(test_name, measure, argument_map, osm_path, epw_path)

    # check roof/window measure implementation
    roof_measure_implemented = false
    window_measure_implemented = false
    test_result = JSON.parse(test_result.to_s)
    test_result['step_values'].each do |step_value|
      # check if roof measure variable is available
      if step_value['name'] == 'env_roof_insul_roof_area_ft_2'
        roof_measure_implemented = true
      end

      # check if window measure variable is available
      if step_value['name'] == 'env_secondary_window_fen_area_ft_2'
        window_measure_implemented = true
      end
    end
    assert_equal(roof_measure_implemented, true, 'cannot find variable that was saved in roof upgrade measure via registerValue: env_roof_insul_roof_area_ft_2')
    assert_equal(window_measure_implemented, false, 'cannot find variable that was saved in window upgrade measure via registerValue: env_secondary_window_fen_area_ft_2')
  end

  def test_380_retail_psz_gas_6b
    osm_name = '380_retail_psz_gas_6B.osm'
    epw_name = 'NE_Kearney_Muni_725526_16.epw'

    test_name = 'test_380_retail_psz_gas_6B'

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
      if arg.name == 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff') # override std_perf arg
        argument_map[arg.name] = hprtu_scenario
      elsif arg.name == 'window'
        window = arguments[idx].clone
        window.setValue(true)
        argument_map[arg.name] = window
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    test_result = verify_hp_rtu(test_name, measure, argument_map, osm_path, epw_path)

    # check roof/window measure implementation
    roof_measure_implemented = false
    window_measure_implemented = false
    test_result = JSON.parse(test_result.to_s)
    test_result['step_values'].each do |step_value|
      # check if roof measure variable is available
      if step_value['name'] == 'env_roof_insul_roof_area_ft_2'
        roof_measure_implemented = true
      end

      # check if window measure variable is available
      if step_value['name'] == 'env_secondary_window_fen_area_ft_2'
        window_measure_implemented = true
      end
    end
    assert_equal(roof_measure_implemented, false, 'cannot find variable that was saved in roof upgrade measure via registerValue: env_roof_insul_roof_area_ft_2')
    assert_equal(window_measure_implemented, true, 'cannot find variable that was saved in window upgrade measure via registerValue: env_secondary_window_fen_area_ft_2')
  end

  ##########################################################################
  # This section tests proper classification of partially-applicable building types
  def test_380_full_service_restaurant_psz_gas_coil
    osm_name = '380_full_service_restaurant_psz_gas_coil.osm'
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
      if arg.name == 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff') # override std_perf arg
        argument_map[arg.name] = hprtu_scenario
      else
        argument_map[arg.name] = temp_arg_var
      end
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
      thermal_zone_names_to_exclude = ['Kitchen', 'kitchen', 'KITCHEN']
      if thermal_zone_names_to_exclude.any? { |word| unitary_sys.name.to_s.include?(word) }
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
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false, apply: true)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    # get heating coils from final model for kitchen and non kitchen spaces
    tz_kitchens_final = []
    kitchen_htg_coils_final = []
    tz_all_other_final = []
    nonkitchen_htg_coils_final = []
    model.getAirLoopHVACUnitarySystems.sort.each do |unitary_sys|
      # skip kitchen spaces
      thermal_zone_names_to_exclude = ['Kitchen', 'kitchen', 'KITCHEN']
      if thermal_zone_names_to_exclude.any? { |word| unitary_sys.name.to_s.include?(word) }
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
  # This test is for cfm/ton check for standard performance unit
  def test_380_full_service_restaurant_psz_gas_coil_std_perf
    osm_name = '380_full_service_restaurant_psz_gas_coil.osm'
    epw_name = 'GA_ROBINS_AFB_722175_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    lookup_table_test = {
      table_name: 'h_cap_T',
      ind1: 21.11,
      ind2: -17.78,
      dep: 0.3974
    }

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
      if arg.name == 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('two_speed_standard_eff') # override std_perf arg
        argument_map[arg.name] = hprtu_scenario
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false, apply: true)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    # check performance category
    performance_category = nil
    result.stepValues.each do |input_arg|
      next unless input_arg.name == 'hprtu_scenario'

      performance_category = input_arg.valueAsString
    end

    # test lookup table values
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    if performance_category == 'two_speed_standard_eff'
      # Check if lookup table is available
      lookup_table_name = lookup_table_test[:table_name]
      # table_multivar_lookups = model.getTableMultiVariableLookups
      table_multivar_lookups = model.getTableLookups
      lookup_table = table_multivar_lookups.find { |table| table.name.to_s == lookup_table_name }
      refute_nil(lookup_table, "Cannot find table named #{lookup_table_name} from model.")

      # Compare table lookup value against hard-coded values
      dep_var_ref = lookup_table_test[:dep]
      dep_var = AddHeatPumpRtu.get_dep_var_from_lookup_table_with_interpolation(runner, lookup_table, lookup_table_test[:ind1], lookup_table_test[:ind2])
      # puts("### lookup table test")
      # puts("--- lookup_table_name = #{lookup_table_name}")
      # puts("--- input_var1 = #{lookup_table_test[:ind1]} | input_var2 = #{lookup_table_test[:ind2]}")
      # puts("--- dep_var reference = #{dep_var_ref} | dep_var from model = #{dep_var}")
      assert_in_epsilon(dep_var_ref, dep_var, 0.001, "Table lookup value test didn't pass: table name = #{lookup_table_name} | ind_var1 = #{lookup_table_test[:ind1]} | ind_var2 = #{lookup_table_test[:ind2]} | expected #{dep_var_ref} but got #{dep_var}")
    end

    # assert cfm/ton violation
    verify_cfm_per_ton(model, result)
  end

  ###########################################################################
  # This test is for dual fuel RTU unit
  def test_380_full_service_restaurant_psz_gas_coil_dual_fuel_rtu
    osm_name = '380_full_service_restaurant_psz_gas_coil.osm'
    epw_name = 'GA_ROBINS_AFB_722175_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    lookup_table_tests = [
      {
        table_name: 'cap_mod_cooling_high_t',
        ind1: 19.44,
        ind2: 46.11,
        dep: 0.8631
      },
      {
        table_name: 'cap_mod_cooling_low_t',
        ind1: 22.22,
        ind2: 40.56,
        dep: 1.0385
      },
      {
        table_name: 'cap_mod_heating_high_t',
        ind1: 12.78,
        ind2: 10.0,
        dep: 1.0833
      },
      {
        table_name: 'eir_mod_cooling_high_t',
        ind1: 16.67,
        ind2: 40.56,
        dep: 1.2784
      },
      {
        table_name: 'eir_mod_cooling_low_t',
        ind1: 21.67,
        ind2: 46.11,
        dep: 1.3759
      },
      {
        table_name: 'eir_mod_heating_high_t',
        ind1: 12.78,
        ind2: -23.33,
        dep: 3.1502
      }
    ]

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
      if arg.name == 'backup_ht_fuel_scheme'
        backup_ht_fuel_scheme = arguments[idx].clone
        backup_ht_fuel_scheme.setValue('dual_fuel_gas_furnace_backup')
        argument_map[arg.name] = backup_ht_fuel_scheme
      elsif arg.name == 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('carrier_48qe_dualfuel') # carrier_48qe_dualfuel, two_speed_standard_eff
        argument_map[arg.name] = hprtu_scenario
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false, apply: true)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    # check performance category
    performance_category = nil
    result.stepValues.each do |input_arg|
      next unless input_arg.name == 'hprtu_scenario'

      performance_category = input_arg.valueAsString
    end

    # check performance category
    back_up_type = nil
    result.stepValues.each do |input_arg|
      next unless input_arg.name == 'backup_ht_fuel_scheme'

      back_up_type = input_arg.valueAsString
    end

    # test lookup table values
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    if performance_category == 'carrier_48qe_dualfuel'
      lookup_table_tests.each do |lookup_table_test|
        # Check if lookup table is available
        lookup_table_name = lookup_table_test[:table_name]
        # table_multivar_lookups = model.getTableMultiVariableLookups
        table_multivar_lookups = model.getTableLookups
        lookup_table = table_multivar_lookups.find { |table| table.name.to_s == lookup_table_name }
        refute_nil(lookup_table, "Cannot find table named #{lookup_table_name} from model.")

        # Compare table lookup value against hard-coded values
        dep_var_ref = lookup_table_test[:dep]
        dep_var = AddHeatPumpRtu.get_dep_var_from_lookup_table_with_interpolation(runner, lookup_table, lookup_table_test[:ind1], lookup_table_test[:ind2])
        # puts("### lookup table test")
        # puts("--- lookup_table_name = #{lookup_table_name}")
        # puts("--- input_var1 = #{lookup_table_test[:ind1]} | input_var2 = #{lookup_table_test[:ind2]}")
        # puts("--- dep_var reference = #{dep_var_ref} | dep_var from model = #{dep_var}")
        assert_in_epsilon(dep_var_ref, dep_var, 0.001, "Table lookup value test didn't pass: table name = #{lookup_table_name} | ind_var1 = #{lookup_table_test[:ind1]} | ind_var2 = #{lookup_table_test[:ind2]} | expected #{dep_var_ref} but got #{dep_var}")
      end
    end
    if back_up_type == 'dual_fuel_gas_furnace_backup'
      number_of_applicable_airloops = 6 # hard-coded based on example model

      # count energymanagementsystem:program objects with specific naming patterns
      count_ems_prgm_init = model.getEnergyManagementSystemPrograms.select { |prgm| prgm.name.to_s.end_with?('_initialization') }.size
      count_ems_prgm = model.getEnergyManagementSystemPrograms.select { |prgm| prgm.name.to_s.end_with?('_two_stage_gas_coil') }.size

      # count energymanagementsystem:programcallingmanager objects with specific naming patterns
      count_ems_pcm_init = model.getEnergyManagementSystemProgramCallingManagers.select { |pcm| pcm.name.to_s.end_with?('_initialization') }.size
      count_ems_pcm = model.getEnergyManagementSystemProgramCallingManagers.select { |pcm| pcm.name.to_s.end_with?('_pcm_gas_coil') }.size

      # assert counts
      assert_equal(number_of_applicable_airloops, count_ems_prgm_init, "expected #{number_of_applicable_airloops} ems programs with '_initialization' but got #{count_ems_prgm_init}")
      assert_equal(number_of_applicable_airloops, count_ems_prgm, "expected #{number_of_applicable_airloops} ems programs with '_two_stage_gas_coil' but got #{count_ems_prgm}")
      assert_equal(number_of_applicable_airloops, count_ems_pcm_init, "expected #{number_of_applicable_airloops} ems program calling managers with '_initialization' but got #{count_ems_pcm_init}")
      assert_equal(number_of_applicable_airloops, count_ems_pcm, "expected #{number_of_applicable_airloops} ems program calling managers with '_two_stage_gas_coil' but got #{count_ems_pcm}")
    end

    # assert cfm/ton violation
    verify_cfm_per_ton(model, result)
  end

  ###########################################################################
  # This test is for cfm/ton check for upsized unit
  def test_380_full_service_restaurant_psz_gas_coil_upsizing
    osm_name = '380_full_service_restaurant_psz_gas_coil.osm'
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

    # get arguments
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      case arg.name
      when 'sizing_run'
        sizing_run = arguments[idx].clone
        sizing_run.setValue(false)
        argument_map[arg.name] = sizing_run
      when 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff') # variable_speed_high_eff, two_speed_standard_eff
        argument_map[arg.name] = hprtu_scenario
      when 'performance_oversizing_factor'
        performance_oversizing_factor = arguments[idx].clone
        performance_oversizing_factor.setValue(0.25) # override performance_oversizing_factor arg
        argument_map[arg.name] = performance_oversizing_factor
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false, apply: true)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    # assert cfm/ton violation
    verify_cfm_per_ton(model, result)
  end

  def test_380_small_office_psz_gas_coil_7a_upsizing_adv
    osm_name = '380_small_office_psz_gas_coil_7A.osm'
    epw_name = 'USA_AK_Fairbanks.Intl.AP.702610_TMY3.epw'

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

    # populate specific argument for testing
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      case arg.name
      when 'sizing_run'
        sizing_run = arguments[idx].clone
        sizing_run.setValue(true)
        argument_map[arg.name] = sizing_run
      when 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff') # variable_speed_high_eff, two_speed_standard_eff
        argument_map[arg.name] = hprtu_scenario
      when 'debug_verbose'
        debug_verbose = arguments[idx].clone
        debug_verbose.setValue(true)
        argument_map[arg.name] = debug_verbose
      when 'performance_oversizing_factor'
        performance_oversizing_factor = arguments[idx].clone
        performance_oversizing_factor.setValue(0.25)
        argument_map[arg.name] = performance_oversizing_factor
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    verify_cfm_per_ton(model, result)
  end

  def test_380_small_office_psz_gas_coil_7a_upsizing_std
    osm_name = '380_small_office_psz_gas_coil_7A.osm'
    epw_name = 'USA_AK_Fairbanks.Intl.AP.702610_TMY3.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    lookup_table_test = {
      table_name: 'c_eir_high_T',
      ind1: 22.22,
      ind2: 35.0,
      dep: 0.9438
    }

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate specific argument for testing
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      case arg.name
      when 'sizing_run'
        sizing_run = arguments[idx].clone
        sizing_run.setValue(true)
        argument_map[arg.name] = sizing_run
      when 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('two_speed_standard_eff') # variable_speed_high_eff, two_speed_standard_eff
        argument_map[arg.name] = hprtu_scenario
      when 'debug_verbose'
        debug_verbose = arguments[idx].clone
        debug_verbose.setValue(true)
        argument_map[arg.name] = debug_verbose
      when 'performance_oversizing_factor'
        performance_oversizing_factor = arguments[idx].clone
        performance_oversizing_factor.setValue(0.25)
        argument_map[arg.name] = performance_oversizing_factor
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    # check performance category
    performance_category = nil
    result.stepValues.each do |input_arg|
      next unless input_arg.name == 'hprtu_scenario'

      performance_category = input_arg.valueAsString
    end

    # test lookup table values
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    if performance_category == 'two_speed_standard_eff'
      # Check if lookup table is available
      lookup_table_name = lookup_table_test[:table_name]
      # table_multivar_lookups = model.getTableMultiVariableLookups
      table_multivar_lookups = model.getTableLookups
      lookup_table = table_multivar_lookups.find { |table| table.name.to_s == lookup_table_name }
      refute_nil(lookup_table, "Cannot find table named #{lookup_table_name} from model.")

      # Compare table lookup value against hard-coded values
      dep_var_ref = lookup_table_test[:dep]
      dep_var = AddHeatPumpRtu.get_dep_var_from_lookup_table_with_interpolation(runner, lookup_table, lookup_table_test[:ind1], lookup_table_test[:ind2])
      # puts("### lookup table test")
      # puts("--- lookup_table_name = #{lookup_table_name}")
      # puts("--- input_var1 = #{lookup_table_test[:ind1]} | input_var2 = #{lookup_table_test[:ind2]}")
      # puts("--- dep_var reference = #{dep_var_ref} | dep_var from model = #{dep_var}")
      assert_in_epsilon(dep_var_ref, dep_var, 0.001, "Table lookup value test didn't pass: table name = #{lookup_table_name} | ind_var1 = #{lookup_table_test[:ind1]} | ind_var2 = #{lookup_table_test[:ind2]} | expected #{dep_var_ref} but got #{dep_var}")
    end

    verify_cfm_per_ton(model, result)
  end

  ###########################################################################
  # This section tests proper classification of non applicable HVAC systems
  # assert that non applicable HVAC system registers as NA
  def test_380_strip_mall_residential_ac_with_residential_forced_air_furnace_2a
    # this makes sure measure registers an na for non applicable model
    osm_name = '380_StripMall_Residential AC with residential forced air furnace_2A.osm'
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
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false, apply: true, expected_results: 'NA')
  end

  # assert that non applicable HVAC system registers as NA
  def test_380_warehouse_pvav_gas_boiler_reheat_2a
    # this makes sure measure registers an na for non applicable model
    osm_name = '380_warehouse_pvav_gas_boiler_reheat_2A.osm'
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
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      if arg.name == 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff') # override std_perf arg
        argument_map[arg.name] = hprtu_scenario
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false, apply: true, expected_results: 'NA')
  end

  # assert that non applicable HVAC system registers as NA
  def test_380_medium_office_doas_fan_coil_acc_boiler_3a
    # this makes sure measure registers an na for non applicable model
    osm_name = '380_medium_office_doas_fan_coil_acc_boiler_3A.osm'
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
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      if arg.name == 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff') # override std_perf arg
        argument_map[arg.name] = hprtu_scenario
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false, apply: true, expected_results: 'NA')
  end

  # test that ERVs do no impact existing ERVs when ERV argument is NOT toggled
  def test_380_full_service_restaurant_psz_gas_coil_single_erv_3a
    # this makes sure measure registers an na for non applicable model
    osm_name = '380_full_service_restaurant_psz_gas_coil_single_erv_3A.osm'
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
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      if arg.name == 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff') # override std_perf arg
        argument_map[arg.name] = hprtu_scenario
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # get baseline ERVs
    ervs_baseline = model.getHeatExchangerAirToAirSensibleAndLatents

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false, apply: true)
    model = load_model(model_output_path(__method__))

    # assert no difference in ERVs in upgrade model
    ervs_upgrade = model.getHeatExchangerAirToAirSensibleAndLatents
    assert_equal(ervs_baseline, ervs_upgrade)
  end

  # test that ERVs do no impact non-applicable building types
  def test_380_full_service_restaurant_psz_gas_coil_single_erv_3a_na
    # this makes sure measure registers an na for non applicable model
    osm_name = '380_full_service_restaurant_psz_gas_coil_single_erv_3A.osm'
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
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      if arg.name == 'hprtu_scenario'
        hprtu_scenario = arguments[idx].clone
        hprtu_scenario.setValue('variable_speed_high_eff') # override std_perf arg
        argument_map[arg.name] = hprtu_scenario
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # get baseline ERVs
    ervs_baseline = model.getHeatExchangerAirToAirSensibleAndLatents

    # Apply the measure to the model and optionally run the model
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false, apply: true)
    model = load_model(model_output_path(__method__))

    # assert no difference in ERVs in upgrade model
    ervs_upgrade = model.getHeatExchangerAirToAirSensibleAndLatents
    assert_equal(ervs_baseline, ervs_upgrade)
  end

  def test_confirm_heating_setback_change_square_wave
    # confirm that any heating setbacks are now 2F
    osm_name = 'Retail_PSZ-AC.osm'
    epw_name = 'NE_Kearney_Muni_725526_16.epw'

    test_name = 'confirm_heating_setback_change_square_wave'

    puts "\n######\nTEST:#{test_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    setback_val = 2.0
    setback_value_c = setback_val * 5 / 9

    # populate argument with specified hash value if specified
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      if arg.name == 'setback_value'
        setback_value_arg = arguments[idx].clone
        setback_value_arg.setValue(setback_val) # set setback value
        argument_map[arg.name] = setback_value_arg
      elsif arg.name == 'modify_setbacks'
        modify_setbacks = arguments[idx].clone
        modify_setbacks.setValue(true)
        argument_map[arg.name] = modify_setbacks
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # run the measure
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path,
                                                   run_model: false)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))

    schedule_deltas = [] # keep track of differences between min and max values in schedules


    # Loop thru zones and look at temp setbacks
    model.getAirLoopHVACs.sort.each do |air_loop_hvac|
      puts "loop class #{air_loop_hvac.class}"
      zones = air_loop_hvac.thermalZones


      zones.sort.each do |thermal_zone|
        next unless thermal_zone.thermostatSetpointDualSetpoint.is_initialized

        zone_thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
        htg_schedule = zone_thermostat.heatingSetpointTemperatureSchedule
        if htg_schedule.empty?
          puts("Heating setpoint schedule not found for zone '#{zone.name.get}'")
          next
        elsif htg_schedule.get.to_ScheduleRuleset.empty?
          puts("Schedule '#{htg_schedule.get.name.get}' is not a ScheduleRuleset, will not be adjusted")
          next
        else
          htg_schedule = htg_schedule.get.to_ScheduleRuleset.get
        end
        profiles = [htg_schedule.defaultDaySchedule]
        htg_schedule.scheduleRules.each { |rule| profiles << rule.daySchedule }
        profiles.sort.each do |tstat_profile|
          tstat_profile.values.uniq.size
          tstat_profile_min = tstat_profile.values.min
          tstat_profile_max = tstat_profile.values.max
          schedule_deltas << (tstat_profile_max - tstat_profile_min) # assuming that any changes in the schedule during the day represent nighttime setbacks
        end
      end
    end

    # Make sure no deltas are greater than the expected setback value
    deltas_out_of_range = schedule_deltas.any? { |x| x > setback_value_c }

    puts("Temperature deltas in schedule match expected values: #{deltas_out_of_range == false}")

    assert_equal(deltas_out_of_range, false)

    true
  end

  def test_confirm_heating_setback_change_opt_start
    # confirm that any heating setbacks are now 2F
    osm_name = 'Retail_PSZ-AC_updated_39_opt_start.osm'
    epw_name = 'NE_Kearney_Muni_725526_16.epw'

    test_name = 'confirm_heating_setback_change_opt_start'

    puts "\n######\nTEST:#{test_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    setback_val = 2.0
    setback_value_c = setback_val * 5 / 9

    # populate argument with specified hash value if specified
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      if arg.name == 'setback_value'
        setback_value_arg = arguments[idx].clone
        setback_value_arg.setValue(setback_val) # set setback value
        argument_map[arg.name] = setback_value_arg
      elsif arg.name == 'modify_setbacks'
        modify_setbacks = arguments[idx].clone
        modify_setbacks.setValue(true)
        argument_map[arg.name] = modify_setbacks
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # run the measure
    result = set_weather_and_apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path,
                                                   run_model: false)
    assert_equal('Success', result.value.valueName)
    model = load_model(model_output_path(__method__))


    schedule_deltas = [] # keep track of differences between min and max values in schedules


    # Loop thru zones and look at temp setbacks
    model.getAirLoopHVACs.sort.each do |air_loop_hvac|
      zones = air_loop_hvac.thermalZones


      zones.sort.each do |thermal_zone|
        next unless thermal_zone.thermostatSetpointDualSetpoint.is_initialized

        zone_thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
        htg_schedule = zone_thermostat.heatingSetpointTemperatureSchedule
        if htg_schedule.empty?
          puts("Heating setpoint schedule not found for zone '#{zone.name.get}'")
          next
        elsif htg_schedule.get.to_ScheduleRuleset.empty?
          puts("Schedule '#{htg_schedule.get.name.get}' is not a ScheduleRuleset, will not be adjusted")
          next
        else
          htg_schedule = htg_schedule.get.to_ScheduleRuleset.get
        end
        profiles = [htg_schedule.defaultDaySchedule]
        htg_schedule.scheduleRules.each { |rule| profiles << rule.daySchedule }
        profiles.sort.each do |tstat_profile|
          working_profile = tstat_profile.values.dup
          tstat_profile_min = tstat_profile.values.min
          tstat_profile.values.max
          tstat_profile.values.each_with_index do |value, i| # find minimum except for values during opt start
            # test values for optimum start (need to be at least the third timestep in the profile to test)
            if i > 3 && possible_opt_start(i, tstat_profile, tstat_profile_min) # identify if the time step could have been part of an optimum start
              working_profile.delete(value)
            end
          end
          tstat_profile_min_adj = working_profile.min
          tstat_profile_max_adj = working_profile.max
          schedule_deltas << (tstat_profile_max_adj - tstat_profile_min_adj) # assuming that any changes in the schedule during the day represent nighttime setbacks
        end
      end
    end

    # Make sure no deltas are greater than the expected setback value
    deltas_out_of_range = schedule_deltas.any? { |x| x > setback_value_c }


    puts("Temperature deltas in schedule match expected values: #{deltas_out_of_range == false}")

    assert_equal(deltas_out_of_range, false)

    true
  end

  # ##########################################################################
  # This section tests proper application of dual fuel RTU option
  # -----------------------------
  # Constants
  # -----------------------------
  W_TO_KW = 1.0 / 1000.0
  DEFAULT_THERMAL_EFFICIENCY = 0.8

  # -----------------------------
  # Helpers
  # -----------------------------
  def normalize_header(str)
    str
      .to_s
      .gsub(/[[:space:]]+/, ' ')
      .strip
      .downcase
  end

  def sum_columns_by_substring(csv_data, substring)
    return 0.0 if csv_data.empty?

    sub = substring.downcase
    headers = csv_data.headers.select do |h|
      h.downcase.include?(sub)
    end

    csv_data.sum do |row|
      headers.sum { |h| row[h].to_f }
    end * W_TO_KW
  end

  def find_header(headers, normalized_headers, zone_name_norm, includes:)
    headers.find do |h|
      normalized_headers[h].include?(zone_name_norm) &&
        includes.all? { |s| h.include?(s) }
    end
  end

  # -----------------------------
  # CSV aggregation (simple)
  # -----------------------------
  def get_aggregated_values_from_csv(csv_data, substring)
    sum_columns_by_substring(csv_data, substring)
  end

  # -----------------------------
  # CSV aggregation (EMS-based)
  # -----------------------------
  def get_aggregated_alternative_values_from_csv(
    csv_data,
    model,
    thermal_efficiency: DEFAULT_THERMAL_EFFICIENCY
  )
    return [0.0, 0.0] if csv_data.empty?

    headers = csv_data.headers
    normalized_headers =
      headers.to_h { |h| [h, normalize_header(h)] }

    elec_equiv_kwh = 0.0
    gas_equiv_kwh  = 0.0

    label_map = {
      'wholebuilding' => 'wb',
      'office' => 'off',
      'zone' => 'zn',
      'story' => 'stry',
      'ground' => 'grnd',
      'psz-ac' => '',
      'fullservicerestaurant' => 'fsr',
      'dining' => 'din'
    }

    zone_map = []

    model.getThermalZones.each do |tz|
      full_name = tz.name.get
      zone_norm = normalize_header(full_name)

      ems_name = full_name.downcase
      label_map.each { |k, v| ems_name.gsub!(k, v) }

      ems_name =
        ems_name
        .gsub(/[^a-z0-9]/, '_')
        .gsub(/_+/, '_')
        .gsub(/^_+|_+$/, '')

      zone_data = {
        heat_rate: find_header(
          headers,
          normalized_headers,
          zone_norm,
          includes: [
            'HEAT PUMP HEATING COIL:Heating Coil Heating Rate'
          ]
        ),
        elec_rate: find_header(
          headers,
          normalized_headers,
          zone_norm,
          includes: [
            'HEAT PUMP HEATING COIL:Heating Coil Electricity Rate'
          ]
        ),
        dx_load: headers.find do |h|
          h.downcase.include?(ems_name) &&
            h.downcase.include?(
              'dx_load_during_hybrid_heating'
            )
        end,
        plr_1: headers.find do |h|
          h.downcase.include?(ems_name) &&
            h.downcase.include?('status_heating_plr_1')
        end,
        plr_2: headers.find do |h|
          h.downcase.include?(ems_name) &&
            h.downcase.include?('status_heating_plr_2')
        end
      }

      missing =
        zone_data.select { |_, v| v.nil? }.keys

      if missing.empty?
        zone_map << zone_data
      else
        puts(
          "--- Skipping Zone: #{full_name}, " \
          "missing columns: #{missing.join(', ')} ---"
        )
      end
    end

    csv_data.each do |row|
      zone_map.each do |z|
        heat_rate = row[z[:heat_rate]].to_f
        elec_rate = row[z[:elec_rate]].to_f
        dx_load   = row[z[:dx_load]].to_f
        plr_1     = row[z[:plr_1]].to_f
        plr_2     = row[z[:plr_2]].to_f

        next if dx_load <= 0

        op_cop =
          elec_rate.positive? ? heat_rate / elec_rate : 0.0
        plr =
          plr_2.positive? ? plr_2 : plr_1
        plf = [plr, 0.7].max

        if op_cop.positive?
          elec_equiv_kwh +=
            (dx_load / op_cop) * W_TO_KW
        end

        if plr.positive?
          gas_equiv_kwh +=
            (dx_load / thermal_efficiency / plf) *
            W_TO_KW
        end
      end
    end

    [elec_equiv_kwh, gas_equiv_kwh]
  end

  # -----------------------------
  # Measure argument prep
  # -----------------------------
  def prepare_arg_map(measure, model, hp_t, fuel_scheme)
    args = measure.arguments(model)
    map =
      OpenStudio::Measure
      .convertOSArgumentVectorToMap(args)

    settings = {
      'hp_min_comp_lockout_temp_f' => hp_t,
      'hprtu_scenario' =>
        'carrier_48qe_dualfuel',
      'backup_ht_fuel_scheme' => fuel_scheme,
      'debug_verbose' => true
    }

    settings.each do |name, val|
      next unless map[name]

      arg = map[name].clone
      arg.setValue(val)
      map[name] = arg
    end

    map
  end

  # -----------------------------
  # Capacity calculations
  # -----------------------------
  def calculate_capacities(model, type)
    dx_cap_w  = 0.0
    gas_cap_w = 0.0

    model.getCoilHeatingDXSingleSpeeds.each do |coil|
      next unless
        coil.ratedTotalHeatingCapacity.is_initialized

      cap = coil.ratedTotalHeatingCapacity.get
      dx_cap_w += cap

      next unless type == 'up'

      _, stage2_w =
        AddHeatPumpRtu.get_dual_fuel_gas_coil_capacity(cap, 0, true)

      gas_cap_w += stage2_w
    end

    if type == 'ref'
      model.getCoilHeatingGass.each do |coil|
        next unless coil.nominalCapacity.is_initialized

        gas_cap_w += coil.nominalCapacity.get
      end
    end

    { dx_w: dx_cap_w, gas_w: gas_cap_w }
  end

  # -----------------------------
  # Usage extraction
  # -----------------------------
  def get_usage_data(run_id, type, _test_name, model)
    csv_path =
      "#{File.dirname(__FILE__)}/output/" \
      "#{run_id}/run/eplusout.csv"

    csv_data = CSV.read(csv_path, headers: true)

    gas_substring =
      if type == 'up'
        '_ov_fuel_usage'
      else
        'GAS BACKUP COIL:Heating Coil NaturalGas Rate ' \
          '[W](Hourly)'
      end

    hp_elec_equiv, hp_gas_equiv =
      if type == 'up'
        get_aggregated_alternative_values_from_csv(
          csv_data,
          model
        )
      else
        [0.0, 0.0]
      end

    {
      hp_elec_kwh:
        sum_columns_by_substring(
          csv_data,
          'HEAT PUMP HEATING COIL:Heating Coil ' \
          'Electricity Rate [W](Hourly)'
        ),
      gas_kwh:
        sum_columns_by_substring(csv_data, gas_substring),
      hp_load_kwh:
        sum_columns_by_substring(
          csv_data,
          'dx_load_during_hybrid_heating [W](Hourly)'
        ),
      defrost_kwh:
        sum_columns_by_substring(
          csv_data,
          'HEAT PUMP HEATING COIL:Heating Coil ' \
          'Defrost Electricity Rate [W](Hourly)'
        ),
      hp_elec_equiv_kwh: hp_elec_equiv,
      hp_gas_equiv_kwh: hp_gas_equiv
    }
  end

  # -----------------------------
  # Results output
  # -----------------------------
  def save_results_to_csv(results)
    path =
      "#{File.dirname(__FILE__)}/output/" \
      'overall_results.csv'

    headers = [
      'osm', 'epw', 'hp_t', 'type', 'dx_w', 'gas_w', 'hp_kwh', 'gas_kwh', 'gas_equiv_kwh', 'defrost_kwh'
    ]

    CSV.open(path, 'w') do |csv|
      csv << headers
      results.each { |r| csv << r }
    end
  end

  # -----------------------------
  # Main test runner
  # -----------------------------
  def test_dual_fuel_rtu_example_models
    osm_epw_pair = {
      '310_retailstandalone_DC.osm' => 'G5101370.epw',
      '310_retailstandalone_MA.osm' => 'G0900110.epw',
      '310_retailstandalone_MN.osm' => 'G2701230.epw'
    }

    hp_lockout_temps = [-10, 0, 17, 47]
    results = []
    test_name = 'test_dual_fuel_rtu_example_models'
    min_cop = 3.0
    max_cop = 4.0
    gas_thermal_efficiency = 0.8

    puts "\n######\nTEST: #{test_name}\n######\n"

    osm_epw_pair.each_with_index do |(osm, epw), idx|
      osm_p = model_input_path(osm)
      epw_p = epw_input_path(epw)

      hp_lockout_temps.each do |hp_t|
        scenarios = [
          {
            type: 'ref',
            fuel: 'match_original_primary_heating_fuel'
          },
          {
            type: 'up',
            fuel: 'dual_fuel_gas_furnace_backup'
          }
        ]

        scenarios.each do |scen|
          run_id =
            "#{test_name}_#{idx}_" \
            "#{scen[:type]}_#{hp_t.to_i}"

          measure = AddHeatPumpRtu.new
          model   = load_model(osm_p)

          arg_map =
            prepare_arg_map(
              measure,
              model,
              hp_t,
              scen[:fuel]
            )

          if File.exist?(sql_path(run_id)) && File.exist?(model_output_path(run_id))
            puts("Skipping run #{run_id} because results already exist.")
          else
            set_weather_and_apply_measure_and_run(
              run_id,
              measure,
              arg_map,
              osm_p,
              epw_p,
              run_model: true,
              apply: true
            )
          end

          out_model =
            load_model(model_output_path(run_id))

          caps  =
            calculate_capacities(out_model, scen[:type])
          usage =
            get_usage_data(
              run_id,
              scen[:type],
              test_name,
              out_model
            )

          results << [
            osm, epw, hp_t, scen[:type],
            caps[:dx_w], caps[:gas_w],
            usage[:hp_elec_kwh],
            usage[:gas_kwh],
            0.0,
            usage[:defrost_kwh]
          ]

          next unless scen[:type] == 'up'

          results << [
            osm, epw, hp_t, 'up_with_gas_equiv',
            caps[:dx_w], caps[:gas_w],
            usage[:hp_elec_kwh] -
            usage[:hp_elec_equiv_kwh],
            usage[:gas_kwh] +
            usage[:hp_gas_equiv_kwh],
            usage[:hp_gas_equiv_kwh],
            usage[:defrost_kwh]
          ]
        end
      end
    end

    # Remove the index that contains the specific lockout temp (hp_t)
    # from the grouping key if it was there, and ensure 'type' is consistent
    # across the temperatures you want to compare.
    grouped_results = results.group_by { |r| [r[0], r[1], r[3]] }
    grouped_results.each do |metadata, rows|
      puts('### --------------------------------------------------------------')
      puts("### metadata = #{metadata}")
      # Sort by lockout temperature descending (e.g., [40, 20, 0])
      # As temperature goes DOWN, we expect specific trends.
      sorted_rows = rows.sort_by { |r| r[2] }.reverse

      puts("### sorted_rows = #{sorted_rows}")

      sorted_rows.each_cons(2) do |higher_t_row, lower_t_row|
        # Variables for clarity
        h_temp = higher_t_row[2]
        l_temp = lower_t_row[2]

        # HP Electric Usage (Column 6)
        h_hp_kwh = higher_t_row[6]
        l_hp_kwh = lower_t_row[6]

        # Defrost Usage (Column 9)
        h_defrost = higher_t_row[9]
        l_defrost = lower_t_row[9]

        # Gas/Backup Usage (Column 7) - Adding this as it completes the logic!
        h_gas = higher_t_row[7]
        l_gas = lower_t_row[7]

        puts("--- h_temp = #{h_temp} | h_hp_kwh = #{h_hp_kwh} | h_defrost = #{h_defrost} | h_gas = #{h_gas}")
        puts("--- l_temp = #{l_temp} | l_hp_kwh = #{l_hp_kwh} | l_defrost = #{l_defrost} | l_gas = #{l_gas}")

        # 1. HP Usage Check: Lower Lockout -> More HP runtime -> Higher HP kWh
        if (l_hp_kwh - h_hp_kwh).abs / h_hp_kwh > 0.1 # Only assert if there's a meaningful difference to avoid noise
          assert(
            l_hp_kwh > h_hp_kwh,
            "Trend Error (HP kWh) for #{metadata}: At #{l_temp}F, HP usage should be > than at #{h_temp}F."
          )
        end

        # 2. Defrost Check: Lower Lockout -> More runtime in frost zones -> Higher Defrost kWh
        if (l_defrost - h_defrost).abs / h_defrost > 0.1 # Only assert if there's a meaningful difference to avoid noise
          assert(
            l_defrost > h_defrost,
            "Trend Error (Defrost) for #{metadata}: At #{l_temp}F, Defrost should be > than at #{h_temp}F."
          )
        end

        # 3. Gas Check: Lower Lockout -> Less reliance on boiler -> Lower Gas kWh
        if (l_gas - h_gas).abs / h_gas > 0.1 # Only assert if there's a meaningful difference to avoid noise
          assert(
            l_gas < h_gas,
            "Trend Error (Gas) for #{metadata}: At #{l_temp}F, Gas usage should be < than at #{h_temp}F."
          )
        end
      end

      # assert: equivalent gas usage conversion is within COP range of 3 and 4 and gas thermal efficiency of 0.8
      puts('### --------------------------------------------------------------')
      puts('### Performing COP range check for gas equivalent calculations...')
      # 1. Identify the 'up' rows for comparison
      # We look for the group that matches the current model/weather but is tagged 'up'
      up_metadata = [metadata[0], metadata[1], 'up']
      up_rows = grouped_results[up_metadata]
      rows.each do |row|
        # Only run this logic for the 'up_with_gas_equiv' rows
        next unless metadata[2] == 'up_with_gas_equiv'

        # 2. Find the matching 'up' row (matching by temperature at index 2)
        current_temp = row[2]
        matching_up_row = up_rows.find { |r| r[2] == current_temp }

        if matching_up_row
          # HP usage in 'up' scenario (higher)
          up_hp_kwh = matching_up_row[6]
          # HP usage in 'up_with_gas_equiv' scenario (lower)
          equiv_hp_kwh = row[6]

          # 3. Calculate the delta (The HP energy that was replaced by gas)
          hp_kwh_delta = up_hp_kwh - equiv_hp_kwh
          gas_equiv_kwh = row[8]

          # Calculation logic: (Delta_HP_kWh * COP) / Efficiency
          min_expected_gas = (hp_kwh_delta * min_cop) / gas_thermal_efficiency
          max_expected_gas = (hp_kwh_delta * max_cop) / gas_thermal_efficiency

          puts("--- Calculating reasonable gas kWh range from: HP Delta: #{hp_kwh_delta.round(2)} kWh | COP Range: [#{min_cop} - #{max_cop}] | Gas Thermal Efficiency: #{gas_thermal_efficiency}")
          puts("--- Range: [#{min_expected_gas.round(2)} - #{max_expected_gas.round(2)}] | Actual: #{gas_equiv_kwh.round(2)}")

          assert(
            gas_equiv_kwh >= min_expected_gas && gas_equiv_kwh <= max_expected_gas,
            "COP Range Error for #{metadata}: Gas equiv (#{gas_equiv_kwh.round(2)}) is outside " \
            "expected range based on HP Delta of #{hp_kwh_delta.round(2)} kWh."
          )
        else
          puts "--- WARNING: Could not find matching 'up' row for temp #{current_temp} to calculate HP delta."
        end
      end
    end

    # save_results_to_csv(results)
  end
end
