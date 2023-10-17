# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'openstudio'
require 'openstudio/ruleset/ShowRunnerOutput'
require 'minitest/autorun'
require_relative '../measure.rb'
require 'fileutils'

class SetSpaceTypeLoadSubcategoriesTest < MiniTest::Test

  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs

    # create an instance of the measure
    measure = SetSpaceTypeLoadSubcategories.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(0, arguments.size)
  end

  def test_MFm_enduse_subcategory
    # create an instance of the measure
    measure = SetSpaceTypeLoadSubcategories.new

    # create runner with empty OSW
    osw = OpenStudio::WorkflowJSON.new
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/MFm-CEC T24-CEC6.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}/output/test_output.osm"
    model.save(output_file_path, true)
  end

end
