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
class DFLightingControl < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'demand flexibility - lighting control'
  end

  # human readable description
  def description
    return 'This measure implements demand flexibility measure on daily lighting control with load shed strategy, by adjusting Lighting Power Density (reflecting lighting dimming) corresponding to the peak schedule based on daily peak load prediction.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    choices_obj = ['peak load', 'emission', 'utility bill cost', 'operational cost']
    demand_flexibility_objective = OpenStudio::Ruleset::OSArgument.makeChoiceArgument('demand_flexibility_objective', choices_obj, true)
    demand_flexibility_objective.setDisplayName("Objective of demand flexibility control (peak load, emission, utility bill cost, operational cost)")
    demand_flexibility_objective.setDefaultValue('peak load')
    args << demand_flexibility_objective 

    peak_len = OpenStudio::Measure::OSArgument.makeIntegerArgument('peak_len', true)
    peak_len.setDisplayName("Length of dispatch window (hour)")
    peak_len.setDefaultValue(4)
    args << peak_len

    light_adjustment_choices = ['absolute change', 'relative change']
    light_adjustment_method = OpenStudio::Ruleset::OSArgument.makeChoiceArgument('light_adjustment_method', light_adjustment_choices, true)
    light_adjustment_method.setDisplayName("Method of lighting dimming (absolute change, relative change)")
    light_adjustment_method.setDefaultValue('absolute change')
    args << light_adjustment_method

    light_adjustment = OpenStudio::Measure::OSArgument.makeDoubleArgument('light_adjustment', true)
    light_adjustment.setDisplayName("Percentage to decrease light dimming/LPD by (0-100)")
    light_adjustment.setDefaultValue(30.0)
    args << light_adjustment

    num_timesteps_in_hr = OpenStudio::Measure::OSArgument.makeIntegerArgument('num_timesteps_in_hr', true)
    num_timesteps_in_hr.setDisplayName("Number/Count of timesteps in an hour for sample simulations")
    num_timesteps_in_hr.setDefaultValue(4)
    args << num_timesteps_in_hr

    choices = ['full baseline', 'bin sample', 'part year bin sample', 'fix', 'oat']
    load_prediction_method = OpenStudio::Ruleset::OSArgument.makeChoiceArgument('load_prediction_method', choices, true)
    load_prediction_method.setDisplayName("Method of load prediction (full baseline run, bin sample, part year bin sample, fixed schedule, outdoor air temperature-based)")
    load_prediction_method.setDefaultValue('full baseline')
    args << load_prediction_method

    peak_lag = OpenStudio::Measure::OSArgument.makeIntegerArgument('peak_lag', true)
    peak_lag.setDisplayName("Time lag of peak responding to temperature peak (hour), for oat prediction method only")
    peak_lag.setDefaultValue(2)
    args << peak_lag

    choices_strate = ['max savings', 'start with peak', 'end with peak', 'center with peak']
    peak_window_strategy = OpenStudio::Ruleset::OSArgument.makeChoiceArgument('peak_window_strategy', choices_strate, true)
    peak_window_strategy.setDisplayName("Method of determining peak windows (max savings, start with peak, end with peak, center with peak)")
    peak_window_strategy.setDefaultValue('center with peak')
    args << peak_window_strategy

    choices_scenarios = [
      'AER_95DecarbBy2035',
      'AER_95DecarbBy2050',
      'AER_HighRECost',
      'AER_LowRECost',
      'AER_MidCase',
      'LRMER_95DecarbBy2035_15',
      'LRMER_95DecarbBy2035_30',
      'LRMER_95DecarbBy2035_15_2025start',
      'LRMER_95DecarbBy2035_25_2025start',
      'LRMER_95DecarbBy2050_15',
      'LRMER_95DecarbBy2050_30',
      'LRMER_HighRECost_15',
      'LRMER_HighRECost_30',
      'LRMER_LowRECost_15',
      'LRMER_LowRECost_30',
      'LRMER_LowRECost_15_2025start',
      'LRMER_LowRECost_25_2025start',
      'LRMER_MidCase_15',
      'LRMER_MidCase_30',
      'LRMER_MidCase_15_2025start',
      'LRMER_MidCase_25_2025start'
    ]
    cambium_scenario = OpenStudio::Ruleset::OSArgument.makeChoiceArgument('cambium_scenario', choices_scenarios, true)
    cambium_scenario.setDisplayName("Cambium emission scenario")
    cambium_scenario.setDefaultValue('LRMER_MidCase_15')
    args << cambium_scenario

    # apply_measure = OpenStudio::Measure::OSArgument.makeBoolArgument('apply_measure', true)
    # apply_measure.setDisplayName('Apply measure?')
    # apply_measure.setDescription('')
    # apply_measure.setDefaultValue(true)
    # args << apply_measure

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)  # Do **NOT** remove this line

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    ############################################
    # assign the user inputs to variables
    ############################################
    demand_flexibility_objective = runner.getStringArgumentValue("demand_flexibility_objective",user_arguments)
    peak_len = runner.getIntegerArgumentValue("peak_len",user_arguments)
    light_adjustment_method = runner.getStringArgumentValue("light_adjustment_method",user_arguments)
    light_adjustment = runner.getDoubleArgumentValue('light_adjustment', user_arguments)
    num_timesteps_in_hr = runner.getIntegerArgumentValue("num_timesteps_in_hr",user_arguments)
    load_prediction_method = runner.getStringArgumentValue("load_prediction_method",user_arguments)
    peak_lag = runner.getIntegerArgumentValue("peak_lag",user_arguments)
    peak_window_strategy = runner.getStringArgumentValue("peak_window_strategy",user_arguments)
    cambium_scenario = runner.getStringArgumentValue("cambium_scenario",user_arguments)

    def light_adj_based_on_sch(peak_sch, light_adjustment)
      light_adj_values = peak_sch.map{|a| 1-light_adjustment/100.0*a}
      return light_adj_values
    end
    
    def get_interval_schedule_from_schedule_ruleset(model, schedule_ruleset, size)
      # https://github.com/NREL/openstudio-standards/blob/9e6bdf751baedfe73567f532007fefe6656f5abf/lib/openstudio-standards/standards/Standards.ScheduleRuleset.rb#L696
      yd = model.getYearDescription
      start_date = yd.makeDate(1, 1)
      end_date = yd.makeDate(12, 31)
      values = []#OpenStudio::Vector.new
      if size == 8760 || size == 8784
        interval = OpenStudio::Time.new(1.0 / 24.0)#1h interval
      elsif size == 35040 || size == 35136
        interval = OpenStudio::Time.new(1.0 / 24.0 / 4.0)#15min interval
      else
        raise "Interval not supported"
      end
      day_schedules = schedule_ruleset.getDaySchedules(start_date, end_date)
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

    def adjust_lighting_sch(model,runner,light_adjustment_method,light_adj_values)
      yd = model.getYearDescription
      start_date = yd.makeDate(1, 1)
      lights = model.getLightss
      # create a hash to map the old schedule name to the new schedule
      light_schedules = {}
      nl = 0
      nla = 0
      lights.each do |light|
        puts "light: #{light.name}"
        light_sch = light.schedule
        # puts "light_sch: #{light_sch}"
        if light_sch.empty?
          runner.registerWarning("#{light.name} doesn't have a schedule.")
        else
          if light_schedules.key?(light_sch.get.name.to_s)
            new_light_sch = light_schedules[light_sch.get.name.to_s]
          else
            schedule = light_sch.get.clone(model)
            schedule = schedule.to_Schedule.get
            # convert old sch to time series
            schedule_ts = get_interval_schedule_from_schedule_ruleset(model, schedule.to_ScheduleRuleset.get, size=light_adj_values.size)
            if light_adjustment_method == 'absolute change'
              new_schedule_ts = schedule_ts.map.with_index { |val, ind| [val-(1.0-light_adj_values[ind]), 0].max}
            elsif light_adjustment_method == 'relative change'
              if schedule_ts.size <= light_adj_values.size
                new_schedule_ts = schedule_ts.map.with_index { |val, ind| val * light_adj_values[ind] }
              else
                new_schedule_ts = light_adj_values.map.with_index { |val, ind| val * schedule_ts[ind] }
              end
            else
              raise "Not supported light adjustment method"
            end
            schedule_values = OpenStudio::Vector.new(new_schedule_ts.length, 0.0)
            new_schedule_ts.each_with_index do |val,i|
              schedule_values[i] = val
            end
            # make a schedule
            if schedule_values.size == 35040 || schedule_values.size == 35136
              interval_hr = OpenStudio::Time.new(0, 0, 15)
            elsif schedule_values.size == 8760 || schedule_values.size == 8784
              interval_hr = OpenStudio::Time.new(0, 1, 0)
            else
              runner.registerError("Interval not supported")
              return false
            end
            timeseries = OpenStudio::TimeSeries.new(start_date, interval_hr, schedule_values, "C")
            new_light_sch = OpenStudio::Model::ScheduleInterval::fromTimeSeries(timeseries, model)
            # puts("###DEBUG new_light_sch=#{new_light_sch.get}")
            if new_light_sch.empty?
              runner.registerError("Unable to make schedule")
              return false
            end
            new_light_sch = new_light_sch.get
            new_light_sch.setName("#{light_sch.get.name.to_s} new")
            # add to the hash
            light_schedules[light_sch.get.name.to_s] = new_light_sch
          end
          light.setSchedule(new_light_sch)
          nla += 1
        end
        nl += 1
      end
      return nl, nla
    end
    
    def isapplicable_buildingtype(model,runner,applicable_building_types)
      model_building_type = nil
      if model.getBuilding.standardsBuildingType.is_initialized
        model_building_type = model.getBuilding.standardsBuildingType.get
      else
        runner.registerError('model.getBuilding.standardsBuildingType is empty.')
        return false
      end
      puts("--- model_building_type = #{model_building_type}")
      if !applicable_building_types.include?(model_building_type)#.downcase)
        runner.registerAsNotApplicable("applicability not passed due to building type (office buildings): #{model_building_type}")
        return false
      else
        puts("--- applicability passed for building type: #{model_building_type}")
        return true
      end
    end

    # # adding output variables (for debugging)
    # out_vars = [
    #   'Lights Electricity Energy',
    #   'Lights Electricity Rate',
    #   'Zone Lights Electricity Energy',
    #   'Zone Lights Electricity Rate',
    #   'Schedule Value'
    # ]
    # out_vars.each do |out_var_name|
    #     ov = OpenStudio::Model::OutputVariable.new('ov', model)
    #     ov.setKeyValue('*')
    #     ov.setReportingFrequency('timestep')
    #     ov.setVariableName(out_var_name)
    # end

    ############################################
    # Applicability check
    ############################################
    puts("### ============================================================")
    puts("### Applicability check...")
    applicable_building_types = [
      # "Hotel",
      "SmallOffice",
      "MediumOffice",
      "LargeOffice",
      "OfL",
      "OfS",
      "Office",
      "Warehouse",
      "PrimarySchool",
      "SecondarySchool"
    ]
    if isapplicable_buildingtype(model,runner,applicable_building_types)
      puts("--- building type applicability passed")
    else
      return true
    end
    runner.registerInitialCondition("The building is applicable for this measure.")

    # # applicability: don't apply measure if specified in input
    # if apply_measure == false
    #   runner.registerAsNotApplicable('Measure is not applied based on user input.')
    #   return true
    # end

    ############################################
    # Load prediction
    ############################################
    puts("### Reading weather file...")
    oat = read_epw(model)
    puts("--- oat.size = #{oat.size}")
    if load_prediction_method == 'full baseline'
      puts("### ============================================================")
      puts("### Running full baseline for load prediction...")
      annual_load = load_prediction_from_full_run(model, num_timesteps_in_hr=num_timesteps_in_hr)
      # puts("--- annual_load = #{annual_load}")
      puts("--- annual_load.size = #{annual_load.size}")
    elsif load_prediction_method.include?('bin sample')
      puts("### ============================================================")
      if load_prediction_method == 'bin sample'
        puts("### Creating bins...")
        bins, selectdays, ns, max_doy = create_binsamples(oat,'random')
        # puts("--- bins = #{bins}")
        # puts("--- selectdays = #{selectdays}")
        # puts("--- ns = #{ns}")
        puts("### ============================================================")
        puts("### Running simulation on samples...")
        y_seed = run_samples(model, year, selectdays, num_timesteps_in_hr)
        # puts("--- y_seed = #{y_seed}")
      elsif load_prediction_method == 'part year bin sample'
        puts("### Creating bins...")
        bins, selectdays, ns, max_doy = create_binsamples(oat,'sort')
        # puts("--- bins = #{bins}")
        # puts("--- selectdays = #{selectdays}")
        # puts("--- ns = #{ns}")
        puts("============================================================")
        puts("### Running simulation on part year samples...")
        y_seed = run_part_year_samples(model, max_doy=max_doy, selectdays=selectdays, num_timesteps_in_hr=num_timesteps_in_hr)#, epw_path=epw_path)
        # puts("--- y_seed = #{y_seed}")
      end
      puts("### ============================================================")
      puts("### Creating annual prediction...")
      annual_load = load_prediction_from_sample(model, y_seed, bins)
      # puts("--- annual_load = #{annual_load}")
      puts("--- annual_load.size = #{annual_load.size}")
    else
      puts("### ============================================================")
      puts("### No load prediction needed...")
    end

    ############################################
    # Emission prediction
    ############################################
    
    if demand_flexibility_objective == 'emission'
      puts("### ============================================================")
      puts("### Predicting emission...")
      egrid_co2e_kg_per_mwh, cambium_co2e_kg_per_mwh = read_emission_factors(model, scenario=cambium_scenario)
      if cambium_co2e_kg_per_mwh == []
        hourly_emissions_kg = emission_prediction(annual_load, factor=egrid_co2e_kg_per_mwh, num_timesteps_in_hr=num_timesteps_in_hr)
      else
        hourly_emissions_kg = emission_prediction(annual_load, factor=cambium_co2e_kg_per_mwh, num_timesteps_in_hr=num_timesteps_in_hr)
      end
      puts("--- hourly_emissions_kg.size = #{hourly_emissions_kg.size}")
    end

    ############################################
    # Generate peak schedule
    ############################################
    puts("### ============================================================")
    puts("### Creating peak schedule...")
    if demand_flexibility_objective == 'peak load'
      puts("### Creating peak schedule for peak load reduction...")
      if load_prediction_method == 'fix'
        puts("### Fixed schedule...")
        template = 'ComStock 90.1-2019'
        std = Standard.build(template)
        climate_zone = std.model_standards_climate_zone(model)
        runner.registerInfo("climate zone = #{climate_zone}")
        if climate_zone.empty?
          runner.registerError('Unable to determine climate zone for model. Cannot apply window film without climate zone information.')
        else
          if climate_zone.include?("CEC")
            climate_zone_num_ca = climate_zone.split("CEC")[-1]
            puts "--- climate_zone_num_ca = #{climate_zone_num_ca}"
            cz = map_cec_to_iecc[climate_zone_num_ca.to_i]
          elsif climate_zone.include?("ASHRAE")
            cz = climate_zone.split("-")[-1]
          else
            runner.registerError('Unable to determine climate zone for model. Cannot apply window film without climate zone information.')
          end
        end
        puts "--- cz = #{cz}"
        peak_schedule, peak_schedule_htg = peak_schedule_generation_fix(cz, oat, rebound_len=0, prepeak_len=0, season='all')
      elsif load_prediction_method == 'oat'
        puts("### OAT-based schedule...")
        peak_schedule, peak_schedule_htg = peak_schedule_generation_oat(oat, peak_len, peak_lag=peak_lag, rebound_len=rebound_len, prepeak_len=0, season='all')
      else
        puts("### Predictive schedule...")
        peak_schedule = peak_schedule_generation(annual_load, oat, peak_len, num_timesteps_in_hr=num_timesteps_in_hr, peak_window_strategy=peak_window_strategy, rebound_len=0, prepeak_len=0, season='all')
      end
    elsif demand_flexibility_objective == 'emission'
      puts("### Creating peak schedule for emission reduction...")
      peak_schedule = peak_schedule_generation(hourly_emissions_kg, oat, peak_len, num_timesteps_in_hr=1, peak_window_strategy=peak_window_strategy, rebound_len=0, prepeak_len=0, season='all')
    else
      runner.registerError('Not supported objective.')
    end

    # puts("--- peak_schedule = #{peak_schedule}")
    puts("--- peak_schedule.size = #{peak_schedule.size}")

    ############################################
    # Update lighting schedule 
    ############################################
    puts("### ============================================================")
    puts("### Creating lighting factor values...")
    light_adj_values = light_adj_based_on_sch(peak_schedule, light_adjustment)
    # puts("--- light_adj_values = #{light_adj_values}")
    puts("--- light_adj_values.size = #{light_adj_values.size}")
    puts("### Updating lighting schedule...")
    nl, nla = adjust_lighting_sch(model,runner,light_adjustment_method,light_adj_values)

    runner.registerFinalCondition("Updated #{nla}/#{nl} lighting schedules")
    return true
  end
end

# register the measure to be used by the application
DFLightingControl.new.registerWithApplication
