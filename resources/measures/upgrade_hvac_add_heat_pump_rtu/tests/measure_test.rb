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

class AddHeatPumpRtuTest < Minitest::Test

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

  def model_input_path(osm_name)
    # return models_for_tests.select { |x| set[:model] == osm_name }
    return File.join(File.dirname(__FILE__), '../../../tests/models', osm_name)
  end

  def epw_input_path(epw_name)
    return File.join(File.dirname(__FILE__), '../../../tests/weather', epw_name)
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
  def apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false, model: nil)
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
    if model.nil?
      model = load_model(new_osm_path)
    end

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

    return result
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

  
  def verify_hp_rtu(model, measure, argument_map, osm_path, epw_path)
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
     result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
     assert_equal('Success', result.value.valueName)
     model = load_model(model_output_path(__method__))
 
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

    # list thermal zone not applicable to HR
    thermal_zone_names_to_exclude = [
      'Kitchen',
      'kitchen',
      'KITCHEN',
      'dining',
      'DINING',
      'Dining'
    ]

  ###This section tests proper application of measure on fully applicable models
  # tests include:
  # 1) running model to ensure succesful completion
  # 2) checking user-specified electric backup heating is applied
  # 3) checking that all gas heating couls have been removed from model
  # 4) all air loops contain multispeed heating coil
  # 5) coil speeds capacities and flow rates are ascending
  # 6) coil speeds fall within E+ specified cfm/ton ranges

  def test_370_Small_Office_PSZ_Gas_2A
  
    osm_name = '370_small_office_psz_gas_2A.osm'
    epw_name = 'Mobile Downtown AL USA.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new
	
    # set arguments
    backup_ht_fuel_scheme = arguments[0].clone
    assert(backup_ht_fuel_scheme.setValue('electric_resistance_backup'))
    argument_map['backup_ht_fuel_scheme'] = backup_ht_fuel_scheme
    # allowance for heating oversizing
    performance_oversizing_factor = arguments[1].clone
    assert(performance_oversizing_factor.setValue(0))
    argument_map['performance_oversizing_factor'] = performance_oversizing_factor
    # how to size heating
    htg_sizing_option = arguments[2].clone	
    assert(htg_sizing_option.setValue('0F'))
    argument_map['htg_sizing_option'] = htg_sizing_option
    # cooling oversizing estimate
    clg_oversizing_estimate = arguments[3].clone
    assert(clg_oversizing_estimate.setValue(1))
    argument_map['clg_oversizing_estimate'] = clg_oversizing_estimate
    # htg to clg ratio
    htg_to_clg_hp_ratio = arguments[4].clone
    assert(htg_to_clg_hp_ratio.setValue(1))
    argument_map['htg_to_clg_hp_ratio'] = htg_to_clg_hp_ratio
    # std perf
    std_perf = arguments[5].clone
    assert(std_perf.setValue(false))
    argument_map['std_perf'] = std_perf
    # hr
    hr = arguments[6].clone
    assert(hr.setValue(true))
    argument_map['hr'] = hr
    # dcv
    dcv = arguments[7].clone
    assert(dcv.setValue(false))
    argument_map['dcv'] = dcv
    # economizer
    econ = arguments[8].clone
    assert(econ.setValue(false))
    argument_map['econ'] = econ


    test_result = verify_hp_rtu(model, measure, argument_map, osm_path, epw_path)
  end

  def test_370_small_office_psz_gas_coil_7A
  
    osm_name = '370_small_office_psz_gas_coil_7A.osm'
    epw_name = 'WY Yellowstone Lake.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new
	
    # set arguments
    backup_ht_fuel_scheme = arguments[0].clone
    assert(backup_ht_fuel_scheme.setValue('electric_resistance_backup'))
    argument_map['backup_ht_fuel_scheme'] = backup_ht_fuel_scheme
    # allowance for heating oversizing
    performance_oversizing_factor = arguments[1].clone
    assert(performance_oversizing_factor.setValue(0))
    argument_map['performance_oversizing_factor'] = performance_oversizing_factor
    # how to size heating
    htg_sizing_option = arguments[2].clone	
    assert(htg_sizing_option.setValue('0F'))
    argument_map['htg_sizing_option'] = htg_sizing_option
    # cooling oversizing estimate
    clg_oversizing_estimate = arguments[3].clone
    assert(clg_oversizing_estimate.setValue(1))
    argument_map['clg_oversizing_estimate'] = clg_oversizing_estimate
    # htg to clg ratio
    htg_to_clg_hp_ratio = arguments[4].clone
    assert(htg_to_clg_hp_ratio.setValue(1))
    argument_map['htg_to_clg_hp_ratio'] = htg_to_clg_hp_ratio
    # std perf
    std_perf = arguments[5].clone
    assert(std_perf.setValue(false))
    argument_map['std_perf'] = std_perf
    # hr
    hr = arguments[6].clone
    assert(hr.setValue(true))
    argument_map['hr'] = hr
    # dcv
    dcv = arguments[7].clone
    assert(dcv.setValue(false))
    argument_map['dcv'] = dcv
    # economizer
    econ = arguments[8].clone
    assert(econ.setValue(false))
    argument_map['econ'] = econ

    test_result = verify_hp_rtu(model, measure, argument_map, osm_path, epw_path)
  end

  
  def test_370_warehouse_psz_gas_6A
  
    osm_name = '370_warehouse_psz_gas_6A.osm'
    epw_name = 'WI La Crosse Municipal.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new
	
    # set arguments
    backup_ht_fuel_scheme = arguments[0].clone
    assert(backup_ht_fuel_scheme.setValue('electric_resistance_backup'))
    argument_map['backup_ht_fuel_scheme'] = backup_ht_fuel_scheme
    # allowance for heating oversizing
    performance_oversizing_factor = arguments[1].clone
    assert(performance_oversizing_factor.setValue(0))
    argument_map['performance_oversizing_factor'] = performance_oversizing_factor
    # how to size heating
    htg_sizing_option = arguments[2].clone	
    assert(htg_sizing_option.setValue('0F'))
    argument_map['htg_sizing_option'] = htg_sizing_option
    # cooling oversizing estimate
    clg_oversizing_estimate = arguments[3].clone
    assert(clg_oversizing_estimate.setValue(1))
    argument_map['clg_oversizing_estimate'] = clg_oversizing_estimate
    # htg to clg ratio
    htg_to_clg_hp_ratio = arguments[4].clone
    assert(htg_to_clg_hp_ratio.setValue(1))
    argument_map['htg_to_clg_hp_ratio'] = htg_to_clg_hp_ratio
    # std perf
    std_perf = arguments[5].clone
    assert(std_perf.setValue(false))
    argument_map['std_perf'] = std_perf
    # hr
    hr = arguments[6].clone
    assert(hr.setValue(true))
    argument_map['hr'] = hr
    # dcv
    dcv = arguments[7].clone
    assert(dcv.setValue(false))
    argument_map['dcv'] = dcv
    # economizer
    econ = arguments[8].clone
    assert(econ.setValue(false))
    argument_map['econ'] = econ

    test_result = verify_hp_rtu(model, measure, argument_map, osm_path, epw_path)
  end

  def test_370_retail_psz_gas_6B
  
    osm_name = '370_retail_psz_gas_6B.osm'
    epw_name = 'WY Cody Muni Awos.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AddHeatPumpRtu.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new
	
    # set arguments
    backup_ht_fuel_scheme = arguments[0].clone
    assert(backup_ht_fuel_scheme.setValue('electric_resistance_backup'))
    argument_map['backup_ht_fuel_scheme'] = backup_ht_fuel_scheme
    # allowance for heating oversizing
    performance_oversizing_factor = arguments[1].clone
    assert(performance_oversizing_factor.setValue(0))
    argument_map['performance_oversizing_factor'] = performance_oversizing_factor
    # how to size heating
    htg_sizing_option = arguments[2].clone	
    assert(htg_sizing_option.setValue('0F'))
    argument_map['htg_sizing_option'] = htg_sizing_option
    # cooling oversizing estimate
    clg_oversizing_estimate = arguments[3].clone
    assert(clg_oversizing_estimate.setValue(1))
    argument_map['clg_oversizing_estimate'] = clg_oversizing_estimate
    # htg to clg ratio
    htg_to_clg_hp_ratio = arguments[4].clone
    assert(htg_to_clg_hp_ratio.setValue(1))
    argument_map['htg_to_clg_hp_ratio'] = htg_to_clg_hp_ratio
    # std perf
    std_perf = arguments[5].clone
    assert(std_perf.setValue(false))
    argument_map['std_perf'] = std_perf
    # hr
    hr = arguments[6].clone
    assert(hr.setValue(true))
    argument_map['hr'] = hr
    # dcv
    dcv = arguments[7].clone
    assert(dcv.setValue(false))
    argument_map['dcv'] = dcv
    # economizer
    econ = arguments[8].clone
    assert(econ.setValue(false))
    argument_map['econ'] = econ

    test_result = verify_hp_rtu(model, measure, argument_map, osm_path, epw_path)
  end


  ###########################################################################
  ####This section tests proper classification of partially-applicable building types
    def test_370_full_service_restaurant_psz_gas_coil
  
      osm_name = '370_full_service_restaurant_psz_gas_coil.osm'
      epw_name = 'Birmingham Muni.epw'

      puts "\n######\nTEST:#{osm_name}\n######\n"

      osm_path = model_input_path(osm_name)
      epw_path = epw_input_path(epw_name)

      # Create an instance of the measure
      measure = AddHeatPumpRtu.new

      # Load the model; only used here for populating arguments
      model = load_model(osm_path)
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure::OSArgumentMap.new
    
      # set arguments
      backup_ht_fuel_scheme = arguments[0].clone
      assert(backup_ht_fuel_scheme.setValue('electric_resistance_backup'))
      argument_map['backup_ht_fuel_scheme'] = backup_ht_fuel_scheme
      # allowance for heating oversizing
      performance_oversizing_factor = arguments[1].clone
      assert(performance_oversizing_factor.setValue(0))
      argument_map['performance_oversizing_factor'] = performance_oversizing_factor
      # how to size heating
      htg_sizing_option = arguments[2].clone	
      assert(htg_sizing_option.setValue('0F'))
      argument_map['htg_sizing_option'] = htg_sizing_option
      # cooling oversizing estimate
      clg_oversizing_estimate = arguments[3].clone
      assert(clg_oversizing_estimate.setValue(1))
      argument_map['clg_oversizing_estimate'] = clg_oversizing_estimate
      # htg to clg ratio
      htg_to_clg_hp_ratio = arguments[4].clone
      assert(htg_to_clg_hp_ratio.setValue(1))
      argument_map['htg_to_clg_hp_ratio'] = htg_to_clg_hp_ratio
      # std perf
      std_perf = arguments[5].clone
      assert(std_perf.setValue(false))
      argument_map['std_perf'] = std_perf
      # hr
      hr = arguments[6].clone
      assert(hr.setValue(true))
      argument_map['hr'] = hr
      # dcv
      dcv = arguments[7].clone
      assert(dcv.setValue(false))
      argument_map['dcv'] = dcv
      # economizer
      econ = arguments[8].clone
      assert(econ.setValue(false))
      argument_map['econ'] = econ
    
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
      assert_equal('Success', result.value.valueName)
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
        assert(htg_coil.to_CoilHeatingDXMultiSpeed.is_initialized)
      end

      # assert kitchen spaces still contain gas coils
      kitchen_htg_coils_final.each do |htg_coil|
        assert(htg_coil.to_CoilHeatingGas.is_initialized)
      end
    end

  ############################################################################
  #####This section tests proper classification of non applicable HVAC systems

  # assert that non applicable HVAC system registers as NA
  def test_370_StripMall_Residential_AC_with_residential_forced_air_furnace_2A
  
  # this makes sure measure registers an na for non applicable model
  osm_name = '370_StripMall_Residential AC with residential forced air furnace_2A.osm'
  epw_name = 'Middleton Fld.epw'

  puts "\n######\nTEST:#{osm_name}\n######\n"

  osm_path = model_input_path(osm_name)
  epw_path = epw_input_path(epw_name)

  # Create an instance of the measure
  measure = AddHeatPumpRtu.new

  # Load the model; only used here for populating arguments
  model = load_model(osm_path)
  arguments = measure.arguments(model)
  argument_map = OpenStudio::Measure::OSArgumentMap.new

  # set arguments
  backup_ht_fuel_scheme = arguments[0].clone
  assert(backup_ht_fuel_scheme.setValue('electric_resistance_backup'))
  argument_map['backup_ht_fuel_scheme'] = backup_ht_fuel_scheme
  # allowance for heating oversizing
  performance_oversizing_factor = arguments[1].clone
  assert(performance_oversizing_factor.setValue(0))
  argument_map['performance_oversizing_factor'] = performance_oversizing_factor
  # how to size heating
  htg_sizing_option = arguments[2].clone	
  assert(htg_sizing_option.setValue('0F'))
  argument_map['htg_sizing_option'] = htg_sizing_option
  # cooling oversizing estimate
  clg_oversizing_estimate = arguments[3].clone
  assert(clg_oversizing_estimate.setValue(1))
  argument_map['clg_oversizing_estimate'] = clg_oversizing_estimate
  # htg to clg ratio
  htg_to_clg_hp_ratio = arguments[4].clone
  assert(htg_to_clg_hp_ratio.setValue(1))
  argument_map['htg_to_clg_hp_ratio'] = htg_to_clg_hp_ratio
  # std perf
  std_perf = arguments[5].clone
  assert(std_perf.setValue(false))
  argument_map['std_perf'] = std_perf
  # hr
  hr = arguments[6].clone
  assert(hr.setValue(true))
  argument_map['hr'] = hr
  # dcv
  dcv = arguments[7].clone
  assert(dcv.setValue(false))
  argument_map['dcv'] = dcv
  # economizer
  econ = arguments[8].clone
  assert(econ.setValue(false))
  argument_map['econ'] = econ

  # Apply the measure to the model and optionally run the model
  result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
  assert_equal('NA', result.value.valueName)
  end

  # assert that non applicable HVAC system registers as NA
  def test_370_warehouse_pvav_gas_boiler_reheat_2A
  
    # this makes sure measure registers an na for non applicable model
    osm_name = '370_warehouse_pvav_gas_boiler_reheat_2A.osm'
    epw_name = 'Mobile Downtown AL USA.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"
  
    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)
  
    # Create an instance of the measure
    measure = AddHeatPumpRtu.new
  
    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new
  
    # set arguments
    backup_ht_fuel_scheme = arguments[0].clone
    assert(backup_ht_fuel_scheme.setValue('electric_resistance_backup'))
    argument_map['backup_ht_fuel_scheme'] = backup_ht_fuel_scheme
    # allowance for heating oversizing
    performance_oversizing_factor = arguments[1].clone
    assert(performance_oversizing_factor.setValue(0))
    argument_map['performance_oversizing_factor'] = performance_oversizing_factor
    # how to size heating
    htg_sizing_option = arguments[2].clone	
    assert(htg_sizing_option.setValue('0F'))
    argument_map['htg_sizing_option'] = htg_sizing_option
    # cooling oversizing estimate
    clg_oversizing_estimate = arguments[3].clone
    assert(clg_oversizing_estimate.setValue(1))
    argument_map['clg_oversizing_estimate'] = clg_oversizing_estimate
    # htg to clg ratio
    htg_to_clg_hp_ratio = arguments[4].clone
    assert(htg_to_clg_hp_ratio.setValue(1))
    argument_map['htg_to_clg_hp_ratio'] = htg_to_clg_hp_ratio
    # std perf
    std_perf = arguments[5].clone
    assert(std_perf.setValue(false))
    argument_map['std_perf'] = std_perf
    # hr
    hr = arguments[6].clone
    assert(hr.setValue(true))
    argument_map['hr'] = hr
    # dcv
    dcv = arguments[7].clone
    assert(dcv.setValue(false))
    argument_map['dcv'] = dcv
    # economizer
    econ = arguments[8].clone
    assert(econ.setValue(false))
    argument_map['econ'] = econ
  
    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    assert_equal('NA', result.value.valueName)
    end

  # assert that non applicable HVAC system registers as NA
  def test_370_medium_office_doas_fan_coil_acc_boiler_3A
  
    # this makes sure measure registers an na for non applicable model
    osm_name = '370_medium_office_doas_fan_coil_acc_boiler_3A.osm'
    epw_name = 'Birmingham Muni.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"
  
    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)
  
    # Create an instance of the measure
    measure = AddHeatPumpRtu.new
  
    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new
  
    # set arguments
    backup_ht_fuel_scheme = arguments[0].clone
    assert(backup_ht_fuel_scheme.setValue('electric_resistance_backup'))
    argument_map['backup_ht_fuel_scheme'] = backup_ht_fuel_scheme
    # allowance for heating oversizing
    performance_oversizing_factor = arguments[1].clone
    assert(performance_oversizing_factor.setValue(0))
    argument_map['performance_oversizing_factor'] = performance_oversizing_factor
    # how to size heating
    htg_sizing_option = arguments[2].clone	
    assert(htg_sizing_option.setValue('0F'))
    argument_map['htg_sizing_option'] = htg_sizing_option
    # cooling oversizing estimate
    clg_oversizing_estimate = arguments[3].clone
    assert(clg_oversizing_estimate.setValue(1))
    argument_map['clg_oversizing_estimate'] = clg_oversizing_estimate
    # htg to clg ratio
    htg_to_clg_hp_ratio = arguments[4].clone
    assert(htg_to_clg_hp_ratio.setValue(1))
    argument_map['htg_to_clg_hp_ratio'] = htg_to_clg_hp_ratio
    # std perf
    std_perf = arguments[5].clone
    assert(std_perf.setValue(false))
    argument_map['std_perf'] = std_perf
    # hr
    hr = arguments[6].clone
    assert(hr.setValue(true))
    argument_map['hr'] = hr
    # dcv
    dcv = arguments[7].clone
    assert(dcv.setValue(false))
    argument_map['dcv'] = dcv
    # economizer
    econ = arguments[8].clone
    assert(econ.setValue(false))
    argument_map['econ'] = econ
  
    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    assert_equal('NA', result.value.valueName)
    end

  ############################################################################
  #####This section tests proper application of energy recovery systems in semi-applicable buildings

  # check space type applicability
  thermal_zone_names_to_exclude = [
    'Kitchen',
    'kitchen',
    'KITCHEN',
    'dining',
    'DINING',
    'Dining'
  ]

  # TODO - Test Incomplete
  # # test that ERVs are properly implemented in models with some existing ERVs
  # # this model has existing ervs in both applicable and non applicable zones
  # # existing ervs in applicable zones should be replaced
  # # existing ervs in nonapplicable zones should not be modified
  # def test_370_strip_mall_psz_gas_some_erv_4a

  #   osm_name = '370_strip_mall_psz_gas_some_erv_4a.osm'
  #   epw_name = 'PA Northeast Philadelph.epw'

  #   puts "\n######\nTEST:#{osm_name}\n######\n"
  
  #   osm_path = model_input_path(osm_name)
  #   epw_path = epw_input_path(epw_name)
  
  #   # Create an instance of the measure
  #   measure = AddHeatPumpRtu.new
  
  #   # Load the model; only used here for populating arguments
  #   model = load_model(osm_path)
  #   arguments = measure.arguments(model)
  #   argument_map = OpenStudio::Measure::OSArgumentMap.new
  
  #   # set arguments
  #   backup_ht_fuel_scheme = arguments[0].clone
  #   assert(backup_ht_fuel_scheme.setValue('electric_resistance_backup'))
  #   argument_map['backup_ht_fuel_scheme'] = backup_ht_fuel_scheme
  #   # allowance for heating oversizing
  #   performance_oversizing_factor = arguments[1].clone
  #   assert(performance_oversizing_factor.setValue(0))
  #   argument_map['performance_oversizing_factor'] = performance_oversizing_factor
  #   # how to size heating
  #   htg_sizing_option = arguments[2].clone	
  #   assert(htg_sizing_option.setValue('0F'))
  #   argument_map['htg_sizing_option'] = htg_sizing_option
  #   # cooling oversizing estimate
  #   clg_oversizing_estimate = arguments[3].clone
  #   assert(clg_oversizing_estimate.setValue(1))
  #   argument_map['clg_oversizing_estimate'] = clg_oversizing_estimate
  #   # htg to clg ratio
  #   htg_to_clg_hp_ratio = arguments[4].clone
  #   assert(htg_to_clg_hp_ratio.setValue(1))
  #   argument_map['htg_to_clg_hp_ratio'] = htg_to_clg_hp_ratio
  #   # hr
  #   hr = arguments[5].clone
  #   assert(hr.setValue(true))
  #   argument_map['hr'] = hr
  #   # dcv
  #   dcv = arguments[6].clone
  #   assert(dcv.setValue(false))
  #   argument_map['dcv'] = dcv
  #   # economizer
  #   econ = arguments[7].clone
  #   assert(econ.setValue(false))
  #   argument_map['econ'] = econ

  #   # skip food service space types
  #   thermal_zone_names_to_exclude = [
  #     'Kitchen',
  #     'kitchen',
  #     'KITCHEN',
  #     'dining',
  #     'DINING',
  #     'Dining'
  #   ]

  #   # get baseline ERVs
  #   airloops_w_existing_ervs = []
  #   dict_exist_ervs_applicable = {}
  #   dict_exist_ervs_na = {}
  #   ervs_baseline = model.getHeatExchangerAirToAirSensibleAndLatents
  #   ervs_baseline.each do |erv|
  #     air_loop_hvac = erv.airLoopHVAC.get.to_AirLoopHVAC.get
  #     airloops_w_existing_ervs << air_loop_hvac
  #     # classify non applicable thermal zones
  #     if thermal_zone_names_to_exclude.any? { |word| (air_loop_hvac.name.to_s).include?(word) }
  #       dict_exist_ervs_na[air_loop_hvac] = erv
  #       puts "dict_exist_ervs_na[air_loop_hvac], #{air_loop_hvac} = erv: #{dict_exist_ervs_na[air_loop_hvac] = erv}"
  #     else
  #       dict_exist_ervs_applicable[air_loop_hvac] = erv
  #       puts "dict_exist_ervs_applicable[air_loop_hvac], #{air_loop_hvac} = erv: #{dict_exist_ervs_applicable[air_loop_hvac] = erv}"
  #     end
  #   end

  #   # determine air loops with/without food service (kitchens and dining)
  #   airloop_na_no_erv = []
  #   airloop_na_erv = []
  #   airloop_applic_no_erv = []
  #   airloop_applic_erv = []
  #   model.getAirLoopHVACs.sort.each do |air_loop_hvac|

  #     # classify non applicable thermal zones
  #     if thermal_zone_names_to_exclude.any? { |word| (air_loop_hvac.name.to_s).include?(word) }
  #       # classified as NA for HR, but inlcudes existing HR
  #       if airloops_w_existing_ervs.include? air_loop_hvac
  #         airloop_na_erv << air_loop_hvac
  #         #puts "NA, ERV: #{air_loop_hvac.name}"
  #       # NA for new ERV, no existing ERV
  #       else
  #         airloop_na_no_erv << air_loop_hvac
  #         #puts "NA, No ERV: #{air_loop_hvac.name}"
  #       end
  #       # skip to next loop
  #       next
  #     end
      
  #     # add remaining applicable zones to list
  #     # existing ERV
  #     if airloops_w_existing_ervs.include? air_loop_hvac
  #       airloop_applic_erv << air_loop_hvac
  #       #puts "Applicable, ERV: #{air_loop_hvac.name}"
  #     # no existing ERV
  #     else
  #       airloop_applic_no_erv << air_loop_hvac
  #       #puts "Applicable, No ERV: #{air_loop_hvac.name}"
  #     end
  #   end
  
  #   # Apply the measure to the model and optionally run the model
  #   result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
  #   model = load_model(model_output_path(__method__))
  #   assert_equal('Success', result.value.valueName)

  #   # get upgrade ERVs
  #   airloops_w_existing_ervs_up = []
  #   dict_exist_ervs_applicable_up = {}
  #   dict_exist_ervs_na_up = {}
  #   ervs_upgrade = model.getHeatExchangerAirToAirSensibleAndLatents
  #   ervs_upgrade.each do |erv|
  #     air_loop_hvac = erv.airLoopHVAC.get.to_AirLoopHVAC.get
  #     airloops_w_existing_ervs_up << air_loop_hvac
  #     # classify non applicable thermal zones
  #     if thermal_zone_names_to_exclude.any? { |word| (air_loop_hvac.name.to_s).include?(word) }
  #       dict_exist_ervs_na_up[air_loop_hvac] = erv
  #       puts "dict_exist_ervs_na_up[air_loop_hvac], #{air_loop_hvac} = erv: #{dict_exist_ervs_na_up[air_loop_hvac] = erv}"
  #     else
  #       dict_exist_ervs_applicable_up[air_loop_hvac] = erv
  #       puts "dict_exist_ervs_applicable_up[air_loop_hvac], #{air_loop_hvac} = erv: #{dict_exist_ervs_applicable_up[air_loop_hvac] = erv}"
  #     end
  #   end

  #   # get upgrade ervs
  #   ervs_upgrade = model.getHeatExchangerAirToAirSensibleAndLatents

  #   # get upgrade ERVs
  #   airloops_w_existing_ervs_upgrade = []
  #   ervs_baseline = model.getHeatExchangerAirToAirSensibleAndLatents
  #   ervs_baseline.each do |erv|
  #     airloops_w_existing_ervs_upgrade << erv.airLoopHVAC.get.to_AirLoopHVAC.get
  #   end

  #   # determine air loops with/without food service (kitchens and dining)
  #   airloop_na_no_erv_upgrade = []
  #   airloop_na_erv_upgrade = []
  #   airloop_applic_no_erv_upgrade = []
  #   airloop_applic_erv_upgrade = []
  #   model.getAirLoopHVACs.sort.each do |air_loop_hvac|

  #     # skip food service space types
  #     thermal_zone_names_to_exclude = [
  #       'Kitchen',
  #       'kitchen',
  #       'KITCHEN',
  #       'dining',
  #       'DINING',
  #       'Dining'
  #     ]

  #     # classify non applicable thermal zones
  #     if thermal_zone_names_to_exclude.any? { |word| (air_loop_hvac.name.to_s).include?(word) }
  #       # classified as NA for HR, but inlcudes existing HR
  #       if airloops_w_existing_ervs.include? air_loop_hvac
  #         airloop_na_erv_upgrade << air_loop_hvac
  #         #puts "NA, ERV: #{air_loop_hvac.name}"
  #       # NA for new ERV, no existing ERV
  #       else
  #         airloop_na_no_erv_upgrade << air_loop_hvac
  #         #puts "NA, No ERV: #{air_loop_hvac.name}"
  #       end
  #       # skip to next element
  #       next
  #     end
      
  #     # add remaining applicable zones to list
  #     # existing ERV
  #     if airloops_w_existing_ervs.include? air_loop_hvac
  #       airloop_applic_erv_upgrade << air_loop_hvac
  #       #puts "Applicable, ERV: #{air_loop_hvac.name}"
  #     # no existing ERV
  #     else
  #       airloop_applic_no_erv_upgrade << air_loop_hvac
  #       #puts "Applicable, No ERV: #{air_loop_hvac.name}"
  #     end
  #   end

    ########
      # # determine air loops with/without food service (kitchens and dining)
      # tz_na = []
      # tz_applicable = []
      # model.getAirLoopHVACUnitarySystems.sort.each do |unitary_sys|

      #   # skip kitchen spaces
      #   thermal_zone_names_to_exclude = [
      #     'Kitchen',
      #     'kitchen',
      #     'KITCHEN',
      #   ]
      #   if thermal_zone_names_to_exclude.any? { |word| (unitary_sys.name.to_s).include?(word) }
      #     tz_kitchens << unitary_sys

      #     # add kitchen heating coil to list
      #     kitchen_htg_coils << unitary_sys.heatingCoil.get

      #     next
      #   end
        
      #   # add non kitchen zone and heating coil to list
      #   tz_all_other << unitary_sys
      #   # add kitchen heating coil to list
      #   nonkitchen_htg_coils << unitary_sys.heatingCoil.get
      # end

      # # Apply the measure to the model and optionally run the model
      # result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
      # assert_equal('Success', result.value.valueName)
      # model = load_model(model_output_path(__method__))

      # # get heating coils from final model for kitchen and non kitchen spaces
      # tz_kitchens_final = []
      # kitchen_htg_coils_final = []
      # tz_all_other_final = []
      # nonkitchen_htg_coils_final = []
      # model.getAirLoopHVACUnitarySystems.sort.each do |unitary_sys|

      #   # skip kitchen spaces
      #   thermal_zone_names_to_exclude = [
      #     'Kitchen',
      #     'kitchen',
      #     'KITCHEN',
      #   ]
      #   if thermal_zone_names_to_exclude.any? { |word| (unitary_sys.name.to_s).include?(word) }
      #     tz_kitchens_final << unitary_sys

      #     # add kitchen heating coil to list
      #     kitchen_htg_coils_final << unitary_sys.heatingCoil.get

      #     next
      #   end
        
      #   # add non kitchen zone and heating coil to list
      #   tz_all_other_final << unitary_sys
      #   # add kitchen heating coil to list
      #   nonkitchen_htg_coils_final << unitary_sys.heatingCoil.get
      # end

      # # assert no changes to kitchen unitary systems
      # assert_equal(tz_kitchens_final, tz_kitchens)

      # # assert non kitchen spaces contain multispeed DX heating coils
      # nonkitchen_htg_coils_final.each do |htg_coil|
      #   assert(htg_coil.to_CoilHeatingDXMultiSpeed.is_initialized)
      # end

      # # assert kitchen spaces still contain gas coils
      # kitchen_htg_coils_final.each do |htg_coil|
      #   assert(htg_coil.to_CoilHeatingGas.is_initialized)
      # end


    ########

  # end

  # test that ERVs do no impact existing ERVs when ERV argument is NOT toggled
  def test_370_full_service_restaurant_psz_gas_coil_single_erv_3A
  
    # this makes sure measure registers an na for non applicable model
    osm_name = '370_full_service_restaurant_psz_gas_coil_single_erv_3A.osm'
    epw_name = 'Birmingham Muni.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"
  
    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)
  
    # Create an instance of the measure
    measure = AddHeatPumpRtu.new
  
    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new
  
    # set arguments
    backup_ht_fuel_scheme = arguments[0].clone
    assert(backup_ht_fuel_scheme.setValue('electric_resistance_backup'))
    argument_map['backup_ht_fuel_scheme'] = backup_ht_fuel_scheme
    # allowance for heating oversizing
    performance_oversizing_factor = arguments[1].clone
    assert(performance_oversizing_factor.setValue(0))
    argument_map['performance_oversizing_factor'] = performance_oversizing_factor
    # how to size heating
    htg_sizing_option = arguments[2].clone	
    assert(htg_sizing_option.setValue('0F'))
    argument_map['htg_sizing_option'] = htg_sizing_option
    # cooling oversizing estimate
    clg_oversizing_estimate = arguments[3].clone
    assert(clg_oversizing_estimate.setValue(1))
    argument_map['clg_oversizing_estimate'] = clg_oversizing_estimate
    # htg to clg ratio
    htg_to_clg_hp_ratio = arguments[4].clone
    assert(htg_to_clg_hp_ratio.setValue(1))
    argument_map['htg_to_clg_hp_ratio'] = htg_to_clg_hp_ratio
    # std perf
    std_perf = arguments[5].clone
    assert(std_perf.setValue(false))
    argument_map['std_perf'] = std_perf
    # hr
    hr = arguments[6].clone
    assert(hr.setValue(true))
    argument_map['hr'] = hr
    # dcv
    dcv = arguments[7].clone
    assert(dcv.setValue(false))
    argument_map['dcv'] = dcv
    # economizer
    econ = arguments[8].clone
    assert(econ.setValue(false))
    argument_map['econ'] = econ

    # get baseline ERVs
    ervs_baseline = model.getHeatExchangerAirToAirSensibleAndLatents
  
    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    assert_equal('Success', result.value.valueName)

    # assert no difference in ERVs in upgrade model
    ervs_upgrade = model.getHeatExchangerAirToAirSensibleAndLatents
    assert_equal(ervs_baseline, ervs_upgrade)
  end

  # test that ERVs do no impact non-applicable building types
  def test_370_full_service_restaurant_psz_gas_coil_single_erv_3A_na
  
    # this makes sure measure registers an na for non applicable model
    osm_name = '370_full_service_restaurant_psz_gas_coil_single_erv_3A.osm'
    epw_name = 'Birmingham Muni.epw'

    puts "\n######\nTEST:#{osm_name}\n######\n"
  
    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)
  
    # Create an instance of the measure
    measure = AddHeatPumpRtu.new
  
    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new
  
    # set arguments
    backup_ht_fuel_scheme = arguments[0].clone
    assert(backup_ht_fuel_scheme.setValue('electric_resistance_backup'))
    argument_map['backup_ht_fuel_scheme'] = backup_ht_fuel_scheme
    # allowance for heating oversizing
    performance_oversizing_factor = arguments[1].clone
    assert(performance_oversizing_factor.setValue(0))
    argument_map['performance_oversizing_factor'] = performance_oversizing_factor
    # how to size heating
    htg_sizing_option = arguments[2].clone	
    assert(htg_sizing_option.setValue('0F'))
    argument_map['htg_sizing_option'] = htg_sizing_option
    # cooling oversizing estimate
    clg_oversizing_estimate = arguments[3].clone
    assert(clg_oversizing_estimate.setValue(1))
    argument_map['clg_oversizing_estimate'] = clg_oversizing_estimate
    # htg to clg ratio
    htg_to_clg_hp_ratio = arguments[4].clone
    assert(htg_to_clg_hp_ratio.setValue(1))
    argument_map['htg_to_clg_hp_ratio'] = htg_to_clg_hp_ratio
    # std perf
    std_perf = arguments[5].clone
    assert(std_perf.setValue(false))
    argument_map['std_perf'] = std_perf
    # hr
    hr = arguments[6].clone
    assert(hr.setValue(true))
    argument_map['hr'] = hr
    # dcv
    dcv = arguments[7].clone
    assert(dcv.setValue(false))
    argument_map['dcv'] = dcv
    # economizer
    econ = arguments[8].clone
    assert(econ.setValue(false))
    argument_map['econ'] = econ
    argument_map['std_perf'] = std_perf

    # get baseline ERVs
    ervs_baseline = model.getHeatExchangerAirToAirSensibleAndLatents
  
    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    assert_equal('Success', result.value.valueName)

    # assert no difference in ERVs in upgrade model
    ervs_upgrade = model.getHeatExchangerAirToAirSensibleAndLatents
    assert_equal(ervs_baseline, ervs_upgrade)
  end

end
