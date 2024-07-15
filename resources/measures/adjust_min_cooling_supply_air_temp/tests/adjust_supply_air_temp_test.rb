# insert your copyright here

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'minitest/autorun'
require_relative '../measure.rb'
require 'fileutils'
require 'openstudio-standards'

class AdjustSupplyAirTemperatureTest < Minitest::Test
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

  # runs the model
  def apply_measure_test_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false)
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



    # copy the osm and epw to the test directory
    new_osm_path = "#{run_dir(test_name)}/#{File.basename(osm_path)}"
    FileUtils.cp(osm_path, new_osm_path)
    new_epw_path = "#{run_dir(test_name)}/#{File.basename(epw_path)}"
    FileUtils.cp(epw_path, new_epw_path)
    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # load the test model
    model = load_model(new_osm_path)

    # set model weather file
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(new_epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
    assert(model.weatherFile.is_initialized)

    # save model
    model.save(model_output_path(test_name), true)

    errs = []
    if run_model
      puts "\nRUNNING ANNUAL SIMULATION..."

      std = Standard.build('NREL ZNE Ready 2017')
      #check if output directory exists if it doesnt run the model.
      if !File.exist?(report_path(test_name))

        std.model_run_simulation_and_log_errors(model, run_dir(test_name))

      end

      # check that the model ran successfully and generated a report
      assert(File.exist?(model_output_path(test_name)))
      assert(File.exist?(sql_path(test_name)))
      assert(File.exist?(report_path(test_name)))

      # set runner variables
      runner.setLastEpwFilePath(epw_path)
      runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_output_path(test_name)))
      runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))
      sql = runner.lastEnergyPlusSqlFile.get
      model.setSqlFile(sql)

      # #get annual energy from seed model
      # std = Standard.build('90.1-2013')
      # annual_gas_use_seed = std.model_annual_energy_by_fuel_and_enduse(model, 'Natural Gas', 'Heating')
      # puts 'Annual Heating Gas Use Seed = ' + annual_gas_use_seed.to_s
      # annual_electricity_use_seed = std.model_annual_energy_by_fuel_and_enduse(model, 'Electricity','Cooling')
      # puts 'Annual Cooling Electricity Use Seed = ' + annual_electricity_use_seed.to_s
    end
    # change back directory
    Dir.chdir(start_dir)


    test_name = test_name + "_Reduce_SAT"
    # run the measure
    puts "\nAPPLYING MEASURE..."
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)
    assert(result.warnings.empty?)


    # save model
    model.save(model_output_path(test_name), true)


    # run model with measure applied
    if run_model && (result.value.valueName == 'Success')
      puts "\nRUNNING ANNUAL SIMULATION..."
      std = Standard.build('NREL ZNE Ready 2017')
      # MD NOTE: you don't need to re-run the model every time. There are examples to check whether the output exists. You can delete the output directory and run again if you change the measure and want to re-generate and re-run the model

      if !File.exist?(report_path(test_name))

        std.model_run_simulation_and_log_errors(model, run_dir(test_name))

      end


      # check that the model ran successfully and generated a report
      assert(File.exist?(model_output_path(test_name)))
      assert(File.exist?(sql_path(test_name)))
      assert(File.exist?(report_path(test_name)))

      # set runner variables
      runner.setLastEpwFilePath(epw_path)
      runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_output_path(test_name)))
      runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))
      sql = runner.lastEnergyPlusSqlFile.get
      model.setSqlFile(sql)

      # get annual energy use post measure
      annual_gas_use_post = std.model_annual_energy_by_fuel_and_enduse(model, 'Natural Gas', 'Heating')
      puts 'Annual Heating Gas Energy Post = ' + annual_gas_use_post.to_s
      annual_electricity_use_post = std.model_annual_energy_by_fuel_and_enduse(model, 'Electricity','Cooling')
      puts 'Annual Cooling Electricity Energy Post = ' + annual_electricity_use_post.to_s
      annual_energy_post = annual_electricity_use_post + annual_gas_use_post
      puts 'Annual Heating and Cooling Energy Post = ' + annual_energy_post.to_s
      annual_energy_seed = annual_electricity_use_seed + annual_gas_use_seed
      puts 'Annual Heating and Cooling Energy Seed = ' + annual_energy_seed.to_s

      # check if heating energy was increased
      if annual_gas_use_post > annual_gas_use_seed
        puts "For #{test_name} there was an increase in heating energy consumption. Either model is not suitable for heat recovery chillers or error in inputs occured."
      else
        puts "For #{test_name} annual gas use was decreased. Heat recovery chiller saves gas energy."
      end

      # check if cooling energy was increased
      if annual_electricity_use_post > annual_electricity_use_seed
        puts "For #{test_name} there was a decrease in cooling energy. This is not expected in heat recovery operation. Troubleshoot model or inputs."
      else
        puts "For #{test_name} there was either no change or an increase in cooling energy as anticipated."
      end
    end
    # change back directory
    Dir.chdir(start_dir)

    assert(errs.empty?, errs.join("\n"))

    return result
  end


  def test_number_of_arguments_and_argument_names
    # create an instance of the measure
    measure = AdjustSupplyAirTemperature.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(3, arguments.size)
    assert_equal('sat', arguments[0].name)
    assert_equal('apply_measure', arguments[1].name)
    assert_equal('apply_to_sizing', arguments[2].name)

  end

  def test_bad_argument_values
    # create an instance of the measure
    measure = AdjustSupplyAirTemperature.new

    # create runner with empty OSW
    osw = OpenStudio::WorkflowJSON.new
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # create hash of argument values
    args_hash = {}
    args_hash['sat'] = '32'

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args_hash.key?(arg.name)
        assert(temp_arg_var.setValue(args_hash[arg.name]))
      end
      argument_map[arg.name] = temp_arg_var
    end

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Fail', result.value.valueName)
  end

  def test_good_argument_values
    # create an instance of the measure
    measure = AdjustSupplyAirTemperature.new

    # create runner with empty OSW
    osw = OpenStudio::WorkflowJSON.new
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/secondar_school_vav_system_comstock.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get

    # store the number of spaces in the seed model
    num_spaces_seed = model.getSpaces.size

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # create hash of argument values.
    # If the argument has a default that you want to use, you don't need it in the hash
    args_hash = {}
    args_hash['sat'] = 52.0
    # using defaults values from measure.rb for other arguments

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args_hash.key?(arg.name)
        assert(temp_arg_var.setValue(args_hash[arg.name]))
      end
      argument_map[arg.name] = temp_arg_var
    end

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)
    assert(result.warnings.empty?)


    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}/output/test_output.osm"
    model.save(output_file_path, true)
  end

  def test_secondar_school_vav_system_comstock
    # this tests what adding a heat recovery chiller does to the model
    test_name = 'secondar_school_vav_system_comstock'
    puts "\n######\nTEST: #{test_name}\n######\n"
    osm_path = "#{File.dirname(__FILE__)}/secondar_school_vav_system_comstock.osm"
    epw_path = "#{File.dirname(__FILE__)}/secondar_school_vav_system_comstock.epw"

    # create an instance of the measure
   measure = AdjustSupplyAirTemperature.new

   #load the model; only used here for populating arugments
   model = load_model(osm_path)

   # get arguments
   arguments = measure.arguments(model)
   argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

   # create hash of argument values.
   # If the argument has a default that you want to use, you don't need it in the hash
   args_hash = {}
   args_hash['sat'] = 52.0
   # using defaults values from measure.rb for other arguments

   # populate argument with specified hash value if specified
   arguments.each do |arg|
     temp_arg_var = arg.clone
     if args_hash.key?(arg.name)
       assert(temp_arg_var.setValue(args_hash[arg.name]))
     end
     argument_map[arg.name] = temp_arg_var
   end

   #run the model and test applied measure
   result = apply_measure_test_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: true)



   # assert that it ran correctly
   assert(result.value.valueName == 'Success')

 end

end
