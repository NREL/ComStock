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
require 'openstudio-standards'
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'
require 'minitest/autorun'
require_relative '../measure.rb'
require 'csv'

class HVACEconomizer_Test < Minitest::Test

  # def test_number_of_arguments_and_argument_names
  #   # this test ensures that the current test is matched to the measure inputs
  #   test_name = 'test_number_of_arguments_and_argument_names'
  #   puts "\n######\nTEST:#{test_name}\n######\n"

  #   # create an instance of the measure
  #   measure = HVACEconomizer.new

  #   # make an empty model
  #   model = OpenStudio::Model::Model.new

  #   # Get arguments and test that they are what we are expecting
  #   arguments = measure.arguments(model)
  #   assert_equal(0, arguments.size)
  # end

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

  def get_design_oa_flow_rates(model)
    hash_oa_design_rates = {}
    # get OA design rates prior to measure implementation
    model.getControllerOutdoorAirs.each do |ctrloa|

      # get related airloophvac
      name_ctrloa = ctrloa.name.to_s

      # get design OA flow rate
      min_oa_rate = nil
      if ctrloa.autosizedMinimumOutdoorAirFlowRate.is_initialized
        min_oa_rate = ctrloa.autosizedMinimumOutdoorAirFlowRate.get
      elsif ctrloa.minimumOutdoorAirFlowRate.is_initialized
        min_oa_rate = ctrloa.minimumOutdoorAirFlowRate.get
      else
        raise 'no design OA flow rate found'
      end
      if min_oa_rate == 0.0
        puts("### DEBUGGING: min_oa_rate is zero so skipping this outdoor air system for comparison.")
      else
        puts("### DEBUGGING: name_ctrloa = #{name_ctrloa} | min_oa_rate = #{min_oa_rate}")
        # add key (airloop name) and value (design OA rate)
        hash_oa_design_rates[name_ctrloa] = min_oa_rate.round(6)
      end

    end

    return hash_oa_design_rates
  end

  def economizer_available(model)
    economizer_availability = []
    model.getAirLoopHVACs.each do |air_loop_hvac|
      # get airLoopHVACOutdoorAirSystem
      oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem
      if oa_sys.is_initialized
        oa_sys = oa_sys.get
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.Model', "#{air_loop.name} is required to have an economizer, but it has no OA system.")
        next
      end
      # get controller:outdoorair
      oa_control = oa_sys.getControllerOutdoorAir
      # change/check settings: control type
      if oa_control.getEconomizerControlType != 'NoEconomizer'
        economizer_availability << true
      else
        economizer_availability << false
      end
    end
    return economizer_availability
  end

  def day_of_year_to_date(year, day_of_year)
    date = Date.new(year, 1, 1) + day_of_year - 1
    month = date.month
    day = date.day
    return month, day
  end

  def run_simulation_and_get_timeseries(model, year, max_doy, num_timesteps_in_hr, timeseriesnames, epw_path=nil, run_dir = "#{Dir.pwd}/output")

    # Make the directory if it doesn't exist
    unless Dir.exist?(run_dir)
      FileUtils.mkdir_p(run_dir)
    end

    # Load template
    template = 'ComStock 90.1-2019'
    std = Standard.build(template)

    # Initialize runperiod
    begin_month, begin_day = day_of_year_to_date(year, 1)
    end_month, end_day = day_of_year_to_date(year, max_doy)

    # Set runperiod
    model.getYearDescription.setCalendarYear(year)
    model.getRunPeriod.setBeginMonth(begin_month)
    model.getRunPeriod.setBeginDayOfMonth(begin_day)
    model.getRunPeriod.setEndMonth(end_month)
    model.getRunPeriod.setEndDayOfMonth(end_day)
    if num_timesteps_in_hr != 4
      model.getTimestep.setNumberOfTimestepsPerHour(num_timesteps_in_hr)
    end
    model.getSimulationControl.setDoZoneSizingCalculation(false)
    model.getSimulationControl.setDoSystemSizingCalculation(false)
    model.getSimulationControl.setDoPlantSizingCalculation(false)

    # Save model
    osm_name = 'in.osm'
    osw_name = 'in.osw'
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', "Starting simulation here: #{run_dir}.")
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Started simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
    osm_path = OpenStudio::Path.new("#{run_dir}/#{osm_name}")
    osw_path = OpenStudio::Path.new("#{run_dir}/#{osw_name}")
    model.save(osm_path, true)

    # Find the weather file
    if epw_path==nil
      epw_path = std.model_get_full_weather_file_path(model)
      if epw_path.empty?
        return false
      end
      epw_path = epw_path.get
      # puts epw_path
    end

    # Close current sql file
    model.resetSqlFile
    sql_path = nil

    # Initialize OSW
    begin
      workflow = OpenStudio::WorkflowJSON.new
    rescue NameError
      raise 'Cannot run simulation with OSW approach'
    end

    # Copy the weather file to this directory
    epw_name = 'in.epw'
    begin
      FileUtils.copy(epw_path.to_s, "#{run_dir}/#{epw_name}")
    rescue StandardError
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Due to limitations on Windows file path lengths, this measure won't work unless your project is located in a directory whose filepath is less than 90 characters long, including slashes.")
      return false
    end

    # Set OSW
    workflow.setSeedFile(osm_name)
    workflow.setWeatherFile(epw_name)
    workflow.saveAs(File.absolute_path(osw_path.to_s))

    # Run simulation
    cli_path = OpenStudio.getOpenStudioCLI
    cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""
    puts cmd
    OpenstudioStandards.run_command(cmd)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
    sql_path = OpenStudio::Path.new("#{run_dir}/run/eplusout.sql")

    # Get sql
    sqlFile = OpenStudio::SqlFile.new(sql_path)

    # Check available options
    availableEnvPeriods = sqlFile.availableEnvPeriods.to_a
    availableTimeSeries = sqlFile.availableTimeSeries.to_a
    availableReportingFrequencies = []
    availableEnvPeriods.each do |envperiod|
      sqlFile.availableReportingFrequencies(envperiod).to_a.each do |repfreq|
        availableReportingFrequencies << repfreq
      end
    end

    # Hard-code: run period set to 'RUN PERIOD 1'
    envperiod = nil
    if availableEnvPeriods.size == 1
      envperiod = 'RUN PERIOD 1'
    else
      raise "options for availableEnvPeriods are not just one: #{availableEnvPeriods}"
    end

    # Hard-code: reporting frequency to zone timestep
    reportingfrequency = 'Zone Timestep' #'Zone Timestep'
    unless availableReportingFrequencies.include?(reportingfrequency)
      # puts("### Debugging: Hourly reporting frequency is not available. Use Zone Timestep.")
      reportingfrequency = 'Zone Timestep'
      unless availableReportingFrequencies.include?(reportingfrequency)
        raise "reportingfrequency of #{reportingfrequency} not included in available options: #{availableReportingFrequencies}"
      end
    end    

    # Check if timeseries name is available in sql
    timeseriesnames.each do |timeseriesname|
      unless availableEnvPeriods.include?(envperiod) 
        raise "envperiod of #{envperiod} not included in available options: #{availableEnvPeriods}"
      end
      # puts("### DEBUGGING: availableTimeSeries = #{availableTimeSeries}")
      unless availableTimeSeries.include?(timeseriesname) 
        raise "timeseriesname of #{timeseriesname} not included in available options: #{availableTimeSeries}"
      end
    end

    # Extract timeseries data
    timeseries_results_combined = {}
    
    timeseriesnames.each do |timeseriesname|
      availableKeyValues = sqlFile.availableKeyValues(envperiod,reportingfrequency,timeseriesname).to_a

      # puts("### ------------------------------------------------")
      # puts("### DEBUGGING: timeseriesname = #{timeseriesname}")
      # puts("### DEBUGGING: availableKeyValues = #{availableKeyValues}")

      availableKeyValues.each do |key_value|
        unless timeseries_results_combined.key?(key_value)
          timeseries_results_combined[key_value] = {}
        end
        timeseries_result = sqlFile.timeSeries(envperiod,reportingfrequency,timeseriesname,key_value).get     
        vals = []
        elec_vals = timeseries_result.values
        for i in 0..(elec_vals.size - 1)
          vals << elec_vals[i].round(4)
        end
        # raise if vals is empty
        if vals.empty?
          raise 'load profile for the sample run returned empty'
        end
        timeseries_results_combined[key_value][timeseriesname] = vals
      end
    end
    
    return timeseries_results_combined
  end

  def models_to_test_design_oa_rates
    test_sets = []
    # test_sets << { model: 'PVAV_gas_heat_electric_reheat_4A', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'PSZ-AC_with_gas_coil_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    test_sets << { model: '361_Warehouse_PVAV_2a', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'LargeOffice_VAV_chiller_boiler', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'LargeOffice_VAV_district_chw_hw', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'Outpatient_VAV_chiller_PFP_boxes', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'Retail_PVAV_gas_ht_elec_rht', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'VAV_chiller_boiler_4A', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    # test_sets << { model: 'VAV_with_reheat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
    return test_sets
  end

  # def test_design_oa_rates
  #   # Define test name
  #   test_name = 'test_design_oa_rates'
  #   puts "\n######\nTEST:#{test_name}\n######\n"

  #   # loop through each model from models_to_test_design_oa_rates and conduct test
  #   models_to_test_design_oa_rates.each do |set|
  #     instance_test_name = set[:model]
  #     puts "instance test name: #{instance_test_name}"
  #     osm_path = models_for_tests.select { |x| set[:model] == File.basename(x, '.osm') }
  #     epw_path = epws_for_tests.select { |x| set[:weather] == File.basename(x, '.epw') }
  #     assert(!osm_path.empty?)
  #     assert(!epw_path.empty?)
  #     osm_path = osm_path[0]
  #     epw_path = epw_path[0]

  #     # Initialize hash
  #     oa_design_rates_before = {}
  #     oa_design_rates_after = {}

  #     # Create an instance of the measure
  #     measure = HVACEconomizer.new

  #     # Load the model; only used here for populating arguments
  #     model = load_model(osm_path)
  #     arguments = measure.arguments(model)
  #     argument_map = OpenStudio::Measure::OSArgumentMap.new

  #     # Set weather
  #     epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(epw_path))
  #     OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)

  #     # Hardsize model
  #     puts("### DEBUGGING: first hardsize")
  #     standard = Standard.build('ComStock DOE Ref Pre-1980')
  #     if standard.model_run_sizing_run(model, "#{File.dirname(__FILE__)}/output/#{instance_test_name}/SR1") == false
  #       puts("Sizing run for Hardsize model failed, cannot hard-size model.")
  #       return false
  #     end
  #     model.applySizingValues

  #     # Check economizer availability and see if original model does not include economizer
  #     economizer_availability_before = economizer_available(model)
  #     puts("### DEBUGGING: economizer available before measure = #{economizer_availability_before}")
  #     assert(economizer_availability_before.include?(false))

  #     # Get OA rates before applying measure
  #     oa_design_rates_before = get_design_oa_flow_rates(model)

  #     # Apply the measure to the model and optionally run the model
  #     result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)
  #     model = load_model(model_output_path(instance_test_name))
  #     puts("### DEBUGGING: result = #{result}")

  #     # Hardsize model
  #     puts("### DEBUGGING: second hardsize")
  #     standard = Standard.build('ComStock DOE Ref Pre-1980')
  #     if standard.model_run_sizing_run(model, "#{File.dirname(__FILE__)}/output/#{instance_test_name}/SR2") == false
  #       puts("Sizing run for Hardsize model failed, cannot hard-size model.")
  #       return false
  #     end
  #     model.applySizingValues

  #     # Check economizer availability and see if updated model includes economizer
  #     economizer_availability_after = economizer_available(model)
  #     puts("### DEBUGGING: economizer available after measure = #{economizer_availability_after}")
  #     assert(economizer_availability_after.include?(true))

  #     # Get OA rates after applying measure
  #     oa_design_rates_after = get_design_oa_flow_rates(model)
  #     puts("### DEBUGGING: oa_design_rates_before = #{oa_design_rates_before}")
  #     puts("### DEBUGGING: oa_design_rates_after = #{oa_design_rates_after}")

  #     # Check if OA rates are the same before and after the measure implementation
  #     assert(oa_design_rates_before == oa_design_rates_after)
  #   end
  # end

  def test_requested_oa_rates
    # Define test name
    test_name = 'test_requested_oa_rates'
    puts "\n######\nTEST:#{test_name}\n######\n"

    number_of_days_to_test = 365
    number_of_timesteps_in_an_hr_test = 1
    csv_file_path = run_dir(test_name) + "_after" + '/output_timeseries.csv'

    # loop through each model from models_to_test_design_oa_rates and conduct test
    models_to_test_design_oa_rates.each do |set|
      instance_test_name = set[:model]
      puts "instance test name: #{instance_test_name}"
      osm_path = models_for_tests.select { |x| set[:model] == File.basename(x, '.osm') }
      epw_path = epws_for_tests.select { |x| set[:weather] == File.basename(x, '.epw') }
      assert(!osm_path.empty?)
      assert(!epw_path.empty?)
      osm_path = osm_path[0]
      epw_path = epw_path[0]

      # Initialize variables
      oa_design_rates_before = {}
      oa_design_rates_after = {}
      timeseries_results_combined = {}
      test_pass = true

      # Create an instance of the measure
      measure = HVACEconomizer.new

      # Load the model; only used here for populating arguments
      model = load_model(osm_path)
      arguments = measure.arguments(model)
      argument_map = OpenStudio::Measure::OSArgumentMap.new

      # Set weather
      epw_file = OpenStudio::EpwFile.new(OpenStudio::Path.new(epw_path))
      OpenStudio::Model::WeatherFile.setWeatherFile(model, epw_file)

      # Define output vars for simulation before measure implementation
      timeseriesnames = [
        'Air System Outdoor Air Mechanical Ventilation Requested Mass Flow Rate', 
      ]

      # Add output vars for simulation before measure implementation
      timeseriesnames.each do |out_var_name|
        ov = OpenStudio::Model::OutputVariable.new('ov', model)
        ov.setKeyValue('*')
        ov.setReportingFrequency('timestep')
        ov.setVariableName(out_var_name)
      end

      # Run simulation prior to measure application
      puts("### DEBUGGING: first simulation prior to measure application")      
      timeseries_results_combined_before = run_simulation_and_get_timeseries(model, 2018, number_of_days_to_test, number_of_timesteps_in_an_hr_test, timeseriesnames, epw_path=epw_path, run_dir = run_dir(test_name)+"_before")
      timeseries_results_combined['before'] = timeseries_results_combined_before

      # puts("### ##########################################################")
      # puts("### DEBUGGING: timeseries_results_combine = #{timeseries_results_combined}")
      # puts("### ##########################################################")

      # Apply the measure to the model
      result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)
      model = load_model(model_output_path(instance_test_name))
      # puts("### DEBUGGING: result = #{result}")

      # Get EMS actuator created by the measure
      li_ems_act_oa_flow = []
      model.getEnergyManagementSystemActuators.each do |ems_actuator|
        li_ems_act_oa_flow << ems_actuator
      end

      # Create OutputEnergyManagementSystem object (a 'unique' object) and configure to allow EMS reporting
      output_EMS = model.getOutputEnergyManagementSystem
      output_EMS.setInternalVariableAvailabilityDictionaryReporting('Verbose')
      output_EMS.setEMSRuntimeLanguageDebugOutputLevel('Verbose')
      output_EMS.setActuatorAvailabilityDictionaryReporting('Verbose')

      # Create output var for EMS variables
      ems_output_variable_list = []
      li_ems_act_oa_flow.each do |act|
        name = act.name
        ems_act_oa_flow = OpenStudio::Model::EnergyManagementSystemOutputVariable.new(model, act)
        ems_act_oa_flow.setUpdateFrequency('Timestep')
        ems_act_oa_flow.setName("#{name}_ems_outvar")
        ems_output_variable_list << ems_act_oa_flow.name.to_s
      end

      # Add EMS output variables to regular output variables
      ems_output_variable_list.each do |variable|
        output = OpenStudio::Model::OutputVariable.new(variable,model)
        output.setKeyValue("*")
        output.setReportingFrequency('Timestep')
        timeseriesnames << variable
      end

      # Add output vars for simulation after measure implementation
      timeseriesnames.each do |out_var_name|
        ov = OpenStudio::Model::OutputVariable.new('ov', model)
        ov.setKeyValue('*')
        ov.setReportingFrequency('timestep')
        ov.setVariableName(out_var_name)
      end

      # Run simulation after measure application
      puts("### DEBUGGING: second simulation after measure application")
      timeseries_results_combined_after = run_simulation_and_get_timeseries(model, 2018, number_of_days_to_test, number_of_timesteps_in_an_hr_test, timeseriesnames, epw_path=epw_path, run_dir = run_dir(test_name)+"_after")
      timeseries_results_combined['after'] = timeseries_results_combined_after

      # puts("### -------------------------------------------------------------")
      # puts("### DEBUGGING: timeseries_results_combined = #{timeseries_results_combined}")
      # puts("### -------------------------------------------------------------")

      # Get unique identifier names
      unique_identifiers = timeseries_results_combined.values.flat_map(&:keys).uniq

      # Define interested output var name
      output_var_name = 'Air System Outdoor Air Mechanical Ventilation Requested Mass Flow Rate'

      # Compare output var results before and after the measure
      unique_identifiers.each do |identifier|

        # skip if the output var key is EMS
        next if identifier == "EMS"

        # get reference string for string match
        identifier_lowercase = identifier.gsub(' ', '_').downcase

        # get output var timeseries
        timeseries_outputvar_before = []
        timeseries_outputvar_after = []
        unless identifier == "EMS"
          timeseries_outputvar_before = timeseries_results_combined['before'][identifier][output_var_name]
          timeseries_outputvar_after = timeseries_results_combined['after'][identifier][output_var_name]
        end

        # get reference (ems actuator) timeseries
        timeseries_reference = []
        timeseries_results_combined['after']['EMS'].keys.each do |output_var_ems|
          output_var_ems_lowercase = output_var_ems.downcase
          if output_var_ems_lowercase.include?(identifier_lowercase)
            timeseries_reference = timeseries_results_combined['after']['EMS'][output_var_ems]
          end
        end

        puts("### ----------------------------------------------------------------------------")
        puts("### DEBUGGING: identifier = #{identifier}")
        puts("### DEBUGGING: length timeseries_outputvar_before = #{timeseries_outputvar_before.size}")
        puts("### DEBUGGING: length timeseries_outputvar_after = #{timeseries_outputvar_after.size}")
        puts("### DEBUGGING: length timeseries_reference = #{timeseries_reference.size}")

        # Get indices of interest (non-zero values in actuator)
        indices_of_interest = timeseries_reference.each_index.select { |i| timeseries_reference[i] != 0 }
        puts("### DEBUGGING: number of times actuator override = #{indices_of_interest.size}")

        # Get filtered output vars
        timeseries_outputvar_before = timeseries_outputvar_before.values_at(*indices_of_interest)
        timeseries_outputvar_after = timeseries_outputvar_after.values_at(*indices_of_interest)
        puts("### DEBUGGING: length timeseries_outputvar_before (filtered) = #{timeseries_outputvar_before.size}")
        puts("### DEBUGGING: length timeseries_outputvar_after (filtered) = #{timeseries_outputvar_after.size}")
        puts("### DEBUGGING: unique values of filtered timeseries values = #{(timeseries_outputvar_before + timeseries_outputvar_after).uniq}")

        assert(timeseries_outputvar_before == timeseries_outputvar_after)

      end



      # # filter data when EMS actuator is setting OA flow to min value
      # filtered_indices = transposed_array[0].each_index.select { |i| transposed_array[0][i].include?("act_oa_flow_") }
      # filtered_rows = transposed_array.select { |row| filtered_indices.all? { |i| row[i] != 0.0 } }

      # puts("### --------------------------------------------------------------------")
      # puts("### DEBUGGING: filtered_rows:")
      # filtered_rows.each { |row| p row }
      # puts("### --------------------------------------------------------------------")

      # # Check if each row (except the header) has the same value
      # same_value = filtered_rows[1..-1].all? { |row| row.uniq.length == 1 }
      # unless same_value
      #   test_pass = false
      # end

      # # Check if OA rates are the same before and after the measure implementation
      # assert(test_pass == true)
    end
  end

  # # create an array of hashes with model name, weather, and expected result
  # def models_to_test
  #   test_sets = []
  #   test_sets << { model: 'PVAV_gas_heat_electric_reheat_4A', weather: 'VA_MANASSAS_724036_12', result: 'Success' }
  #   test_sets << { model: 'Baseboard_electric_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'NA' }
  #   test_sets << { model: 'PSZ-AC_with_gas_coil_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
  #   test_sets << { model: 'Residential_AC_with_electric_baseboard_heat_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'NA' }
  #   test_sets << { model: 'Residential_heat_pump_3B', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'NA' }
  #   test_sets << { model: 'DOAS_wshp_gshp_3A', weather: 'GA_ROBINS_AFB_722175_12', result: 'NA' }
  #   test_sets << { model: 'Outpatient_VAV_chiller_PFP_boxes', weather: 'CA_LOS-ANGELES-DOWNTOWN-USC_722874S_16', result: 'Success' }
  #   return test_sets
  # end

  # def test_models
  #   test_name = 'test_models'
  #   puts "\n######\nTEST:#{test_name}\n######\n"

  #   models_to_test.each do |set|
  #     instance_test_name = set[:model]
  #     puts "instance test name: #{instance_test_name}"
  #     osm_path = models_for_tests.select { |x| set[:model] == File.basename(x, '.osm') }
  #     epw_path = epws_for_tests.select { |x| set[:weather] == File.basename(x, '.epw') }
  #     assert(!osm_path.empty?)
  #     assert(!epw_path.empty?)
  #     osm_path = osm_path[0]
  #     epw_path = epw_path[0]

  #     # create an instance of the measure
  #     measure = HVACEconomizer.new

  #     # load the model; only used here for populating arguments
  #     model = load_model(osm_path)

  #     # set arguments here; will vary by measure
  #     arguments = measure.arguments(model)
  #     argument_map = OpenStudio::Measure::OSArgumentMap.new

  #     # apply the measure to the model and optionally run the model
  #     result = apply_measure_and_run(instance_test_name, measure, argument_map, osm_path, epw_path, run_model: false)

  #     # check the measure result; result values will equal Success, Fail, or Not Applicable
  #     # also check the amount of warnings, info, and error messages
  #     # use if or case statements to change expected assertion depending on model characteristics
  #     assert(result.value.valueName == set[:result])
  #   end
  # end
end
