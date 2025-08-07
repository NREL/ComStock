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

class UpgradeHvacRtuAdvTest < Minitest::Test

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
      assert_equal(false, model.getDesignDays.size.zero?)
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
      'Unitary System DX Coil Cycling Ratio',
      'Unitary System DX Coil Speed Ratio',
      'Unitary System DX Coil Speed Level',
      'Unitary System Total Cooling Rate',
      'Unitary System Total Heating Rate',
      'Unitary System Electricity Rate',
      'HVAC System Solver Iteration Count',
      'Site Outdoor Air Drybulb Temperature',
      'Heating Coil Crankcase Heater Electricity Rate',
      'Heating Coil Defrost Electricity Rate',
      'Zone Windows Total Transmitted Solar Radiation Rate',
    ]
    out_vars.each do |out_var_name|
        ov = OpenStudio::Model::OutputVariable.new('ov', model)
        ov.setKeyValue('*')
        ov.setReportingFrequency('hourly')
        ov.setVariableName(out_var_name)
    end
    model.getOutputControlFiles.setOutputCSV(true)

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
    measure = UpgradeHvacRtuAdv.new

    # Make an empty model
    model = OpenStudio::Model::Model.new

    # Get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(3, arguments.size)
    assert_equal('hr', arguments[0].name)
    assert_equal('dcv', arguments[1].name)
    assert_equal('debug_verbose', arguments[2].name)
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
      assert(x2_first_changes >= x1_first_changes, "Invalid data point order: x1 varies before x2 in some cases")
    end
  end

  def test_table_lookup_format
    # This test ensures the format of lookup tables
    test_name = 'test_lookup_table_format'
    puts "\n######\nTEST:#{test_name}\n######\n"

    path_to_jsons = "#{__dir__}/../resources/*.json"
    json_files = Dir.glob(path_to_jsons)
    json_files.each do |file_path|
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
      else
        # unitary.applySizingValues
      end
    end
    # TODO: remove once this functionality is added to the OpenStudio C++ for hard sizing Sizing:System
    model.getSizingSystems.each do |sizing_system|
      next if sizing_system.isDesignOutdoorAirFlowRateAutosized

      sizing_system.setSystemOutdoorAirMethod('ZoneSum')
    end

    return model
  end

  def verify_adv_rtu(test_name, model, measure, argument_map, osm_path, epw_path)
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

      # assert supplemental heating coil availability
      sup_htg_coil = system.supplementalHeatingCoil.get
      assert(sup_htg_coil.to_CoilHeatingElectric.is_initialized)

      # ***cooling***
      # assert new unitary systems all have variable DX cooling coils
      clg_coil = system.coolingCoil.get
      assert(clg_coil.to_CoilCoolingDXVariableSpeed.is_initialized)
      clg_coil = clg_coil.to_CoilCoolingDXVariableSpeed.get

      # assert multispeed heating coil has 4 stages
      assert_equal(clg_coil.numberOfStages, 3)
      clg_coil_spd3 = clg_coil.stages[2]

      # assert speed 4 flowrate matches design flow rate
      clg_dsn_flowrate = system.supplyAirFlowRateDuringCoolingOperation
      assert_in_delta(clg_dsn_flowrate.to_f, clg_coil_spd3.ratedAirFlowRate.get, 0.000001)

      # assert flow rate reduces for lower speeds
      clg_coil_spd2 = clg_coil.stages[1]
      clg_coil_spd1 = clg_coil.stages[0]
      assert(clg_coil_spd3.ratedAirFlowRate.get > clg_coil_spd2.ratedAirFlowRate.get)
      assert(clg_coil_spd2.ratedAirFlowRate.get > clg_coil_spd1.ratedAirFlowRate.get)

      # assert capacity reduces for lower speeds
      assert(clg_coil_spd3.grossRatedTotalCoolingCapacity.get > clg_coil_spd2.grossRatedTotalCoolingCapacity.get)
      assert(clg_coil_spd2.grossRatedTotalCoolingCapacity.get > clg_coil_spd1.grossRatedTotalCoolingCapacity.get)
    end
    result
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
  #     measure = UpgradeHvacRtuAdv.new

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
  # This section tests proper application of measure on fully applicable models
  # tests include:
  # 1) running model to ensure succesful completion
  # 2) checking user-specified electric backup heating is applied
  # 3) checking that all gas heating couls have been removed from model
  # 4) all air loops contain multispeed heating coil
  # 5) coil speeds capacities and flow rates are ascending
  # 6) coil speeds fall within E+ specified cfm/ton ranges
  # 7) check roof/window measure related variables are saved or not saved in model

  def test_380_Small_Office_PSZ_Gas_2A
    osm_name = '380_Small_Office_PSZ_Gas_2A.osm'
    epw_name = 'SC_Columbia_Metro_723100_12.epw'

    test_name = 'test_380_Small_Office_PSZ_Gas_2A'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = UpgradeHvacRtuAdv.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      if arg.name == 'debug_verbose'
        debug_verbose = arguments[idx].clone
        debug_verbose.setValue(true)
        argument_map[arg.name] = debug_verbose
      else
        argument_map[arg.name] = temp_arg_var
      end
    end
    test_result = verify_adv_rtu(test_name, model, measure, argument_map, osm_path, epw_path)
    
  end

  def test_380_small_office_psz_gas_coil_7A
    osm_name = '380_small_office_psz_gas_coil_7A.osm'
    epw_name = 'NE_Kearney_Muni_725526_16.epw'

    test_name = 'test_380_small_office_psz_gas_coil_7A'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = UpgradeHvacRtuAdv.new

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

    test_result = verify_adv_rtu(test_name, model, measure, argument_map, osm_path, epw_path)

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
    assert_equal(roof_measure_implemented, false, "cannot find variable that was saved in roof upgrade measure via registerValue: env_roof_insul_roof_area_ft_2")
    assert_equal(window_measure_implemented, false, "cannot find variable that was saved in window upgrade measure via registerValue: env_secondary_window_fen_area_ft_2")
  end

  def test_small_office_psz_not_hard_sized
    osm_name = 'small_office_psz_not_hard_sized.osm'
    epw_name = 'USA_AK_Fairbanks.Intl.AP.702610_TMY3.epw'

    test_name = 'test_small_office_psz_not_hard_sized'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = UpgradeHvacRtuAdv.new

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

    test_result = verify_adv_rtu(test_name, model, measure, argument_map, osm_path, epw_path)

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
    assert_equal(roof_measure_implemented, true, "cannot find variable that was saved in roof upgrade measure via registerValue: env_roof_insul_roof_area_ft_2")
    assert_equal(window_measure_implemented, false, "cannot find variable that was saved in window upgrade measure via registerValue: env_secondary_window_fen_area_ft_2")
  end

  def test_380_retail_psz_gas_6B
    osm_name = '380_retail_psz_gas_6B.osm'
    epw_name = 'NE_Kearney_Muni_725526_16.epw'

    test_name = 'test_380_retail_psz_gas_6B'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = UpgradeHvacRtuAdv.new

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

    test_result = verify_adv_rtu(test_name, model, measure, argument_map, osm_path, epw_path)

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
    assert_equal(roof_measure_implemented, false, "cannot find variable that was saved in roof upgrade measure via registerValue: env_roof_insul_roof_area_ft_2")
    assert_equal(window_measure_implemented, true, "cannot find variable that was saved in window upgrade measure via registerValue: env_secondary_window_fen_area_ft_2")
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
    measure = UpgradeHvacRtuAdv.new

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
  # This section tests proper classification of non applicable HVAC systems
  # assert that non applicable HVAC system registers as NA
  def test_380_StripMall_Residential_AC_with_residential_forced_air_furnace_2A
    # this makes sure measure registers an na for non applicable model
    osm_name = '380_StripMall_Residential AC with residential forced air furnace_2A.osm'
    epw_name = 'TN_KNOXVILLE_723260_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = UpgradeHvacRtuAdv.new

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
  def test_380_warehouse_pvav_gas_boiler_reheat_2A
    # this makes sure measure registers an na for non applicable model
    osm_name = '380_warehouse_pvav_gas_boiler_reheat_2A.osm'
    epw_name = 'TN_KNOXVILLE_723260_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = UpgradeHvacRtuAdv.new

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
  def test_380_medium_office_doas_fan_coil_acc_boiler_3A
    # this makes sure measure registers an na for non applicable model
    osm_name = '380_medium_office_doas_fan_coil_acc_boiler_3A.osm'
    epw_name = 'TN_KNOXVILLE_723260_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = UpgradeHvacRtuAdv.new

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
  def test_380_full_service_restaurant_psz_gas_coil_single_erv_3A
    # this makes sure measure registers an na for non applicable model
    osm_name = '380_full_service_restaurant_psz_gas_coil_single_erv_3A.osm'
    epw_name = 'SC_Columbia_Metro_723100_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = UpgradeHvacRtuAdv.new

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
  def test_380_full_service_restaurant_psz_gas_coil_single_erv_3A_na
    # this makes sure measure registers an na for non applicable model
    osm_name = '380_full_service_restaurant_psz_gas_coil_single_erv_3A.osm'
    epw_name = 'SC_Columbia_Metro_723100_12.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = UpgradeHvacRtuAdv.new

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

end
