# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
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

# dependencies
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'
require 'minitest/autorun'
require_relative '../measure.rb'

# only necessary to include here if annual simulation request and the measure doesn't require openstudio-standards
require 'openstudio-standards'

class AddThermostatSetpointVariability_Test < Minitest::Test
  # all tests are a sub definition of this class, e.g.:
  # def test_new_kind_of_test
  #   # test content
  # end

  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # create an instance of the measure
    measure = AddThermostatSetpointVariability.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(4, arguments.size)
    assert_equal('clg_sp_f', arguments[0].name)
    assert_equal('clg_delta_f', arguments[1].name)
    assert_equal('htg_sp_f', arguments[2].name)
    assert_equal('htg_delta_f', arguments[3].name)
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

  def load_model(osm_path)
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(OpenStudio::Path.new(osm_path))
    assert(!model.empty?)
    model = model.get
    return model
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    path = "#{File.dirname(__FILE__)}/output/#{test_name}"
    unless File.directory?(path)
      FileUtils.mkdir_p(path)
    end
    return path
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

  # applies the measure and then runs the model
  def apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false)
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
    model = load_model(new_osm_path)

    # set model weather file
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(new_epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
    assert(model.weatherFile.is_initialized)

    # run the measure
    puts "\nAPPLYING MEASURE..."
    measure.run(model, runner, argument_map)
    result = runner.result
    result_success = result.value.valueName == 'Success'

    # show the output
    show_output(result)

    # save model
    model.save(model_output_path(test_name), true)

    if run_model && result_success
      puts "\nRUNNING MODEL..."

      std = Standard.build('ComStock DEER 2020')
      std.model_run_simulation_and_log_errors(model, run_dir(test_name))

      # check that the model ran successfully
      assert(File.exist?(sql_path(test_name)))
    end

    # change back directory
    Dir.chdir(start_dir)

    return result
  end

  # create an array of hashes with model name, weather, and expected result
  def models_to_test
    test_sets = []
    test_sets << { model: 'PSZ-AC_with_gas_coil_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success'}
    test_sets << { model: 'Warehouse_5A', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    return test_sets
  end

  #create helper method for test
  def get_sch_minmax(sch)
    profiles = [sch.defaultDaySchedule]
    sch.scheduleRules.each{|p| profiles << p.daySchedule}
    values = []
    profiles.each{|p| values << p.values}
    return {min: values.flatten.min, max: values.flatten.max}
  end

  def test_models
    test_name = 'test_models'
    puts "\n######\nTEST:#{test_name}\n######\n"

    models_to_test.each do |set|
      instance_test_name = set[:model]
      puts "instance test name: #{instance_test_name}"
      osm_path = models_for_tests.select { |x| set[:model] == File.basename(x, '.osm') }
      epw_path = epws_for_tests.select { |x| set[:weather] == File.basename(x, '.epw') }
      assert(!osm_path.empty?)
      assert(!epw_path.empty?)
      osm_path = osm_path[0]
      epw_path = epw_path[0]

      # create an instance of the measure
      measure = AddThermostatSetpointVariability.new

      # load the model; only used here for populating arguments
      model = load_model(osm_path)

      # set arguments here; will vary by measure
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure::OSArgumentMap.new

      # set arguments here; will vary by measure
      args_hash = {
        'clg_sp_f' => 73,
        'clg_delta_f' => 4,
        'htg_sp_f' => 68,
        'htg_delta_f' => 4
      }

      # populate argument with specified hash value if specified
      arguments.each do |arg|
        temp_arg_var = arg.clone
        if args_hash.key?(arg.name)
          assert(temp_arg_var.setValue(args_hash[arg.name]))
        end
        argument_map[arg.name] = temp_arg_var
      end

      # gather initial setpoint schedules
      clg_schs = []
      htg_schs = []
      model.getThermalZones.each do |zone|
        next unless zone.thermostatSetpointDualSetpoint.is_initialized
        next unless zone.thermostatSetpointDualSetpoint.get.coolingSetpointTemperatureSchedule.is_initialized
        next if clg_schs.include?(zone.thermostatSetpointDualSetpoint.get.coolingSetpointTemperatureSchedule.get)
        clg_schs << zone.thermostatSetpointDualSetpoint.get.coolingSetpointTemperatureSchedule.get
        next unless zone.thermostatSetpointDualSetpoint.get.heatingSetpointTemperatureSchedule.is_initialized
        next if htg_schs.include?(zone.thermostatSetpointDualSetpoint.get.heatingSetpointTemperatureSchedule.get)
        htg_schs << zone.thermostatSetpointDualSetpoint.get.heatingSetpointTemperatureSchedule.get
      end

      puts "#{clg_schs.size} Cooling Schedules"
      puts "#{htg_schs.size} Heating Schedules"

      before_vals = {}
      (clg_schs+htg_schs).each do |sch|
        sch = sch.to_ScheduleRuleset.get
        before_vals[sch.name.get] = get_sch_minmax(sch)
      end



      # apply the measure to the model and optionally run the model
      result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

      # check the measure result; result values will equal Success, Fail, or Not Applicable
      # also check the amount of warnings, info, and error messages
      # use if or case statements to change expected assertion depending on model characteristics
      assert(result.value.valueName == set[:result])

      # to check that something changed in the model, load the model and the check the objects match expected new value
      model = load_model(model_output_path(instance_test_name))

      # add additional tests here to check model outputs
      changed_clg = []
      changed_htg = []
      model.getThermostatSetpointDualSetpoints.each do |tstat|
        clg = tstat.coolingSetpointTemperatureSchedule.get.to_ScheduleRuleset.get
        clg_name = clg.name.get

        # get new min/max
        min_clg = OpenStudio.convert(get_sch_minmax(clg)[:min],'C','F').get
        max_clg = OpenStudio.convert(get_sch_minmax(clg)[:max],'C','F').get

        if result.stepWarnings.any?{|w| w.include?("#{clg_name} has a minimum setpoint over")}
          # values beyond limits
          assert_equal(OpenStudio.convert(before_vals[clg_name][:min],'C','F').get, min_clg)
        else
          # setpoint applied
          assert_in_delta(args_hash['clg_sp_f'], min_clg, 0.001)
          # test setback
          if result.stepWarnings.any?{|w| w.include?("#{clg_name} only has 1 temperature")}
            # flat schedule
            assert_in_delta(args_hash['clg_sp_f'], max_clg, 0.001)
          else
            # setback applied
            assert_in_delta(args_hash['clg_sp_f'] + args_hash['clg_delta_f'], max_clg, 0.001)
          end
        end

        # heating
        htg = tstat.heatingSetpointTemperatureSchedule.get.to_ScheduleRuleset.get
        htg_name = htg.name.get

        # get new min/max
        min_htg = OpenStudio.convert(get_sch_minmax(htg)[:min],'C','F').get
        max_htg = OpenStudio.convert(get_sch_minmax(htg)[:max],'C','F').get

        if result.stepWarnings.any?{|w| w.include?("#{htg_name} has a maximum setpoint under")} || htg_name == "Warehouse HtgSetp"
          # value beyond limits
          assert_equal(OpenStudio.convert(before_vals[htg_name][:max],'C','F').get, max_htg)
        else
          # setpoint applied
          assert_in_delta(args_hash['htg_sp_f'], max_htg, 0.001)
          # test setback
          if result.stepWarnings.any?{|w| w.include?("#{htg_name} only has 1 temperature")}
            # flat schedule
            assert_in_delta(args_hash['htg_sp_f'], min_htg, 0.001)
          else
            # setback applied
            assert_in_delta(args_hash['htg_sp_f'] - args_hash['htg_delta_f'], min_htg, 0.001)
          end
        end
      end
    end
  end
end
