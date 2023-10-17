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

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'
require 'open3'

require_relative '../measure.rb'
require 'minitest/autorun'

class TimeseriesCSVExport_Test < Minitest::Test
  def is_openstudio_2?
    begin
      workflow = OpenStudio::WorkflowJSON.new
    rescue StandardError
      return false
    end
    return true
  end

  def model_in_path_default
    return "#{File.dirname(__FILE__)}/ExampleModel.osm"
  end

  def epw_path_default
    # make sure we have a weather data location
    epw = nil
    epw = OpenStudio::Path.new("#{File.dirname(__FILE__)}/USA_CO_Golden-NREL.724666_TMY3.epw")
    assert(File.exist?(epw.to_s))
    return epw.to_s
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    "#{File.dirname(__FILE__)}/output/#{test_name}/run"
  end

  def model_out_path(test_name)
    "#{run_dir(test_name)}/TestOutput.osm"
  end

  def workspace_path(test_name)
    if is_openstudio_2?
      return "#{run_dir(test_name)}/run/in.idf"
    else
      return "#{run_dir(test_name)}/ModelToIdf/in.idf"
    end
  end

  def sql_path(test_name)
    if is_openstudio_2?
      return "#{run_dir(test_name)}/run/eplusout.sql"
    else
      return "#{run_dir(test_name)}/ModelToIdf/EnergyPlusPreProcess-0/EnergyPlus-0/eplusout.sql"
    end
  end

  def report_path(test_name)
    "#{run_dir(test_name)}/run/enduse_timeseries.csv"
  end

  # method for running the test simulation using OpenStudio 1.x API
  def setup_test_1(test_name, epw_path)
    co = OpenStudio::Runmanager::ConfigOptions.new(true)
    co.findTools(false, true, false, true)

    if !File.exist?(sql_path(test_name))
      puts 'Running EnergyPlus'

      wf = OpenStudio::Runmanager::Workflow.new('modeltoidf->energypluspreprocess->energyplus')
      wf.add(co.getTools)
      job = wf.create(OpenStudio::Path.new(run_dir(test_name)), OpenStudio::Path.new(model_out_path(test_name)), OpenStudio::Path.new(epw_path))

      rm = OpenStudio::Runmanager::RunManager.new
      rm.enqueue(job, true)
      rm.waitForFinished
    end
  end

  # method for running the test simulation using OpenStudio 2.x API
  def setup_test_2(test_name, epw_path)
    if !File.exist?(sql_path(test_name))
      osw_path = File.join(run_dir(test_name), 'in.osw')
      osw_path = File.absolute_path(osw_path)

      workflow = OpenStudio::WorkflowJSON.new
      workflow.setSeedFile(File.absolute_path(model_out_path(test_name)))
      workflow.setWeatherFile(File.absolute_path(epw_path))
      workflow.saveAs(osw_path)

      cli_path = OpenStudio.getOpenStudioCLI
      cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""

      # blank out bundler and gem path modifications, will be re-setup by new call
      new_env = {}
      new_env['BUNDLER_ORIG_MANPATH'] = nil
      new_env['BUNDLER_ORIG_PATH'] = nil
      new_env['BUNDLER_VERSION'] = nil
      new_env['BUNDLE_BIN_PATH'] = nil
      new_env['RUBYLIB'] = nil
      new_env['RUBYOPT'] = nil
      new_env['GEM_PATH'] = nil
      new_env['GEM_HOME'] = nil
      new_env['BUNDLE_GEMFILE'] = nil
      new_env['BUNDLE_PATH'] = nil
      new_env['BUNDLE_WITHOUT'] = nil

      stdout_str, stderr_str, status = Open3.capture3(new_env, cmd)

      unless status.success?
        puts("Error running command: '#{cmd}'")
        puts("stdout: #{stdout_str}")
        puts("stderr: #{stderr_str}")
        cmd2 = "\"#{cli_path}\" gem_list"
        stdout_str_2, stderr_str_2, status_2 = Open3.capture3(new_env, cmd2)
        puts("Gems available to openstudio cli according to (openstudio gem_list): \n #{stdout_str_2}")
      end
    end

    return true
  end

  # create test files if they do not exist when the test first runs
  def setup_test(test_name, idf_output_requests, model_in_path = model_in_path_default, epw_path = epw_path_default)
    if !File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert(File.exist?(run_dir(test_name)))

    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end

    assert(File.exist?(model_in_path))

    if File.exist?(model_out_path(test_name))
      FileUtils.rm(model_out_path(test_name))
    end

    # convert output requests to OSM for testing, OS App and PAT will add these to the E+ Idf
    workspace = OpenStudio::Workspace.new('Draft'.to_StrictnessLevel, 'EnergyPlus'.to_IddFileType)
    workspace.addObjects(idf_output_requests)
    rt = OpenStudio::EnergyPlus::ReverseTranslator.new
    request_model = rt.translateWorkspace(workspace)

    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(model_in_path)
    assert(!model.empty?)
    model = model.get
    model.addObjects(request_model.objects)
    model.save(model_out_path(test_name), true)

    if ENV['OPENSTUDIO_TEST_NO_CACHE_SQLFILE']
      if File.exist?(sql_path(test_name))
        FileUtils.rm_f(sql_path(test_name))
      end
    end

    if is_openstudio_2?
      setup_test_2(test_name, epw_path)
    else
      setup_test_1(test_name, epw_path)
    end
  end

  # assert that no section errors were thrown
  def section_errors(runner)
    test_string = 'section failed and was skipped because'

    if is_openstudio_2?
      section_errors = []
      runner.result.stepWarnings.each do |warning|
        if warning.include?(test_string)
          section_errors << warning
        end
      end
      assert(section_errors.empty?)
    else
      section_errors = []
      runner.result.warnings.each do |warning|
        if warning.logMessage.include?(test_string)
          section_errors << warning
        end
      end
      assert(section_errors.empty?)
    end

    return section_errors
  end

  def test_sm_hotel

    test_name = 'sm_hotel'
    model_in_path = "#{File.dirname(__FILE__)}/1004_SmallHotel_a.osm"

    # create an instance of the measure
    measure = TimeseriesCSVExport.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # create hash of argument values
    args_hash = {
      'reporting_frequency' => 'Timestep',
      'inc_output_variables' => true
    }

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args_hash[arg.name]
        assert(temp_arg_var.setValue(args_hash[arg.name]))
      end
      argument_map[arg.name] = temp_arg_var
    end

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new), argument_map)
    assert(idf_output_requests.size > 0, 'Expected IDF output requests, but none were found')

    # mimic the process of running this measure in OS App or PAT
    epw_path = epw_path_default
    setup_test(test_name, idf_output_requests, model_in_path)

    assert(File.exist?(model_out_path(test_name)))
    assert(File.exist?(sql_path(test_name)), "Could not find sql file at #{sql_path(test_name)}")
    # assert(File.exist?(''))

    # set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(test_name)))
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path(test_name)))
    runner.setLastEpwFilePath('')
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # delete the output if it exists
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end
    assert(!File.exist?(report_path(test_name)))

    # temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(test_name))

      # run the measure
      start_time = Time.new
      measure.run(runner, argument_map)
      end_time = Time.new
      puts "*********Timing: measure elapsed time = #{end_time - start_time}"
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)

      # look for section_errors
      assert(section_errors(runner).empty?)
    ensure
      Dir.chdir(start_dir)
    end

    # make sure the report file exists
    assert(File.exist?(report_path(test_name)))
  end

  def test_restaurant

    test_name = 'restaurant'
    model_in_path = "#{File.dirname(__FILE__)}/FullServiceRestaurant.osm"

    # create an instance of the measure
    measure = TimeseriesCSVExport.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # create hash of argument values
    args_hash = {
      'reporting_frequency' => 'Timestep',
      'inc_output_variables' => true
    }

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args_hash[arg.name]
        assert(temp_arg_var.setValue(args_hash[arg.name]))
      end
      argument_map[arg.name] = temp_arg_var
    end

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new), argument_map)
    assert(idf_output_requests.size > 0, 'Expected IDF output requests, but none were found')

    # mimic the process of running this measure in OS App or PAT
    epw_path = epw_path_default
    setup_test(test_name, idf_output_requests, model_in_path)

    assert(File.exist?(model_out_path(test_name)))
    assert(File.exist?(sql_path(test_name)), "Could not find sql file at #{sql_path(test_name)}")
    # assert(File.exist?(''))

    # set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(test_name)))
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path(test_name)))
    runner.setLastEpwFilePath('')
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # delete the output if it exists
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end
    assert(!File.exist?(report_path(test_name)))

    # temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(test_name))

      # run the measure
      start_time = Time.new
      measure.run(runner, argument_map)
      end_time = Time.new
      puts "*********Timing: measure elapsed time = #{end_time - start_time}"
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)

      # look for section_errors
      assert(section_errors(runner).empty?)
    ensure
      Dir.chdir(start_dir)
    end

    # make sure the report file exists
    assert(File.exist?(report_path(test_name)))

    # make sure that the expected columns are in the file
    f = File.open(report_path(test_name), 'r').each_with_index do |line, i|
      if i == 0
        cols = line.split(',')
        # Electricity
        assert(cols.include?('total_site_electricity_kwh'))
        assert(cols.include?('electricity_heating_kwh'))
        assert(cols.include?('electricity_cooling_kwh'))
        assert(cols.include?('electricity_interior_lighting_kwh'))
        assert(cols.include?('electricity_interior_equipment_kwh'))
        assert(cols.include?('electricity_exterior_lighting_kwh'))
        assert(cols.include?('electricity_fans_kwh'))
        assert(cols.include?('electricity_pumps_kwh'))
        assert(cols.include?('electricity_refrigeration_kwh'))
        assert(cols.include?('electricity_water_systems_kwh'))
        assert(!cols.include?('electricity_exterior_equipment_kwh'))
        assert(!cols.include?('electricity_heat_rejection_kwh'))
        assert(!cols.include?('electricity_humidification_kwh'))
        assert(!cols.include?('electricity_heat_recovery_kwh'))
        assert(!cols.include?('electricity_generators_kwh'))
        # Natural Gas
        assert(cols.include?('total_site_gas_kbtu'))
        assert(cols.include?('gas_interior_equipment_kbtu'))
        assert(cols.include?('gas_water_systems_kbtu'))
        assert(!cols.include?('gas_heating_kbtu'))
        assert(!cols.include?('gas_exterior_equipment_kbtu'))
        # Fuel Oil No 2
        assert(cols.include?('total_site_fueloil_kbtu'))
        assert(cols.include?('fueloil_water_systems_kbtu'))
        assert(!cols.include?('fueloil_heating_kbtu'))
        # Propane
        assert(cols.include?('total_site_propane_kbtu'))
        assert(cols.include?('propane_water_systems_kbtu'))
        assert(!cols.include?('propane_heating_kbtu'))
        # District Heating
        assert(!cols.include?('total_site_districtheating_kbtu'))
        assert(!cols.include?('districtheating_water_systems_kbtu'))
        assert(!cols.include?('districtheating_heating_kbtu'))
        # District Cooling
        assert(!cols.include?('total_site_districtcooling_kbtu'))
        assert(!cols.include?('districtcooling_cooling_kbtu'))
        # Water
        assert(cols.include?('total_site_water_gal'))
        assert(!cols.include?('cooling_gal'))
        assert(cols.include?('water_systems_gal'))
        assert(!cols.include?('heat_rejection_gal'))
      end
    end
  end

  def test_retail

    test_name = 'retail'
    model_in_path = "#{File.dirname(__FILE__)}/Retail.osm"

    # create an instance of the measure
    measure = TimeseriesCSVExport.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get arguments
    arguments = measure.arguments
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new), argument_map)
    assert(idf_output_requests.size > 0, 'Expected IDF output requests, but none were found')

    # mimic the process of running this measure in OS App or PAT
    epw_path = epw_path_default
    setup_test(test_name, idf_output_requests, model_in_path)

    assert(File.exist?(model_out_path(test_name)))
    assert(File.exist?(sql_path(test_name)), "Could not find sql file at #{sql_path(test_name)}")
    # assert(File.exist?(''))

    # set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(test_name)))
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path(test_name)))
    runner.setLastEpwFilePath('')
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # delete the output if it exists
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end
    assert(!File.exist?(report_path(test_name)))

    # temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(test_name))

      # run the measure
      start_time = Time.new
      measure.run(runner, argument_map)
      end_time = Time.new
      puts "*********Timing: measure elapsed time = #{end_time - start_time}"
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)

      # look for section_errors
      assert(section_errors(runner).empty?)
    ensure
      Dir.chdir(start_dir)
    end

    # make sure the report file exists
    assert(File.exist?(report_path(test_name)))
  end
end
