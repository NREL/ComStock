# insert your copyright here

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'minitest/autorun'
require_relative '../measure.rb'
require 'fileutils'

class DfThermostatControlLoadShedTest < Minitest::Test
  # def setup
  # end

  # def teardown
  # end

  def test_number_of_arguments_and_argument_names
    # create an instance of the measure
    measure = DfThermostatControlLoadShed.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(1, arguments.size)
    assert_equal('space_name', arguments[0].name)
  end

  # def test_bad_argument_values
  #   # create an instance of the measure
  #   measure = DfThermostatControlLoadShed.new

  #   # create runner with empty OSW
  #   osw = OpenStudio::WorkflowJSON.new
  #   runner = OpenStudio::Measure::OSRunner.new(osw)

  #   # make an empty model
  #   model = OpenStudio::Model::Model.new

  #   # get arguments
  #   arguments = measure.arguments(model)
  #   argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

  #   # create hash of argument values
  #   args_hash = {}
  #   args_hash['space_name'] = ''

  #   # populate argument with specified hash value if specified
  #   arguments.each do |arg|
  #     temp_arg_var = arg.clone
  #     if args_hash.key?(arg.name)
  #       assert(temp_arg_var.setValue(args_hash[arg.name]))
  #     end
  #     argument_map[arg.name] = temp_arg_var
  #   end

  #   # run the measure
  #   measure.run(model, runner, argument_map)
  #   result = runner.result

  #   # show the output
  #   show_output(result)

  #   # assert that it ran correctly
  #   assert_equal('Fail', result.value.valueName)
  # end

  # def test_good_argument_values
  #   # create an instance of the measure
  #   measure = DfThermostatControlLoadShed.new

  #   # create runner with empty OSW
  #   osw = OpenStudio::WorkflowJSON.new
  #   runner = OpenStudio::Measure::OSRunner.new(osw)

  #   # load the test model
  #   translator = OpenStudio::OSVersion::VersionTranslator.new
  #   path = "#{File.dirname(__FILE__)}/example_model.osm"
  #   model = translator.loadModel(path)
  #   assert(!model.empty?)
  #   model = model.get

  #   # store the number of spaces in the seed model
  #   num_spaces_seed = model.getSpaces.size

  #   # get arguments
  #   arguments = measure.arguments(model)
  #   argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

  #   # create hash of argument values.
  #   # If the argument has a default that you want to use, you don't need it in the hash
  #   args_hash = {}
  #   args_hash['space_name'] = 'New Space'
  #   # using defaults values from measure.rb for other arguments

  #   # populate argument with specified hash value if specified
  #   arguments.each do |arg|
  #     temp_arg_var = arg.clone
  #     if args_hash.key?(arg.name)
  #       assert(temp_arg_var.setValue(args_hash[arg.name]))
  #     end
  #     argument_map[arg.name] = temp_arg_var
  #   end

  #   # run the measure
  #   measure.run(model, runner, argument_map)
  #   result = runner.result

  #   # show the output
  #   show_output(result)

  #   # assert that it ran correctly
  #   assert_equal('Success', result.value.valueName)
  #   assert(result.info.size == 1)
  #   assert(result.warnings.empty?)

  #   # check that there is now 1 space
  #   assert_equal(1, model.getSpaces.size - num_spaces_seed)

  #   # save the model to test output directory
  #   output_file_path = "#{File.dirname(__FILE__)}//output/test_output.osm"
  #   model.save(output_file_path, true)
  # end

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

  # create an array of hashes with model name, weather, and expected result
  def models_to_test
    test_sets = []

    # test: not applicable building type
    test_sets << {
      model: 'Small_Office_2A',
      weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16',
      result: 'Success'
    }
    
    return test_sets
  end

  def load_model(osm_path)
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(OpenStudio::Path.new(osm_path))
    assert(!model.empty?)
    model = model.get
    return model
  end

  # def test_models
  #   test_name = 'test_models'
  #   puts "\n######\nTEST:#{test_name}\n######\n"

  #   models_to_test.each do |set|
  #     instance_test_name = set[:model]
  #     puts "instance test name: #{instance_test_name}"
  #     osm_path = models_for_tests.select { |x| set[:model] == File.basename(x, '.osm') }
  #     epw_path = epws_for_tests.select { |x| set[:weather] == File.basename(x, '.epw') }
  #     assert(!osm_path.empty?)
  #     assert(!epw_path.empty?)
  #     osm_path = osm_path[0]
  #     epw_path = epw_path[0]

  #     # create an instance of the measure
  #     measure = DfThermostatControlLoadShed.new

  #     # load the model; only used here for populating arguments
  #     model = load_model(osm_path)

  #     # set arguments here; will vary by measure
  #     arguments = measure.arguments(model)
  #     argument_map = OpenStudio::Measure::OSArgumentMap.new

  #     # set arguments: choice of economizer
  #     vrf_defrost_strategy = arguments[0].clone
  #     assert(vrf_defrost_strategy.setValue('reverse-cycle'))
  #     argument_map['vrf_defrost_strategy'] = vrf_defrost_strategy

  #     # set arguments: changeover temperature C
  #     disable_defrost = arguments[1].clone
  #     assert(disable_defrost.setValue(false))
  #     argument_map['disable_defrost'] = disable_defrost

  #     # set arguments: changeover temperature C
  #     upsizing_allowance_pct = arguments[2].clone
  #     assert(upsizing_allowance_pct.setValue(25.0))
  #     argument_map['upsizing_allowance_pct'] = upsizing_allowance_pct

  #     # set arguments: apply measure
  #     apply_measure = arguments[3].clone	
  #     assert(apply_measure.setValue(true))
  #     argument_map['apply_measure'] = apply_measure

  #     # apply the measure to the model and optionally run the model
  #     result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

  #     # check the measure result; result values will equal Success, Fail, or Not Applicable (NA)
  #     # also check the amount of warnings, info, and error messages
  #     # use if or case statements to change expected assertion depending on model characteristics
  #     assert(result.value.valueName == set[:result])

  #     # to check that something changed in the model, load the model and the check the objects match expected new value
  #     model = load_model(model_output_path(instance_test_name))

  #   end
  # end

end
