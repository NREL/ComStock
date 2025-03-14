# insert your copyright here

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'minitest/autorun'
require 'fileutils'
require 'openstudio-standards'
require_relative '../measure'

class UpgradeHvacChillerTest < Minitest::Test
  def test_number_of_arguments_and_argument_names
    # create an instance of the measure
    measure = UpgradeHvacChiller.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(4, arguments.size)
    assert_equal('upgrade_pump', arguments[0].name)
    assert_equal('chw_oat_reset', arguments[1].name)
    assert_equal('cw_oat_reset', arguments[2].name)
    assert_equal('debug_verbose', arguments[3].name)
  end

  def test_models
    # test models
    test_sets = []
    # test: 380_doas_with_fan_coil_air_cooled_chiller_with_boiler
    test_sets << {
      model: '380_doas_with_fan_coil_air_cooled_chiller_with_boiler',
      weather: 'USA_NY_New.York-Central.Park.725033_TMY3', # weather file does not matter with current tests
      result: 'Success'
    }
    # test: 380_doas_with_fan_coil_chiller_with_boiler
    test_sets << {
      model: '380_doas_with_fan_coil_chiller_with_boiler',
      weather: 'USA_NY_New.York-Central.Park.725033_TMY3', # weather file does not matter with current tests
      result: 'Success'
    }
    # test: 380_vav_air_cooled_chiller_with_gas_boiler_reheat
    test_sets << {
      model: '380_vav_air_cooled_chiller_with_gas_boiler_reheat',
      weather: 'USA_NY_New.York-Central.Park.725033_TMY3', # weather file does not matter with current tests
      result: 'Success'
    }
    # test: 380_vav_chiller_with_gas_boiler_reheat
    test_sets << {
      model: '380_vav_chiller_with_gas_boiler_reheat',
      weather: 'USA_NY_New.York-Central.Park.725033_TMY3', # weather file does not matter with current tests
      result: 'Success'
    }

    test_sets.each do |set|
      instance_test_name = set[:model]
      puts "instance test name: #{instance_test_name}"
      osm_path = models_for_tests.select { |x| set[:model] == File.basename(x, '.osm') }
      epw_path = epws_for_tests.select { |x| set[:weather] == File.basename(x, '.epw') }
      assert(!osm_path.empty?)
      assert(!epw_path.empty?)
      osm_path = osm_path[0]
      epw_path = epw_path[0]

      # apply measure to model
      apply_model(osm_path, instance_test_name)
    end
  end

  # apply measure to model and test,
  # measure application result
  # initial/final condition check
  # variable speed pump coefficient check
  def apply_model(path, instance_test_name)
    # build standard
    template = 'ComStock 90.1-2019'
    std = Standard.build(template)

    # create an instance of the measure
    measure = UpgradeHvacChiller.new

    # create runner with empty OSW
    osw = OpenStudio::WorkflowJSON.new
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    # path = "#{File.dirname(__FILE__)}/example_model.osm"
    model = translator.loadModel(path)
    refute_empty(model)
    model = model.get

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # create hash of argument values.
    # If the argument has a default that you want to use, you don't need it in the hash
    args_hash = {}
    args_hash['space_name'] = 'New Space'
    # using defaults values from measure.rb for other arguments

    # populate argument with specified hash value if specified
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      case arg.name
      when 'debug_verbose'
        debug_verbose = arguments[idx].clone
        debug_verbose.setValue(true)
        argument_map[arg.name] = debug_verbose
      when 'chw_oat_reset'
        chw_oat_reset = arguments[idx].clone
        chw_oat_reset.setValue(true)
        argument_map[arg.name] = chw_oat_reset
      when 'cw_oat_reset'
        cw_oat_reset = arguments[idx].clone
        cw_oat_reset.setValue(true)
        argument_map[arg.name] = cw_oat_reset
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # get chiller specs before measure
    chillers = model.getChillerElectricEIRs
    results_b = UpgradeHvacChiller.chiller_specifications(chillers)
    counts_chillers_acc_b = results_b[0]
    capacity_total_w_acc_b = results_b[1]
    cop_acc_b = results_b[2]
    counts_chillers_wcc_b = results_b[3]
    capacity_total_w_wcc_b = results_b[4]
    cop_wcc_b = results_b[5]
    curve_summary_b = results_b[6]

    # get pump specs before measure
    pumps_const_spd = model.getPumpConstantSpeeds
    pump_specs_cst_spd_before = UpgradeHvacChiller.pump_specifications([], pumps_const_spd, std)
    pump_rated_flow_total_c_before = pump_specs_cst_spd_before[1]
    pump_motor_eff_weighted_average_c_before = pump_specs_cst_spd_before[2]
    pump_motor_bhp_weighted_average_c_before = pump_specs_cst_spd_before[3]
    pumps_var_spd = model.getPumpVariableSpeeds
    pump_specs_var_spd_before = UpgradeHvacChiller.pump_specifications([], pumps_var_spd, std)
    pump_rated_flow_total_v_before = pump_specs_var_spd_before[1]
    pump_motor_eff_weighted_average_v_before = pump_specs_var_spd_before[2]
    pump_motor_bhp_weighted_average_v_before = pump_specs_var_spd_before[3]
    pump_var_part_load_curve_coeff1_weighted_avg_before = pump_specs_var_spd_before[4]
    pump_var_part_load_curve_coeff2_weighted_avg_before = pump_specs_var_spd_before[5]
    pump_var_part_load_curve_coeff3_weighted_avg_before = pump_specs_var_spd_before[6]
    pump_var_part_load_curve_coeff4_weighted_avg_before = pump_specs_var_spd_before[7]

    # get control specs before measure
    fraction_chw_oat_reset_enabled_b, fraction_cw_oat_reset_enabled_b = UpgradeHvacChiller.control_specifications(model)

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # get chiller specs after measure
    chillers = model.getChillerElectricEIRs
    results_a = UpgradeHvacChiller.chiller_specifications(chillers)
    counts_chillers_acc_a = results_a[0]
    capacity_total_w_acc_a = results_a[1]
    cop_acc_a = results_a[2]
    counts_chillers_wcc_a = results_a[3]
    capacity_total_w_wcc_a = results_a[4]
    cop_wcc_a = results_a[5]
    curve_summary_a = results_a[6]

    # get pump specs after measure
    pumps_const_spd = model.getPumpConstantSpeeds
    pump_specs_cst_spd_after = UpgradeHvacChiller.pump_specifications([], pumps_const_spd, std)
    pump_rated_flow_total_c_after = pump_specs_cst_spd_after[1]
    pump_motor_eff_weighted_average_c_after = pump_specs_cst_spd_after[2]
    pump_motor_bhp_weighted_average_c_after = pump_specs_cst_spd_after[3]
    pumps_var_spd = model.getPumpVariableSpeeds
    pump_specs_var_spd_after = UpgradeHvacChiller.pump_specifications([], pumps_var_spd, std)
    pump_rated_flow_total_v_after = pump_specs_var_spd_after[1]
    pump_motor_eff_weighted_average_v_after = pump_specs_var_spd_after[2]
    pump_motor_bhp_weighted_average_v_after = pump_specs_var_spd_after[3]
    pump_var_part_load_curve_coeff1_weighted_avg_after = pump_specs_var_spd_after[4]
    pump_var_part_load_curve_coeff2_weighted_avg_after = pump_specs_var_spd_after[5]
    pump_var_part_load_curve_coeff3_weighted_avg_after = pump_specs_var_spd_after[6]
    pump_var_part_load_curve_coeff4_weighted_avg_after = pump_specs_var_spd_after[7]

    # get control specs after measure
    fraction_chw_oat_reset_enabled_a, fraction_cw_oat_reset_enabled_a = UpgradeHvacChiller.control_specifications(model)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    refute_empty(result.stepInitialCondition)

    refute_empty(result.stepFinalCondition)

    # check chilled water system specs
    puts("### DEBUGGING: counts_chillers_acc_b = #{counts_chillers_acc_b} | counts_chillers_acc_a = #{counts_chillers_acc_a}")
    puts("### DEBUGGING: capacity_total_w_acc_b = #{capacity_total_w_acc_b} | capacity_total_w_acc_a = #{capacity_total_w_acc_a}")
    puts("### DEBUGGING: cop_acc_b = #{cop_acc_b} | cop_acc_a = #{cop_acc_a}")
    puts("### DEBUGGING: counts_chillers_wcc_b = #{counts_chillers_wcc_b} | counts_chillers_wcc_a = #{counts_chillers_wcc_a}")
    puts("### DEBUGGING: capacity_total_w_wcc_b = #{capacity_total_w_wcc_b} | capacity_total_w_wcc_a = #{capacity_total_w_wcc_a}")
    puts("### DEBUGGING: cop_wcc_b = #{cop_wcc_b} | cop_wcc_a = #{cop_wcc_a}")
    puts("### DEBUGGING: pump_motor_eff_weighted_average_c_before = #{pump_motor_eff_weighted_average_c_before} | pump_motor_eff_weighted_average_c_after = #{pump_motor_eff_weighted_average_c_after}")
    puts("### DEBUGGING: pump_motor_bhp_weighted_average_c_before = #{pump_motor_bhp_weighted_average_c_before} | pump_motor_bhp_weighted_average_c_after = #{pump_motor_bhp_weighted_average_c_after}")
    puts("### DEBUGGING: pump_motor_eff_weighted_average_v_before = #{pump_motor_eff_weighted_average_v_before} | pump_motor_eff_weighted_average_v_after = #{pump_motor_eff_weighted_average_v_after}")
    puts("### DEBUGGING: pump_motor_bhp_weighted_average_v_before = #{pump_motor_bhp_weighted_average_v_before} | pump_motor_bhp_weighted_average_v_after = #{pump_motor_bhp_weighted_average_v_after}")
    puts("### DEBUGGING: pump part load curve coeffi 1 = #{pump_var_part_load_curve_coeff1_weighted_avg_before} | coeff1_a = #{pump_var_part_load_curve_coeff1_weighted_avg_after}")
    puts("### DEBUGGING: pump part load curve coeffi 2 = #{pump_var_part_load_curve_coeff2_weighted_avg_before} | coeff2_a = #{pump_var_part_load_curve_coeff2_weighted_avg_after}")
    puts("### DEBUGGING: pump part load curve coeffi 3 = #{pump_var_part_load_curve_coeff3_weighted_avg_before} | coeff3_a = #{pump_var_part_load_curve_coeff3_weighted_avg_after}")
    puts("### DEBUGGING: pump part load curve coeffi 4 = #{pump_var_part_load_curve_coeff4_weighted_avg_before} | coeff4_a = #{pump_var_part_load_curve_coeff4_weighted_avg_after}")
    coefficient_set_different = false
    if (pump_var_part_load_curve_coeff1_weighted_avg_before != pump_var_part_load_curve_coeff1_weighted_avg_after) ||
       (pump_var_part_load_curve_coeff2_weighted_avg_before != pump_var_part_load_curve_coeff2_weighted_avg_after) ||
       (pump_var_part_load_curve_coeff3_weighted_avg_before != pump_var_part_load_curve_coeff3_weighted_avg_after) ||
       (pump_var_part_load_curve_coeff4_weighted_avg_before != pump_var_part_load_curve_coeff4_weighted_avg_after)
      coefficient_set_different = true
    end

    assert_equal(counts_chillers_acc_b, counts_chillers_acc_a)
    assert_equal(capacity_total_w_acc_b, capacity_total_w_acc_a)
    if cop_acc_b != 0 && cop_acc_b <= 5.32 # this if statement was added because of this: https://github.com/NREL/openstudio-standards/issues/1904
      refute_equal(cop_acc_b, cop_acc_a)
    end
    assert_equal(counts_chillers_wcc_b, counts_chillers_wcc_a)
    assert_equal(capacity_total_w_wcc_b, capacity_total_w_wcc_a)
    unless cop_wcc_b == 0 # COP equal to zero means case when there is no WCC
      refute_equal(cop_wcc_b, cop_wcc_a)
    end
    assert_equal(true, coefficient_set_different)

    # check curve name changes
    curve_summary_b.keys.each do |chiller_name|
      name_cap_f_t_b = curve_summary_b[chiller_name]['cap_f_t']
      name_eir_f_t_b = curve_summary_b[chiller_name]['eir_f_t']
      name_eir_f_plr_b = curve_summary_b[chiller_name]['eir_f_plr']
      name_cap_f_t_a = curve_summary_a[chiller_name]['cap_f_t']
      name_eir_f_t_a = curve_summary_a[chiller_name]['eir_f_t']
      name_eir_f_plr_a = curve_summary_a[chiller_name]['eir_f_plr']
      refute_equal(name_cap_f_t_b, name_cap_f_t_a)
      refute_equal(name_eir_f_t_b, name_eir_f_t_a)
      refute_equal(name_eir_f_plr_b, name_eir_f_plr_a)
    end

    # check control specs
    puts("### DEBUGGING: fraction_chw_oat_reset_enabled_b = #{fraction_chw_oat_reset_enabled_b} | fraction_chw_oat_reset_enabled_a = #{fraction_chw_oat_reset_enabled_a}")
    puts("### DEBUGGING: fraction_cw_oat_reset_enabled_b = #{fraction_cw_oat_reset_enabled_b} | fraction_cw_oat_reset_enabled_a = #{fraction_cw_oat_reset_enabled_a}")
    refute_equal(fraction_chw_oat_reset_enabled_b, fraction_chw_oat_reset_enabled_a)
    if counts_chillers_wcc_b == 0
      assert_equal(fraction_cw_oat_reset_enabled_a, 0.0)
    else
      assert_equal(fraction_cw_oat_reset_enabled_a, 1.0)
    end

    # # save the model to test output directory
    # output_file_path = "#{File.dirname(__FILE__)}/output/#{instance_test_name}.osm"
    # model.save(output_file_path, true)
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
end
