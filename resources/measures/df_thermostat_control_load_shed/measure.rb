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

# require all .rb files in resources folder
Dir[File.dirname(__FILE__) + '/resources/*.rb'].each { |file| require file }

require 'openstudio'
require 'date'
require 'openstudio-standards'

# start the measure
class DfThermostatControlLoadShed < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return "df thermostat control load shed"
  end

  # human readable description
  def description
    return "tbd"
  end

  # human readable description of modeling approach
  def modeler_description
    return "tbd"
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    peak_len = OpenStudio::Measure::OSArgument.makeIntegerArgument('peak_len', true)
    peak_len.setDisplayName("Length of dispatch window (hour)")
    peak_len.setDefaultValue(4)
    args << peak_len

    rebound_len = OpenStudio::Measure::OSArgument.makeIntegerArgument('rebound_len', true)
    rebound_len.setDisplayName("Length of rebound period after dispatch window (hour)")
    rebound_len.setDefaultValue(2)
    args << rebound_len

    sp_adjustment = OpenStudio::Measure::OSArgument.makeDoubleArgument('sp_adjustment', true)
    sp_adjustment.setDisplayName("Degrees C to Adjust Setpoint By")
    sp_adjustment.setDefaultValue(2)
    args << sp_adjustment

    num_timesteps_in_hr = OpenStudio::Measure::OSArgument.makeIntegerArgument('num_timesteps_in_hr', true)
    num_timesteps_in_hr.setDisplayName("Number/Count of timesteps in an hour for sample simulations")
    num_timesteps_in_hr.setDefaultValue(4)
    args << num_timesteps_in_hr

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    ############################################
    # use the built-in error checking
    ############################################
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    ############################################
    # assign the user inputs to variables
    ############################################
    peak_len = runner.getIntegerArgumentValue("peak_len",user_arguments)
    rebound_len = runner.getIntegerArgumentValue("rebound_len",user_arguments)
    num_timesteps_in_hr = runner.getIntegerArgumentValue("num_timesteps_in_hr",user_arguments)

    def temp_setp_adjust_hourly_based_on_sch(peak_sch, sp_adjustment)
      sp_adjustment_values = peak_sch.map{|a| sp_adjustment*a}
      return sp_adjustment_values
    end

    def get_8760_values_from_schedule_ruleset(model, schedule_ruleset)
      yd = model.getYearDescription
      #puts yd
      yd.setIsLeapYear(false)
      start_date = yd.makeDate(1, 1)
      end_date = yd.makeDate(12, 31)
      day_of_week = start_date.dayOfWeek.valueName
      values = []#OpenStudio::Vector.new
      day = OpenStudio::Time.new(1.0)
      interval = OpenStudio::Time.new(1.0 / 24.0)
      day_schedules = schedule_ruleset.getDaySchedules(start_date, end_date)
  
      #numdays = day_schedules.size
      # Make new array of day schedules for year
      day_sched_array = []
      day_schedules.each do |day_schedule|
        day_sched_array << day_schedule
      end

      numdays = day_schedules.size
  
      day_sched_array.each do |day_schedule|
        current_hour = interval
        time_values = day_schedule.times
        num_times = time_values.size
        value_sum = 0
        value_count = 0
        time_values.each do |until_hr|
          if until_hr < current_hour
            # Add to tally for next hour average
            value_sum += day_schedule.getValue(until_hr).to_f
            value_count += 1
          elsif until_hr >= current_hour + interval
            # Loop through hours to catch current hour up to until_hr
            while current_hour <= until_hr
              values << day_schedule.getValue(until_hr).to_f
              current_hour += interval
            end
  
            if (current_hour - until_hr) < interval
              # This means until_hr is not an even hour break
              # i.e. there is a sub-hour time step
              # Increment the sum for averaging
              value_sum += day_schedule.getValue(until_hr).to_f
              value_count += 1
            end
  
          else
            # Add to tally for this hour average
            value_sum += day_schedule.getValue(until_hr).to_f
            value_count += 1
            # Calc hour average
            if value_count > 0
              value_avg = value_sum / value_count
            else
              value_avg = 0
            end
            values << value_avg
            # setup for next hour
            value_sum = 0
            value_count = 0
            current_hour += interval
          end
        end
      end
  
      return values
    end

    ############################################
    # For bin-sample run
    ############################################
    puts("### ============================================================")
    puts("### Reading weather file...")
    year, oat = read_epw(model)
    puts("--- year = #{year}")
    puts("--- oat.size = #{oat.size}")

    puts("### ============================================================")
    puts("### Creating bins...")
    bins, selectdays, ns = create_binsamples(oat)
    puts("--- bins = #{bins}")
    puts("--- selectdays = #{selectdays}")
    puts("--- ns = #{ns}")

    puts("### ============================================================")
    puts("### Running simulation on samples...")
    y_seed = run_samples(model, year, selectdays, num_timesteps_in_hr)
    puts("--- y_seed = #{y_seed}")

    puts("### ============================================================")
    puts("### Creating annual prediction...")
    annual_load = load_prediction_from_sample(y_seed, bins)
    puts("--- annual_load = #{annual_load}")
    puts("--- annual_load.class = #{annual_load.class}")

    puts("### ============================================================")
    puts("### Creating peak schedule...")
    peak_schedule = peak_schedule_generation(annual_load, peak_len, rebound_len)
    puts("--- peak_schedule = #{peak_schedule}")
    
    sp_adjustment_values = temp_setp_adjust_hourly_based_on_sch(peak_schedule, sp_adjustment)

    return true
  end
end

# register the measure to be used by the application
DfThermostatControlLoadShed.new.registerWithApplication
