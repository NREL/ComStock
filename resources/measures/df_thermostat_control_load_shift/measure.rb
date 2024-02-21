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
class DfThermostatControlLoadShift < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return "demand flexibility - thermostat control load shift"
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

    prepeak_len = OpenStudio::Measure::OSArgument.makeIntegerArgument('prepeak_len', true)
    prepeak_len.setDisplayName("Length of pre-peak period before dispatch window (hour)")
    prepeak_len.setDefaultValue(2)
    args << prepeak_len

    sp_adjustment = OpenStudio::Measure::OSArgument.makeDoubleArgument('sp_adjustment', true)
    sp_adjustment.setDisplayName("Degrees C to Adjust Setpoint By")
    sp_adjustment.setDefaultValue(2.0)
    args << sp_adjustment

    num_timesteps_in_hr = OpenStudio::Measure::OSArgument.makeIntegerArgument('num_timesteps_in_hr', true)
    num_timesteps_in_hr.setDisplayName("Number/Count of timesteps in an hour for sample simulations")
    num_timesteps_in_hr.setDefaultValue(4)
    args << num_timesteps_in_hr

    choices = ['full baseline', 'bin sample', 'part year bin sample']
    load_prediction_method = OpenStudio::Ruleset::OSArgument.makeChoiceArgument('load_prediction_method', choices, true)
    load_prediction_method.setDisplayName("Method of load prediction (full baseline run, bin sample, part year bin sample)")
    load_prediction_method.setDefaultValue('full baseline')
    args << load_prediction_method

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
    prepeak_len = runner.getIntegerArgumentValue("prepeak_len",user_arguments)
    sp_adjustment = runner.getDoubleArgumentValue('sp_adjustment', user_arguments)
    num_timesteps_in_hr = runner.getIntegerArgumentValue("num_timesteps_in_hr",user_arguments)
    load_prediction_method = runner.getStringArgumentValue("load_prediction_method",user_arguments)

    def leap_year?(year)
      if (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
        return true
      else
        return false
      end
    end

    def temp_setp_adjust_hourly_based_on_sch(peak_sch, sp_adjustment)
      sp_adjustment_values = peak_sch.map{|a| sp_adjustment*a}
      return sp_adjustment_values
    end

    def get_hourly_schedule_from_schedule_ruleset(model, schedule_ruleset)
      yd = model.getYearDescription
      #puts yd
      # yd.setIsLeapYear(false)
      start_date = yd.makeDate(1, 1)
      end_date = yd.makeDate(12, 31)
      day_of_week = start_date.dayOfWeek.valueName
      values = []#OpenStudio::Vector.new
      day = OpenStudio::Time.new(1.0)
      interval = OpenStudio::Time.new(1.0 / 24.0)
      day_schedules = schedule_ruleset.getDaySchedules(start_date, end_date)
      # numdays = day_schedules.size
      # Make new array of day schedules for year
      day_sched_array = []
      day_schedules.each do |day_schedule|
        day_sched_array << day_schedule
      end
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

    def assign_clgsch_to_thermostats(model,applicable_clg_thermostats,runner,clgsp_adjustment_values)
      clg_set_schs = {}
      heat_set_schs = {}
      # values = []
      # header = []
      nts = 0
      # thermostats = model.getThermostatSetpointDualSetpoints
      applicable_clg_thermostats.each do |thermostat|
        # setup new cooling setpoint schedule
        clg_set_sch = thermostat.coolingSetpointTemperatureSchedule
        heat_set_sch = thermostat.heatingSetpointTemperatureSchedule
        if !clg_set_sch.empty? && !heat_set_sch.empty?
          #puts("#{clg_set_sch.get.name.to_s}")
          #puts clg_set_sch.get
          # clone of not already in hash
          if clg_set_schs.key?(clg_set_sch.get.name.to_s)
            # exist
            new_clg_set_sch = clg_set_schs[clg_set_sch.get.name.to_s]
          else
            # new
            schedule = clg_set_sch.get.clone(model)
            schedule = schedule.to_Schedule.get
            schedule_heat = heat_set_sch.get.clone(model)
            schedule_heat = schedule_heat.to_Schedule.get
            #puts "cloned new name: #{schedule.name.to_s}"
            #puts schedule
            #puts schedule.class
            #puts schedule.to_ScheduleRuleset.class
            #puts schedule.to_ScheduleRuleset.get
            # puts("Populating existing schedule ruleset to 8760 schedules...")
            # header << clg_set_sch.get.name.to_s
            schedule_8760 = get_hourly_schedule_from_schedule_ruleset(model, schedule.to_ScheduleRuleset.get)
            schedule_8760_heat = get_hourly_schedule_from_schedule_ruleset(model, schedule_heat.to_ScheduleRuleset.get)
            # values << schedule_8760
            # puts("Update 8760 schedule...")
            # header << "#{clg_set_sch.get.name.to_s} adjusted"
            if schedule_8760.size != clgsp_adjustment_values.size
              msize = [schedule_8760.size, clgsp_adjustment_values.size].min
              nums = [schedule_8760.take(msize), clgsp_adjustment_values.take(msize)]
            else
              nums = [schedule_8760, clgsp_adjustment_values]
            end
            new_schedule_8760 = nums.transpose.map(&:sum)
            num_rows = new_schedule_8760.length
            # values << new_schedule_8760
            schedule_values = OpenStudio::Vector.new(num_rows, 0.0)
            new_schedule_8760.each_with_index do |val,i|
              # in case clg sp lower than heat sp
              schedule_values[i] = (val>schedule_8760_heat[i] ? val:(schedule_8760_heat[i]+1.0))
            end
            # infer interval
            interval = []
            if (num_rows == 8760) || (num_rows == 8784) #hourly data
              interval = OpenStudio::Time.new(0, 1, 0)
            elsif (num_rows == 35040) || (num_rows == 35136) # 15 min interval data
              interval = OpenStudio::Time.new(0, 0, 15)
            else
              runner.registerError('This measure does not support non-hourly or non-15 min interval data.  Cast your values as 15-min or hourly interval data.  See the values template.')
              return false
            end
            # puts("Make new interval schedule...")
            # make a schedule
            startDate = OpenStudio::Date.new(OpenStudio::MonthOfYear.new(1), 1)
            timeseries = OpenStudio::TimeSeries.new(startDate, interval, schedule_values, "C")
            new_clg_set_sch = OpenStudio::Model::ScheduleInterval::fromTimeSeries(timeseries, model)
            if new_clg_set_sch.empty?
              runner.registerError("Unable to make schedule")
              return false
            end
            new_clg_set_sch = new_clg_set_sch.get
            new_clg_set_sch.setName("#{clg_set_sch.get.name.to_s} adjusted")
            ### add to the hash
            clg_set_schs[clg_set_sch.get.name.to_s] = new_clg_set_sch
          end
          # hook up clone to thermostat
          # puts("Setting new schedule #{new_clg_set_sch.name.to_s}")
          thermostat.setCoolingSetpointTemperatureSchedule(new_clg_set_sch)
          nts += 1
        else
          runner.registerWarning("Thermostat '#{thermostat.name}' doesn't have cooling and heating setpoint schedules")
        end
      end
      return nts
    end

    def assign_heatsch_to_thermostats(model,applicable_htg_thermostats,runner,heatsp_adjustment_values)
      heat_set_schs = {}
      # values = []
      # header = []
      nts = 0
      # thermostats = model.getThermostatSetpointDualSetpoints
      applicable_htg_thermostats.each do |thermostat|
        # setup new cooling setpoint schedule
        heat_set_sch = thermostat.heatingSetpointTemperatureSchedule
        if !heat_set_sch.empty?
          #puts("#{heat_set_sch.get.name.to_s}")
          #puts heat_set_sch.get
          # clone of not already in hash
          if heat_set_schs.key?(heat_set_sch.get.name.to_s)
            # exist
            new_heat_set_sch = heat_set_schs[heat_set_sch.get.name.to_s]
          else
            # new
            schedule = heat_set_sch.get.clone(model)
            schedule = schedule.to_Schedule.get
            #puts "cloned new name: #{schedule.name.to_s}"
            #puts schedule
            #puts schedule.class
            #puts schedule.to_ScheduleRuleset.class
            #puts schedule.to_ScheduleRuleset.get
            # puts("Populating existing schedule ruleset to 8760 schedules...")
            # header << heat_set_sch.get.name.to_s
            schedule_8760 = get_hourly_schedule_from_schedule_ruleset(model, schedule.to_ScheduleRuleset.get)
            # values << schedule_8760
            # puts("Update 8760 schedule...")
            # header << "#{heat_set_sch.get.name.to_s} adjusted"
            if schedule_8760.size != heatsp_adjustment_values.size
              msize = [schedule_8760.size, heatsp_adjustment_values.size].min
              nums = [schedule_8760.take(msize), heatsp_adjustment_values.take(msize)]
            else
              nums = [schedule_8760, heatsp_adjustment_values]
            end
            new_schedule_8760 = nums.transpose.map(&:sum)
            num_rows = new_schedule_8760.length
            # values << new_schedule_8760
            schedule_values = OpenStudio::Vector.new(num_rows, 0.0)
            new_schedule_8760.each_with_index do |val,i|
              schedule_values[i] = val
            end
            # infer interval
            interval = []
            if (num_rows == 8760) || (num_rows == 8784) #hourly data
              interval = OpenStudio::Time.new(0, 1, 0)
            elsif (num_rows == 35040) || (num_rows == 35136) # 15 min interval data
              interval = OpenStudio::Time.new(0, 0, 15)
            else
              runner.registerError('This measure does not support non-hourly or non-15 min interval data.  Cast your values as 15-min or hourly interval data.  See the values template.')
              return false
            end
            # puts("Make new interval schedule...")
            # make a schedule
            startDate = OpenStudio::Date.new(OpenStudio::MonthOfYear.new(1), 1)
            timeseries = OpenStudio::TimeSeries.new(startDate, interval, schedule_values, "C")
            new_heat_set_sch = OpenStudio::Model::ScheduleInterval::fromTimeSeries(timeseries, model)
            if new_heat_set_sch.empty?
              runner.registerError("Unable to make schedule")
              return false
            end
            new_heat_set_sch = new_heat_set_sch.get
            new_heat_set_sch.setName("#{heat_set_sch.get.name.to_s} adjusted")
            ### add to the hash
            heat_set_schs[heat_set_sch.get.name.to_s] = new_heat_set_sch
          end
          # hook up clone to thermostat
          # puts("Setting new schedule #{new_heat_set_sch.name.to_s}")
          thermostat.setHeatingSetpointTemperatureSchedule(new_heat_set_sch)
          nts += 1
        else
          runner.registerWarning("Thermostat '#{thermostat.name}' doesn't have a cooling setpoint schedule")
        end
      end
      return nts
    end

    def isapplicable_buildingtype(model,runner,applicable_building_types)
      model_building_type = nil
      if model.getBuilding.standardsBuildingType.is_initialized
        model_building_type = model.getBuilding.standardsBuildingType.get
      else
        runner.registerError('model.getBuilding.standardsBuildingType is empty.')
        return false
      end
      # puts("--- model_building_type = #{model_building_type}")
      if !applicable_building_types.include?(model_building_type)#.downcase)
        # puts("&&& applicability not passed due to building type (buildings with large exhaust): #{model_building_type}")
        runner.registerAsNotApplicable("applicability not passed due to building type (office buildings): #{model_building_type}")
        return false
      elsif model_building_type == 'Office' || model_building_type == 'OfL' || model_building_type == 'OfS'
        # https://github.com/NREL/ComStock/blob/a541f15d27206f4e23d56be53ef8b7e154edda9e/postprocessing/comstockpostproc/cbecs.py#L309-L327
        model_building_floor_area_m2 = model.building.get.floorArea.to_f
        model_building_floor_area_sqft = OpenStudio.convert(model_building_floor_area_m2, 'm^2', 'ft^2').get
        # puts("--- model_building_floor_area_sqft = #{model_building_floor_area_sqft}")
        model_num_floor = nil
        buildingstories = model.building.get.buildingStories
        model_num_floor = buildingstories.size
        # puts("--- buildingstories = #{buildingstories}")
        # puts("--- model_num_floor = #{model_num_floor}")
        if model_building_floor_area_sqft < 25000
          if model_num_floor <= 3
              cstock_bldg_type = 'SmallOffice'
          else
              cstock_bldg_type = 'MediumOffice'
          end
        elsif model_building_floor_area_sqft >= 25000 && model_building_floor_area_sqft < 150000
          if model_num_floor <= 5
              cstock_bldg_type = 'MediumOffice'
          else
              cstock_bldg_type = 'LargeOffice'
          end
        elsif model_building_floor_area_sqft >= 150000
          cstock_bldg_type = 'LargeOffice'
        end
        puts("--- cstock_bldg_type = #{cstock_bldg_type}")
        if !applicable_building_types.include?(cstock_bldg_type)#.downcase)
          # puts("&&& applicability not passed due to building type (buildings with large exhaust): #{model_building_type}")
          runner.registerAsNotApplicable("applicability not passed due to building type (large office buildings): #{cstock_bldg_type}")
          return false
        else
          puts("--- applicability passed for building type: #{cstock_bldg_type}")
          return true
        end
      else
        puts("--- applicability passed for building type: #{model_building_type}")
        return true
      end
    end

    def applicable_thermostats(model)
      applicable_clg_thermostats = []
      applicable_htg_thermostats = []
      thermostats = model.getThermostatSetpointDualSetpoints
      thermostats.each do |thermostat|
        thermalzone = thermostat.to_Thermostat.get.thermalZone.get
        clg_fueltypes = thermalzone.coolingFuelTypes.map(&:valueName).uniq
        htg_fueltypes = thermalzone.heatingFuelTypes.map(&:valueName).uniq
        # puts("### DEBUGGING: clg_fueltypes = #{clg_fueltypes}")
        # puts("### DEBUGGING: htg_fueltypes = #{htg_fueltypes}")
        if clg_fueltypes == ["Electricity"]
          applicable_clg_thermostats << thermostat
        end
        if htg_fueltypes == ["Electricity"]
          applicable_htg_thermostats << thermostat
        end
      end
      return applicable_clg_thermostats, applicable_htg_thermostats, thermostats.size
    end

    puts("### ============================================================")
    puts("### Applicability check...")
    applicable_building_types = [
      # "Hotel",
      # "SmallOffice",
      # "MediumOffice",
      "LargeOffice",
      "OfL",
      "OfS",
      "Office"
    ]
    if isapplicable_buildingtype(model,runner,applicable_building_types)
      puts("--- building type applicability passed")
    else
      return true
    end
    applicable_clg_thermostats, applicable_htg_thermostats, nts = applicable_thermostats(model)
    # puts(applicable_clg_thermostats.size)
    # puts(applicable_htg_thermostats.size)
    if applicable_clg_thermostats.size > 0 && applicable_htg_thermostats.size > 0
      puts("--- electric cooling and heating applicability passed")
    elsif applicable_clg_thermostats.size > 0
      puts("--- electric cooling applicability passed")
    elsif applicable_htg_thermostats.size > 0
      puts("--- electric heating applicability passed")
    else
      runner.registerAsNotApplicable("applicability not passed for electric cooling or heating")
      return true
    end
    runner.registerInitialCondition("The building initially has #{nts} thermostats, of which #{applicable_clg_thermostats.size} are associated with electric cooling and #{applicable_htg_thermostats.size} are associated with electric heating.")
    ############################################
    # Load prediction
    ############################################
    puts("### ============================================================")
    puts("### Reading weather file...")
    year, oat = read_epw(model)
    puts("--- year = #{year}")
    puts("--- oat.size = #{oat.size}")
    if load_prediction_method == 'full baseline'
      puts("### ============================================================")
      puts("### Running full baseline for load prediction...")
      # start_time = Time.now
      annual_load = load_prediction_from_full_run(model, year=year, num_timesteps_in_hr=num_timesteps_in_hr)
      # end_time = Time.now
      # puts "Script execution time: #{end_time - start_time} seconds"
      # puts("--- annual_load = #{annual_load}")
      puts("--- annual_load.size = #{annual_load.size}")
    else
      ############################################
      # For bin-sample run
      ############################################
      puts("### ============================================================")
      puts("### Creating bins...")
      bins, selectdays, ns, max_doy = create_binsamples(oat)
      puts("--- bins = #{bins}")
      puts("--- selectdays = #{selectdays}")
      puts("--- ns = #{ns}")
      if load_prediction_method == 'bin sample'
        puts("### ============================================================")
        puts("### Running simulation on samples...")
        y_seed = run_samples(model, year, selectdays, num_timesteps_in_hr)
        puts("--- y_seed = #{y_seed}")
      elsif load_prediction_method == 'part year bin sample'
        puts("============================================================")
        puts("### Running simulation on part year samples...")
        y_seed = run_part_year_samples(model, year=year, max_doy=max_doy, selectdays=selectdays, num_timesteps_in_hr=num_timesteps_in_hr)#, epw_path=epw_path)
        # puts("--- y_seed = #{y_seed}")
      end
      puts("### ============================================================")
      puts("### Creating annual prediction...")
      annual_load = load_prediction_from_sample(y_seed, bins, year)
      # puts("--- annual_load = #{annual_load}")
      puts("--- annual_load.size = #{annual_load.size}")
    end

    puts("### ============================================================")
    puts("### Creating peak schedule...")
    # prepeak_schedule_winter = peak_schedule_generation(annual_load, oat, peak_len, rebound_len=0, prepeak_len=prepeak_len, seasons='winter')
    # prepeak_schedule_nonwinter = peak_schedule_generation(annual_load, oat, peak_len, rebound_len=0, prepeak_len=prepeak_len, seasons='nonwinter')
    prepeak_schedule = peak_schedule_generation(annual_load, oat, peak_len, rebound_len=0, prepeak_len=prepeak_len, seasons='all')
    # puts("--- prepeak_schedule = #{prepeak_schedule}")
    # puts("--- prepeak_schedule.size = #{prepeak_schedule.size}")
    
    puts("### ============================================================")
    nts_clg = 0
    nts_htg = 0
    if applicable_clg_thermostats.size > 0
      puts("### Creating cooling setpoint adjustment schedule...")
      clgsp_adjustment_values = temp_setp_adjust_hourly_based_on_sch(prepeak_schedule, sp_adjustment=-sp_adjustment)
      # clgsp_adjustment_values = temp_setp_adjust_hourly_based_on_sch(prepeak_schedule_nonwinter, sp_adjustment=-sp_adjustment)
      puts("### Updating thermostat cooling setpoint schedule...")
      nts_clg = assign_clgsch_to_thermostats(model,applicable_clg_thermostats,runner,clgsp_adjustment_values)
    end
    ### Leave pre-heating for future development
    # if applicable_htg_thermostats.size > 0
    #   puts("### Creating heating setpoint adjustment schedule...")
    #   # heatsp_adjustment_values = temp_setp_adjust_hourly_based_on_sch(prepeak_schedule, sp_adjustment=sp_adjustment)
    #   heatsp_adjustment_values = temp_setp_adjust_hourly_based_on_sch(prepeak_schedule_winter, sp_adjustment=sp_adjustment)
    #   puts("### Updating thermostat cooling setpoint schedule...")
    #   nts_htg = assign_heatsch_to_thermostats(model,applicable_htg_thermostats,runner,heatsp_adjustment_values)
    # end
    # puts("--- clgsp_adjustment_values = #{clgsp_adjustment_values}")
    # puts("--- heatsp_adjustment_values = #{heatsp_adjustment_values}")
    runner.registerFinalCondition("Updated #{nts_clg}/#{applicable_clg_thermostats.size} thermostat cooling setpoint schedules and #{nts_htg}/#{applicable_htg_thermostats.size} thermostat heating setpoint schedules to model, with #{sp_adjustment} degree C offset for #{prepeak_len} hours of daily pre-cooling/pre-heating before #{peak_len}-hour peak window, using #{load_prediction_method} simulation for load prediction")
    return true
  end
end

# register the measure to be used by the application
DfThermostatControlLoadShift.new.registerWithApplication
