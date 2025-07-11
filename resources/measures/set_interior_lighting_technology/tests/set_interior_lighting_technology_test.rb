# ComStock™, Copyright (c) 2024 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# dependencies
require 'fileutils'
require 'minitest/autorun'
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require_relative '../measure'

class SetInteriorLightingTechnologyTest < MiniTest::Test
  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs

    # create an instance of the measure
    measure = SetInteriorLightingTechnology.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(1, arguments.size)
    assert_equal('lighting_generation', arguments[0].name)
  end

  def test_outpatient
    # create an instance of the measure
    measure = SetInteriorLightingTechnology.new

    # create runner with empty OSW
    osw = OpenStudio::WorkflowJSON.new
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/outpatient.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    lighting_generation = arguments[0].clone
    assert(lighting_generation.setValue('gen4_led'))
    argument_map['lighting_generation'] = lighting_generation

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}/output/test_outpatient.osm"
    model.save(output_file_path, true)
  end

  def test_hospital
    # create an instance of the measure
    measure = SetInteriorLightingTechnology.new

    # create runner with empty OSW
    osw = OpenStudio::WorkflowJSON.new
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/hospital.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    lighting_generation = arguments[0].clone
    assert(lighting_generation.setValue('gen3_t5_cfl'))
    argument_map['lighting_generation'] = lighting_generation

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}/output/test_hospital.osm"
    model.save(output_file_path, true)
  end

  def test_secondary_school
    # create an instance of the measure
    measure = SetInteriorLightingTechnology.new

    # create runner with empty OSW
    osw = OpenStudio::WorkflowJSON.new
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/secondary_school.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    lighting_generation = arguments[0].clone
    assert(lighting_generation.setValue('gen2_t8_halogen'))
    argument_map['lighting_generation'] = lighting_generation

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # make sure it assigned a high bay fixture to the gym spaces
    model.getSpaceTypes.each do |space_type|
      next unless space_type.name.to_s == 'SecondarySchool Gym'

      space_type.lights.each do |light|
        next unless light.name.to_s == 'SecondarySchool Gym General Lighting'

        light_definition = light.lightsDefinition
        lighting_technology = light_definition.additionalProperties.getFeatureAsString('lighting_technology').to_s
        assert_equal(lighting_technology, 'HID High Bay Metal Halide')
      end
    end

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}/output/test_secondary_school.osm"
    model.save(output_file_path, true)
  end

  def test_small_office
    # create an instance of the measure
    measure = SetInteriorLightingTechnology.new

    # create runner with empty OSW
    osw = OpenStudio::WorkflowJSON.new
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/small_office.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    lighting_generation = arguments[0].clone
    assert(lighting_generation.setValue('gen2_t8_halogen'))
    argument_map['lighting_generation'] = lighting_generation

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}/output/test_small_office.osm"
    model.save(output_file_path, true)
  end

  def test_retailstandalone
    # create an instance of the measure
    measure = SetInteriorLightingTechnology.new

    # create runner with empty OSW
    osw = OpenStudio::WorkflowJSON.new
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/RetailStandalone.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    lighting_generation = arguments[0].clone
    assert(lighting_generation.setValue('gen4_led'))
    argument_map['lighting_generation'] = lighting_generation

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}/output/test_retailstandalone.osm"
    model.save(output_file_path, true)
  end

  def test_rtl
    # create an instance of the measure
    measure = SetInteriorLightingTechnology.new

    # create runner with empty OSW
    osw = OpenStudio::WorkflowJSON.new
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/RtL.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    lighting_generation = arguments[0].clone
    assert(lighting_generation.setValue('gen2_t8_halogen'))
    argument_map['lighting_generation'] = lighting_generation

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}/output/test_RtL.osm"
    model.save(output_file_path, true)
  end
end
