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
require_relative '../../../../test/helpers/minitest_helper'

# only necessary to include here if annual simulation request and the measure doesn't require openstudio-standards
require 'openstudio-standards'

class MeasureTest < Minitest::Test

  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # create an instance of the measure
    measure = SetInteriorLightingBPR.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(4, arguments.size)
    assert_equal('modify_wkdy_bpr', arguments[0].name)
    assert_equal('wkdy_bpr', arguments[1].name)
    assert_equal('modify_wknd_bpr', arguments[2].name)
    assert_equal('wknd_bpr', arguments[3].name)
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

      std = Standard.build('90.1-2013')
      std.model_run_simulation_and_log_errors(model, run_dir(test_name))

      # check that the model ran successfully
      assert(File.exist?(sql_path(test_name)))
    end

    # change back directory
    Dir.chdir(start_dir)

    return result
  end


  def test_small_office
    test_name = 'test_small_office'
    puts "\n######\nTEST:#{test_name}\n######\n"

    test_set = { model: 'Small_Office_2A', weather: 'MI_DETROIT_725375_12', result: 'NA' }
    instance_test_name = test_set[:model]
    puts "instance test name: #{instance_test_name}"
    osm_path = models_for_tests.select { |x| test_set[:model] == File.basename(x, '.osm') }
    epw_path = epws_for_tests.select { |x| test_set[:weather] == File.basename(x, '.epw') }
    assert(!osm_path.empty?)
    assert(!epw_path.empty?)
    osm_path = osm_path[0]
    epw_path = epw_path[0]

    # create an instance of the measure
    measure = SetInteriorLightingBPR.new

    # load the model; only used here for populating arguments
    model = load_model(osm_path)

    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    modify_wkdy_bpr = arguments[0].clone
    wkdy_bpr = arguments[1].clone
    modify_wknd_bpr = arguments[2].clone
    wknd_bpr = arguments[3].clone
    assert(modify_wkdy_bpr.setValue(false))
    assert(wkdy_bpr.setValue(0.0))
    assert(modify_wknd_bpr.setValue(false))
    assert(wknd_bpr.setValue(0.0))
    argument_map['modify_wkdy_bpr'] = modify_wkdy_bpr
    argument_map['wkdy_bpr'] = wkdy_bpr
    argument_map['modify_wknd_bpr'] = modify_wknd_bpr
    argument_map['wknd_bpr'] = wknd_bpr

    # apply the measure to the model and optionally run the model
    result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

    # check the measure result; result values will equal Success, Fail, or Not Applicable
    assert(result.value.valueName == test_set[:result])

  end

  def test_warehouse
    test_name = 'test_warehouse'
    puts "\n######\nTEST:#{test_name}\n######\n"

    test_set = { model: 'Warehouse_5A', weather: 'MI_DETROIT_725375_12', result: 'Success' }
    instance_test_name = test_set[:model]
    puts "instance test name: #{instance_test_name}"
    osm_path = models_for_tests.select { |x| test_set[:model] == File.basename(x, '.osm') }
    epw_path = epws_for_tests.select { |x| test_set[:weather] == File.basename(x, '.epw') }
    assert(!osm_path.empty?)
    assert(!epw_path.empty?)
    osm_path = osm_path[0]
    epw_path = epw_path[0]

    # create an instance of the measure
    measure = SetInteriorLightingBPR.new

    # load the model; only used here for populating arguments
    model = load_model(osm_path)

    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    modify_wkdy_bpr = arguments[0].clone
    wkdy_bpr = arguments[1].clone
    modify_wknd_bpr = arguments[2].clone
    wknd_bpr = arguments[3].clone
    assert(modify_wkdy_bpr.setValue(true))
    assert(wkdy_bpr.setValue(0.0))
    assert(modify_wknd_bpr.setValue(true))
    assert(wknd_bpr.setValue(0.0))
    argument_map['modify_wkdy_bpr'] = modify_wkdy_bpr
    argument_map['wkdy_bpr'] = wkdy_bpr
    argument_map['modify_wknd_bpr'] = modify_wknd_bpr
    argument_map['wknd_bpr'] = wknd_bpr

    # apply the measure to the model and optionally run the model
    result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

    # check the measure result; result values will equal Success, Fail, or Not Applicable
    # also check the amount of warnings, info, and error messages
    # use if or case statements to change expected assertion depending on model characteristics
    model = load_model(model_output_path(instance_test_name))
    model.getSpaceTypes.each do |space_type|
      space_type.lights.each do |lt|
        if lt.schedule.is_initialized
          lt_sch = lt.schedule.get
          case lt_sch.name.get.to_s
          when "Warehouse Bldg Light BPR Adjusted"
            ltg_sch = lt_sch.to_ScheduleRuleset.get
            ltg_sch.defaultDaySchedule.setInterpolatetoTimestep('No')
            expected_hrly_vals = [
                [2, 0],
                [10, 0.9],
                [19, 0.9],
                [23, 0]
            ]
            expected_hrly_vals.each do |hr, val|
              time = OpenStudio::Time.new(0, hr)
              assert_equal(val, ltg_sch.defaultDaySchedule.getValue(time))
            end
          end
        end
      end
    end

    modify_wkdy_bpr = arguments[0].clone
    wkdy_bpr = arguments[1].clone
    modify_wknd_bpr = arguments[2].clone
    wknd_bpr = arguments[3].clone
    assert(modify_wkdy_bpr.setValue(true))
    assert(wkdy_bpr.setValue(0.9))
    assert(modify_wknd_bpr.setValue(true))
    assert(wknd_bpr.setValue(0.9))
    argument_map['modify_wkdy_bpr'] = modify_wkdy_bpr
    argument_map['wkdy_bpr'] = wkdy_bpr
    argument_map['modify_wknd_bpr'] = modify_wknd_bpr
    argument_map['wknd_bpr'] = wknd_bpr

    # apply the measure to the model and optionally run the model
    result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

    # check the measure result; result values will equal Success, Fail, or Not Applicable
    # also check the amount of warnings, info, and error messages
    # use if or case statements to change expected assertion depending on model characteristics
    model = load_model(model_output_path(instance_test_name))
    model.getSpaceTypes.each do |space_type|
      space_type.lights.each do |lt|
        if lt.schedule.is_initialized
          lt_sch = lt.schedule.get
          case lt_sch.name.get.to_s
          when "Warehouse Bldg Light BPR Adjusted"
            ltg_sch = lt_sch.to_ScheduleRuleset.get
            ltg_sch.defaultDaySchedule.setInterpolatetoTimestep('No')
            expected_hrly_vals = [
                [2, 0.81],
                [10, 0.9],
                [19, 0.9],
                [23, 0.81]
            ]
            expected_hrly_vals.each do |hr, val|
              time = OpenStudio::Time.new(0, hr)
              assert_equal(val, ltg_sch.defaultDaySchedule.getValue(time))
            end
          end
        end
      end
    end
  end

  def test_retail
    test_name = 'test_retail'
    puts "\n######\nTEST:#{test_name}\n######\n"

    test_set = { model: 'Retail_7', weather: 'MI_DETROIT_725375_12', result: 'Success' }
    instance_test_name = test_set[:model]
    puts "instance test name: #{instance_test_name}"
    osm_path = models_for_tests.select { |x| test_set[:model] == File.basename(x, '.osm') }
    epw_path = epws_for_tests.select { |x| test_set[:weather] == File.basename(x, '.epw') }
    assert(!osm_path.empty?)
    assert(!epw_path.empty?)
    osm_path = osm_path[0]
    epw_path = epw_path[0]

    # create an instance of the measure
    measure = SetInteriorLightingBPR.new

    # load the model; only used here for populating arguments
    model = load_model(osm_path)

    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    modify_wkdy_bpr = arguments[0].clone
    wkdy_bpr = arguments[1].clone
    modify_wknd_bpr = arguments[2].clone
    wknd_bpr = arguments[3].clone
    assert(modify_wkdy_bpr.setValue(true))
    assert(wkdy_bpr.setValue(0.0))
    assert(modify_wknd_bpr.setValue(true))
    assert(wknd_bpr.setValue(0.0))
    argument_map['modify_wkdy_bpr'] = modify_wkdy_bpr
    argument_map['wkdy_bpr'] = wkdy_bpr
    argument_map['modify_wknd_bpr'] = modify_wknd_bpr
    argument_map['wknd_bpr'] = wknd_bpr

    # apply the measure to the model and optionally run the model
    result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

    # check the measure result; result values will equal Success, Fail, or Not Applicable
    # also check the amount of warnings, info, and error messages
    # use if or case statements to change expected assertion depending on model characteristics
    model = load_model(model_output_path(instance_test_name))
    model.getSpaceTypes.each do |space_type|
      space_type.lights.each do |lt|
        if lt.schedule.is_initialized
          lt_sch = lt.schedule.get
          case lt_sch.name.get.to_s
          when "Retail Bldg Light BPR Adjusted"
            ltg_sch = lt_sch.to_ScheduleRuleset.get
            ltg_sch.defaultDaySchedule.setInterpolatetoTimestep('No')
            expected_hrly_vals = [
                [2, 0],
                [12, 0.9],
                [17, 0.9]
            ]
            expected_hrly_vals.each do |hr, val|
              time = OpenStudio::Time.new(0, hr)
              assert_equal(val, ltg_sch.defaultDaySchedule.getValue(time))
            end
          end
        end
      end
    end

    modify_wkdy_bpr = arguments[0].clone
    wkdy_bpr = arguments[1].clone
    modify_wknd_bpr = arguments[2].clone
    wknd_bpr = arguments[3].clone
    assert(modify_wkdy_bpr.setValue(true))
    assert(wkdy_bpr.setValue(0.9))
    assert(modify_wknd_bpr.setValue(true))
    assert(wknd_bpr.setValue(0.9))
    argument_map['modify_wkdy_bpr'] = modify_wkdy_bpr
    argument_map['wkdy_bpr'] = wkdy_bpr
    argument_map['modify_wknd_bpr'] = modify_wknd_bpr
    argument_map['wknd_bpr'] = wknd_bpr

    # apply the measure to the model and optionally run the model
    result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

    # check the measure result; result values will equal Success, Fail, or Not Applicable
    # also check the amount of warnings, info, and error messages
    # use if or case statements to change expected assertion depending on model characteristics
    model = load_model(model_output_path(instance_test_name))
    model.getSpaceTypes.each do |space_type|
      space_type.lights.each do |lt|
        if lt.schedule.is_initialized
          lt_sch = lt.schedule.get
          case lt_sch.name.get.to_s
          when "Retail Bldg Light BPR Adjusted"
            ltg_sch = lt_sch.to_ScheduleRuleset.get
            ltg_sch.defaultDaySchedule.setInterpolatetoTimestep('No')
            expected_hrly_vals = [
                [2, 0.81],
                [15, 0.9],
                [17, 0.9],
                [21, 0.868235294117647]
            ]
            expected_hrly_vals.each do |hr, val|
              time = OpenStudio::Time.new(0, hr)
              assert_equal(val, ltg_sch.defaultDaySchedule.getValue(time))
            end
          end
        end
      end
    end
  end

  def test_full_service_restaurant
    test_name = 'test_full_service_restaurant'
    puts "\n######\nTEST:#{test_name}\n######\n"

    test_set = { model: 'Full_Service_Restaurant_4A', weather: 'MI_DETROIT_725375_12', result: 'Success' }
    instance_test_name = test_set[:model]
    puts "instance test name: #{instance_test_name}"
    osm_path = models_for_tests.select { |x| test_set[:model] == File.basename(x, '.osm') }
    epw_path = epws_for_tests.select { |x| test_set[:weather] == File.basename(x, '.epw') }
    assert(!osm_path.empty?)
    assert(!epw_path.empty?)
    osm_path = osm_path[0]
    epw_path = epw_path[0]

    # create an instance of the measure
    measure = SetInteriorLightingBPR.new

    # load the model; only used here for populating arguments
    model = load_model(osm_path)

    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    modify_wkdy_bpr = arguments[0].clone
    wkdy_bpr = arguments[1].clone
    modify_wknd_bpr = arguments[2].clone
    wknd_bpr = arguments[3].clone
    assert(modify_wkdy_bpr.setValue(true))
    assert(wkdy_bpr.setValue(0.0))
    assert(modify_wknd_bpr.setValue(true))
    assert(wknd_bpr.setValue(0.0))
    argument_map['modify_wkdy_bpr'] = modify_wkdy_bpr
    argument_map['wkdy_bpr'] = wkdy_bpr
    argument_map['modify_wknd_bpr'] = modify_wknd_bpr
    argument_map['wknd_bpr'] = wknd_bpr

    # apply the measure to the model and optionally run the model
    result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

    # check the measure result; result values will equal Success, Fail, or Not Applicable
    # also check the amount of warnings, info, and error messages
    # use if or case statements to change expected assertion depending on model characteristics
    model = load_model(model_output_path(instance_test_name))
    model.getSpaceTypes.each do |space_type|
      space_type.lights.each do |lt|
        if lt.schedule.is_initialized
          lt_sch = lt.schedule.get
          case lt_sch.name.get.to_s
          when "FullServiceRestaurant Bldg Light BPR Adjusted"
            ltg_sch = lt_sch.to_ScheduleRuleset.get
            ltg_sch.defaultDaySchedule.setInterpolatetoTimestep('No')
            expected_hrly_vals = [
                [4, 0.0],
                [6, 0.63],
                [12, 0.9],
                [23, 0.9]
            ]
            expected_hrly_vals.each do |hr, val|
              time = OpenStudio::Time.new(0, hr)
              assert_equal(val, ltg_sch.defaultDaySchedule.getValue(time))
            end
          end
        end
      end
    end

    modify_wkdy_bpr = arguments[0].clone
    wkdy_bpr = arguments[1].clone
    modify_wknd_bpr = arguments[2].clone
    wknd_bpr = arguments[3].clone
    assert(modify_wkdy_bpr.setValue(true))
    assert(wkdy_bpr.setValue(0.9))
    assert(modify_wknd_bpr.setValue(true))
    assert(wknd_bpr.setValue(0.9))
    argument_map['modify_wkdy_bpr'] = modify_wkdy_bpr
    argument_map['wkdy_bpr'] = wkdy_bpr
    argument_map['modify_wknd_bpr'] = modify_wknd_bpr
    argument_map['wknd_bpr'] = wknd_bpr

    # apply the measure to the model and optionally run the model
    result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

    # check the measure result; result values will equal Success, Fail, or Not Applicable
    # also check the amount of warnings, info, and error messages
    # use if or case statements to change expected assertion depending on model characteristics
    model = load_model(model_output_path(instance_test_name))
    model.getSpaceTypes.each do |space_type|
      space_type.lights.each do |lt|
        if lt.schedule.is_initialized
          lt_sch = lt.schedule.get
          case lt_sch.name.get.to_s
          when "FullServiceRestaurant Bldg Light BPR Adjusted"
            ltg_sch = lt_sch.to_ScheduleRuleset.get
            ltg_sch.defaultDaySchedule.setInterpolatetoTimestep('No')
            expected_hrly_vals = [
                [4, 0.81],
                [12, 0.9],
                [16, 0.9],
                [24, 0.873]
            ]
            expected_hrly_vals.each do |hr, val|
              time = OpenStudio::Time.new(0, hr)
              assert_equal(val, ltg_sch.defaultDaySchedule.getValue(time))
            end
          end
        end
      end
    end
  end

  end
