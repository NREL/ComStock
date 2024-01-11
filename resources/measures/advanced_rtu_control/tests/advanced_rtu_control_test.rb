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

class AdvancedRTUControlTest < Minitest::Test

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
	puts "run dir expanded=" + "#{File.expand_path(File.join(File.dirname(__FILE__),'output', test_name.to_s))}"
    return File.join(File.dirname(__FILE__),"output","#{test_name}")
  end

  def model_input_path(osm_name)
    # return models_for_tests.select { |x| set[:model] == osm_name }
	puts (File.expand_path(File.dirname(__FILE__))) #expands path relative to current wd, passing abs path back 
    return File.expand_path(File.join(File.dirname(__FILE__), '../../../tests/models', osm_name))
  end

  def epw_input_path(epw_name)
    return File.join(File.dirname(__FILE__), '../../../tests/weather', epw_name)
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
  def apply_measure_and_run(test_name, measure, argument_map, osm_path, epw_path, run_model: false, model: nil)
    assert(File.exist?(osm_path))
    assert(File.exist?(epw_path))

    # create run directory if it does not exist
    if !File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert(File.exist?(run_dir(test_name)))



    # remove prior runs if they exist
    # if File.exist?(model_output_path(test_name))
      # FileUtils.rm(model_output_path(test_name))
    # end
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end

    # copy the osm and epw to the test directory
	#osm_path = File.expand_path(osm_path) 
	puts(osm_path) 
    new_osm_path = "#{run_dir(test_name)}/#{File.basename(osm_path)}"
	new_osm_path = File.expand_path(new_osm_path) 
	puts(new_osm_path) 
    FileUtils.cp(osm_path, new_osm_path)
    new_epw_path = File.expand_path("#{run_dir(test_name)}/#{File.basename(epw_path)}") 
    FileUtils.cp(epw_path, new_epw_path)
    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # load the test model
    if model.nil?
	  puts 'loading test model 1' 
      model = load_model(new_osm_path)
    end
	

    # set model weather file
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(new_epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
    assert(model.weatherFile.is_initialized)
	
    # run the simulation if necessary
    unless File.exist?(sql_path(test_name))
      puts "\nRUNNING SIZING RUN FOR #{test_name}..."

      std = Standard.build('90.1-2013')
      std.model_run_sizing_run(model, run_dir(test_name))
    end
    assert(File.exist?(File.join(run_dir(test_name), "in.osm"))) 
    assert(File.exist?(sql_path(test_name)))
  
    # change into run directory for tests
    start_dir = Dir.pwd
    Dir.chdir run_dir(test_name)
  

    # run the measure
    puts "\nAPPLYING MEASURE..."
    measure.run(model, runner, argument_map)
    result = runner.result
    result_success = result.value.valueName == 'Success'
	
	# change back directory
    Dir.chdir(start_dir)

    # Show the output
    show_output(result)

    # Save model
	puts "saving model to" + File.expand_path(model_output_path(test_name))
    model.save(File.expand_path(model_output_path(test_name)), true)

    if run_model && result_success
      puts "\nRUNNING MODEL..."

      std = Standard.build('90.1-2013')
      std.model_run_simulation_and_log_errors(model, run_dir(test_name))

      # Check that the model ran successfully
      assert(File.exist?(sql_path(test_name)))
    end

    return result
  end

  def dont_test_number_of_arguments_and_argument_names
    # This test ensures that the current test is matched to the measure inputs
    test_name = 'test_number_of_arguments_and_argument_names'
    puts "\n######\nTEST:#{test_name}\n######\n"

    # Create an instance of the measure
    measure = AdvancedRTUControl.new

    # Make an empty model
    model = OpenStudio::Model::Model.new

    # Get arguments and test that they are what we are expecting
    arguments = measure.arguments(model)
    assert_equal(0, arguments.size)
  end

  def test_r_value_cz_3a
    osm_name = '361_Retail_PSZ_Gas_5a.osm'
    epw_name = 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16.epw'



    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AdvancedRTUControl.new

    # Load the model; only used here for populating arguments
	puts "loading test model 2" 
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)
     #put base case assertions here 
    # create hash of argument values
    args_hash = { 'add_econo' => false, 'add_dcv' => false}
    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args_hash.key?(arg.name)
        assert(temp_arg_var.setValue(args_hash[arg.name]), "Could not set #{arg.name} to #{args_hash[arg.name]}")
      end
      argument_map[arg.name] = temp_arg_var
    end
	

    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)
    puts "loading test model 3" 
    #model = load_model(model_output_path(__method__))
    model = load_model(File.expand_path(model_output_path(__method__)))
	
#put in assertions here 
#then duplicate it for other models if needed 
  end

  def dont_test_r_value_cz_7
    osm_name = 'Retail_7.osm'
    epw_name = 'MN_Cloquet_Carlton_Co_726558_16.epw'

    # Test expectations
    target_r_value_ip = 21.0 # 7

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AdvancedRTUControl.new

    # Load the model; only used here for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

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
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)

    model = load_model(model_output_path(__method__))
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
  end

  def dont_test_na_less_than_half_inch_insul_needed
    osm_name = 'Retail_7.osm'
    epw_name = 'MN_Cloquet_Carlton_Co_726558_16.epw'

    # Test expectations
    target_r_value_ip = 21.0 # 7

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AdvancedRTUControl.new

    # Load the model for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    # Modify the initial model to represent an R-value almost high enough
    ins = model.getMasslessOpaqueMaterialByName('Typical Insulation R-15.06').get
    bef_r_si = ins.thermalResistance
    ins.setThermalResistance(ins.thermalResistance * 1.2)
    aft_r_si = ins.thermalResistance
    assert(aft_r_si > bef_r_si)

    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false, model: model)

    # Should be NA because insulation thickness required is less than 0.5 inches
    assert_equal('NA', result.value.valueName)
  end

  def dont_test_na_no_insul_needed
    osm_name = 'Retail_7.osm'
    epw_name = 'MN_Cloquet_Carlton_Co_726558_16.epw'

    # Test expectations
    target_r_value_ip = 21.0 # 7

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AdvancedRTUControl.new

    # Load the model for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

    # Modify the initial model to represent an R-value already high enough
    ins = model.getMasslessOpaqueMaterialByName('Typical Insulation R-15.06').get
    bef_r_si = ins.thermalResistance
    ins.setThermalResistance(ins.thermalResistance * 2.0)
    aft_r_si = ins.thermalResistance
    assert(aft_r_si > bef_r_si)

    # Apply the measure to the model and optionally run the model
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false, model: model)

    # Should be NA because insulation thickness required is less than 0.5 inches
    assert_equal('NA', result.value.valueName)
  end

  def dont_test_na_metal_building
    osm_name = 'Warehouse_5A.osm'
    epw_name = 'MI_DETROIT_725375_12.epw'

    # Test expectations
    target_r_value_ip = 21.0 # 7

    osm_path = model_input_path(osm_name)
    epw_path = epw_input_path(epw_name)

    # Create an instance of the measure
    measure = AdvancedRTUControl.new

    # Load the model for populating arguments
    model = load_model(osm_path)
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure::OSArgumentMap.new

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
    result = apply_measure_and_run(__method__, measure, argument_map, osm_path, epw_path, run_model: false)

    # Should be NA because this is a warehouse with metal building walls
    assert_equal('NA', result.value.valueName)
  end
end