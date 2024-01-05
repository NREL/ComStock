# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2020, Alliance for Sustainable Energy, LLC.
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

### convert day of year to month-day date ######################### NEED TO ADD FUNCTIONALITY OF DEALING WITH LEAP YEAR
def day_of_year_to_date(year, day_of_year)
  date = Date.new(year, 1, 1) + day_of_year - 1
  month = date.month
  day = date.day
  return month, day
end

### if year is leap year
def leap_year?(year)
  if (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    return true
  else
    return false
  end
end

### run simulation on selected day of year
def read_epw(model, epw_path=nil)

  if epw_path==nil
    # get EPWFile class from model
    weatherfile = nil
    if model.weatherFile.is_initialized
      weatherfile = model.weatherFile.get
      epw_file = nil
      if weatherfile.file.is_initialized
        epw_file = weatherfile.file.get
      else
        runner.registerError('Cannot find weather file from model using EPWFile class')
      end
    else
      runner.registerError('Cannot find weather file from model using weatherFile class')
    end
  else
    puts("Override with given epw from #{epw_path}")
    epw_file = OpenStudio::EpwFile.new(epw_path)
  end

  # weather_startDate = epw_file.startDate
  weather_startDateActualYear = epw_file.startDateActualYear
  year = weather_startDateActualYear.to_i
  weather_timeStep = epw_file.timeStep
  weather_daylightSavingEndDate = epw_file.daylightSavingEndDate
  weather_daylightSavingStartDate = epw_file.daylightSavingStartDate
  # puts("weather name: #{epw_file.city}_#{epw_file.stateProvinceRegion}_#{epw_file.country}")
  
  field = 'DryBulbTemperature'
  weather_ts = epw_file.getTimeSeries(field)
  
  if weather_ts.is_initialized
    weather_ts = weather_ts.get
  else
    puts "FAIL, could not retrieve field: #{field} from #{epw_file}"
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
  if year == 0
    year = 2018
  end
  return year, vals
end

### create bins based on temperature profile and select sample days in bins
def create_binsamples(oat)

  if oat.size == 8784
    nd = 366
  else
    nd = 365
  end
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
  (0..nd-1).each do |d|
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
  srand(42)
  max_doys = []
  combbins.keys.each do |key|
    # puts key
    combbins[key].keys.each do |keykey|
      # puts keykey
      # puts combbins[key][keykey].length
      if combbins[key][keykey].length > 14
        selectdays[key][keykey] = combbins[key][keykey].sort.take(3).to_a
        # selectdays[key][keykey] = combbins[key][keykey].sample(3)
        ns += 3
      elsif combbins[key][keykey].length > 7
        selectdays[key][keykey] = combbins[key][keykey].sort.take(2).to_a
        # selectdays[key][keykey] = combbins[key][keykey].sample(2)
        ns += 2
      elsif combbins[key][keykey].length > 0
        selectdays[key][keykey] = combbins[key][keykey].sort.take(1).to_a
        # selectdays[key][keykey] = combbins[key][keykey].sample(1)
        ns += 1
      end
      if selectdays[key][keykey] != []
        max_doys << selectdays[key][keykey].max
      end
    end
  end
  max_doy = max_doys.max
  return combbins, selectdays, ns, max_doy
end

### run simulation on selected day of year
def model_run_simulation_on_doy(model, year, doy, num_timesteps_in_hr, epw_path=nil, run_dir = "#{Dir.pwd}/Run")
  ### reference: https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/utilities/simulation.rb#L187
  # Make the directory if it doesn't exist
  unless Dir.exist?(run_dir)
    FileUtils.mkdir_p(run_dir)
  end
  puts("### DEBUGGING: run_dir = #{run_dir}")
  template = 'ComStock 90.1-2019'
  std = Standard.build(template)
  # Save the model to energyplus idf
  osm_name = 'in.osm'
  osw_name = 'in.osw'
  OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', "Starting simulation here: #{run_dir}.")
  OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Started simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
  forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
  if doy == 1
    begin_month, begin_day = day_of_year_to_date(year, doy)
    end_month, end_day = day_of_year_to_date(year, doy+1)
  else
    begin_month, begin_day = day_of_year_to_date(year, doy)
    end_month, end_day = day_of_year_to_date(year, doy)
  end
  # puts("### DEBUGGING: begin_month = #{begin_month}")
  # puts("### DEBUGGING: begin_day = #{begin_day}")
  # puts("### DEBUGGING: end_month = #{end_month}")
  # puts("### DEBUGGING: end_day = #{end_day}")
  ### reference: SetRunPeriod measure on BCL
  model.getYearDescription.setCalendarYear(year)
  model.getRunPeriod.setBeginMonth(begin_month)
  model.getRunPeriod.setBeginDayOfMonth(begin_day)
  model.getRunPeriod.setEndMonth(end_month)
  model.getRunPeriod.setEndDayOfMonth(end_day)
  if num_timesteps_in_hr != 4
    model.getTimestep.setNumberOfTimestepsPerHour(num_timesteps_in_hr)
  end
  # model.getSimulationControl.setDoZoneSizingCalculation(false)
  # model.getSimulationControl.setDoSystemSizingCalculation(false)
  # model.getSimulationControl.setDoPlantSizingCalculation(false)
  # puts("### DEBUGGING: model.getRunPeriod.getBeginDayOfMonth = #{model.getRunPeriod.getBeginDayOfMonth}")
  # puts("### DEBUGGING: model.getRunPeriod.getBeginMonth = #{model.getRunPeriod.getBeginMonth}")
  # puts("### DEBUGGING: model.getRunPeriod.getEndMonth = #{model.getRunPeriod.getEndMonth}")
  # puts("### DEBUGGING: model.getRunPeriod.getEndDayOfMonth = #{model.getRunPeriod.getEndDayOfMonth}")
  # puts("### DEBUGGING: model.getSimulationControl.doZoneSizingCalculation = #{model.getSimulationControl.doZoneSizingCalculation}")
  # puts("### DEBUGGING: model.getSimulationControl.doSystemSizingCalculation = #{model.getSimulationControl.doSystemSizingCalculation}")
  # puts("### DEBUGGING: model.getSimulationControl.doPlantSizingCalculation = #{model.getSimulationControl.doPlantSizingCalculation}")
  osm_path = OpenStudio::Path.new("#{run_dir}/#{osm_name}")
  osw_path = OpenStudio::Path.new("#{run_dir}/#{osw_name}")
  model.save(osm_path, true)
  # Set up the simulation
  # Find the weather file
  if epw_path==nil
    epw_path = std.model_get_full_weather_file_path(model)
    if epw_path.empty?
      return false
    end
    epw_path = epw_path.get
    puts epw_path
  end
  # close current sql file
  model.resetSqlFile
  # initialize OSW
  begin
    workflow = OpenStudio::WorkflowJSON.new
  rescue NameError
    raise 'Cannot run simulation with OSW approach'
  end
  sql_path = nil
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
  puts osm_path
  workflow.setWeatherFile(epw_name)
  workflow.saveAs(File.absolute_path(osw_path.to_s))
  # 'touch' the weather file - for some odd reason this fixes the simulation not running issue we had on openstudio-server.
  # Removed for until further investigation completed.
  # FileUtils.touch("#{run_dir}/#{epw_name}")
  cli_path = OpenStudio.getOpenStudioCLI
  cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""
  # cmd = "\"#{cli_path}\" --verbose run -w \"#{osw_path}\""
  puts cmd
  # Run the sizing run
  OpenstudioStandards.run_command(cmd)
  OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
  sql_path = OpenStudio::Path.new("#{run_dir}/run/eplusout.sql")
  # puts("### DEBUGGING: sql_path = #{sql_path}")
  # get sql
  sqlFile = OpenStudio::SqlFile.new(sql_path)
  # if sqlFile.is_initialized
  #   sqlFile = sqlFile.get
  # end
  # check available timeseries extraction options
  availableEnvPeriods = sqlFile.availableEnvPeriods.to_a
  availableTimeSeries = sqlFile.availableTimeSeries.to_a
  availableReportingFrequencies = []
  availableEnvPeriods.each do |envperiod|
    sqlFile.availableReportingFrequencies(envperiod).to_a.each do |repfreq|
      availableReportingFrequencies << repfreq
    end
  end
  # puts("### DEBUGGING: availableEnvPeriods = #{availableEnvPeriods}")
  # puts("### DEBUGGING: availableTimeSeries = #{availableTimeSeries}")
  # puts("### DEBUGGING: availableReportingFrequencies = #{availableReportingFrequencies}")
  envperiod = nil
  if availableEnvPeriods.size == 1
    envperiod = 'RUN PERIOD 1'
  else
    raise "options for availableEnvPeriods are not just one: #{availableEnvPeriods}"
  end
  timeseriesname = 'Electricity:Facility'
  reportingfrequency = 'Hourly' #'Zone Timestep'
  unless availableEnvPeriods.include?(envperiod) 
    raise "envperiod of #{envperiod} not included in available options: #{availableEnvPeriods}"
  end
  unless availableTimeSeries.include?(timeseriesname) 
    raise "timeseriesname of #{timeseriesname} not included in available options: #{availableTimeSeries}"
  end
  unless availableReportingFrequencies.include?(reportingfrequency)
    puts("Hourly reporting frequency is not available")
    reportingfrequency = 'Zone Timestep'
    unless availableReportingFrequencies.include?(reportingfrequency)
      raise "reportingfrequency of #{reportingfrequency} not included in available options: #{availableReportingFrequencies}"
    end
  end

  electricity_results = sqlFile.timeSeries(envperiod,reportingfrequency,timeseriesname)
  vals = []
  electricity_results.each do |electricity_result|
    # puts("--- electricity_result.intervalLength = #{electricity_result.intervalLength}")
    # puts("--- electricity_result.startDateTime = #{electricity_result.startDateTime}")
    # electricity_result.values.each_with_index do |value, i|
    #   puts("--- value #{i} = #{value}")
    # end
    elec_vals = electricity_result.values
    # for i in (elec_vals.size/2)..(elec_vals.size - 1)
    #   vals << elec_vals[i]
    # end
    for i in 0..(elec_vals.size - 1)
      vals << elec_vals[i]
    end
  end
  # raise if vals is empty
  if vals.empty?
    raise 'load profile for the sample run returned empty'
  end
  return vals
end

### run simulation on all sample days of year
def run_samples(model, year, selectdays, num_timesteps_in_hr, epw_path=nil)
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
      # puts key, keykey
      ns = selectdays[key][keykey].length.to_f
      # puts "Number of samples: #{ns}"
      selectdays[key][keykey].each do |doy|
        start_time = Time.now
        puts "Simulation on day of year: #{doy}"
        yd = model_run_simulation_on_doy(model, year, doy, num_timesteps_in_hr, epw_path=epw_path)
        puts("--- yd = #{yd}")
        puts("--- yd.size = #{yd.size}")
        if yd.size > 24
          averages = []
          yd.each_slice(yd.size/24) do |slice|
            average = slice.reduce(:+).to_f
            averages << average
          end
          yd = averages
        end
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

### run simulation on part of year
def model_run_simulation_on_part_of_year(model, year, max_doy, num_timesteps_in_hr, epw_path=nil, run_dir = "#{Dir.pwd}/Run")
  ### reference: https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/utilities/simulation.rb#L187
  # Make the directory if it doesn't exist
  unless Dir.exist?(run_dir)
    FileUtils.mkdir_p(run_dir)
  end
  # puts("### DEBUGGING: run_dir = #{run_dir}")
  template = 'ComStock 90.1-2019'
  std = Standard.build(template)
  # Save the model to energyplus idf
  osm_name = 'in.osm'
  osw_name = 'in.osw'
  OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', "Starting simulation here: #{run_dir}.")
  OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Started simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
  # forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
  begin_month, begin_day = day_of_year_to_date(year, 1)
  end_month, end_day = day_of_year_to_date(year, max_doy)
  ### reference: SetRunPeriod measure on BCL
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
  # puts("### DEBUGGING: model.getRunPeriod.getBeginDayOfMonth = #{model.getRunPeriod.getBeginDayOfMonth}")
  # puts("### DEBUGGING: model.getRunPeriod.getBeginMonth = #{model.getRunPeriod.getBeginMonth}")
  # puts("### DEBUGGING: model.getRunPeriod.getEndMonth = #{model.getRunPeriod.getEndMonth}")
  # puts("### DEBUGGING: model.getRunPeriod.getEndDayOfMonth = #{model.getRunPeriod.getEndDayOfMonth}")
  # puts("### DEBUGGING: model.getSimulationControl.doZoneSizingCalculation = #{model.getSimulationControl.doZoneSizingCalculation}")
  # puts("### DEBUGGING: model.getSimulationControl.doSystemSizingCalculation = #{model.getSimulationControl.doSystemSizingCalculation}")
  # puts("### DEBUGGING: model.getSimulationControl.doPlantSizingCalculation = #{model.getSimulationControl.doPlantSizingCalculation}")
  osm_path = OpenStudio::Path.new("#{run_dir}/#{osm_name}")
  osw_path = OpenStudio::Path.new("#{run_dir}/#{osw_name}")
  model.save(osm_path, true)
  # Set up the simulation
  # Find the weather file
  if epw_path==nil
    epw_path = std.model_get_full_weather_file_path(model)
    if epw_path.empty?
      return false
    end
    epw_path = epw_path.get
    # puts epw_path
  end
  # close current sql file
  model.resetSqlFile
  # initialize OSW
  begin
    workflow = OpenStudio::WorkflowJSON.new
  rescue NameError
    raise 'Cannot run simulation with OSW approach'
  end
  sql_path = nil
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
  # puts osm_path
  workflow.setWeatherFile(epw_name)
  workflow.saveAs(File.absolute_path(osw_path.to_s))
  # 'touch' the weather file - for some odd reason this fixes the simulation not running issue we had on openstudio-server.
  # Removed for until further investigation completed.
  # FileUtils.touch("#{run_dir}/#{epw_name}")
  cli_path = OpenStudio.getOpenStudioCLI
  cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""
  # cmd = "\"#{cli_path}\" --verbose run -w \"#{osw_path}\""
  puts cmd
  # Run the sizing run
  OpenstudioStandards.run_command(cmd)
  OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
  sql_path = OpenStudio::Path.new("#{run_dir}/run/eplusout.sql")
  # puts("### DEBUGGING: sql_path = #{sql_path}")
  # get sql
  sqlFile = OpenStudio::SqlFile.new(sql_path)
  # if sqlFile.is_initialized
  #   sqlFile = sqlFile.get
  # end
  # check available timeseries extraction options
  availableEnvPeriods = sqlFile.availableEnvPeriods.to_a
  availableTimeSeries = sqlFile.availableTimeSeries.to_a
  availableReportingFrequencies = []
  availableEnvPeriods.each do |envperiod|
    sqlFile.availableReportingFrequencies(envperiod).to_a.each do |repfreq|
      availableReportingFrequencies << repfreq
    end
  end
  # puts("### DEBUGGING: availableEnvPeriods = #{availableEnvPeriods}")
  # puts("### DEBUGGING: availableTimeSeries = #{availableTimeSeries}")
  # puts("### DEBUGGING: availableReportingFrequencies = #{availableReportingFrequencies}")
  envperiod = nil
  if availableEnvPeriods.size == 1
    envperiod = 'RUN PERIOD 1'
  else
    raise "options for availableEnvPeriods are not just one: #{availableEnvPeriods}"
  end
  timeseriesname = 'Electricity:Facility'
  unless availableEnvPeriods.include?(envperiod) 
    raise "envperiod of #{envperiod} not included in available options: #{availableEnvPeriods}"
  end
  unless availableTimeSeries.include?(timeseriesname) 
    raise "timeseriesname of #{timeseriesname} not included in available options: #{availableTimeSeries}"
  end
  reportingfrequency = 'Hourly' #'Zone Timestep'
  unless availableReportingFrequencies.include?(reportingfrequency)
    puts("Hourly reporting frequency is not available. Use Zone Timestep.")
    reportingfrequency = 'Zone Timestep'
    unless availableReportingFrequencies.include?(reportingfrequency)
      raise "reportingfrequency of #{reportingfrequency} not included in available options: #{availableReportingFrequencies}"
    end
  end
  electricity_results = sqlFile.timeSeries(envperiod,reportingfrequency,timeseriesname)
  vals = []
  electricity_results.each do |electricity_result|
    elec_vals = electricity_result.values
    for i in 0..(elec_vals.size - 1)
      vals << elec_vals[i]
    end
  end
  # raise if vals is empty
  if vals.empty?
    raise 'load profile for the sample run returned empty'
  end
  return vals
end

### run simulation on part of year and extract samples
def run_part_year_samples(model, year, max_doy, selectdays, num_timesteps_in_hr, epw_path=nil)
  y_seed = {
    'ext-hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
    'hot' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
    'mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
    'cool-mild' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
    'cool' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] },
    'cold' => { 'morning' => [], 'noon' => [], 'afternoon' => [], 'late-afternoon' => [], 'evening' => [], 'other' => [] }
  }
  puts "Simulation on part year until day: #{max_doy}"
  # start_time = Time.now
  yd = model_run_simulation_on_part_of_year(model, year, max_doy, num_timesteps_in_hr, epw_path=epw_path)
  # end_time = Time.now
  # puts "Script execution time: #{end_time - start_time} seconds"
  # puts("--- yd.size = #{yd.size}")
  if num_timesteps_in_hr != 1 #yd.size > 24*max_doy
    puts("Convert interval to hourly")
    sums = []
    yd.each_slice(yd.size/24/max_doy) do |slice|
      sum = slice.reduce(:+).to_f
      sums << sum
    end
    yd = sums
  end
  # puts("--- yd = #{yd}")
  # puts("--- yd.size = #{yd.size}")
  selectdays.keys.each do |key|
    selectdays[key].keys.each do |keykey|
      # puts key, keykey
      ns = selectdays[key][keykey].length.to_f
      # puts "Number of samples: #{ns}"
      selectdays[key][keykey].each do |doy|
        if ns == 1
          y_seed[key][keykey] = yd[(doy*24-24)..(doy*24-1)]
        elsif ns > 1
          if y_seed[key][keykey] == []
            y_seed[key][keykey] = yd[(doy*24-24)..(doy*24-1)].map { |a| a/ns }
          else
            y_seed[key][keykey] = yd[(doy*24-24)..(doy*24-1)].zip(y_seed[key][keykey]).map { |a, b| (a/ns+b) }
          end
        end
        # y_seed[key][keykey] = yd / selectdays[key][keykey].length.to_f
        # puts y_seed[key][keykey]
        # break
      end
      # break
      # puts y_seed[key][keykey]
    end
    # break
  end
  return y_seed
