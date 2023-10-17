# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
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

class SetNISTInfiltrationCorrelationsTest < Minitest::Test

  def run_test(model, args_hash)
    # create an instance of the measure
    measure = SetNISTInfiltrationCorrelations.new

    # create runner with empty OSW
    osw = OpenStudio::WorkflowJSON.new
    runner = OpenStudio::Measure::OSRunner.new(osw)

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

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

    return result
  end

  def test_number_of_arguments_and_argument_names
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # create an instance of the measure
    measure = SetNISTInfiltrationCorrelations.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(7, arguments.size)
    assert_equal('airtightness_value', arguments[0].name)
    assert_equal('airtightness_pressure', arguments[1].name)
    assert_equal('airtightness_area', arguments[2].name)
    assert_equal('air_barrier', arguments[3].name)
    assert_equal('hvac_schedule', arguments[4].name)
    assert_equal('climate_zone', arguments[5].name)
    assert_equal('building_type', arguments[6].name)
  end

  def test_bad_airtightness_value
    test_name = 'test_bad_airtightness_value'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # make an empty model
    model = OpenStudio::Model::Model.new
    
    # create hash of argument values
    args_hash = {}
    args_hash['airtightness_value'] = -1.0

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Fail', result.value.valueName)
  end

  def test_bldg03_smalloffice_pszac
    test_name = 'test_bldg03_smalloffice_pszac'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000003.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get
    args_hash = {}

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day_value = infil_on_schedule.to_ScheduleConstant.get.value
    off_day_value = infil_off_schedule.to_ScheduleConstant.get.value
    assert((on_day_value + off_day_value - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000003_infil_adj.osm"
    model.save(output_file_path, true)
  end

  def test_bldg04_retail_pszacnoheat
    test_name = 'test_bldg04_retail_pszacnoheat'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000004.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get
    args_hash = {}
    args_hash['climate_zone'] = '5B'
    args_hash['building_type'] = 'RetailStandalone'

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day = infil_on_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    off_day = infil_off_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    sum_arr = on_day.values + off_day.values
    assert((sum_arr.min - 1.0) < 0.001)
    assert((sum_arr.max - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000004_infil_adj.osm"
    model.save(output_file_path, true)
  end

  def test_bldg05_ca_rts
    test_name = 'test_bldg05_ca_rts'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000005.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get
    args_hash = {}

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day_value = infil_on_schedule.to_ScheduleConstant.get.value
    off_day_value = infil_off_schedule.to_ScheduleConstant.get.value
    assert((on_day_value + off_day_value - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000005_infil_adj.osm"
    model.save(output_file_path, true)
  end

  def test_bldg25_retail_resforcedair
    test_name = 'test_bldg25_retail_resforcedair'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000025.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get

    # create hash of argument values
    args_hash = {}
    args_hash['airtightness_value'] = 10.0
    args_hash['airtightness_pressure'] = 50
    args_hash['airtightness_area'] = '6-sided'

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day = infil_on_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    off_day = infil_off_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    sum_arr = on_day.values + off_day.values
    assert((sum_arr.min - 1.0) < 0.001)
    assert((sum_arr.max - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000025_infil_adj.osm"
    model.save(output_file_path, true)
  end

  def test_bldg25_retail_resforcedair_air_barrier
    test_name = 'test_bldg25_retail_resforcedair_air_barrier'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000025.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get

    # create hash of argument values
    args_hash = {}
    args_hash['airtightness_value'] = 5.0
    args_hash['airtightness_pressure'] = 50
    args_hash['airtightness_area'] = '6-sided'
    args_hash['air_barrier'] = true

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day = infil_on_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    off_day = infil_off_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    sum_arr = on_day.values + off_day.values
    assert((sum_arr.min - 1.0) < 0.001)
    assert((sum_arr.max - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000025_infil_adj.osm"
    model.save(output_file_path, true)
  end

  def test_bldg31_quick_service_restaurant_pthp
    test_name = 'test_bldg31_quick_service_restaurant_pthp'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000031.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get
    args_hash = {}

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)
    assert(result.warnings.size == 1)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day = infil_on_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    off_day = infil_off_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    sum_arr = on_day.values + off_day.values
    assert((sum_arr.min - 1.0) < 0.001)
    assert((sum_arr.max - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000031_infil_adj.osm"
    model.save(output_file_path, true)
  end

  def test_bldg31_quick_service_restaurant_pthp_air_barrier
    test_name = 'test_bldg31_quick_service_restaurant_pthp_air_barrier'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000031.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get
    args_hash = {}
    args_hash['air_barrier'] = true

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)
    assert(result.warnings.size == 1)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day = infil_on_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    off_day = infil_off_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    sum_arr = on_day.values + off_day.values
    assert((sum_arr.min - 1.0) < 0.001)
    assert((sum_arr.max - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000031_infil_adj.osm"
    model.save(output_file_path, true)
  end

  def test_bldg43_warehouse_baseboardelec
    test_name = 'test_bldg43_warehouse_baseboardelec'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000043.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get
    args_hash = {}

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)
    assert(result.warnings.size == 2)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day = infil_on_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    off_day = infil_off_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    sum_arr = on_day.values + off_day.values
    assert((sum_arr.min - 1.0) < 0.001)
    assert((sum_arr.max - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000043_infil_adj.osm"
    model.save(output_file_path, true)
  end

  def test_bldg45_stripmall_windowac
    test_name = 'test_bldg45_stripmall_windowac'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000045.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get
    args_hash = {}

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day = infil_on_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    off_day = infil_off_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    sum_arr = on_day.values + off_day.values
    assert((sum_arr.min - 1.0) < 0.001)
    assert((sum_arr.max - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000045_infil_adj.osm"
    model.save(output_file_path, true)
  end

  def test_bldg53_smallhotel_pszac
    test_name = 'test_bldg53_smallhotel_pszac'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000053.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get
    args_hash = {}
    args_hash['airtightness_area'] = '6-sided'

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day = infil_on_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    off_day = infil_off_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    sum_arr = on_day.values + off_day.values
    assert((sum_arr.min - 1.0) < 0.001)
    assert((sum_arr.max - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000053_infil_adj.osm"
    model.save(output_file_path, true)
  end

  def test_bldg53_smallhotel_pszac_air_barrier
    test_name = 'test_bldg53_smallhotel_pszac_air_barrier'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000053.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get
    args_hash = {}
    args_hash['airtightness_area'] = '6-sided'
    args_hash['air_barrier'] = true

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day = infil_on_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    off_day = infil_off_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    sum_arr = on_day.values + off_day.values
    assert((sum_arr.min - 1.0) < 0.001)
    assert((sum_arr.max - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000053_infil_adj.osm"
    model.save(output_file_path, true)
  end

  def test_bldg82_hospitalvav
    test_name = 'test_bldg82_hospitalvav'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = "#{File.dirname(__FILE__)}/bldg0000082.osm"
    model = translator.loadModel(path)
    assert(!model.empty?)
    model = model.get
    args_hash = {}

    result = run_test(model, args_hash)

    # show the output
    show_output(result)

    # assert that it ran correctly
    assert_equal('Success', result.value.valueName)

    # check that the infiltration schedules sum to 1
    infil_on_schedule = model.getScheduleByName('Infiltration HVAC On Schedule').get
    infil_off_schedule = model.getScheduleByName('Infiltration HVAC Off Schedule').get
    on_day = infil_on_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    off_day = infil_off_schedule.to_ScheduleRuleset.get.defaultDaySchedule
    sum_arr = on_day.values + off_day.values
    assert((sum_arr.min - 1.0) < 0.001)
    assert((sum_arr.max - 1.0) < 0.001)

    # save the model to test output directory
    output_file_path = "#{File.dirname(__FILE__)}//output/bldg0000082_infil_adj.osm"
    model.save(output_file_path, true)
  end
end
