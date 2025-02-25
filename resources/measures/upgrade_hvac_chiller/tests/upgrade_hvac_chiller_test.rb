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
    assert_equal(1, arguments.size)
    assert_equal('debug_verbose', arguments[0].name)
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
      apply_model(osm_path)

    end
  end

  # apply measure to model and test,
  # measure application result
  # initial/final condition check
  # variable speed pump coefficient check
  def apply_model(path)

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
      if arg.name == 'debug_verbose'
        debug_verbose = arguments[idx].clone
        debug_verbose.setValue(true)
        argument_map[arg.name] = debug_verbose
      else
        argument_map[arg.name] = temp_arg_var
      end
    end

    # get chiller specs before measure
    chillers = model.getChillerElectricEIRs
    counts_chillers_acc_b, capacity_total_w_acc_b, cop_acc_b, counts_chillers_wcc_b, capacity_total_w_wcc_b, cop_wcc_b = UpgradeHvacChiller.chiller_specifications(chillers)

    # get pump specs before measure
    # pumps_const_spd = model.getPumpConstantSpeeds
    pumps_var_spd = model.getPumpVariableSpeeds
    # _, pump_rated_flow_total_c, _, _, = UpgradeHvacChiller.pump_specifications(applicable_pumps, pumps_const_spd, std)
    _, _, _, _, coeff1_b, coeff2_b, coeff3_b, coeff4_b = UpgradeHvacChiller.pump_specifications([], pumps_var_spd, std)

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # get chiller specs after measure
    chillers = model.getChillerElectricEIRs
    counts_chillers_acc_a, capacity_total_w_acc_a, cop_acc_a, counts_chillers_wcc_a, capacity_total_w_wcc_a, cop_wcc_a = UpgradeHvacChiller.chiller_specifications(chillers)

    # get pump specs after measure
    # pumps_const_spd = model.getPumpConstantSpeeds
    pumps_var_spd = model.getPumpVariableSpeeds
    # _, pump_rated_flow_total_c, _, _, = UpgradeHvacChiller.pump_specifications(applicable_pumps, pumps_const_spd, std)
    _, _, _, _, coeff1_a, coeff2_a, coeff3_a, coeff4_a = UpgradeHvacChiller.pump_specifications([], pumps_var_spd, std)

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
    puts("### DEBUGGING: coeff1_b = #{coeff1_b} | coeff1_a = #{coeff1_a}")
    puts("### DEBUGGING: coeff2_b = #{coeff2_b} | coeff2_a = #{coeff2_a}")
    puts("### DEBUGGING: coeff3_b = #{coeff3_b} | coeff3_a = #{coeff3_a}")
    puts("### DEBUGGING: coeff4_b = #{coeff4_b} | coeff4_a = #{coeff4_a}")
    coefficient_set_different = false
    if (coeff1_b != coeff1_a) || (coeff2_b != coeff2_a) || (coeff3_b != coeff3_a) || (coeff4_b != coeff4_a)
      coefficient_set_different = true
    end
    assert_equal(counts_chillers_acc_b, counts_chillers_acc_a)
    assert_equal(capacity_total_w_acc_b, capacity_total_w_acc_a)
    assert_equal(cop_acc_b, cop_acc_a)
    assert_equal(counts_chillers_wcc_b, counts_chillers_wcc_a)
    assert_equal(capacity_total_w_wcc_b, capacity_total_w_wcc_a)
    assert_equal(cop_wcc_b, cop_wcc_a)
    assert_equal(true, coefficient_set_different)

    # save the model to test output directory
    # output_file_path = "#{File.dirname(__FILE__)}/output/test_output.osm"
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
