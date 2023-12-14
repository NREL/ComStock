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
require 'date'
require 'openstudio-standards'

# start the measure
class DispatchScheduleGeneration < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Dispatch Schedule Generation'
  end

  # human readable description
  def description
    return 'This measure reads in epw weather file, create outdoor air bins, pick sample days in bins and run simulation for samples to create dispactch schedule based on daily peaks'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Replace this text with an explanation for the energy modeler specifically.  It should explain how the measure is modeled, including any requirements about how the baseline model must be set up, major assumptions, citations of references to applicable modeling resources, etc.  The energy modeler should be able to read this description and understand what changes the measure is making to the model and why these changes are being made.  Because the Modeler Description is written for an expert audience, using common abbreviations for brevity is good practice.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    input_path = OpenStudio::Ruleset::OSArgument::makeStringArgument("input_path",true)
    input_path.setDisplayName("Path to weather file (epw)")
    input_path.setDefaultValue("C:/Users/jxiong/Documents/GitHub/ComStock/resources/measures/dispatch_schedule_generation/tests/in.epw")
    args << input_path

    peak_len = OpenStudio::Measure::OSArgument.makeIntegerArgument('peak_len', true)
    peak_len.setDisplayName("Length of dispatch window (hour)")
    peak_len.setDefaultValue(4)
    args << peak_len

    rebound_len = OpenStudio::Measure::OSArgument.makeIntegerArgument('rebound_len', true)
    rebound_len.setDisplayName("Length of rebound period after dispatch window (hour)")
    rebound_len.setDefaultValue(2)
    args << rebound_len

    output_path = OpenStudio::Ruleset::OSArgument::makeStringArgument("output_path",true)
    output_path.setDisplayName("Path to output data CSV. INCLUDE .CSV EXTENSION")
    output_path.setDefaultValue("../outputs/output.csv")
    args << output_path

    sample_num_timesteps_in_hr = OpenStudio::Measure::OSArgument.makeIntegerArgument('sample_num_timesteps_in_hr', true)
    sample_num_timesteps_in_hr.setDisplayName("Number/Count of timesteps in an hour for sample simulations")
    sample_num_timesteps_in_hr.setDefaultValue(4)
    args << sample_num_timesteps_in_hr

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    weather_file = runner.getStringArgumentValue("input_path",user_arguments)
    peak_len = runner.getIntegerArgumentValue("peak_len",user_arguments)
    rebound_len = runner.getIntegerArgumentValue("rebound_len",user_arguments)
    output_path = runner.getStringArgumentValue("output_path",user_arguments)
    sample_num_timesteps_in_hr = runner.getIntegerArgumentValue("sample_num_timesteps_in_hr",user_arguments)

    ### Functions
    ### convert day of year to month-day date ######################### NEED TO ADD FUNCTIONALITY OF DEALING WITH LEAP YEAR
    def day_of_year_to_date(year, day_of_year)
      date = Date.new(year, 1, 1) + day_of_year - 1
      month = date.month
      day = date.day
      return month, day
    end

    ### run simulation on selected day of year
    def read_epw(weather_file)#,peak_threshold)
      epw_file = OpenStudio::EpwFile.new(weather_file)
      # weather_lat = epw_file.latitude
      # weather_lon = epw_file.longitude
      # weather_time = epw_file.timeZone
      # weather_elev = epw_file.elevation
      # weather_startDate = epw_file.startDate
      weather_startDateActualYear = epw_file.startDateActualYear
      year = weather_startDateActualYear.to_i
      weather_timeStep = epw_file.timeStep
      weather_daylightSavingEndDate = epw_file.daylightSavingEndDate
      weather_daylightSavingStartDate = epw_file.daylightSavingStartDate
      # puts("weather name: #{epw_file.city}_#{epw_file.stateProvinceRegion}_#{epw_file.country}")
      # puts "latitude, longtitude, timezone, elevation"
      # puts weather_lat
      # puts weather_lon
      # puts weather_time
      # puts weather_elev
      # puts "start date, start year, start day of week"
      # puts weather_startDate
      # puts year
      # puts weather_startDayOfWeek
      # puts "timestep, daylightsaving end, start"
      # puts weather_timeStep
      # puts weather_daylightSavingEndDate
      # puts weather_daylightSavingStartDate

      field = 'DryBulbTemperature'
      weather_ts = epw_file.getTimeSeries(field)

      if weather_ts.is_initialized
        weather_ts = weather_ts.get
      else
        puts "FAIL, could not retrieve field: #{field} from #{weather_file_path}"
      end
      # puts weather_ts
      # Put dateTimes into array
      times = []
      os_times = weather_ts.dateTimes
      for i in 0..(os_times.size - 1)
        times << os_times[i].toString()
      end
      # Put values into array
      vals = []
      os_vals = weather_ts.values
      for i in 0..(os_vals.size - 1)
        vals << os_vals[i]
      end
      # # Loop through the time/value pairs
      # times.zip(vals).each_with_index do |t, v|
      #   puts("#{t} = #{v}")
      # end
      # return weather_ts
      return year, vals
    end

    ### create bins based on temperature profile and select sample days in bins
    def create_binsamples(oat)
      # daystats = []
      # tempbins = {'ext-hot' => [], 'hot' => [], 'mild' => [], 'cool-mild' => [], 'cool' => [], 'cold' => []}
      # hourbins = {'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => []}
      combbins = {
        'ext-hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'cool-mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'cool' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'cold' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] }
      }
      selectdays = {
        'ext-hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'cool-mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'cool' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'cold' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] }
      }

      ### NEED TO ADJUST FOR LEAP YEAR 
      (0..364).each do |d|
        # daystats[d] = {
        #   'day' => d + 1,
        #   'OATmax' => Xday[Xday.index.day_of_year == d + 1]['OAT'].max,
        #   'OATmaxhour' => Xday[Xday.index.day_of_year == d + 1]['OAT'].index(Xday[Xday.index.day_of_year == d + 1]['OAT'].max),
        #   'OATmin' => Xday[Xday.index.day_of_year == d + 1]['OAT'].min,
        #   'OATmean' => Xday[Xday.index.day_of_year == d + 1]['OAT'].mean,
        #   'OATstd' => Xday[Xday.index.day_of_year == d + 1]['OAT'].std,
        #   'OATmed' => Xday[Xday.index.day_of_year == d + 1]['OAT'].median,
        # }
        oatmax = oat[24*d..24*(d+1)-1].max
        oatmaxind = oat[24*d..24*(d+1)-1].index(oat[24*d..24*(d+1)-1].max)

        if oatmax >= 32.0
          # tempbins['ext-hot'] << d+1
          if (oatmaxind >= 9.0) && (oatmaxind <= 11.0)
            combbins['ext-hot']['morning'] << d+1
          elsif (oatmaxind > 11.0) && (oatmaxind <= 14.0)
            combbins['ext-hot']['noon'] << d+1
          elsif (oatmaxind > 14.0) && (oatmaxind <= 15.0)
            combbins['ext-hot']['afternoon'] << d+1
          elsif (oatmaxind > 15.0) && (oatmaxind <= 17.0)
            combbins['ext-hot']['late-afternoon'] << d+1
          elsif (oatmaxind > 17.0) && (oatmaxind <= 20.0)
            combbins['ext-hot']['evening'] << d+1
          else
            combbins['ext-hot']['other'] << d+1
          end
        elsif oatmax >= 30.0
          # tempbins['hot'] << d+1
          if (oatmaxind >= 9.0) && (oatmaxind <= 11.0)
            combbins['hot']['morning'] << d+1
          elsif (oatmaxind > 11.0) && (oatmaxind <= 14.0)
            combbins['hot']['noon'] << d+1
          elsif (oatmaxind > 14.0) && (oatmaxind <= 15.0)
            combbins['hot']['afternoon'] << d+1
          elsif (oatmaxind > 15.0) && (oatmaxind <= 17.0)
            combbins['hot']['late-afternoon'] << d+1
          elsif (oatmaxind > 17.0) && (oatmaxind <= 20.0)
            combbins['hot']['evening'] << d+1
          else
            combbins['hot']['other'] << d+1
          end
        elsif oatmax >= 26.0
          # tempbins['mild'] << d+1
          if (oatmaxind >= 9.0) && (oatmaxind <= 11.0)
            combbins['mild']['morning'] << d+1
          elsif (oatmaxind > 11.0) && (oatmaxind <= 14.0)
            combbins['mild']['noon'] << d+1
          elsif (oatmaxind > 14.0) && (oatmaxind <= 15.0)
            combbins['mild']['afternoon'] << d+1
          elsif (oatmaxind > 15.0) && (oatmaxind <= 17.0)
            combbins['mild']['late-afternoon'] << d+1
          elsif (oatmaxind > 17.0) && (oatmaxind <= 20.0)
            combbins['mild']['evening'] << d+1
          else
            combbins['mild']['other'] << d+1
          end
        elsif oatmax >= 20.0
          # tempbins['cool-mild'] << d+1
          if (oatmaxind >= 9.0) && (oatmaxind <= 11.0)
            combbins['cool-mild']['morning'] << d+1
          elsif (oatmaxind > 11.0) && (oatmaxind <= 14.0)
            combbins['cool-mild']['noon'] << d+1
          elsif (oatmaxind > 14.0) && (oatmaxind <= 15.0)
            combbins['cool-mild']['afternoon'] << d+1
          elsif (oatmaxind > 15.0) && (oatmaxind <= 17.0)
            combbins['cool-mild']['late-afternoon'] << d+1
          elsif (oatmaxind > 17.0) && (oatmaxind <= 20.0)
            combbins['cool-mild']['evening'] << d+1
          else
            combbins['cool-mild']['other'] << d+1
          end
        elsif oatmax >= 15.0
          # tempbins['cool'] << d+1
          if (oatmaxind >= 9.0) && (oatmaxind <= 11.0)
            combbins['cool']['morning'] << d+1
          elsif (oatmaxind > 11.0) && (oatmaxind <= 14.0)
            combbins['cool']['noon'] << d+1
          elsif (oatmaxind > 14.0) && (oatmaxind <= 15.0)
            combbins['cool']['afternoon'] << d+1
          elsif (oatmaxind > 15.0) && (oatmaxind <= 17.0)
            combbins['cool']['late-afternoon'] << d+1
          elsif (oatmaxind > 17.0) && (oatmaxind <= 20.0)
            combbins['cool']['evening'] << d+1
          else
            combbins['cool']['other'] << d+1
          end
        else
          # tempbins['cold'] << d+1
          if (oatmaxind >= 9.0) && (oatmaxind <= 11.0)
            combbins['cold']['morning'] << d+1
          elsif (oatmaxind > 11.0) && (oatmaxind <= 14.0)
            combbins['cold']['noon'] << d+1
          elsif (oatmaxind > 14.0) && (oatmaxind <= 15.0)
            combbins['cold']['afternoon'] << d+1
          elsif (oatmaxind > 15.0) && (oatmaxind <= 17.0)
            combbins['cold']['late-afternoon'] << d+1
          elsif (oatmaxind > 17.0) && (oatmaxind <= 20.0)
            combbins['cold']['evening'] << d+1
          else
            combbins['cold']['other'] << d+1
          end
        end
      end

      ns = 0
      combbins.keys.each do |key|
        # puts key
        combbins[key].keys.each do |keykey|
          # puts keykey
          # puts combbins[key][keykey].length
          if combbins[key][keykey].length > 14
            selectdays[key][keykey] = combbins[key][keykey].sample(3)
            ns += 3
          elsif combbins[key][keykey].length > 7
            selectdays[key][keykey] = combbins[key][keykey].sample(2)
            ns += 2
          elsif combbins[key][keykey].length > 0
            selectdays[key][keykey] = combbins[key][keykey].sample(1)
            ns += 1
          end
        end
      end
      return combbins, selectdays, ns
    end

    ### run simulation on selected day of year
    def model_run_simulation_on_doy(model, year, doy, run_dir = "#{Dir.pwd}/Run")
      ### reference: https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/utilities/simulation.rb#L187
      # Make the directory if it doesn't exist
      unless Dir.exist?(run_dir)
        FileUtils.mkdir_p(run_dir)
      end

      template = 'ComStock 90.1-2019'
      std = Standard.build(template)
      # Save the model to energyplus idf
      # idf_name = 'in.idf'
      osm_name = 'in.osm'
      osw_name = 'in.osw'
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', "Starting simulation here: #{run_dir}.")
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Started simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
      # forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
      begin_month, begin_day = day_of_year_to_date(year, doy-1)
      end_month, end_day = day_of_year_to_date(year, doy)
      nts = 1
      ### reference: SetRunPeriod measure on BCL
      model.getYearDescription.setCalendarYear(year)
      model.getRunPeriod.setBeginMonth(begin_month)
      model.getRunPeriod.setBeginDayOfMonth(begin_day)
      model.getRunPeriod.setEndMonth(end_month)
      model.getRunPeriod.setEndDayOfMonth(end_day)
      model.getTimestep.setNumberOfTimestepsPerHour(nts)
      # puts("### DEBUGGING: model.getRunPeriod.getBeginDayOfMonth = #{model.getRunPeriod.getBeginDayOfMonth}")
      # puts("### DEBUGGING: model.getRunPeriod.getBeginMonth = #{model.getRunPeriod.getBeginMonth}")
      # puts("### DEBUGGING: model.getRunPeriod.getEndMonth = #{model.getRunPeriod.getEndMonth}")
      # puts("### DEBUGGING: model.getRunPeriod.getEndDayOfMonth = #{model.getRunPeriod.getEndDayOfMonth}")
      # idf = forward_translator.translateModel(model)
      # idf_path = OpenStudio::Path.new("#{run_dir}/#{idf_name}")
      osm_path = OpenStudio::Path.new("#{run_dir}/#{osm_name}")
      osw_path = OpenStudio::Path.new("#{run_dir}/#{osw_name}")
      # idf.save(idf_path, true)
      model.save(osm_path, true)
      # Set up the simulation
      # Find the weather file
      epw_path = std.model_get_full_weather_file_path(model)
      if epw_path.empty?
        return false
      end
      epw_path = epw_path.get
      # close current sql file
      model.resetSqlFile
      # If running on a regular desktop, use RunManager.
      # If running on OpenStudio Server, use WorkFlowMananger
      # to avoid slowdown from the run.
      use_runmanager = true
      begin
        workflow = OpenStudio::WorkflowJSON.new
        use_runmanager = false
      rescue NameError
        use_runmanager = true
      end
  
      sql_path = nil
      if use_runmanager
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', 'Running with RunManager.')
        # Find EnergyPlus
        ep_dir = OpenStudio.getEnergyPlusDirectory
        ep_path = OpenStudio.getEnergyPlusExecutable
        ep_tool = OpenStudio::Runmanager::ToolInfo.new(ep_path)
        idd_path = OpenStudio::Path.new(ep_dir.to_s + '/Energy+.idd')
        output_path = OpenStudio::Path.new("#{run_dir}/")
        # Make a run manager and queue up the run
        run_manager_db_path = OpenStudio::Path.new("#{run_dir}/run.db")
        # HACK: workaround for Mac with Qt 5.4, need to address in the future.
        OpenStudio::Application.instance.application(false)
        run_manager = OpenStudio::Runmanager::RunManager.new(run_manager_db_path, true, false, false, false)
        job = OpenStudio::Runmanager::JobFactory.createEnergyPlusJob(ep_tool,
                                                                     idd_path,
                                                                     idf_path,
                                                                     epw_path,
                                                                     output_path)
        run_manager.enqueue(job, true)
        # Start the run and wait for it to finish.
        while run_manager.workPending
          sleep 1
          OpenStudio::Application.instance.processEvents
        end
        sql_path = OpenStudio::Path.new("#{run_dir}/EnergyPlus/eplusout.sql")
        # puts("### DEBUGGING: sql_path = #{sql_path}")
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
  
      else # method to running simulation within measure using OpenStudio 2.x WorkflowJSON
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', 'Running with OS 2.x WorkflowJSON.')
        # Copy the weather file to this directory
        epw_name = 'in.epw'
        begin
          FileUtils.copy(epw_path.to_s, "#{run_dir}/#{epw_name}")
        rescue StandardError
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Due to limitations on Windows file path lengths, this measure won't work unless your project is located in a directory whose filepath is less than 90 characters long, including slashes.")
          return false
        end
        workflow.setSeedFile(osm_name)
        workflow.setWeatherFile(epw_name)
        workflow.saveAs(File.absolute_path(osw_path.to_s))
        # 'touch' the weather file - for some odd reason this fixes the simulation not running issue we had on openstudio-server.
        # Removed for until further investigation completed.
        # FileUtils.touch("#{run_dir}/#{epw_name}")
        cli_path = OpenStudio.getOpenStudioCLI
        cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""
        # cmd = "\"#{cli_path}\" --verbose run -w \"#{osw_path}\""
        # puts cmd
        # Run the sizing run
        OpenstudioStandards.run_command(cmd)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
        sql_path = OpenStudio::Path.new("#{run_dir}/run/eplusout.sql")
        # puts("### DEBUGGING: sql_path = #{sql_path}")
      end

      # get sql
      # sqlFile = model.sqlFile
      sqlFile = OpenStudio::SqlFile.new(sql_path)
      # if sqlFile.is_initialized
      #   sqlFile = sqlFile.get
      # end
      # TEMPORARY
      # puts(" ============================================================")
      # puts("--- sqlFile.availableEnvPeriods = #{sqlFile.availableEnvPeriods}")
      # puts("--- sqlFile.availableTimeSeries = #{sqlFile.availableTimeSeries}")
      # puts("--- sqlFile.availableReportingFrequencies('RUN PERIOD 1') = #{sqlFile.availableReportingFrequencies('RUN PERIOD 1')}")
      envperiod = 'RUN PERIOD 1'
      timeseriesname = 'Electricity:Facility'
      reportingfrequency = 'Hourly'
      electricity_results = sqlFile.timeSeries(envperiod,reportingfrequency,timeseriesname)
      vals = []
      electricity_results.each do |electricity_result|
        # puts("--- electricity_result.intervalLength = #{electricity_result.intervalLength}")
        # puts("--- electricity_result.startDateTime = #{electricity_result.startDateTime}")
        # electricity_result.values.each_with_index do |value, i|
        #   puts("--- value #{i} = #{value}")
        # end
        elec_vals = electricity_result.values
        for i in (elec_vals.size/2)..(elec_vals.size - 1)
          vals << elec_vals[i]
        end
      end
      # puts vals
      return vals
    end

    ### run simulation on all sample days of year
    def run_samples(model, year, selectdays)
      y_seed = {
        'ext-hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'cool-mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'cool' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
        'cold' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] }
      }

      run_time = 0
      selectdays.keys.each do |key|
        selectdays[key].keys.each do |keykey|
          puts key, keykey
          ns = selectdays[key][keykey].length.to_f
          puts "Number of samples: #{ns}"
          selectdays[key][keykey].each do |doy|
            start_time = Time.now
            puts "Simulation on day of year: #{doy}"
            yd = model_run_simulation_on_doy(model, year, doy)
            # puts yd
            if ns == 1
              y_seed[key][keykey] = yd
            elsif ns > 1
              if y_seed[key][keykey] == []
                y_seed[key][keykey] = yd.map { |a| a/ns }
              else
                y_seed[key][keykey] = yd.zip(y_seed[key][keykey]).map { |a, b| (a/ns+b) }
              end
            end
            end_time = Time.now
            run_time += end_time - start_time
            puts "Script execution time: #{end_time - start_time} seconds"
            # y_seed[key][keykey] = yd / selectdays[key][keykey].length.to_f
            # puts y_seed[key][keykey]
            # break
          end
          # break
          # puts y_seed[key][keykey]
        end
        # break
      end
      puts "Run time for sample simulation run: #{run_time} seconds"
      return y_seed
    end

    ### populate load profile of samples to all days based on bins
    def load_prediction_from_sample(y_seed, combbins)
      annual_load = []
      (0..364).each do |d|
        combbins.each do |key,subbin|
          if subbin.value?(d+1)
            keykey = subbin.key(d+1)
            annual_load.concat(y_seed[key][keykey])
            break
          end
        end
      end
      return annual_load
    end

    ### run simulation on full year
    def load_prediction_from_full_run(model, year, run_dir = "#{Dir.pwd}/Run")
      ### reference: https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/utilities/simulation.rb#L187
      # Make the directory if it doesn't exist
      unless Dir.exist?(run_dir)
        FileUtils.mkdir_p(run_dir)
      end

      template = 'ComStock 90.1-2019'
      std = Standard.build(template)
  
      # Save the model to energyplus idf
      # idf_name = 'in.idf'
      osm_name = 'in.osm'
      osw_name = 'in.osw'
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', "Starting simulation here: #{run_dir}.")
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Started simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
      # forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new

      nts = 1
      ### reference: SetRunPeriod measure on BCL
      model.getYearDescription.setCalendarYear(year)
      model.getRunPeriod.setBeginMonth(1)
      model.getRunPeriod.setBeginDayOfMonth(1)
      model.getRunPeriod.setEndMonth(12)
      model.getRunPeriod.setEndDayOfMonth(31)
      model.getTimestep.setNumberOfTimestepsPerHour(nts)
      # puts("### DEBUGGING: model.getRunPeriod.getBeginDayOfMonth = #{model.getRunPeriod.getBeginDayOfMonth}")
      # puts("### DEBUGGING: model.getRunPeriod.getBeginMonth = #{model.getRunPeriod.getBeginMonth}")
      # puts("### DEBUGGING: model.getRunPeriod.getEndMonth = #{model.getRunPeriod.getEndMonth}")
      # puts("### DEBUGGING: model.getRunPeriod.getEndDayOfMonth = #{model.getRunPeriod.getEndDayOfMonth}")

      # idf = forward_translator.translateModel(model)
      # idf_path = OpenStudio::Path.new("#{run_dir}/#{idf_name}")
      osm_path = OpenStudio::Path.new("#{run_dir}/#{osm_name}")
      osw_path = OpenStudio::Path.new("#{run_dir}/#{osw_name}")
      # idf.save(idf_path, true)
      model.save(osm_path, true)
  
      # Set up the simulation
      # Find the weather file
      epw_path = std.model_get_full_weather_file_path(model)
      if epw_path.empty?
        return false
      end
  
      epw_path = epw_path.get
  
      # close current sql file
      model.resetSqlFile

      # If running on a regular desktop, use RunManager.
      # If running on OpenStudio Server, use WorkFlowMananger
      # to avoid slowdown from the run.
      use_runmanager = true
  
      begin
        workflow = OpenStudio::WorkflowJSON.new
        use_runmanager = false
      rescue NameError
        use_runmanager = true
      end
  
      sql_path = nil
      if use_runmanager
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', 'Running with RunManager.')
  
        # Find EnergyPlus
        ep_dir = OpenStudio.getEnergyPlusDirectory
        ep_path = OpenStudio.getEnergyPlusExecutable
        ep_tool = OpenStudio::Runmanager::ToolInfo.new(ep_path)
        idd_path = OpenStudio::Path.new(ep_dir.to_s + '/Energy+.idd')
        output_path = OpenStudio::Path.new("#{run_dir}/")
  
        # Make a run manager and queue up the run
        run_manager_db_path = OpenStudio::Path.new("#{run_dir}/run.db")
        # HACK: workaround for Mac with Qt 5.4, need to address in the future.
        OpenStudio::Application.instance.application(false)
        run_manager = OpenStudio::Runmanager::RunManager.new(run_manager_db_path, true, false, false, false)
        job = OpenStudio::Runmanager::JobFactory.createEnergyPlusJob(ep_tool,
                                                                     idd_path,
                                                                     idf_path,
                                                                     epw_path,
                                                                     output_path)
  
        run_manager.enqueue(job, true)
  
        # Start the run and wait for it to finish.
        while run_manager.workPending
          sleep 1
          OpenStudio::Application.instance.processEvents
        end
  
        sql_path = OpenStudio::Path.new("#{run_dir}/EnergyPlus/eplusout.sql")
        # puts("### DEBUGGING: sql_path = #{sql_path}")

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
  
      else # method to running simulation within measure using OpenStudio 2.x WorkflowJSON
  
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', 'Running with OS 2.x WorkflowJSON.')
  
        # Copy the weather file to this directory
        epw_name = 'in.epw'
        begin
          FileUtils.copy(epw_path.to_s, "#{run_dir}/#{epw_name}")
        rescue StandardError
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Due to limitations on Windows file path lengths, this measure won't work unless your project is located in a directory whose filepath is less than 90 characters long, including slashes.")
          return false
        end
  
        workflow.setSeedFile(osm_name)
        workflow.setWeatherFile(epw_name)
        workflow.saveAs(File.absolute_path(osw_path.to_s))
  
        # 'touch' the weather file - for some odd reason this fixes the simulation not running issue we had on openstudio-server.
        # Removed for until further investigation completed.
        # FileUtils.touch("#{run_dir}/#{epw_name}")
  
        cli_path = OpenStudio.getOpenStudioCLI
        cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""
        # cmd = "\"#{cli_path}\" --verbose run -w \"#{osw_path}\""
        # puts cmd
  
        # Run the sizing run
        OpenstudioStandards.run_command(cmd)
  
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
  
        sql_path = OpenStudio::Path.new("#{run_dir}/run/eplusout.sql")
        # puts("### DEBUGGING: sql_path = #{sql_path}")
  
      end

      # get sql
      # sqlFile = model.sqlFile
      sqlFile = OpenStudio::SqlFile.new(sql_path)
      # if sqlFile.is_initialized
      #   sqlFile = sqlFile.get
      # end
  
      # TEMPORARY
      # puts(" ============================================================")
      # puts("--- sqlFile.availableEnvPeriods = #{sqlFile.availableEnvPeriods}")
      # puts("--- sqlFile.availableTimeSeries = #{sqlFile.availableTimeSeries}")
      # puts("--- sqlFile.availableReportingFrequencies('RUN PERIOD 1') = #{sqlFile.availableReportingFrequencies('RUN PERIOD 1')}")
      envperiod = 'RUN PERIOD 1'
      timeseriesname = 'Electricity:Facility'
      reportingfrequency = 'Hourly'
      electricity_results = sqlFile.timeSeries(envperiod,reportingfrequency,timeseriesname)
      vals = []
      electricity_results.each do |electricity_result|
        # puts("--- electricity_result.intervalLength = #{electricity_result.intervalLength}")
        # puts("--- electricity_result.startDateTime = #{electricity_result.startDateTime}")
        # electricity_result.values.each_with_index do |value, i|
        #   puts("--- value #{i} = #{value}")
        # end
        elec_vals = electricity_result.values
        elec_vals.each do |val|
          vals << val
        end
      end
      # puts vals
      return vals
    end

    ### determine daily peak window based on daily load profile
    def find_daily_peak_window(daily_load, peak_len)
      maxload_ind = daily_load.index(daily_load.max)
      # maxload = daily_load.max
      peak_sum = (0..peak_len-1).map do |i|
        daily_load[(maxload_ind - i)..(maxload_ind - i + peak_len - 1)].sum
      end
      peak_ind = maxload_ind - peak_sum.index(peak_sum.max)
      return peak_ind
    end

    ### Generate peak schedule for whole year with rebound option ########################### NEED TO JUSTIFY PUTTING REBOUND OPTION HERE OR IN INDIVIDUAL DF MEASURES
    def peak_schedule_generation(annual_load, peak_len, rebound_len)
      peak_schedule = Array.new(365 * 24, 0)
      # peak_ind_ann = []
      (0..364).each do |d|
        range_start = d * 24
        range_end = d * 24 + 23
        peak_ind = find_daily_peak_window(annual_load[range_start..range_end], peak_len)
        peak_schedule[(range_start + peak_ind)..(range_start + peak_ind + peak_len - 1)] = Array.new(peak_len, 1)
        if rebound_len > 0
          range_rebound_start = range_start + peak_ind + peak_len - 1
          range_rebound_end = range_start + peak_ind + peak_len + rebound_len
          peak_schedule[range_rebound_start..range_rebound_end] = (0..rebound_len + 1).map { |i| 1.0 - i.to_f / (rebound_len + 1) }
        end
        # peak_ind_ann << peak_ind
      end
      return peak_schedule
    end

    ### For bin-sample run

    puts(" ============================================================")
    puts("Reading weather file...")
    year, oat = read_epw(weather_file)
    puts("Weather file read!")
    # puts oat
    puts(" ============================================================")
    puts("Creating bins...")
    bins, selectdays, ns = create_binsamples(oat)
    puts("Bins created!")
    puts bins
    puts("Samples:")
    puts selectdays
    puts("Number of samples:")
    puts ns
    puts(" ============================================================")
    puts("Running simulation on samples...")
    y_seed = run_samples(model, year, selectdays)
    puts("Sample simulation done!")
    puts y_seed
    puts(" ============================================================")
    puts("Creating annual prediction...")
    annual_load = load_prediction_from_sample(y_seed, bins)
    puts("Annual prediction done!")
    puts annual_load.class
    # puts annual_load

    ### For full year baseline run

    # puts(" ============================================================")
    # puts("Running simulation...")
    # start_time = Time.now
    # annual_load = load_prediction_from_full_run(model, year)
    # end_time = Time.now
    # puts "Script execution time: #{end_time - start_time} seconds"
    # puts("Simulation done!")
    # puts annual_load.class
    # puts annual_load

    puts(" ============================================================")
    puts("Creating peak schedule...")
    start_time = Time.now
    peak_schedule = peak_schedule_generation(annual_load, peak_len, rebound_len)
    end_time = Time.now
    puts "Script execution time: #{end_time - start_time} seconds"
    puts("Schedule generated!")
    puts peak_schedule

    # write_to_csv = weather_ts#.transpose
    # ### write to output csv
    # runner.registerInfo("Writing CSV weather")
    # File.open(output_path, 'w') do |file|
    #   file.puts header.join(',')
    #   write_to_csv.each do |row|
    #     file.puts row.join(',')
    #     #file.puts row
    #   end
    # end
    
    return true
  end
end

# register the measure to be used by the application
DispatchScheduleGeneration.new.registerWithApplication
