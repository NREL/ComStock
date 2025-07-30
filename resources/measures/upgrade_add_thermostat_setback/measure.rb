# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

Dir[File.dirname(__FILE__) + '/resources/*.rb'].each { |file| require file }
# start the measure
class UpgradeAddThermostatSetback < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Upgrade_Add_Thermostat_Setback'
  end

  # human readable description
  def description
    return ''
  end

  # human readable description of modeling approach
  def modeler_description
    return ''
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new
	
	clg_setback = OpenStudio::Measure::OSArgument.makeIntegerArgument('clg_setback', true)
    clg_setback.setDisplayName('Cooling setback magnitude')
    clg_setback.setDescription('Setback magnitude in cooling.')
    args << clg_setback

    htg_setback = OpenStudio::Measure::OSArgument.makeIntegerArgument('htg_setback', true)
    htg_setback.setDisplayName('Heating setback magnitude')
    htg_setback.setDescription('Setback magnitude in heating.')
    args << htg_setback
	
	opt_start_chs = OpenStudio::StringVector.new
    opt_start_chs << '1.5 hour ramp'
    opt_start_chs << '3 hour ramp'
    opt_start_chs << 'None'
    opt_start_type = OpenStudio::Measure::OSArgument.makeChoiceArgument('opt_start_type', opt_start_chs, true)
    opt_start_type.setDisplayName('Optimum start type')
    opt_start_type.setDefaultValue('3 hour ramp')
	args << opt_start_type 
	
	htg_min = OpenStudio::Measure::OSArgument.makeIntegerArgument('htg_min', true)
    htg_min.setDisplayName('Minimum heating setpoint')
    htg_min.setDescription('Minimum heating setpoint')
    args << htg_min
	
	clg_max = OpenStudio::Measure::OSArgument.makeIntegerArgument('clg_max', true)
    clg_max.setDisplayName('Maximum cooling setpoint')
    clg_max.setDescription('Maximum cooling setpoint')
    args << clg_max

    return args
  end
  

  def opt_start?(sch_zone_occ_annual_profile, htg_schedule_annual_profile, min_value, max_value, idx)
    # method to determine if a thermostat schedule contains part of an optimum start sequence at a given index
    if (sch_zone_occ_annual_profile[idx + 1] == 1 || sch_zone_occ_annual_profile[idx + 2] == 1) &&
       (htg_schedule_annual_profile[idx] > min_value && htg_schedule_annual_profile[idx] < max_value)
      true
    end
  end
  
  def valid_tstat_schedule(sched, type, zone)
    valid = true 
	if sched.empty?
	runner.registerWarning("#{type} setpoint schedule not found for zone '#{zone.name.get}'")
	valid = false
	next
   elsif sched.get.to_ScheduleRuleset.empty?
	runner.registerWarning("Schedule '#{sched.name}' is not a ScheduleRuleset, will not be adjusted")
	valid = false
	end
	
	return valid 
end 

