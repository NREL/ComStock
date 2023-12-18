# insert your copyright here

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'minitest/autorun'
require_relative '../measure.rb'
require 'fileutils'

class NewMeasureTest < Minitest::Test
  # def setup
  # end

  # def teardown
  # end
  def model_input_path(osm_name)
    # return models_for_tests.select { |x| set[:model] == osm_name }
    #return File.join(File.dirname(__FILE__), '../../../tests/models', osm_name)
	return File.join(File.dirname(__FILE__), '/models', osm_name)
  end
  
  def epw_input_path(epw_name)
    #runner.registerInfo("file name #{File.join(File.dirname(__FILE__), '../../../tests/weather', epw_name)}")
    #return File.join(File.dirname(__FILE__), '../../../tests/weather', epw_name)
	return File.join(File.dirname(__FILE__), '/weather', epw_name)
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
  
   def model_output_path(test_name)
    return "#{run_dir(test_name)}/#{test_name}.osm"
  end

  def sql_path(test_name)
    return "#{run_dir(test_name)}/run/eplusout.sql"
  end

  def report_path(test_name)
    return "#{run_dir(test_name)}/reports/eplustbl.html"
  end
  
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
  
  #test for a particula rbuilding type 
  def test_361_warehouse_pvav_na
   
   # this makes sure measure registers an na for non applicable model
    osm_name = '361_Warehouse_PVAV_2a_vent_mod.osm'
    epw_name = 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16.epw'

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = NighttimeOAControls.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new
	
	# Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)
	#result = apply_measure_and_run(__method__, measure, osm_path, epw_path, run_model: true)
    assert_equal('NA', result.value.valueName)
	
	end 

  # def test_number_of_arguments_and_argument_names
    # # create an instance of the measure
    # measure = NewMeasure.new

    # # make an empty model
    # model = OpenStudio::Model::Model.new

    # # # get arguments and test that they are what we are expecting
    # # arguments = measure.arguments(model)
    # # assert_equal(1, arguments.size)
    # # assert_equal('space_name', arguments[0].name)
  # end

  # def test_bad_argument_values
    # # create an instance of the measure
    # measure = NewMeasure.new

    # # create runner with empty OSW
    # osw = OpenStudio::WorkflowJSON.new
    # runner = OpenStudio::Measure::OSRunner.new(osw)

    # # make an empty model
    # model = OpenStudio::Model::Model.new

    # # get arguments
    # arguments = measure.arguments(model)
    # argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # # create hash of argument values
    # args_hash = {}
    # args_hash['space_name'] = ''

    # # populate argument with specified hash value if specified
    # arguments.each do |arg|
      # temp_arg_var = arg.clone
      # if args_hash.key?(arg.name)
        # assert(temp_arg_var.setValue(args_hash[arg.name]))
      # end
      # argument_map[arg.name] = temp_arg_var
    # end

    # # run the measure
    # measure.run(model, runner, argument_map)
    # result = runner.result

    # # show the output
    # show_output(result)

    # # assert that it ran correctly
    # assert_equal('Fail', result.value.valueName)
  # end

  # def test_good_argument_values
    # # create an instance of the measure
    # measure = NewMeasure.new

    # # create runner with empty OSW
    # osw = OpenStudio::WorkflowJSON.new
    # runner = OpenStudio::Measure::OSRunner.new(osw)

    # # load the test model
    # translator = OpenStudio::OSVersion::VersionTranslator.new
    # path = "#{File.dirname(__FILE__)}/example_model.osm"
    # model = translator.loadModel(path)
    # assert(!model.empty?)
    # model = model.get

    # # store the number of spaces in the seed model
    # num_spaces_seed = model.getSpaces.size

    # # get arguments
    # arguments = measure.arguments(model)
    # argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # # create hash of argument values.
    # # If the argument has a default that you want to use, you don't need it in the hash
    # args_hash = {}
    # args_hash['space_name'] = 'New Space'
    # # using defaults values from measure.rb for other arguments

    # # populate argument with specified hash value if specified
    # arguments.each do |arg|
      # temp_arg_var = arg.clone
      # if args_hash.key?(arg.name)
        # assert(temp_arg_var.setValue(args_hash[arg.name]))
      # end
      # argument_map[arg.name] = temp_arg_var
    # end

    # # run the measure
    # measure.run(model, runner, argument_map)
    # result = runner.result

    # # show the output
    # show_output(result)

    # # assert that it ran correctly
    # assert_equal('Success', result.value.valueName)
    # assert(result.info.size == 1)
    # assert(result.warnings.empty?)

    # # check that there is now 1 space
    # assert_equal(1, model.getSpaces.size - num_spaces_seed)

    # # save the model to test output directory
    # output_file_path = "#{File.dirname(__FILE__)}//output/test_output.osm"
    # model.save(output_file_path, true)
  #end
end
