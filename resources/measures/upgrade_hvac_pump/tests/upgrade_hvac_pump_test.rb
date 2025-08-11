# insert your copyright here

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'minitest/autorun'
require 'fileutils'
require 'openstudio-standards'
require_relative '../measure'

class UpgradeHvacPumpTest < Minitest::Test
  def setup
    # Create a new empty OpenStudio model to pass into the method
    @model = OpenStudio::Model::Model.new
  end

  def test_evaluate_zero
    curve, = UpgradeHvacPump.curve_fraction_of_full_load_power(@model)
    result = curve.evaluate(0.0)
    assert_in_delta 0.0, result, 1e-6, 'Expected curve output at x=0 to be 0'
  end

  def test_evaluate_one
    curve, = UpgradeHvacPump.curve_fraction_of_full_load_power(@model)
    result = curve.evaluate(1.0)
    assert_in_delta 1.0, result, 1e-6, 'Expected curve output at x=1 to be 1'
  end

  def test_output_bounds_over_range
    # Test across input range 350W to 38800W
    (350..38800).step(500).each do |watts|
      eff = UpgradeHvacPump.estimate_motor_efficiency_pcnt(watts)
      assert eff >= 90.53, "Efficiency below lower bound for #{watts} W: #{eff}"
      assert eff <= 95.95, "Efficiency above upper bound for #{watts} W: #{eff}"
    end
  end

  def test_low_power_value
    eff = UpgradeHvacPump.estimate_motor_efficiency_pcnt(350)
    assert_in_delta 90.53, eff, 0.5, 'Expected efficiency close to lower bound'
  end

  def test_high_power_value
    eff = UpgradeHvacPump.estimate_motor_efficiency_pcnt(38800)
    assert_in_delta 95.95, eff, 0.5, 'Expected efficiency close to upper bound'
  end

  def test_exact_breakpoint
    eff = UpgradeHvacPump.estimate_motor_efficiency_pcnt(5000)
    assert eff.between?(90.53, 95.95), "Efficiency at breakpoint not within bounds: #{eff}"
  end

  def test_zero_input
    assert_raises(ArgumentError) do
      UpgradeHvacPump.estimate_motor_efficiency_pcnt(0)
    end
  end

  def test_input_below_range_clipped
    eff = UpgradeHvacPump.estimate_motor_efficiency_pcnt(100) # 0.1 kW
    assert_in_delta 90.53, eff, 1e-6, 'Expected output to be clipped at lower bound for 100W'
  end

  def test_input_above_range_clipped
    eff = UpgradeHvacPump.estimate_motor_efficiency_pcnt(50000) # 50 kW
    assert_in_delta 95.95, eff, 1e-6, 'Expected output to be clipped at upper bound for 50000W'
  end

  # supporting method: return file paths to test models in test directory
  def models_for_tests
    paths = Dir.glob(File.join(File.dirname(__FILE__), '../../../tests/models/*.osm'))
    paths = paths.map { |path| File.expand_path(path) }
    return paths
  end

  # supporting method: return file paths to epw files in test directory
  def epws_for_tests
    paths = Dir.glob(File.join(File.dirname(__FILE__), '../../../tests/weather/*.epw'))
    paths = paths.map { |path| File.expand_path(path) }
    return paths
  end

  # supporting method: load model from osm path
  def load_model(osm_path)
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(OpenStudio::Path.new(osm_path))
    assert(!model.empty?)
    model.get
  end

  # supporting method: return model output path
  def model_output_path(test_name)
    "#{run_dir(test_name)}/#{test_name}.osm"
  end

  # supporting method: return run path
  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so
    # result files are not made part of the measure
    "#{File.dirname(__FILE__)}/output/#{test_name}"
  end

  # supporting method: return results html path
  def report_path(test_name)
    "#{run_dir(test_name)}/reports/eplustbl.html"
  end

  # supporting method: get sql file path
  def sql_path(test_name)
    "#{run_dir(test_name)}/run/eplusout.sql"
  end

  # supporting method: apply measure to model and test,
  def apply_and_test_model(path, instance_test_name)
    # build standard
    template = 'ComStock 90.1-2019'
    std = Standard.build(template)

    # create an instance of the measure
    measure = UpgradeHvacPump.new

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

    # populate argument with specified hash value if specified
    arguments.each_with_index do |arg, idx|
      temp_arg_var = arg.clone
      case arg.name
      when 'chw_oat_reset'
        chw_oat_reset = arguments[idx].clone
        chw_oat_reset.setValue(true)
        argument_map[arg.name] = chw_oat_reset
      when 'cw_oat_reset'
        cw_oat_reset = arguments[idx].clone
        cw_oat_reset.setValue(true)
        argument_map[arg.name] = cw_oat_reset
      when 'debug_verbose'
        debug_verbose = arguments[idx].clone
        debug_verbose.setValue(true)
        argument_map[arg.name] = debug_verbose
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # get pump specs before measure
    pumps_const_spd = model.getPumpConstantSpeeds
    pump_specs_cst_spd_before = UpgradeHvacPump.pump_specifications([], pumps_const_spd, std)
    pump_rated_flow_total_c_before = pump_specs_cst_spd_before[1]
    pump_motor_eff_weighted_average_c_before = pump_specs_cst_spd_before[2]
    pump_motor_bhp_weighted_average_c_before = pump_specs_cst_spd_before[3]
    pumps_var_spd = model.getPumpVariableSpeeds
    pump_specs_var_spd_before = UpgradeHvacPump.pump_specifications([], pumps_var_spd, std)
    pump_rated_flow_total_v_before = pump_specs_var_spd_before[1]
    pump_motor_eff_weighted_average_v_before = pump_specs_var_spd_before[2]
    pump_motor_bhp_weighted_average_v_before = pump_specs_var_spd_before[3]
    pump_var_part_load_curve_coeff1_weighted_avg_before = pump_specs_var_spd_before[4]
    pump_var_part_load_curve_coeff2_weighted_avg_before = pump_specs_var_spd_before[5]
    pump_var_part_load_curve_coeff3_weighted_avg_before = pump_specs_var_spd_before[6]
    pump_var_part_load_curve_coeff4_weighted_avg_before = pump_specs_var_spd_before[7]

    # get control specs for baseline
    fraction_chw_oat_reset_enabled_b, fraction_cw_oat_reset_enabled_b =
      UpgradeHvacPump.control_specifications(model)

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # get pump specs after measure
    pumps_const_spd = model.getPumpConstantSpeeds
    pump_specs_cst_spd_after = UpgradeHvacPump.pump_specifications([], pumps_const_spd, std)
    pump_rated_flow_total_c_after = pump_specs_cst_spd_after[1]
    pump_motor_eff_weighted_average_c_after = pump_specs_cst_spd_after[2]
    pump_motor_bhp_weighted_average_c_after = pump_specs_cst_spd_after[3]
    pumps_var_spd = model.getPumpVariableSpeeds
    pump_specs_var_spd_after = UpgradeHvacPump.pump_specifications([], pumps_var_spd, std)
    pump_rated_flow_total_v_after = pump_specs_var_spd_after[1]
    pump_motor_eff_weighted_average_v_after = pump_specs_var_spd_after[2]
    pump_motor_bhp_weighted_average_v_after = pump_specs_var_spd_after[3]
    pump_var_part_load_curve_coeff1_weighted_avg_after = pump_specs_var_spd_after[4]
    pump_var_part_load_curve_coeff2_weighted_avg_after = pump_specs_var_spd_after[5]
    pump_var_part_load_curve_coeff3_weighted_avg_after = pump_specs_var_spd_after[6]
    pump_var_part_load_curve_coeff4_weighted_avg_after = pump_specs_var_spd_after[7]

    # get control specs for upgrade
    fraction_chw_oat_reset_enabled_a, fraction_cw_oat_reset_enabled_a =
      UpgradeHvacPump.control_specifications(model)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    refute_empty(result.stepInitialCondition)

    refute_empty(result.stepFinalCondition)

    # check chilled water system specs
    puts("### DEBUGGING: pump_motor_eff_weighted_average_c_before = #{
      pump_motor_eff_weighted_average_c_before
    } | pump_motor_eff_weighted_average_c_after = #{
        pump_motor_eff_weighted_average_c_after
      }")
    puts("### DEBUGGING: pump_motor_bhp_weighted_average_c_before = #{
      pump_motor_bhp_weighted_average_c_before
    } | pump_motor_bhp_weighted_average_c_after = #{
        pump_motor_bhp_weighted_average_c_after
      }")
    puts("### DEBUGGING: pump_motor_eff_weighted_average_v_before = #{
      pump_motor_eff_weighted_average_v_before
    } | pump_motor_eff_weighted_average_v_after = #{
        pump_motor_eff_weighted_average_v_after
      }")
    puts("### DEBUGGING: pump_motor_bhp_weighted_average_v_before = #{
      pump_motor_bhp_weighted_average_v_before
    } | pump_motor_bhp_weighted_average_v_after = #{
        pump_motor_bhp_weighted_average_v_after
      }")
    puts("### DEBUGGING: pump part load curve coeffi 1 = #{
      pump_var_part_load_curve_coeff1_weighted_avg_before
    } | coeff1_a = #{
        pump_var_part_load_curve_coeff1_weighted_avg_after
      }")
    puts("### DEBUGGING: pump part load curve coeffi 2 = #{
      pump_var_part_load_curve_coeff2_weighted_avg_before
    } | coeff2_a = #{pump_var_part_load_curve_coeff2_weighted_avg_after}")
    puts("### DEBUGGING: pump part load curve coeffi 3 = #{
      pump_var_part_load_curve_coeff3_weighted_avg_before
    } | coeff3_a = #{pump_var_part_load_curve_coeff3_weighted_avg_after}")
    puts("### DEBUGGING: pump part load curve coeffi 4 = #{
      pump_var_part_load_curve_coeff4_weighted_avg_before
    } | coeff4_a = #{pump_var_part_load_curve_coeff4_weighted_avg_after}")
    coefficient_set_different = false
    if (pump_var_part_load_curve_coeff1_weighted_avg_before !=
        pump_var_part_load_curve_coeff1_weighted_avg_after) ||
       (pump_var_part_load_curve_coeff2_weighted_avg_before !=
        pump_var_part_load_curve_coeff2_weighted_avg_after) ||
       (pump_var_part_load_curve_coeff3_weighted_avg_before !=
        pump_var_part_load_curve_coeff3_weighted_avg_after) ||
       (pump_var_part_load_curve_coeff4_weighted_avg_before !=
        pump_var_part_load_curve_coeff4_weighted_avg_after)
      coefficient_set_different = true
    end
    assert_equal(true, coefficient_set_different,
                 'Pump part load curve coefficients did not change as expected.')

    # check performance improvement
    if pump_motor_eff_weighted_average_v_after < pump_motor_eff_weighted_average_c_before
      assert(
        false,
        "Pump motor efficiency got worse compared to existing constant speed pump. Before: #{
          pump_motor_eff_weighted_average_c_before
        }, After: #{
            pump_motor_eff_weighted_average_c_after
          }"
      )
    end
    if pump_motor_eff_weighted_average_v_after < pump_motor_eff_weighted_average_v_before
      assert(
        false,
        "Pump motor efficiency got worse compared to existing variable speed pump. Before: #{
          pump_motor_eff_weighted_average_v_before
        }, After: #{pump_motor_eff_weighted_average_v_after}"
      )
    end

    # check control specs
    puts("### DEBUGGING: instance_test_name = #{instance_test_name}")
    puts("### DEBUGGING: fraction_chw_oat_reset_enabled_b = #{
      fraction_chw_oat_reset_enabled_b
    } | fraction_chw_oat_reset_enabled_a = #{
        fraction_chw_oat_reset_enabled_a
      }")
    puts("### DEBUGGING: fraction_cw_oat_reset_enabled_b = #{
      fraction_cw_oat_reset_enabled_b
    } | fraction_cw_oat_reset_enabled_a = #{
        fraction_cw_oat_reset_enabled_a
      }")
    refute_equal(fraction_chw_oat_reset_enabled_b, fraction_chw_oat_reset_enabled_a)
    if instance_test_name.include?('air_cooled')
      assert_equal(fraction_cw_oat_reset_enabled_a, 0.0,
                   'Fraction CW OAT Reset Enabled A is not equal to 0.0')
    else
      assert_equal(fraction_cw_oat_reset_enabled_a, 1.0,
                   'Fraction CW OAT Reset Enabled A is not equal to 1.0')
    end

    # # save the model to test output directory
    # output_file_path = "#{File.dirname(__FILE__)}/output/#{instance_test_name}.osm"
    # model.save(output_file_path, true)
  end

  # test 1: check measure arguments
  def test_number_of_arguments_and_argument_names
    # create an instance of the measure
    measure = UpgradeHvacPump.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(3, arguments.size)
    assert_equal('chw_oat_reset', arguments[0].name)
    assert_equal('cw_oat_reset', arguments[1].name)
    assert_equal('debug_verbose', arguments[2].name)
  end

  # test 2: check model without simulation
  def test_models_without_simulations
    # test models
    test_sets = []
    # test: 380_doas_with_fan_coil_air_cooled_chiller_with_boiler
    test_sets << {
      model: '380_doas_with_fan_coil_air_cooled_chiller_with_boiler',
      weather: 'NY_New_York_John_F_Ke_744860_16', # weather file does not matter with current tests
      result: 'Success'
    }
    # test: 380_doas_with_fan_coil_chiller_with_boiler
    test_sets << {
      model: '380_doas_with_fan_coil_chiller_with_boiler',
      weather: 'NY_New_York_John_F_Ke_744860_16', # weather file does not matter with current tests
      result: 'Success'
    }
    # test: 380_vav_air_cooled_chiller_with_gas_boiler_reheat
    test_sets << {
      model: '380_vav_air_cooled_chiller_with_gas_boiler_reheat',
      weather: 'NY_New_York_John_F_Ke_744860_16', # weather file does not matter with current tests
      result: 'Success'
    }
    # test: 380_vav_chiller_with_gas_boiler_reheat
    test_sets << {
      model: '380_vav_chiller_with_gas_boiler_reheat',
      weather: 'NY_New_York_John_F_Ke_744860_16', # weather file does not matter with current tests
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
      apply_and_test_model(osm_path, instance_test_name)
    end
  end
end