def mod_schedule(tstat_sched, sched_zone_occ, type, setback_val, lim_value) #TODO: need to take model as input? 
	schedule_annual_profile = get_8760_values_from_schedule_ruleset(model, sched)
	sch_zone_occ_annual_profile = get_8760_values_from_schedule_ruleset(model, sched_zone_occ)
	schedule_annual_profile_updated = OpenStudio::DoubleVector.new
	schedule_annual_profile.each_with_index do |_val, idx| # Create new profile based on occupancy
	  # Find maximum value of schedule for the particular week
	  week_values = schedule_annual_profile.each_slice(168).to_a[(idx / 168).round]
	  max_value = week_values.max
	  min_value = week_values.min
	  # Check for case where setpoint is adjusted for an optimum start, and skip
	  # Need at least two more timesteps in the profile to perform optimum start check
	  # Final two timesteps of year will not be optimum start, anyway
	  if (idx < schedule_annual_profile.size - 2) && opt_start?(sch_zone_occ_annual_profile,
																	schedule_annual_profile,
																	min_value,
																	max_value,
																	idx)
		next
	  end
      if type == 'heating' 
	    schedule_annual_profile_updated[idx] = if sch_zone_occ_annual_profile[idx].zero? #If unoccupied, apply setback 
												   (max_value - setback_val, lim_value).max 
												 else
												   max_value # keeping same setback regime
												 end
	 elsif type == 'cooling'
	    schedule_annual_profile_updated[idx] = if sch_zone_occ_annual_profile[idx].zero? #If unoccupied, apply setback 
												   (min_value + setback_val, lim_value).min 
												 else
												   min_value # keeping same setback regime
												 end
     end 
	    
	end
	tstat_sch_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
	tstat_sch_limits.setUnitType('Temperature')
	tstat_sch_limits.setNumericType('Continuous')
    sch_new = make_ruleset_sched_from_8760(model, runner, schedule_annual_profile_updated,
											   "#{tstat_sched.name} Modified Setpoints", tstat_sch_limits)
	# Handle behavior on last day of year--above method makes a schedule ruleset
	# that has a schedule with a specified day
	# of week for 12/31 that isn't intended
	# On leap years, need to correct separate rule made for 12/30 and 12/31
	model_year = model.getYearDescription.assumedYear
	dec_29_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 29, model_year)
	dec_30_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 30, model_year)
	dec_31_date = OpenStudio::Date.new(OpenStudio::MonthOfYear.new('December'), 31, model_year)
	for tstat_rule in sch_new.scheduleRules
	  if tstat_rule.endDate.get == dec_30_date ||
		 (tstat_rule.endDate.get == dec_29_date)
		tstat_rule.setEndDate(dec_31_date)
	  end
	  next unless ((tstat_rule.endDate.get == dec_31_date) &&
							 (tstat_rule.startDate.get == dec_31_date)) || ((tstat_rule.endDate.get == dec_31_date) && (tstat_rule.startDate.get == dec_30_date))

	  tstat_rule.remove
	 end
return sch_new  

