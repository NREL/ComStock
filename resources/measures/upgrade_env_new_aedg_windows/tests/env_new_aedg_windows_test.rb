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

class EnvStormWindowsTest < Minitest::Test
  # all tests are a sub definition of this class, e.g.:
  # def test_new_kind_of_test
  #  test content
  # end

  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # create an instance of the measure
    measure = EnvStormWindows.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(3, arguments.size)
    assert_equal('single_pane_threshold_ip', arguments[0].name)
    assert_equal('u_val_reduct_ip', arguments[1].name)
    assert_equal('shgc_reduct', arguments[2].name)
    assert_equal('vlt_reduct', arguments[3].name)
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

  # create an array of hashes with model name, weather, and expected result
  def models_to_test
    test_sets = []
    test_sets << { model: 'Warehouse_5A', weather: 'MI_DETROIT_725375_12', result: 'Success' }
    test_sets << { model: 'Retail_7', weather: 'MN_Cloquet_Carlton_Co_726558_16', result: 'Success' }
    test_sets << { model: 'Small_Office_2A', weather: 'TX_Port_Arthur_Jeffers_722410_16', result: 'Success' }
    return test_sets
  end

  def test_doe_models
    test_name = 'test_doe_models'
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
      measure = EnvStormWindows.new

      # load the model; only used here for populating arguments
      model = load_model(osm_path)
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure::OSArgumentMap.new

      ############### BEGIN CUSTOMIZE ##################
      old_u_val = nil
      old_shgc = nil
      old_vlt = nil
      model.getSubSurfaces.each do |sub_surface|
        if sub_surface.subSurfaceType.include?('Window')
          old_simple_glazing_obj = sub_surface.construction.get.to_Construction.get.layers[0].to_SimpleGlazing.get
          old_u_val = old_simple_glazing_obj.uFactor
          old_shgc = old_simple_glazing_obj.solarHeatGainCoefficient
          old_vlt = old_simple_glazing_obj.visibleTransmittance.get
        end
      end
      ################ END CUSTOMIZE ####################

      # set arguments here; will vary by measure
      # set u-value reduction argument
      single_pane_threshold_ip = arguments[0].clone
      assert(single_pane_threshold_ip.setValue(0.85))
      argument_map['single_pane_threshold_ip'] = single_pane_threshold_ip

      # set u-value reduction argument
      u_val_reduct_ip = arguments[1].clone
      assert(u_val_reduct_ip.setValue(0.69))
      argument_map['u_val_reduct_ip'] = u_val_reduct_ip

      # set SHGC reduction argument
      shgc_reduct = arguments[2].clone
      assert(shgc_reduct.setValue(0.57))
      argument_map['shgc_reduct'] = shgc_reduct

      # set VLT reduction argument
      vlt_reduct = arguments[3].clone
      assert(vlt_reduct.setValue(0.38))
      argument_map['vlt_reduct'] = vlt_reduct

      # apply the measure to the model and optionally run the model
      result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

      ############### BEGIN CUSTOMIZE ##################
      model = load_model(model_output_path(instance_test_name))
      model.getSubSurfaces.each do |sub_surface|
        if sub_surface.subSurfaceType.include?('Window')
          new_simple_glazing_obj = sub_surface.construction.get.to_Construction.get.layers[0].to_SimpleGlazing.get
          model_u_val = new_simple_glazing_obj.uFactor
          model_shgc = new_simple_glazing_obj.solarHeatGainCoefficient
          model_vlt = new_simple_glazing_obj.visibleTransmittance.get
          u_val_reduct_si = 0.69 * 5.678
          expected_u_val = old_u_val - u_val_reduct_si
          expected_shgc = old_shgc * (1 - 0.57)
          expected_vlt = old_vlt * (1 - 0.38)
          assert((expected_u_val - model_u_val).abs < 0.001)
          assert((expected_shgc - model_shgc).abs < 0.001)
          assert((expected_vlt - model_vlt).abs < 0.001)
        end
      end
      ################ END CUSTOMIZE ####################
    end
  end
end
