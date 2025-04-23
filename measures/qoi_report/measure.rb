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

require 'date'

# start the measure
class QOIReport < OpenStudio::Measure::ReportingMeasure
  # human readable name
  def name
    'QOI Report'
  end

  # human readable description
  def description
    'Reports uncertainty quantification quantities of interest.'
  end

  # define the arguments that the user will input
  def arguments(_model = nil)
    OpenStudio::Measure::OSArgumentVector.new
    # this measure does not require any user arguments, return an empty list
  end

  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  # Warning: Do not change the name of this method to be snake_case. The method must be lowerCamelCase.
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking
    return result unless runner.validateUserArguments(arguments, user_arguments)

    result = OpenStudio::IdfObjectVector.new

    result << OpenStudio::IdfObject.load('Output:Meter,ElectricityPurchased:Facility,hourly;').get
    result << OpenStudio::IdfObject.load('Output:Variable,*,Site Outdoor Air Drybulb Temperature,Hourly;').get

    result
  end

  def seasons
    {
      'winter' => [-1e9, 55],
      'summer' => [70, 1e9],
      'shoulder' => [55, 70]
    }
  end

  def months
    {
      'jan' => 1,
      'feb' => 2,
      'mar' => 3,
      'apr' => 4,
      'may' => 5,
      'jun' => 6,
      'jul' => 7,
      'aug' => 8,
      'sep' => 9,
      'oct' => 10,
      'nov' => 11,
      'dec' => 12
    }
  end

  def average_daily_base_magnitude_by_season
    output_names = []
    seasons.each do |season, _temperature_range|
      output_names << "average_minimum_daily_use_#{season}_kw"
    end
    output_names
  end

  def average_daily_peak_magnitude_by_season
    output_names = []
    seasons.each do |season, _temperature_range|
      output_names << "average_maximum_daily_use_#{season}_kw"
    end
    output_names
  end

  def average_daily_peak_timing_by_season
    output_names = []
    seasons.each do |season, _temperature_range|
      output_names << "average_maximum_daily_timing_#{season}_hour"
    end
    output_names
  end

  def top_ten_daily_seasonal_peak_magnitude_by_season
    output_names = []
    seasons.each do |season, _temperature_range|
      output_names << "average_of_top_ten_highest_peaks_use_#{season}_kw"
    end
    output_names
  end

  def top_ten_seasonal_timing_of_peak_by_season
    output_names = []
    seasons.each do |season, _temperature_range|
      output_names << "average_of_top_ten_highest_peaks_timing_#{season}_hour"
    end
    output_names
  end

  def min_daily_peak_by_month
    output_names = []
    months.each do |month, _month_val|
      output_names << "minimum_daily_peak_use_#{month}_kw"
    end
    output_names
  end

  def q1_daily_peak_by_month
    output_names = []
    months.each do |month, _month_val|
      output_names << "q1_daily_peak_use_#{month}_kw"
    end
    output_names
  end

  def med_daily_peak_by_month
    output_names = []
    months.each do |month, _month_val|
      output_names << "median_daily_peak_use_#{month}_kw"
    end
    output_names
  end

  def q3_daily_peak_by_month
    output_names = []
    months.each do |month, _month_val|
      output_names << "q3_daily_peak_use_#{month}_kw"
    end
    output_names
  end

  def max_daily_peak_by_month
    output_names = []
    months.each do |month, _month_val|
      output_names << "maximum_daily_peak_use_#{month}_kw"
    end
    output_names
  end

  def med_daily_peak_timing_by_month
    output_names = []
    months.each do |month, _month_val|
      output_names << "median_daily_peak_timing_#{month}_hour"
    end
    output_names
  end

  def total_electricity_by_month
    output_names = []
    months.each do |month, _month_val|
      output_names << "total_electricity_use_#{month}_kwh"
    end
    output_names
  end

  def outputs
    output_names = []
    output_names += average_daily_base_magnitude_by_season
    output_names += average_daily_peak_magnitude_by_season
    output_names += average_daily_peak_timing_by_season
    output_names += top_ten_daily_seasonal_peak_magnitude_by_season
    output_names += top_ten_seasonal_timing_of_peak_by_season
    output_names += min_daily_peak_by_month
    output_names += q1_daily_peak_by_month
    output_names += med_daily_peak_by_month
    output_names += q3_daily_peak_by_month
    output_names += max_daily_peak_by_month
    output_names += med_daily_peak_timing_by_month
    output_names += total_electricity_by_month

    result = OpenStudio::Measure::OSOutputVector.new
    output_names.each do |output|
      result << OpenStudio::Measure::OSOutput.makeDoubleOutput(output)
    end

    result
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking
    return false unless runner.validateUserArguments(arguments, user_arguments)

    # get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Cannot find last model.')
      return false
    end
    model = model.get

    sql_file = runner.lastEnergyPlusSqlFile
    if sql_file.empty?
      runner.registerError('Cannot find last sql file.')
      return false
    end
    sql_file = sql_file.get
    model.setSqlFile(sql_file)

    ann_env_pd = nil
    sql_file.availableEnvPeriods.each do |env_pd|
      env_type = sql_file.environmentType(env_pd)
      next unless env_type.is_initialized

      ann_env_pd = env_pd if env_type.get == OpenStudio::EnvironmentType.new('WeatherRunPeriod')
    end
    if ann_env_pd == false
      runner.registerError("Can't find a weather runperiod, make sure you ran an annual simulation, not just the design days.")
      return false
    end

    # get timeseries results for the year
    env_period_ix_query = "SELECT EnvironmentPeriodIndex FROM EnvironmentPeriods WHERE EnvironmentName='#{ann_env_pd}'"
    env_period_ix = sql_file.execAndReturnFirstInt(env_period_ix_query).get
    timeseries = { 'temperature' => [], 'total_site_electricity_kw' => [] }

    # Get temperature values
    # Initialize timeseries hash
    temperature_query = "SELECT VariableValue FROM ReportVariableData WHERE ReportVariableDataDictionaryIndex IN (SELECT ReportVariableDataDictionaryIndex FROM ReportVariableDataDictionary WHERE VariableType='Avg' AND VariableName IN ('Site Outdoor Air Drybulb Temperature') AND ReportingFrequency='Hourly' AND VariableUnits='C') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
    unless sql_file.execAndReturnVectorOfDouble(temperature_query).get.empty?
      temperatures = sql_file.execAndReturnVectorOfDouble(temperature_query).get
      temperatures.each do |val|
        timeseries['temperature'] << OpenStudio.convert(val, 'C', 'F').get
      end
    end

    # Get electricity values
    electricity_query = "SELECT VariableValue FROM ReportMeterData WHERE ReportMeterDataDictionaryIndex IN (SELECT ReportMeterDataDictionaryIndex FROM ReportMeterDataDictionary WHERE VariableTYpe='Sum' AND VariableName='ElectricityPurchased:Facility' AND ReportingFrequency='Hourly' AND VariableUnits='J') AND TimeIndex IN (SELECT TimeIndex FROM Time WHERE EnvironmentPeriodIndex='#{env_period_ix}')"
    unless sql_file.execAndReturnVectorOfDouble(electricity_query).get.empty?
      values = sql_file.execAndReturnVectorOfDouble(electricity_query).get
      values.each do |val|
        timeseries['total_site_electricity_kw'] << OpenStudio.convert(val, 'J', 'kWh').get # hourly data
      end
    end

    seasons.each do |season, temperature_range|
      # Average daily base magnitude (by season) (3)
      report_sim_output(runner, "average_minimum_daily_use_#{season}_kw",
                        average_daily_use(timeseries, temperature_range, 'min'), '', '')

      # Average daily peak magnitude (by season) (3)
      report_sim_output(runner, "average_maximum_daily_use_#{season}_kw",
                        average_daily_use(timeseries, temperature_range, 'max'), '', '')

      # Average daily peak timing (by season) (3)
      report_sim_output(runner, "average_maximum_daily_timing_#{season}_hour",
                        average_daily_timing(timeseries, temperature_range, 'max'), '', '')


      # Top 10 daily seasonal peak magnitude (2)
      report_sim_output(runner, "average_of_top_ten_highest_peaks_use_#{season}_kw",
                        average_daily_use(timeseries, temperature_range, 'max', 10), '', '')

      # Top 10 seasonal timing of peak (2)
      report_sim_output(runner, "average_of_top_ten_highest_peaks_timing_#{season}_hour",
                        average_daily_timing(timeseries, temperature_range, 'max', 10), '', '')
    end

    months.each do |month, month_val|
      # Daily peak minimum by month (12)
      report_sim_output(runner, "minimum_daily_peak_#{month}_kw",
                        daily_peak_stats_by_month(timeseries, month_val, 'min'), '', '')

      # Daily peak first quartile (25%) by month (12)
      report_sim_output(runner, "q1_daily_peak_#{month}_kw", daily_peak_stats_by_month(timeseries, month_val, 'q1'),
                        '', '')

      # Daily peak median by month (12)
      report_sim_output(runner, "median_daily_peak_#{month}_kw",
                        daily_peak_stats_by_month(timeseries, month_val, 'med'), '', '')

      # Daily peak third quartile (75%) by month (12)
      report_sim_output(runner, "q3_daily_peak_#{month}_kw", daily_peak_stats_by_month(timeseries, month_val, 'q3'),
                        '', '')

      # Daily peak maximum by month (12)
      report_sim_output(runner, "maximum_daily_peak_#{month}_kw",
                        daily_peak_stats_by_month(timeseries, month_val, 'max'), '', '')


      # Daily peak timing median by month (12)
      report_sim_output(runner, "median_daily_peak_timing_#{month}_hour",
                        daily_peak_timing_stats_by_month(timeseries, month_val, 'med'), '', '')


      # Daily peak timing median by month (12)
      report_sim_output(runner, "total_electricity_use_#{month}_kwh", monthly_energy(timeseries, month_val, 'total'),
                        '', '')
    end

    sql_file.close

    true
  end

  def average_daily_use(timeseries, temperature_range, min_or_max, top = 'all')
    daily_vals = []
    timeseries['total_site_electricity_kw'].each_slice(24).with_index do |kws, i|
      temps = timeseries['temperature'][(24 * i)...((24 * i) + 24)]
      avg_temp = temps.inject { |sum, el| sum + el }.to_f / temps.size
      if (avg_temp > temperature_range[0]) && (avg_temp < temperature_range[1]) # day is in this season
        if min_or_max == 'min'
          daily_vals << kws.min
        elsif min_or_max == 'max'
          daily_vals << kws.max
        end
      end
    end
    return nil if daily_vals.empty?

    top = if top == 'all'
            daily_vals.length
          else
            [top, daily_vals.length].min # don't try to access indexes that don't exist
          end

    daily_vals = daily_vals.sort.reverse
    daily_vals = daily_vals[0..top]
    daily_vals.inject { |sum, el| sum + el }.to_f / daily_vals.size
  end

  def average_daily_timing(timeseries, temperature_range, min_or_max, top = 'all')
    daily_vals = { 'hour' => [], 'use' => [] }
    timeseries['total_site_electricity_kw'].each_slice(24).with_index do |kws, i|
      temps = timeseries['temperature'][(24 * i)...((24 * i) + 24)]
      avg_temp = temps.inject { |sum, el| sum + el }.to_f / temps.size
      if (avg_temp > temperature_range[0]) && (avg_temp < temperature_range[1]) # day is in this season
        if min_or_max == 'min'
          hour = kws.index(kws.min)
          daily_vals['hour'] << hour
          daily_vals['use'] << kws.min
        elsif min_or_max == 'max'
          hour = kws.index(kws.max)
          daily_vals['hour'] << hour
          daily_vals['use'] << kws.max
        end
      end
    end
    return nil if daily_vals.empty?

    top = if top == 'all'
            daily_vals['hour'].length
          else
            [top, daily_vals['hour'].length].min # don't try to access indexes that don't exist
          end

    return nil if top.zero?

    daily_vals['use'], daily_vals['hour'] = daily_vals['use'].zip(daily_vals['hour']).sort.reverse.transpose
    daily_vals = daily_vals['hour'][0..top]
    daily_vals.inject { |sum, el| sum + el }.to_f / daily_vals.size
  end

  def day_of_year_to_date(day_of_year, year)
    date = Date.new(year, 1, 1) + day_of_year - 1
    month = date.month
    day = date.day
    [month, day]
  end

  def calculate_percentile(array, percentile)
    sorted_array = array.sort
    n = sorted_array.length

    index = (percentile * (n - 1) / 100.0).floor
    fractional_part = (percentile * (n - 1) / 100.0) % 1

    return sorted_array[index] if fractional_part.zero?


    lower_value = sorted_array[index]
    upper_value = sorted_array[index + 1]
    ((1 - fractional_part) * lower_value) + (fractional_part * upper_value)
  end

  def daily_peak_stats_by_month(timeseries, month_val, stats_option = 'max', year = 2018)
    daily_peak_by_month = []
    timeseries['total_site_electricity_kw'].each_slice(24).with_index do |kws, doy|
      month, = day_of_year_to_date(doy, year)
      daily_peak_by_month << kws.max if month == month_val
    end
    stats_by_month = nil
    case stats_option
    when 'min'
      stats_by_month = daily_peak_by_month.min
    when 'q1'
      stats_by_month = calculate_percentile(daily_peak_by_month, 25)
    when 'med'
      stats_by_month = calculate_percentile(daily_peak_by_month, 50)
    when 'q3'
      stats_by_month = calculate_percentile(daily_peak_by_month, 75)
    when 'max'
      stats_by_month = daily_peak_by_month.max
    else
      return nil
    end
    stats_by_month
  end

  def daily_peak_timing_stats_by_month(timeseries, month_val, stats_option = 'med', year = 2018)
    daily_peak_timing_by_month = []
    timeseries['total_site_electricity_kw'].each_slice(24).with_index do |kws, doy|
      month, = day_of_year_to_date(doy, year)
      daily_peak_timing_by_month << kws.index(kws.max) if month == month_val
    end
    stats_by_month = nil
    if stats_option == 'med'
      stats_by_month = calculate_percentile(daily_peak_timing_by_month, 50)
    elsif stats_option == 'mean'
      stats_by_month = daily_peak_timing_by_month.inject { |sum, el| sum + el }.to_f / daily_peak_timing_by_month.size
    else
      return nil
    end
    stats_by_month
  end

  def monthly_energy(timeseries, month_val, stats_option = 'total', year = 2018)
    daily_energy_by_month = []
    timeseries['total_site_electricity_kw'].each_slice(24).with_index do |kws, doy|
      month, = day_of_year_to_date(doy, year)
      daily_energy_by_month << kws.inject { |sum, el| sum + el }.to_f if month == month_val
    end
    energy_by_month = nil
    if stats_option == 'total'
      energy_by_month = daily_energy_by_month.inject { |sum, el| sum + el }.to_f
    elsif stats_option == 'mean'
      energy_by_month = daily_energy_by_month.inject { |sum, el| sum + el }.to_f / daily_energy_by_month.size
    else
      return nil
    end
    energy_by_month
  end

  def report_sim_output(runner, name, total_val, os_units, desired_units, percent_of_val = 1.0)
    if total_val.nil?
      runner.registerInfo("Registering (blank) for #{name}.")
      return
    end
    total_val *= percent_of_val
    val_in_units = if os_units.nil? || desired_units.nil? || (os_units == desired_units)
                     total_val
                   else
                     OpenStudio.convert(total_val, os_units, desired_units).get
                   end
    runner.registerValue(name, val_in_units)
    runner.registerInfo("Registering #{val_in_units.round(2)} for #{name}.")
  end
end

# register the measure to be used by the application
QOIReport.new.registerWithApplication