def has_setback(tstat_profiles_stats)
     has_setback = false
     for profile in tstat_profiles_stats[:profiles]
            sched_min = profile.values.min
            sched_max = profile.values.max
            has_setback = true if sched_max > sched_min
          end
	  return has_setback 
    end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)  # Do **NOT** remove this line

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    clg_setback = runner.getIntegerArgumentValue('clg_setback', user_arguments)
	htg_setback = runner.getIntegerArgumentValue('htg_setback', user_arguments)
    opt_start_type = runner.getStringArgumentValue('opt_start_type', user_arguments)
	clg_max = runner.getIntegerArgumentValue('clg_max', user_arguments)
	htg_min = runner.getIntegerArgumentValue('htg_min', user_arguments)

	
	
	#add in heating setback, add in for cooling, and compare against max/min setpoints 
	#optimum start 
	
     space_types_no_setback = [
        # 'Kitchen',
        # 'kitchen',
        'PatRm',
        'PatRoom',
        'Lab',
        'Exam',
        'PatCorridor',
        'BioHazard',
        'Exam',
        'OR',
        'PreOp',
        'Soil Work',
        'Trauma',
        'Triage',
        # 'PhysTherapy',
        'Data Center',
		'data center', 
        # 'CorridorStairway',
        # 'Corridor',
        'Mechanical',
        # 'Restroom',
        'Entry',
        # 'Dining',
        'IT_Room',
        # 'LockerRoom',
        # 'Stair',
        'Toilet',
        'MechElecRoom',
        'Guest Room',
        'guest room'
      ]
	
	  #Convert setback and threshold values to C 
	  clg_setback_c = clg_setback *5/9
	  htg_setback_c = htg_setback *5/9
	  htg_min_c = htg_min * 5/9
	  clg_max_c = clg_max * 5/9 
	  
	  model.getAirLoopHVACs.each do |air_loop_hvac| #iterate thru air loops 
	  # skip DOAS units; check sizing for all OA and for DOAS in name
      sizing_system = air_loop_hvac.sizingSystem
      if sizing_system.allOutdoorAirinCooling && sizing_system.allOutdoorAirinHeating && (air_loop_res?(air_loop_hvac) == false) && (air_loop_hvac.name.to_s.include?('DOAS') || air_loop_hvac.name.to_s.include?('doas'))
        next
      end
	  zones = air_loop_hvac.thermalZones
        zones.sort.each do |thermal_zone|
          no_people_obj = false # flag for not having People object associated with it
          zone_space_types = []
          thermal_zone.spaces.each do |space| # check for space types this measure won't apply to
            zone_space_types << space.spaceType.get.name.to_s
          end

          skip_space_types = space_types_no_setback.any? do |substring|
            zone_space_types.any? do |str|
              str.include?(substring)
            end
          end

          no_people_obj = true if thermal_zone.numberOfPeople.zero?

          if skip_space_types
            next # go to the next zone if this zone has space types that are skipped for the setback
          end

          next unless thermal_zone.thermostatSetpointDualSetpoint.is_initialized

          zone_thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
          htg_schedule = zone_thermostat.heatingSetpointTemperatureSchedule
		  clg_schedule = zone_thermostat.coolingSetpointTemperatureSchedule
		  #Confirm schedules are valid 
		  htg_valid = valid_tstat_schedule(htg_schedule, zone, "heating") 
		  clg_valid = valid_tstat_schedule(clg_schedule, zone, "cooling")
		  if !htg_valid and !clg_valid
		     next #skip to the next zone if no valid schedules 
		  elsif htg_valid 
		        htg_schedule = htg_schedule.get.to_ScheduleRuleset.get
		  elsif clg_valid 
			clg_schedule = clg_schedule.get.to_ScheduleRuleset.get
		  end 
		  
		  #check for validity later on too 
      
          sch_zone_occ = OpenstudioStandards::ThermalZone.thermal_zones_get_occupancy_schedule(
            [thermal_zone], occupied_percentage_threshold: 0.05
          )
		  
		  # Determine if setbacks present
		  if htg_valid 
           tstat_profiles_stats_htg = get_tstat_profiles_and_stats(htg_schedule)
		  elsif clg_valid
		   tstat_profiles_stats_clg = get_tstat_profiles_and_stats(clg_schedule)
		  end 
		  
		  has_htg_setback = has_setback(tstat_profiles_stats_htg)
		  has_clg_setback = has_setback(tstat_profiles_stats_clg)
		  
		  #modify for htg vs cooling and threshold temps 
		  if !no_people_obj && !has_htg_setback 
		      new_htg_sched = mod_schedule(htg_schedule, sched_zone_occ, 'heating', htg_setback_c, htg_min_c)
			  zone_thermostat.setHeatingSchedule(new_htg_sched)
		  elsif !no_people_obj && !has_clg_setback 
		      new_clg_sched = mod_schedule(clg_schedule, sched_zone_occ, 'cooling', clg_setback_c, clg_max_c)
			  zone_thermostat.setCoolingSchedule(new_clg_sched)
		  end 

          #pick back up here 
          else # Handle zones with setbacks or with spaces without People objects
            profiles = [htg_schedule.defaultDaySchedule]
            htg_schedule.scheduleRules.each { |rule| profiles << rule.daySchedule }
            for tstat_profile in profiles
              tstat_profile_min = tstat_profile.values.min
              tstat_profile_max = tstat_profile.values.max
              tstat_profile_size = tstat_profile.values.uniq.size
              time_h = tstat_profile.times
              if tstat_profile_size == 2 # profile is square wave (2 setpoints, occupied vs unoccupied)
                tstat_profile.values.each_with_index do |value, i| # iterate thru profile and modify values as needed
                  if value == tstat_profile_min
                    tstat_profile.addValue(time_h[i],
                                           tstat_profile_max - setback_value_c)
                  end
                end
              end
              next unless tstat_profile_size > 2 # could be optimal start with ramp

              tstat_profile.values.each_with_index do |value, i|
                if value == tstat_profile_min
                  tstat_profile.addValue(time_h[i], tstat_profile_max - setback_value_c) # set min value back to desired setback
                elsif value > tstat_profile_min && value < tstat_profile_max # dealing with optimum start case
                  if value < tstat_profile_max - setback_value_c # value now less than new min
                    tstat_profile.addValue(time_h[i], tstat_profile_max - setback_value_c) # set so that minimum value is now equal to maximum - setback
                  end
                end
              end
             end
          end
        end
		end 
    return true
  end
end

# register the measure to be used by the application
UpgradeAddThermostatSetback.new.registerWithApplication
