# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2023, Alliance for Sustainable Energy, LLC.
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

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'minitest/autorun'
require_relative '../measure.rb'
require 'fileutils'
require 'openstudio-standards'

class AddHeatRecoveryChillerTest < Minitest::Test

  def test_number_of_arguments_and_argument_names
    # create an instance of the measure
    measure = AddHeatRecoveryChiller.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(12, arguments.size)
    assert_equal('cooling_loop_name', arguments[0].name)
    assert_equal('heating_loop_name', arguments[1].name)
    assert_equal('chiller_choice', arguments[2].name)
    assert_equal('new_chiller_size_tons', arguments[3].name)
    assert_equal('existing_chiller_name', arguments[4].name)
    assert_equal('link_option', arguments[5].name)
    assert_equal('storage_tank_size_gal', arguments[6].name)
    assert_equal('heating_order', arguments[7].name)
    assert_equal('heat_recovery_loop_temperature_f', arguments[8].name)
    assert_equal('reset_hot_water_loop_temperature', arguments[9].name)
    assert_equal('reset_heating_coil_design_temp', arguments[10].name)
    assert_equal('enable_output_variables', arguments[11].name)
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

  def apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, expected_result: 'Success', run_model: false)
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

    # # remove prior runs if they exist
    # if File.exist?(model_output_path(test_name))
    #   FileUtils.rm(model_output_path(test_name))
    # end
    # if File.exist?(report_path(test_name))
    #   FileUtils.rm(report_path(test_name))
    # end

    # copy the osm and epw to the test directory
    new_osm_path = "#{run_dir(test_name)}/#{File.basename(osm_path)}"
    FileUtils.cp(osm_path, new_osm_path)
    new_epw_path = "#{run_dir(test_name)}/#{File.basename(epw_path)}"
    FileUtils.cp(epw_path, new_epw_path)

    # intialize std object for method access
    std = Standard.build('90.1-2013')

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # load the test model
    model = load_model(new_osm_path)

    # store the number of components in the seed model
    num_plant_loop_seed = model.getPlantLoops.size

    # set model weather file
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(new_epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
    assert(model.weatherFile.is_initialized)

    # run the measure
    puts "\nAPPLYING MEASURE..."
    measure.run(model, runner, argument_map)
    result = runner.result

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal(expected_result, result.value.valueName)

    # check that objects were added
    assert_equal(1, model.getPlantLoops.size - num_plant_loop_seed) unless expected_result == 'Fail'

    # save model
    model.save(model_output_path(test_name), true)

    # run model with measure applied
    if run_model && (result.value.valueName == 'Success')
      puts "\nRUNNING ANNUAL SIMULATION..."

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

      # get annual run period
      ann_env_pd = nil
      sql.availableEnvPeriods.each do |env_pd|
        env_type = sql.environmentType(env_pd)
        if env_type.is_initialized
          if env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod')
            ann_env_pd = env_pd
          end
        end
      end
      if ann_env_pd == false
        runner.registerError("Can't find a weather runperiod, make sure you ran an annual simulation, not just the design days.")
        return false
      end

      # get hourly heat recovery demand inlet temperature values
      env_period_ix_query = "SELECT EnvironmentPeriodIndex FROM EnvironmentPeriods WHERE EnvironmentName='#{ann_env_pd}'"
      env_period_ix = sql.execAndReturnFirstInt(env_period_ix_query).get
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'System Node Temperature' AND ReportingFrequency = 'Hourly' AND KeyValue = 'HEAT RECOVERY LOOP DEMAND INLET NODE'"
      var_data_id = sql.execAndReturnFirstInt(var_data_id_query)
      temperature_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}' AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}' AND Interval = '60')"
      temperature_values = sql.execAndReturnVectorOfDouble(temperature_query).get
      if temperature_values.empty?
        runner.registerError('Unable to get hourly timeseries facility electricity use from the model.  Cannot calculate emissions.')
        return false
      end
      demand_inlet_temperature_values_f = []
      temperature_values.each { |val| demand_inlet_temperature_values_f << val * 1.8 + 32.0}

      # get hourly heat recovery demand outlet temperature values
      env_period_ix_query = "SELECT EnvironmentPeriodIndex FROM EnvironmentPeriods WHERE EnvironmentName='#{ann_env_pd}'"
      env_period_ix = sql.execAndReturnFirstInt(env_period_ix_query).get
      var_data_id_query = "SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableName = 'System Node Temperature' AND ReportingFrequency = 'Hourly' AND KeyValue = 'HEAT RECOVERY LOOP DEMAND OUTLET NODE'"
      var_data_id = sql.execAndReturnFirstInt(var_data_id_query)
      temperature_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex = '#{var_data_id.get}' AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}' AND Interval = '60')"
      temperature_values = sql.execAndReturnVectorOfDouble(temperature_query).get
      if temperature_values.empty?
        runner.registerError('Unable to get hourly timeseries facility electricity use from the model.  Cannot calculate emissions.')
        return false
      end
      demand_outlet_temperature_values_f = []
      temperature_values.each { |val| demand_outlet_temperature_values_f << val * 1.8 + 32.0}

      # report out temperature statistics
      temp_arg = argument_map['heat_recovery_loop_temperature_f']
      arg_temp_value_f = temp_arg.hasValue ? temp_arg.valueAsDouble : temp_arg.defaultValueAsDouble
      total_hrs = demand_inlet_temperature_values_f.size
      inlet_temperature_avg_f = demand_inlet_temperature_values_f.sum / total_hrs
      outlet_temperature_avg_f = demand_outlet_temperature_values_f.sum / total_hrs
      inlet_hrs_close_at_temp = demand_inlet_temperature_values_f.select { |v| (v - arg_temp_value_f).abs < 1.0 }
      outlet_hrs_close_at_temp = demand_inlet_temperature_values_f.select { |v| (v - arg_temp_value_f).abs < 1.0 }
      puts "Heat Recovery Loop Demand Inlet Node: min #{demand_inlet_temperature_values_f.min.round(2)}F, avg #{inlet_temperature_avg_f.round(2)}F, max #{demand_inlet_temperature_values_f.max.round(2)}F. Expected operating temperature is #{arg_temp_value_f.round(2)}F. #{inlet_hrs_close_at_temp.size} of #{total_hrs} hrs are within 1 F of expected operating temperature."
      puts "Heat Recovery Loop Demand Outlet Node: min #{demand_outlet_temperature_values_f.min.round(2)}F, avg #{outlet_temperature_avg_f.round(2)}F, max #{demand_outlet_temperature_values_f.max.round(2)}F. Expected operating temperature is #{arg_temp_value_f.round(2)}F. #{outlet_hrs_close_at_temp.size} of #{total_hrs} hrs are within 1 F of expected operating temperature."
    end

    # change back directory
    Dir.chdir(start_dir)

    return result
  end

  def test_default_measure_arguments
     # this tests what adding a heat recovery chiller does to the model
     puts "\n######\nTEST: #{__method__}\n######\n"
     osm_path = "#{File.dirname(__FILE__)}/95.osm"
     epw_path = "#{File.dirname(__FILE__)}/95.epw"

     # create an instance of the measure
    measure = AddHeatRecoveryChiller.new

    #load the model; only used here for populating arugments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # create hash of argument values.
    # If the argument has a default that you want to use, you don't need it in the hash
    args_hash = {}
    # using defaults values from measure.rb for other arguments

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args_hash.key?(arg.name)
        assert(temp_arg_var.setValue(args_hash[arg.name]))
      end
      argument_map[arg.name] = temp_arg_var
    end

    # run the model and test applied measure
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)

    # assert that it ran correctly
    assert(result.value.valueName == 'Success')
  end

  def test_use_existing_chiller
    # this tests what adding a heat recovery chiller does to the model
    puts "\n######\nTEST: #{__method__}\n######\n"
    osm_path = "#{File.dirname(__FILE__)}/95.osm"
    epw_path = "#{File.dirname(__FILE__)}/95.epw"

    # create an instance of the measure
   measure = AddHeatRecoveryChiller.new

   #load the model; only used here for populating arugments
   model = load_model(osm_path)

   # get arguments
   arguments = measure.arguments(model)
   argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

   # create hash of argument values.
   # If the argument has a default that you want to use, you don't need it in the hash
   args_hash = {}
   args_hash['heating_loop_name'] = 'Hot Water Loop'
   args_hash['chiller_choice'] = 'Use Existing Chiller'
   # using defaults values from measure.rb for other arguments

   # populate argument with specified hash value if specified
   arguments.each do |arg|
     temp_arg_var = arg.clone
     if args_hash.key?(arg.name)
       assert(temp_arg_var.setValue(args_hash[arg.name]))
     end
     argument_map[arg.name] = temp_arg_var
   end

   # run the model and test applied measure
   result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)

   # assert that it ran correctly
   assert(result.value.valueName == 'Success')
  end

  def test_use_existing_chiller_series
    # this tests what adding a heat recovery chiller does to the model
    puts "\n######\nTEST: #{__method__}\n######\n"
    osm_path = "#{File.dirname(__FILE__)}/95.osm"
    epw_path = "#{File.dirname(__FILE__)}/95.epw"

    # create an instance of the measure
    measure = AddHeatRecoveryChiller.new

    #load the model; only used here for populating arugments
    model = load_model(osm_path)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # create hash of argument values.
    # If the argument has a default that you want to use, you don't need it in the hash
    args_hash = {}
    args_hash['chiller_choice'] = 'Use Existing Chiller'
    args_hash['heating_order'] = 'Series'
    # using defaults values from measure.rb for other arguments

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args_hash.key?(arg.name)
        assert(temp_arg_var.setValue(args_hash[arg.name]))
      end
      argument_map[arg.name] = temp_arg_var
    end

    # run the model and test applied measure
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: true)

    # assert that it ran correctly
    assert(result.value.valueName == 'Success')
  end

  def test_use_existing_chiller_air_cooled
    # this tests what adding a heat recovery chiller does to the model
    puts "\n######\nTEST: #{__method__}\n######\n"
    osm_path = "#{File.dirname(__FILE__)}/95.osm"
    epw_path = "#{File.dirname(__FILE__)}/95.epw"

    # create an instance of the measure
   measure = AddHeatRecoveryChiller.new

   #load the model; only used here for populating arugments
   model = load_model(osm_path)

   # get arguments
   arguments = measure.arguments(model)
   argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

   # create hash of argument values.
   # If the argument has a default that you want to use, you don't need it in the hash
   args_hash = {}
   args_hash['heating_loop_name'] = 'Hot Water Loop'
   args_hash['chiller_choice'] = 'Use Existing Chiller'
   args_hash['existing_chiller_name'] = 'Chiller - Air Cooled'
   # using defaults values from measure.rb for other arguments

   # populate argument with specified hash value if specified
   arguments.each do |arg|
     temp_arg_var = arg.clone
     if args_hash.key?(arg.name)
       assert(temp_arg_var.setValue(args_hash[arg.name]))
     end
     argument_map[arg.name] = temp_arg_var
   end

   # run the model and test applied measure
   result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, expected_result: 'Fail')

   # assert that it ran correctly
   assert(result.value.valueName == 'Fail')
  end
end