end

### populate load profile of samples to all days based on bins
def load_prediction_from_sample(y_seed, combbins, year)
  # puts("--- y_seed = #{y_seed}")
  # puts("--- combbins = #{combbins}")
  if leap_year?(year)
    nd = 366
  else
    nd = 365
  end
  annual_load = []
  (0..nd-1).each do |d|
    # puts d
    combbins.each do |key,subbin|
      # puts key
      # puts subbin
      subbin.each do |keykey,bin|
        if bin.include?(d+1)
          # puts key, keykey
          annual_load.concat(y_seed[key][keykey])
          # break
        end
      end
    end
  end
  return annual_load
end

### run simulation on full year
def load_prediction_from_full_run(model, year, num_timesteps_in_hr, epw_path=nil, run_dir = "#{Dir.pwd}/Run")
  ### reference: https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/utilities/simulation.rb#L187
  # Make the directory if it doesn't exist
  unless Dir.exist?(run_dir)
    FileUtils.mkdir_p(run_dir)
  end
  
  template = 'ComStock 90.1-2019'
  std = Standard.build(template)
  # Save the model to energyplus idf
  osm_name = 'in.osm'
  osw_name = 'in.osw'
  OpenStudio.logFree(OpenStudio::Debug, 'openstudio.model.Model', "Starting simulation here: #{run_dir}.")
  OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Started simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
  # forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
  ### reference: SetRunPeriod measure on BCL
  model.getYearDescription.setCalendarYear(year)
  model.getRunPeriod.setBeginMonth(1)
  model.getRunPeriod.setBeginDayOfMonth(1)
  model.getRunPeriod.setEndMonth(12)
  model.getRunPeriod.setEndDayOfMonth(31)
  if num_timesteps_in_hr != 4
    model.getTimestep.setNumberOfTimestepsPerHour(num_timesteps_in_hr)
  end
  osm_path = OpenStudio::Path.new("#{run_dir}/#{osm_name}")
  osw_path = OpenStudio::Path.new("#{run_dir}/#{osw_name}")
  model.save(osm_path, true)
  # Set up the simulation
  # Find the weather file
  if epw_path==nil
    epw_path = std.model_get_full_weather_file_path(model)
    if epw_path.empty?
      return false
    end
    epw_path = epw_path.get
    # puts epw_path
  end
  # close current sql file
  model.resetSqlFile
  # initialize OSW
  begin
    workflow = OpenStudio::WorkflowJSON.new
  rescue NameError
    raise 'Cannot run simulation with OSW approach'
  end
  sql_path = nil
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
  # puts osm_path
  workflow.setWeatherFile(epw_name)
  workflow.saveAs(File.absolute_path(osw_path.to_s))
  # 'touch' the weather file - for some odd reason this fixes the simulation not running issue we had on openstudio-server.
  # Removed for until further investigation completed.
  # FileUtils.touch("#{run_dir}/#{epw_name}")
  cli_path = OpenStudio.getOpenStudioCLI
  cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""
  # cmd = "\"#{cli_path}\" --verbose run -w \"#{osw_path}\""
  puts cmd
  # Run the sizing run
  OpenstudioStandards.run_command(cmd)
  OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Finished simulation #{run_dir} at #{Time.now.strftime('%T.%L')}")
  sql_path = OpenStudio::Path.new("#{run_dir}/run/eplusout.sql")
  # puts("### DEBUGGING: sql_path = #{sql_path}")
  # get sql
  sqlFile = OpenStudio::SqlFile.new(sql_path)
  # if sqlFile.is_initialized
  #   sqlFile = sqlFile.get
  # end
  # check available timeseries extraction options
  availableEnvPeriods = sqlFile.availableEnvPeriods.to_a
  availableTimeSeries = sqlFile.availableTimeSeries.to_a
  availableReportingFrequencies = []
  availableEnvPeriods.each do |envperiod|
    sqlFile.availableReportingFrequencies(envperiod).to_a.each do |repfreq|
      availableReportingFrequencies << repfreq
    end
  end
  # puts("### DEBUGGING: availableEnvPeriods = #{availableEnvPeriods}")
  # puts("### DEBUGGING: availableTimeSeries = #{availableTimeSeries}")
  # puts("### DEBUGGING: availableReportingFrequencies = #{availableReportingFrequencies}")
  envperiod = nil
  if availableEnvPeriods.size == 1
    envperiod = 'RUN PERIOD 1'
  else
    raise "options for availableEnvPeriods are not just one: #{availableEnvPeriods}"
  end
  timeseriesname = 'Electricity:Facility'
  unless availableEnvPeriods.include?(envperiod) 
    raise "envperiod of #{envperiod} not included in available options: #{availableEnvPeriods}"
  end
  unless availableTimeSeries.include?(timeseriesname) 
    raise "timeseriesname of #{timeseriesname} not included in available options: #{availableTimeSeries}"
  end
  reportingfrequency = 'Hourly' #'Zone Timestep'
  unless availableReportingFrequencies.include?(reportingfrequency)
    puts("Hourly reporting frequency is not available. Use Zone Timestep.")
    reportingfrequency = 'Zone Timestep'
    unless availableReportingFrequencies.include?(reportingfrequency)
      raise "reportingfrequency of #{reportingfrequency} not included in available options: #{availableReportingFrequencies}"
    end
  end
  electricity_results = sqlFile.timeSeries(envperiod,reportingfrequency,timeseriesname)
  vals = []
  electricity_results.each do |electricity_result|
    elec_vals = electricity_result.values
    for i in 0..(elec_vals.size - 1)
      vals << elec_vals[i]
    end
  end
  # raise if vals is empty
  if vals.empty?
    raise 'load profile for the sample run returned empty'
  end
  if num_timesteps_in_hr > 1
    puts("Convert interval to hourly")
    sums = []
    vals.each_slice(num_timesteps_in_hr) do |slice|
      sum = slice.reduce(:+).to_f
      sums << sum
    end
    vals = sums
  end
  return vals
