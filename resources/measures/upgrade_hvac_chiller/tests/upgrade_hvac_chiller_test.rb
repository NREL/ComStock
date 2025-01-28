# insert your copyright here

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'minitest/autorun'
require 'fileutils'

require_relative '../measure'

class UpgradeHvacChillerTest < Minitest::Test
  # def setup
  # end

  # def teardown
  # end

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

    test_sets = []

    # test: warm weather
    test_sets << {
      model: '380_doas_with_fan_coil_air_cooled_chiller_with_boiler',
      weather: 'USA_NY_New.York-Central.Park.725033_TMY3',
      result: 'Success'
    }
    # # test: cold weather
    # test_sets << {
    #   model: 'Small_Office_2A',
    #   weather: 'USA_AK_Fairbanks.Intl.AP.702610_TMY3',
    #   result: 'Success'
    # }
    # # test: too many indoor units
    # test_sets << {
    #   model: 'Outpatient_VAV_chiller_PFP_boxes',
    #   weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16',
    #   result: 'NA'
    # }
    # # test: floor area too large
    # test_sets << {
    #   model: 'SecondarySchool_PTHP',
    #   weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16',
    #   result: 'NA'
    # }

    test_sets.each do |set|
      instance_test_name = set[:model]
      puts "instance test name: #{instance_test_name}"
      osm_path = models_for_tests.select { |x| set[:model] == File.basename(x, '.osm') }
      epw_path = epws_for_tests.select { |x| set[:weather] == File.basename(x, '.epw') }
      assert(!osm_path.empty?)
      assert(!epw_path.empty?)
      osm_path = osm_path[0]
      epw_path = epw_path[0]

      apply_model(osm_path)

    end
  end

  def apply_model(path)
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

    # store the number of spaces in the seed model
    num_spaces_seed = model.getSpaces.size

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

    # Ensure the model did not start with a space named like requested
    refute_includes(model.getSpaces.map(&:nameString), "New Space")

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    refute_empty(result.stepInitialCondition)

    refute_empty(result.stepFinalCondition)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}/output/test_output.osm"
    model.save(output_file_path, true)
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
