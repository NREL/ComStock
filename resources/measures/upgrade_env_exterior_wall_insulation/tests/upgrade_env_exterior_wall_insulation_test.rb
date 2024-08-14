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

class ExteriorWallInsulation_Test < Minitest::Test
  # all tests are a sub definition of this class, e.g.:
  # def test_new_kind_of_test
  #   # test content
  # end

  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # create an instance of the measure
    measure = ExteriorWallInsulation.new

    # make an empty model
    model = OpenStudio::Model::Model.new

    # Get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(0, arguments.size)
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
    test_sets << { model: 'DOAS_VRF_3A', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success', test_name: 'test_cz_3a', arg_hash: {} }
    test_sets << { model: 'Retail_7', weather: 'Retail_7', result: 'Success', test_name: 'test_cz_7',  arg_hash: {} }
    test_sets << { model: 'Retail_7', weather: 'Retail_7', result: 'NA', test_name: 'test_na_less_than_half_inch_insul_needed', arg_hash: {} }
    test_sets << { model: 'Retail_7', weather: 'Retail_7', result: 'NA', test_name: 'test_na_no_insul_needed', arg_hash: {} }
    test_sets << { model: 'Warehouse_5A', weather: 'Warehouse_5A', result: 'NA', test_name: 'test_na_metal_building', arg_hash: {} }

    return test_sets
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
      measure = ExteriorWallInsulation.new

      # load the model; only used here for populating arguments
      model = load_model(osm_path)

      # set arguments here; will vary by measure
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure::OSArgumentMap.new

      # set default arguments
      arguments.each do |arg|
        temp_arg_var = arg.clone
        argument_map[arg.name] = temp_arg_var # Add argument to map with default value
      end

      # override with values from arg_hash
      args_hash = set[:arg_hash]
      args_hash.each do |arg_name, arg_value|
        arg = arguments.find { |a| a.name == arg_name }
        raise "Argument #{arg_name} not found" if arg.nil?
        assert(arg.setValue(arg_value)) # Override with value from arg_hash
        argument_map[arg_name] = arg
      end

      if set[test_name:] == 'test_cz_3a'
        # Check that the starting R-value is less than the target
        old_r_val_ip = 0
        old_ext_surf_material = nil
        model.getSurfaces.each do |surface|
          next unless (surface.outsideBoundaryCondition == 'Outdoors') && (surface.surfaceType == 'Wall')
          surf_const = surface.construction.get.to_LayeredConstruction.get
          old_r_val_si = 1 / surface.thermalConductance.to_f
          old_r_val_ip = OpenStudio.convert(old_r_val_si, 'm^2*K/W', 'ft^2*h*R/Btu').get
          old_ext_surf_material = surf_const.getLayer(0)
          break
        end
        assert(old_r_val_ip < target_r_value_ip)

        # Apply the measure to the model and optionally run the model
        result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

        model = load_model(model_output_path(instance_test_name))
        model.getSurfaces.each do |surface|
          next unless (surface.outsideBoundaryCondition == 'Outdoors') && (surface.surfaceType == 'Wall')
          surf_const = surface.construction.get.to_LayeredConstruction.get
          new_r_val_si = 1.0 / surface.thermalConductance.to_f
          new_r_val_ip = OpenStudio.convert(new_r_val_si, 'm^2*K/W', 'ft^2*h*R/Btu').get
          new_ext_surf_material = surf_const.getLayer(0)
          insul = surf_const.insulation.get
          insul_thick_in = OpenStudio.convert(insul.thickness, 'm', 'in').get

          # Check that original R-value was below target threshold
          assert(old_r_val_ip < new_r_val_ip)

          # Check that exterior surface material doesn't change
          assert_equal(old_ext_surf_material.name.get.to_s, new_ext_surf_material.name.get.to_s)

          # Check that the new R-value matches the target
          tolerance = 5.0 * 0.5 # R-5/inch * max 1/2 inch off from rounding to nearest inch
          assert_in_delta(target_r_value_ip, new_r_val_ip, tolerance)

          # Check that the thickness of the added insulation is rounded to nearest inch
          assert_in_epsilon(3.0, insul_thick_in, 0.001)
          break
        end
      elsif set[test_name:] == 'test_cz_7'
        # Check that the starting R-value is less than the target
        old_r_val_ip = 0
        old_ext_surf_material = nil
        model.getSurfaces.each do |surface|
          next unless (surface.outsideBoundaryCondition == 'Outdoors') && (surface.surfaceType == 'Wall')
          surf_const = surface.construction.get.to_LayeredConstruction.get
          old_r_val_si = 1 / surface.thermalConductance.to_f
          old_r_val_ip = OpenStudio.convert(old_r_val_si, 'm^2*K/W', 'ft^2*h*R/Btu').get
          old_ext_surf_material = surf_const.getLayer(0)
          break
        end
        assert(old_r_val_ip < target_r_value_ip)

        # Apply the measure to the model and optionally run the model
        result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

        model = load_model(model_output_path(instance_test_name))
        model.getSurfaces.each do |surface|
          next unless (surface.outsideBoundaryCondition == 'Outdoors') && (surface.surfaceType == 'Wall')
          surf_const = surface.construction.get.to_LayeredConstruction.get
          new_r_val_si = 1.0 / surface.thermalConductance.to_f
          new_r_val_ip = OpenStudio.convert(new_r_val_si, 'm^2*K/W', 'ft^2*h*R/Btu').get
          new_ext_surf_material = surf_const.getLayer(0)
          insul = surf_const.insulation.get
          insul_thick_in = OpenStudio.convert(insul.thickness, 'm', 'in').get

          # Check that original R-value was below target threshold
          assert(old_r_val_ip < new_r_val_ip)

          # Check that exterior surface material doesn't change
          assert_equal(old_ext_surf_material.name.get.to_s, new_ext_surf_material.name.get.to_s)

          # Check that the new R-value matches the target
          tolerance = 5.0 * 0.5 # R-5/inch * max 1/2 inch off from rounding to nearest inch
          assert_in_delta(target_r_value_ip, new_r_val_ip, tolerance)

          # Check that the thickness of the added insulation is rounded to nearest inch
          assert_in_epsilon(1.0, insul_thick_in, 0.001)
          break
        end
      elsif set[test_name:] == 'test_na_less_than_half_inch_insul_needed'
        # Modify the initial model to represent an R-value almost high enough
        ins = model.getMasslessOpaqueMaterialByName('Typical Insulation R-15.06').get
        bef_r_si = ins.thermalResistance
        ins.setThermalResistance(ins.thermalResistance * 1.2)
        aft_r_si = ins.thermalResistance
        assert(aft_r_si > bef_r_si)

        # Apply the measure to the model and optionally run the model
        result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)
      elsif set[test_name:] == 'test_na_no_insul_needed'
        # Modify the initial model to represent an R-value already high enough
        ins = model.getMasslessOpaqueMaterialByName('Typical Insulation R-15.06').get
        bef_r_si = ins.thermalResistance
        ins.setThermalResistance(ins.thermalResistance * 2.0)
        aft_r_si = ins.thermalResistance
        assert(aft_r_si > bef_r_si)

        # Apply the measure to the model and optionally run the model
        result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)
      else
        # Test expectations
        target_r_value_ip = 21.0 # 7

        # Check that the starting R-value is less than the target
        old_r_val_ip = 0
        old_ext_surf_material = nil
        model.getSurfaces.each do |surface|
          next unless (surface.outsideBoundaryCondition == 'Outdoors') && (surface.surfaceType == 'Wall')
          surf_const = surface.construction.get.to_LayeredConstruction.get
          old_r_val_si = 1 / surface.thermalConductance.to_f
          old_r_val_ip = OpenStudio.convert(old_r_val_si, 'm^2*K/W', 'ft^2*h*R/Btu').get
          old_ext_surf_material = surf_const.getLayer(0)
          break
        end
        assert(old_r_val_ip < target_r_value_ip)

        # Apply the measure to the model and optionally run the model
        result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)
      end

      # check the measure result; result values will equal Success, Fail, or Not Applicable
      # also check the amount of warnings, info, and error messages
      # use if or case statements to change expected assertion depending on model characteristics
      assert(result.value.valueName == set[:result])

      # to check that something changed in the model, load the model and the check the objects match expected new value
      model = load_model(model_output_path(instance_test_name))

      # add additional tests here to check model outputs


    end
  end

end