end

### determine daily peak window based on daily load profile
def find_daily_peak_window(daily_load, peak_len)
  maxload_ind = daily_load.index(daily_load.max)
  # puts("--- daily_load = #{daily_load}")
  # puts("--- peak_len = #{peak_len}")
  # puts("--- maxload_ind = #{maxload_ind}")
  # maxload = daily_load.max
  peak_sum = (0..peak_len-1).map do |i|
    daily_load[(maxload_ind - i)..(maxload_ind - i + peak_len - 1)].sum
  end
  peak_ind = maxload_ind - peak_sum.index(peak_sum.max)
  return peak_ind
end

### Generate peak schedule for whole year with rebound option ########################### NEED TO JUSTIFY PUTTING REBOUND OPTION HERE OR IN INDIVIDUAL DF MEASURES
def peak_schedule_generation(annual_load, peak_len, rebound_len=0, prepeak_len=0)
  if annual_load.size == 8784
    nd = 366
  elsif annual_load.size == 8760
    nd = 365
  else
    raise 'annual load profile not hourly'
  end
  peak_schedule = Array.new(nd * 24, 0)
  # puts("--- rebound_len = #{rebound_len}")
  # puts("--- peak_len = #{peak_len}")
  # puts("--- peak_schedule.size = #{peak_schedule.size}")
  # peak_ind_ann = []
  (0..nd-1).each do |d|
    range_start = d * 24
    range_end = d * 24 + 23
    peak_ind = find_daily_peak_window(annual_load[range_start..range_end], peak_len)
    # peak and rebound schedule
    if prepeak_len == 0
      peak_schedule[(range_start + peak_ind)..(range_start + peak_ind + peak_len - 1)] = Array.new(peak_len, 1)
      if rebound_len > 0
        range_rebound_start = range_start + peak_ind + peak_len - 1
        range_rebound_end = range_start + peak_ind + peak_len + rebound_len
        peak_schedule[range_rebound_start..range_rebound_end] = (0..rebound_len + 1).map { |i| 1.0 - i.to_f / (rebound_len + 1) }
      end
      # peak_ind_ann << peak_ind
    # prepeak schedule
    else
      if peak_ind >= prepeak_len
        peak_schedule[(range_start + peak_ind - prepeak_len)..(range_start + peak_ind - 1)] = Array.new(prepeak_len, 1)
      else
        peak_schedule[(range_start)..(range_start + peak_ind - 1)] = Array.new(peak_ind, 1)
      end
    end
  end
  return peak_schedule
end