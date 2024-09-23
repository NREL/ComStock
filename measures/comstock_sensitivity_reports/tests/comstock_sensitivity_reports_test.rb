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
require 'openstudio-standards'
require 'openstudio/ruleset/ShowRunnerOutput'
require 'minitest/autorun'
require_relative '../measure.rb'
require 'fileutils'
require_relative '../../../test/helpers/minitest_helper'

class ComStockSensitivityReportsTest < Minitest::Test
  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    return "#{File.dirname(__FILE__)}/output/#{test_name}"
  end

  def model_output_path(test_name)
    return "#{run_dir(test_name)}/#{test_name}.osm"
  end

  def workspace_path(test_name)
    return "#{run_dir(test_name)}/run/in.idf"
  end

  def sql_path(test_name)
    return "#{run_dir(test_name)}/run/eplusout.sql"
  end

  def report_path(test_name)
    return "#{run_dir(test_name)}/reports/eplustbl.html"
  end

  def run_test(test_name, osm_path, epw_path)
    # create run directory if it does not exist
    unless File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert(File.exist?(run_dir(test_name)))

    # change into run directory for tests
    start_dir = Dir.pwd
    Dir.chdir run_dir(test_name)

    # create an instance of the measure
    measure = ComStockSensitivityReports.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # Load the input model to set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(osm_path)
    assert(model.is_initialized)
    model = model.get
    runner.setLastOpenStudioModel(model)

    # get arguments
    arguments = measure.arguments()
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(runner, argument_map)

    # convert output requests to OSM for testing, OS App and PAT will add these to the E+ Idf
    workspace = OpenStudio::Workspace.new('Draft'.to_StrictnessLevel, 'EnergyPlus'.to_IddFileType)
    workspace.addObjects(idf_output_requests)
    rt = OpenStudio::EnergyPlus::ReverseTranslator.new
    request_model = rt.translateWorkspace(workspace)

    # load the test model and add output requests
    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(OpenStudio::Path.new(osm_path))
    assert(!model.empty?)
    model = model.get
    model.addObjects(request_model.objects)
    model.save(model_output_path(test_name), true)

    # set model weather file
    assert(File.exist?(epw_path))
    epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(epw_path))
    OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)
    assert(model.weatherFile.is_initialized)

    # run the simulation if necessary
    unless File.exist?(sql_path(test_name))
      puts "\nRUNNING ANNUAL RUN FOR #{test_name}..."

      std = Standard.build('90.1-2013')
      std.model_run_simulation_and_log_errors(model, run_dir(test_name))
    end
    assert(File.exist?(model_output_path(test_name)))
    assert(File.exist?(sql_path(test_name)))

    # set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_output_path(test_name)))
    runner.setLastEnergyPlusWorkspacePath(OpenStudio::Path.new(workspace_path(test_name)))
    runner.setLastEpwFilePath(epw_path)
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # delete the output if it exists
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end
    assert(!File.exist?(report_path(test_name)))

    # run the measure
    puts "\nRUNNING MEASURE RUN FOR #{test_name}..."
    measure.run(runner, argument_map)
    result = runner.result
    show_output(result)

    # log result to file for comparisons
    values = []
    result.stepValues.each do |value|
      values << value.string
    end
    File.write(run_dir(test_name)+"/output.txt", "[\n#{values.join(',').strip}\n]")

    assert_equal('Success', result.value.valueName)

    # change back directory
    Dir.chdir(start_dir)
    return true
  end

  def test_number_of_arguments_and_argument_names
    # this test ensures that the current test is matched to the measure inputs
    test_name = "test_number_of_arguments_and_argument_names"
    puts "\n######\nTEST:#{test_name}\n######\n"

    # create an instance of the measure
    measure = ComStockSensitivityReports.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments()
    assert_equal(0, arguments.size)
  end

  def test_bldg25
    test_name = 'test_bldg25_retail_resforcedair'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/bldg0000025.osm'
    epw_path = File.dirname(__FILE__) + '/USA_MI_Detroit.City.725375_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_bldg31
    test_name = 'test_bldg31_quick_service_restaurant_pthp'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/bldg0000031.osm'
    epw_path = File.dirname(__FILE__) + '/USA_OH_Toledo.Express.725360_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_bldg43
    test_name = 'test_bldg43_warehouse_baseboardelec'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/bldg0000043.osm'
    epw_path = File.dirname(__FILE__) + '/USA_NV_Nellis.Afb.723865_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_bldg45
    test_name = 'test_bldg45_stripmall_windowac'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/bldg0000045.osm'
    epw_path = File.dirname(__FILE__) + '/USA_TX_San.Marcos.Muni.722539_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_bldg53
    test_name = 'test_bldg53_smallhotel_pszac'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/bldg0000053.osm'
    epw_path = File.dirname(__FILE__) + '/USA_MI_Cherry.Capital.726387_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_bldg82
    test_name = 'test_bldg82_hospitalvav'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/bldg0000082.osm'
    epw_path = File.dirname(__FILE__) + '/USA_KY_Bowman.Fld.724235_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_bldg03
    test_name = 'test_bldg03_smalloffice_pszac'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/bldg0000003.osm'
    epw_path = File.dirname(__FILE__) + '/FortCollins2016.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

   def test_bldg04
    test_name = 'test_bldg04_retail_pszacnoheat'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/bldg0000004.osm'
    epw_path = File.dirname(__FILE__) + '/FortCollins2016.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_fuel_oil_boiler
    test_name = 'test_fuel_oil_boiler'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/bldg0000034.osm'
    epw_path = File.dirname(__FILE__) + '/USA_MD_Baltimore-Washington.Intl.AP.724060_TMY3.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_propane_boiler
    test_name = 'test_propane_boiler'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/bldg0000090.osm'
    epw_path = File.dirname(__FILE__) + '/USA_NV_Nellis.Afb.723865_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_vrf
    test_name = 'test_vrf'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/bldg0146294.osm'
    epw_path = File.dirname(__FILE__) + '/USA_MD_Baltimore-Washington.Intl.AP.724060_TMY3.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_multispeed_heat_pump
    test_name = 'test_multispeed_heat_pump'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/multispeed_hps.osm'
    epw_path = File.dirname(__FILE__) + '/USA_MI_Detroit.City.725375_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_heat_pump_boiler_1
    test_name = 'test_heat_pump_boiler_1'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/heat_pump_boiler_1.osm'
    epw_path = File.dirname(__FILE__) + '/USA_MN_Duluth.Intl.AP.727450_TMY.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_heat_pump_boiler_2
    test_name = 'test_heat_pump_boiler_2'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/heat_pump_boiler_2.osm'
    epw_path = File.dirname(__FILE__) + '/USA_KY_Bowman.Fld.724235_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_shw_hpwh
    test_name = 'test_shw_hpwh'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/hpwh002.osm'
    epw_path = File.dirname(__FILE__) + '/USA_NV_Nellis.Afb.723865_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_ghx_outputs
    test_name = 'test_ground_heat_exchanger_outputs'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/ground_heat_exchanger.osm'
    epw_path = File.dirname(__FILE__) + '/USA_MI_Detroit.City.725375_2012.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_hp_rtu_gas_backup
    test_name = 'test_hp_rtu_gas_backup'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/hp_rtu_gas_backup.osm'
    epw_path = File.dirname(__FILE__) + '/USA_AL_Mobile-Downtown.AP.722235_TMY3.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_vrf_cold_climate
    test_name = 'test_vrf_cold_climate'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/vrf_cold_climate.osm'
    epw_path = File.dirname(__FILE__) + '/USA_MN_Duluth.Intl.AP.727450_TMY.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_8172d17_0000008
    test_name = 'test_8172d17_0000008'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/8172d17_0000008.osm'
    epw_path = File.dirname(__FILE__) + '/USA_AL_Mobile-Downtown.AP.722235_TMY3.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end

  def test_base_0000008
    test_name = 'test_base_0000008'
    puts "\n######\nTEST:#{test_name}\n######\n"
    osm_path = File.dirname(__FILE__) + '/base_0000008.osm'
    epw_path = File.dirname(__FILE__) + '/USA_AL_Mobile-Downtown.AP.722235_TMY3.epw'
    assert(run_test(test_name, osm_path, epw_path))
  end
end
