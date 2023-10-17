# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.


# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class AddThermostatSetpointVariability < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'add_thermostat_setpoint_variability'
  end

  # human readable description
  def description
    return 'Measure will alter the models current thermostat setpoint and setback behavior. If user selects no_setback, the measure will remove heating and cooling thermostat setbacks if they exist. If the user selects setback, the model will add setbacks if none exist. The measure will also alter a models setpoint and setback delta based on user-input values. MEASURE SHOULD BE USED WITH SQUARE-WAVE SCHEDULES ONLY.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Measure will alter the models current thermostat setpoint and setback behavior. If user selects no_setback, the measure will remove heating and cooling thermostat setbacks if they exist. If the user selects setback, the model will add setbacks if none exist. The measure will also alter a models setpoint and setback delta based on user-input values. MEASURE SHOULD BE USED WITH SQUARE-WAVE SCHEDULES ONLY. '
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument for window U-Value
    clg_sp_f = OpenStudio::Measure::OSArgument.makeDoubleArgument('clg_sp_f', true)
    clg_sp_f.setDefaultValue('999')
    clg_sp_f.setDisplayName('Cooling Thermostat Occupied Setpoint')
    clg_sp_f.setDescription('Enter 999 for no change to setpoint.')
    clg_sp_f.setUnits('F')
    args << clg_sp_f

    # make an argument for window U-Value
    clg_delta_f = OpenStudio::Measure::OSArgument.makeDoubleArgument('clg_delta_f', true)
    clg_delta_f.setDefaultValue('999')
    clg_delta_f.setDisplayName('Cooling Thermostat Delta Setback')
    clg_delta_f.setDescription('Enter 999 for no change to setback.')
    clg_delta_f.setUnits('F')
    args << clg_delta_f

    # make an argument for window U-Value
    htg_sp_f = OpenStudio::Measure::OSArgument.makeDoubleArgument('htg_sp_f', true)
    htg_sp_f.setDefaultValue('999')
    htg_sp_f.setDisplayName('Heating Thermostat Occupied Setpoint')
    htg_sp_f.setDescription('Enter 999 for no change to setpoint.')
    htg_sp_f.setUnits('F')
    args << htg_sp_f

    # make an argument for window U-Value
    htg_delta_f = OpenStudio::Measure::OSArgument.makeDoubleArgument('htg_delta_f', true)
    htg_delta_f.setDefaultValue('999')
    htg_delta_f.setDisplayName('Heating Thermostat Delta Setback')
    htg_delta_f.setDescription('Enter 999 for no change to setback.')
    htg_delta_f.setUnits('F')
    args << htg_delta_f

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
    clg_sp_f = runner.getDoubleArgumentValue('clg_sp_f', user_arguments)
    clg_delta_f = runner.getDoubleArgumentValue('clg_delta_f', user_arguments)
    htg_sp_f = runner.getDoubleArgumentValue('htg_sp_f', user_arguments)
    htg_delta_f = runner.getDoubleArgumentValue('htg_delta_f', user_arguments)

    # make conversions for cooling
    clg_sp_c = OpenStudio.convert(clg_sp_f, 'F', 'C').get
    clg_sb_f = clg_sp_f + clg_delta_f
    clg_delta_c = (5/9r)*clg_delta_f
    clg_sb_c = OpenStudio.convert(clg_sb_f, 'F', 'C').get

    # make conversions for heating
    if (htg_sp_f > (clg_sp_f - 2)) && (clg_sb_f != 999) && (htg_sp_f != 999)
      runner.registerWarning("User-input heating setpoint of #{htg_sp_f}F is > 2F from the user-input cooling setpoint of #{clg_sp_f}F which is not permitted. The user-input heating setpoint is now #{clg_sp_f  - 2}F to allow a reasonable deadband range.")
      htg_sp_f = clg_sp_f - 2
    end

    # make conversions for heating
    htg_sp_c = OpenStudio.convert(htg_sp_f, 'F', 'C').get
    htg_sb_f = htg_sp_f - htg_delta_f
    htg_delta_c = (5/9r)*htg_delta_f
    htg_sb_c = OpenStudio.convert(htg_sb_f, 'F', 'C').get

    # Write 'As Not Applicable' message
    if model.getThermalZones.empty?
      runner.registerAsNotApplicable('There are no conditioned thermal zones in the model. Measure is not applicable.')
      return true
    end

    if (clg_sp_f == 999) && (clg_delta_f == 999) && (htg_sp_f == 999) && (htg_delta_f == 999)
      runner.registerAsNotApplicable('All arugments are set to 999 which registers no change to model.')
      return true
    end

    # Initialize variables
    zone_count = 0
    edited_clg_tstat_schedules = []
    edited_htg_tstat_schedules = []

    # Get the thermal zones and loop through them
    model.getThermalZones.each do |thermal_zone|

      # skip data centers
      next if ['Data Center', 'DataCenter', 'data center', 'datacenter'].any? { |word| (thermal_zone.name.get).include?(word) }

      if thermal_zone.thermostatSetpointDualSetpoint.is_initialized
        zone_thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
        zone_count += 1

        if zone_thermostat.coolingSetpointTemperatureSchedule.is_initialized && ((clg_sp_f != 999) || (clg_delta_f != 999))

          clg_tstat_schedule = zone_thermostat.coolingSetpointTemperatureSchedule.get

          # check if already edited
          next if edited_clg_tstat_schedules.include? "#{clg_tstat_schedule.name}"
          edited_clg_tstat_schedules << clg_tstat_schedule.name.get
          clg_tstat_schedule.to_ScheduleRuleset.is_initialized
          clg_tstat_schedule = clg_tstat_schedule.to_ScheduleRuleset.get

          # Gather schedule profiles
          schedule_profiles = []
          default_profile = clg_tstat_schedule.to_ScheduleRuleset.get.defaultDaySchedule
          schedule_profiles << default_profile
          clg_tstat_schedule.scheduleRules.each { |rule| schedule_profiles << rule.daySchedule }

          # get min and max of profiles
          clg_sch_values = []
          schedule_profiles.sort.each do |profile|
            clg_sch_values << profile.values
          end
          clg_sch_values = clg_sch_values.flatten
          clg_tstat_schedule_min = clg_sch_values.min()
          clg_tstat_schedule_max = clg_sch_values.max()
          clg_tstat_schedule_n_values = clg_sch_values.uniq.size

          # puts '---SCHEDULE START---'
          # puts "Schedule Name: #{clg_tstat_schedule.name}"
          # puts "Schedule Size: #{clg_tstat_schedule_n_values}"
          # puts "Cooling SP: #{clg_sp_c}"
          # puts "Cooling SB: #{clg_sb_c}"
          # puts "Schedule Min: #{clg_tstat_schedule_min}"
          # puts "Schedule Max: #{clg_tstat_schedule_max}"
          # puts '---SCHEDULE END---'


          # skip is setpoint value is over 90F, aka no cooling
          if clg_tstat_schedule_min < 32.2222

            if clg_tstat_schedule_n_values == 1
              runner.registerWarning("Cooling schedule #{clg_tstat_schedule.name} only has 1 temperature setpoint and is therefore not applicable for adding any setbacks to the temperature schedules. User-input temperature setpoints will still be applied.")
            end

            # set design day schedules
            if clg_sp_f != 999
              des_day = OpenStudio::Model::ScheduleDay.new(model, clg_sp_c)
              clg_tstat_schedule.setSummerDesignDaySchedule(des_day)
              clg_tstat_schedule.setWinterDesignDaySchedule(des_day)
            end

            # Loop through schedules and make changes
            schedule_profiles.sort.each do |profile|
              # puts profile.name
              profile_name = profile.name
              profile_min = profile.values.min
              profile_max = profile.values.max
              profile_size = profile.values.uniq.size
              time_h =  profile.times

              # if no change is desired, use original setpoint temperatures for cooling
              if clg_sp_f == 999
                clg_sp_c = clg_tstat_schedule_min
                if clg_delta_f != 999
                  clg_sb_c = clg_tstat_schedule_min + clg_delta_c
                end
              end
              if clg_delta_f == 999
                clg_sb_c = clg_tstat_schedule_max
              end

              # If profile is constant sched that matches minimum schedule value (i.e. occupied cooling setpoint)
              if (profile_size == 1) && (profile_min == clg_tstat_schedule_min)
                # runner.registerWarning("For #{clg_tstat_schedule.name} cooling thermostat schedule, cooling profile #{profile_name} is constant with a value of #{OpenStudio.convert(profile_min, 'C', 'F').get.round(1)}F, which matches the original occupied temperature setpoint for this schedule. This schedule will be changed to match user-input cooling setpoint temperature #{clg_sp_f}F. No setback will be added.")
                i=0
                profile.values.each do |value|
                  profile.addValue(time_h[i], clg_sp_c)
                  i+=1
                end

              # If profile is constant sched that matches minimum schedule value (i.e. occupied cooling setpoint)
              elsif (profile_size == 1) && (profile_max == clg_tstat_schedule_max)
                # runner.registerWarning("For #{clg_tstat_schedule.name} cooling thermostat schedule, cooling profile #{profile_name} is constant with a value of #{OpenStudio.convert(profile_max, 'C', 'F').get.round(1)}F, which matches the original setback setpoint for this schedule. This schedule will be changed to match the user-input unnocupied cooling setback delta of #{clg_delta_f}F, if one was specified.")
                # time_h = profile.times
                i=0
                profile.values.each do |value|
                  profile.addValue(time_h[i], clg_sb_c)
                  i+=1
                end

              # If profile is constant and does not match max or min
              elsif (profile_size == 1) && ((profile_max != clg_tstat_schedule_max) || (profile_min == clg_tstat_schedule_min))
                runner.registerWarning("For #{clg_tstat_schedule.name} cooling thermostat schedule, cooling profile #{profile_name} is constant with a value of #{OpenStudio.convert(profile_max, 'C', 'F').get.round(1)}F, which does not match the max or min of the original profile, making it unknown if this is an occupied or unnocupied setpoint. Profile will not be changed.")

              # If profile is square wave (2 setpoints, occupied vs unoccupied)
              elsif (profile_size == 2)
                time_h=profile.times
                i=0
                profile.values.each do |value|
                  if value == clg_tstat_schedule_min
                    profile.addValue(time_h[i], clg_sp_c)
                    i+=1
                  else value == clg_tstat_schedule_max
                    profile.addValue(time_h[i], clg_sb_c)
                    i+=1
                  end
                end

              # If profile is not square wave (i.e. more than two setpoints)
              elsif (profile_size > 2)
                values = profile.values
                values_uniq_ramps = values - [profile_min, profile_max]

                # create hash of ramp values and their proportion to original setpoint and setback
                ramp_fracs = {}
                values_uniq_ramps.sort.each do |ramp|
                  ramp_fracs[ramp] = (ramp - profile_min) / (profile_max - profile_min)
                end

                # Loop through profiles and add new setpoints
                i=0
                profile.values.each do |value|
                  # add values for profile minimum
                  if value == profile_min
                    profile.addValue(time_h[i], clg_sp_c)
                    i+=1
                  # add values for profile maximum
                  elsif value == profile_max
                    profile.addValue(time_h[i], clg_sb_c)
                    i+=1
                  # add values for ramps
                  else
                    ramp_new = (ramp_fracs[value] * clg_delta_c) + clg_sp_c
                    profile.addValue(time_h[i], ramp_new)
                    i+=1
                  end
                end
              end
            end
          else
            runner.registerWarning(("Cooling schedule #{clg_tstat_schedule.name} has a minimum setpoint over 90F, and therefore is not applicable for this measure as it is likely a non-cooled zone. It will be skipped."))
          end
        end

        # repeat for heating thermostats
        if zone_thermostat.heatingSetpointTemperatureSchedule.is_initialized && ((htg_sp_f != 999) || (htg_delta_f != 999))
          htg_tstat_schedule = zone_thermostat.heatingSetpointTemperatureSchedule.get

          # check if already edited
          next if edited_htg_tstat_schedules.include? "#{htg_tstat_schedule.name}"
          edited_htg_tstat_schedules << htg_tstat_schedule.name.get
          htg_tstat_schedule.to_ScheduleRuleset.is_initialized
          htg_tstat_schedule = htg_tstat_schedule.to_ScheduleRuleset.get

          # Gather schedule profiles
          schedule_profiles = []
          default_profile = htg_tstat_schedule.to_ScheduleRuleset.get.defaultDaySchedule
          schedule_profiles << default_profile
          htg_tstat_schedule.scheduleRules.each { |rule| schedule_profiles << rule.daySchedule }

          # get min and max of profiles
          htg_sch_values = []
          schedule_profiles.sort.each do |profile|
            htg_sch_values << profile.values
          end
          htg_sch_values = htg_sch_values.flatten
          htg_tstat_schedule_min = htg_sch_values.min()
          htg_tstat_schedule_max = htg_sch_values.max()
          htg_tstat_schedule_n_values = htg_sch_values.uniq.size

          # skip if maximum setpoint is < 60 F, AKA partially or unheated
          if htg_tstat_schedule_max >= 15.5556
            if htg_tstat_schedule_n_values == 1
              runner.registerWarning("Heating schedule #{htg_tstat_schedule.name} only has 1 temperature setpoint, and is therefore not applicable for adding any setbacks to the temperature schedules. User-input occupied temperature setpoints will still be applied.")
            end

            # set design day schedules
            if htg_sp_f != 999
              des_day = OpenStudio::Model::ScheduleDay.new(model, htg_sp_c)
              htg_tstat_schedule.setSummerDesignDaySchedule(des_day)
              htg_tstat_schedule.setWinterDesignDaySchedule(des_day)
            end

            # Loop through schedules and make changes
            schedule_profiles.sort.each do |profile|
              profile_name = profile.name
              profile_min = profile.values.min
              profile_max = profile.values.max
              profile_size = profile.values.uniq.size
              time_h =  profile.times
              # if no change is desired, use original setpoint temperatures for cooling
              if htg_sp_f == 999
                htg_sp_c = htg_tstat_schedule_max
                if htg_delta_f != 999
                  htg_sb_c = htg_tstat_schedule_max - htg_delta_c
                end
              end
              if htg_delta_f == 999
                htg_sb_c = htg_tstat_schedule_min
              end

              # If profile is constant sched that matches maximum schedule value (i.e. occupied heating setpoint)
              if (profile_size == 1) && (profile_min == htg_tstat_schedule_max)
                runner.registerWarning("For #{htg_tstat_schedule.name} heating thermostat schedule, heating profile #{profile_name} is constant with a value of #{OpenStudio.convert(profile_max, 'C', 'F').get.round(1)}F, which matches the original occupied setpoint temperature for this schedule. This schedule will be changed to match user-input occupied heating setpoint temperature of #{htg_sp_f}F. No setback will be added.")
                time_h =  profile.times
                i=0
                profile.values.each do |value|
                  profile.addValue(time_h[i], htg_sp_c)
                  i+=1
                end
              # If profile is constant sched that matches minimum schedule value (i.e. unoccupied heating setpoint)
              elsif (profile_size == 1) && (profile_max == htg_tstat_schedule_min)
                runner.registerWarning("For #{htg_tstat_schedule.name} heating thermostat schedule, heating profile #{profile_name} is constant with a value of #{OpenStudio.convert(profile_min, 'C', 'F').get.round(1)}F, which matches the original unnocupied setback temperature for this schedule. This schedule will be changed to match the user-input unnocupied heating setback delta of #{htg_delta_f}F, if one was specified.")
                time_h =  profile.times
                i=0
                profile.values.each do |value|
                  profile.addValue(time_h[i], htg_sb_c)
                  i+=1
                end
              # If profile is constant and does not match max or min
              elsif (profile_size == 1) && ((profile_max != htg_tstat_schedule_min) || (profile_min == htg_tstat_schedule_min))
                runner.registerWarning("For #{htg_tstat_schedule.name} heating thermostat schedule, heating profile #{profile_name} is constant with a value of #{OpenStudio.convert(profile_max, 'C', 'F').get.round(1)}F, which does not match the max or min of the original profile, making it unknown if this is an occupied or unnocupied setpoint. Profile will not be changed.")
              # If profile is square wave with 2 setpoints
              elsif (profile_size == 2)
                time_h=profile.times
                i=0
                profile.values.each do |value|
                  if value == htg_tstat_schedule_max
                    profile.addValue(time_h[i], htg_sp_c)
                    i+=1
                  else
                    profile.addValue(time_h[i], htg_sb_c)
                    i+=1
                  end
                end
              # If profile is not square wave (i.e. more than two setpoints)
              elsif profile_size > 2
                values = profile.values
                values_uniq_ramps = values - [profile_min, profile_max]

                # create hash of ramp values and their proportion to original setpoint and setback
                ramp_fracs = {}
                values_uniq_ramps.sort.each do |ramp|
                  ramp_fracs[ramp] = (ramp - profile_min) / (profile_max - profile_min)
                end

                # Loop through profiles and add new setpoints
                i=0
                profile.values.each do |value|
                  # add values for profile minimum (heating setback)
                  if value == profile_min
                    profile.addValue(time_h[i], htg_sb_c)
                    i+=1
                  # add values for profile maximum (heating setpoint)
                  elsif value == profile_max
                    profile.addValue(time_h[i], htg_sp_c)
                    i+=1
                  # add values for ramps
                  else
                    ramp_new = (ramp_fracs[value] * htg_delta_c) + htg_sb_c
                    profile.addValue(time_h[i], ramp_new)
                    i+=1
                  end
                end
              end
            end
          else
          runner.registerWarning(("Heating schedule #{htg_tstat_schedule.name} has a maximum setpoint under 60F, and therefore is not applicable for this measure as it is likely a partially-heated zone. It will be skipped."))
          end
        end
      end
    end

    # report initial condition of model
    runner.registerInitialCondition("The building started with #{edited_clg_tstat_schedules.size} unique cooling thermostat schedules and #{edited_htg_tstat_schedules.size} unique heating thermostat schedules. User-input occupied cooling setpoint is #{clg_sp_f}F with a #{clg_delta_f}F unnocupied setpoint delta. User-input heating occupied setpoint is #{htg_sp_f}F with a #{htg_delta_f}F unnocupied setpoint delta. A value of 999 indicates no user-specified change.")

    # report final condition of model
    runner.registerFinalCondition("#{edited_clg_tstat_schedules.size} cooling and #{edited_htg_tstat_schedules.size} heating schedules have been changed in accordance to user inputs.")

    return true
  end
end

# register the measure to be used by the application
AddThermostatSetpointVariability.new.registerWithApplication
