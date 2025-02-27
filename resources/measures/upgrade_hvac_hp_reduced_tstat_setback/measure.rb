# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
require 'set'
class HPReducedTstatSetback < OpenStudio::Measure::ModelMeasure
 
	require 'openstudio-standards'
	  # human readable name
	  def name
			# Measure name should be the title case of the class name.
			return 'Heat_Pump_Reduced_Thermostat_Setback'
	  end

	# human readable description
    def description
    	return 'This measure is applicable to heat pump RTU and heat pump boiler systems, and modifies unoccupied thermostat setpoint schedules to reflect a setback of only 2F from occupied setpoints.'
    end
	
    def get_tstat_profiles_and_stats(tstat_schedule)
			if tstat_schedule.to_ScheduleRuleset.empty?
			  runner.registerWarning("Schedule '#{tstat_schedule.name.get}' is not a ScheduleRuleset, will not be adjusted")
			  return false
			else
			  tstat_schedule = tstat_schedule.to_ScheduleRuleset.get
			  profiles = [tstat_schedule.defaultDaySchedule]
			  rules = [] 
			  tstat_schedule.scheduleRules.each { |rule| profiles << rule.daySchedule }
              tstat_schedule.scheduleRules.each { |rule| rules << rule } ##AA added 
			  values = []
			  profiles.each { |profile| values << profile.values }
			  values = values.flatten
			  sch_min = values.min
			  sch_max = values.max
			  num_vals = values.uniq.size
			  return { profiles: profiles, rules: rules, values: values, min: sch_min, max: sch_max, num_vals: num_vals }
			end
	 end
	 
	 def find_days_applicable(sched_rule)
	     days_app = []
	     if sched_rule.applyMonday == true 
		     days_app << "Monday"
		 elsif sched_rule.applyTuesday == true 
		     days_app << "Tuesday"
		 elsif sched_rule.applyWednesday == true 
		     days_app << "Wednesday"
		 elsif sched_rule.applyThursday == true 
		     days_app << "Thursday"
		 elsif sched_rule.applyFriday == true 
		     days_app << "Friday"
		 elsif sched_rule.applySaturday == true 
		     days_app << "Saturday"
		 elsif sched_rule.applySunday == true 
		     days_app << "Sunday"
		 end 
		 start_date = sched_rule.startDate.get 
		 end_date = sched_rule.endDate.get
		  
		  return [days_app, [start_date, end_date]]
	 end 

  # human readable description of modeling approach
	def modeler_description
		return 'This measure iterates through and modifies zone-level thermostat schedules.'
	end

	  # define the arguments that the user will input
	  def arguments(model)
		args = OpenStudio::Measure::OSArgumentVector.new

		return args
	  end


	  # define what happens when the measure is run
	def run(model, runner, user_arguments)
		super(model, runner, user_arguments)  # Do **NOT** remove this line

		# use the built-in error checking
		if !runner.validateUserArguments(arguments(model), user_arguments)
		  return false
		end
		
		htg_tstat_schedules = []
		sched_zone_hash = {} #AA added 
		setback_value = 2 #confirm f or c 
		sched_rule_hash = [] 
		
		
	  def adjust_constant_sched_setback(runner, tstat_schedule, occ_schedule, profile_max, setback_value) #operates on schedule days
		#default_day_sched_tstat = tstat_schedule.defaultDaySchedule
		#default_day_sched_occ = occ_schedule.defaultDaySchedule
	 	 for index in 0..occ_schedule.times.size - 1
             occ_value = occ_schedule.values[index]
			 runner.registerInfo("line 47" + "#{occ_schedule.times[index]}")
             if occ_value == 0
			    runner.registerInfo("line 48" + "#{occ_value}") 
                tstat_value = profile_max - setback_value
				# runner.registerInfo("line 49 profile max" + "#{profile_max}")
				# runner.registerInfo("line 49 profile sb" + "#{setback_value}")
              else
                tstat_value = profile_max
				
             end
			    # runner.registerInfo("line 52" + "#{tstat_value}")
                tstat_schedule.addValue(occ_schedule.times[index], tstat_value)
             end
			 return tstat_schedule
	 end 
	   
	   # Collect zone thermostat schedules
	   ##AA update this to loop thru by zone 
		model.getThermalZones.each do |thermal_zone|
		  # skip data centers
		  #next if thermal_zone.name.get.downcase.gsub(' ', '').include?('datacenter')

		  # skip zones without thermostats
		  next unless thermal_zone.thermostatSetpointDualSetpoint.is_initialized
		  zone_thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
		  htg_schedule = zone_thermostat.heatingSetpointTemperatureSchedule
		  if htg_schedule.empty?
			  runner.registerWarning("Heating setpoint schedule not found for zone '#{zone.name.get}'")
			elsif htg_schedule.get.to_ScheduleRuleset.empty?
			  runner.registerWarning("Schedule '#{htg_schedule.get.name.get}' is not a ScheduleRuleset, will not be adjusted")
			else
			  sched_zone_hash[htg_schedule.get.to_ScheduleRuleset.get]=thermal_zone.to_ThermalZone.get ##AA modified 
			end
		 end
		 
		 
		#Create a hash of rules and schedule profiles  
		#space_types_no_setback = [
		 
		
		##AA: Need to address design days too! make sure handling weekends and all cases (profiles) 
	    model.getThermalZones.each do |thermal_zone| ##AA 2/25: populate hash here instead? 
		# skip zones without thermostats
		next unless thermal_zone.thermostatSetpointDualSetpoint.is_initialized
		zone_thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
		htg_schedule = zone_thermostat.heatingSetpointTemperatureSchedule
		if htg_schedule.empty?
			runner.registerWarning("Heating setpoint schedule not found for zone '#{zone.name.get}'")
			next 
		elsif htg_schedule.get.to_ScheduleRuleset.empty?
			runner.registerWarning("Schedule '#{htg_schedule.get.name.get}' is not a ScheduleRuleset, will not be adjusted")
			next 
	    else
			htg_schedule = htg_schedule.get.to_ScheduleRuleset.get
			runner.registerInfo("heating schedule start #{htg_schedule.class.to_s}")
		end 
		#sched_zone_hash.keys.uniq.each do |htg_sch|
		    runner.registerInfo("htg sched name #{htg_schedule}")
		    #sch_info = get_tstat_profiles_and_stats(htg_schedule)
			#sch info is hash, and rules, profiles are arrays, 
			#rules = sch_info[:rules] 
			updated_tstat_schedule = htg_schedule.clone.to_ScheduleRuleset.get #cloning bc multiple zones share this schedule, want to modify this zone's version only 
			updated_tstat_schedule.setName("Htg Tstat Sch Zone #{thermal_zone.name.to_s}")
			for tstat_rule in updated_tstat_schedule.scheduleRules
			    tstat_profile = tstat_rule.daySchedule 
			#runner.registerInfo("profile name #{profile.name}") 
			#write a method to calculate the dates and days for which the rule applies, and then find one from the occupancy schedule that is a superset
				profile_name = tstat_profile.name
				tstat_profile_min = tstat_profile.values.min
				tstat_profile_max = tstat_profile.values.max
				tstat_profile_size = tstat_profile.values.uniq.size
				time_h = tstat_profile.times
			##AA: add in checks for building type: additional properties, and then certain space types, to make sure it's not supposed to operate 24/7
			    if tstat_profile_size == 1 #schedules currently without a setback 
			      runner.registerInfo("tstat profile size =1") 
				#check if 24/7 op needed (With building type os additional props and then space type) 
				#if not, find unoccupied hours and set back 
				#look at occupancy schedule 
					# runner.registerInfo("zone #{sched_zone_hash[htg_sch].class.to_s}")
					sch_zone_occ = OpenstudioStandards::ThermalZone.thermal_zones_get_occupancy_schedule(thermal_zones = [thermal_zone], occupied_percentage_threshold: 0.05) #schedule ruleset 
					#runner.registerInfo("occ schedule line 179" +  "#{sch_zone_occ }")
					runner.registerInfo("occ schedule line 179 default day" +  "#{sch_zone_occ.defaultDaySchedule}")
					#zone_sch_profiles = get_tstat_profiles_and_stats(sch_zone_occ) #create new thermostat schedules that align with these, and then assign them 
					# runner.registerInfo("list class 174 #{sch_zone_occ.scheduleRules.class.to_s}")
					# runner.registerInfo("sch_zone_occ.scheduleRules #{sch_zone_occ.scheduleRules[0]}")
					sch_zone_occ.scheduleRules.each do |occ_rule|
						runner.registerInfo("looking for applicable schedule") 
						days_app_tstat = find_days_applicable(tstat_rule)[0]
						tstat_date_range = [find_days_applicable(tstat_rule)[1][0], find_days_applicable(tstat_rule)[1][1]] ##AA could probably move this out of the loop 
						days_app_occ = find_days_applicable(occ_rule)[0] #add a warning if a match can't be found 
						occ_date_range = [find_days_applicable(occ_rule)[1][0], find_days_applicable(occ_rule)[1][1]]
						if (days_app_tstat & days_app_occ) == days_app_tstat and (occ_date_range[0] <= tstat_date_range[0] and tstat_date_range[1] <= occ_date_range[1])#check if tstat applicability is subset of occ schedule applicability 
						   # runner.registerInfo("found corresponding occ sched") 	  
						   # runner.registerInfo("days app occ #{days_app_occ[0]}") 
						   # runner.registerInfo("days app tstat #{days_app_tstat[0]}") 
						   corresp_occ_profile = occ_rule.daySchedule #add a check for case where none found 
						   # runner.registerInfo("occ profile #{corresp_occ_profile}")
						   # runner.registerInfo("tstat profile_max - setbackvalue #{tstat_profile_max - setback_value}")
						   tstat_profile=adjust_constant_sched_setback(runner, tstat_profile, corresp_occ_profile, tstat_profile_max, setback_value)
						   # runner.registerInfo("tstat profile" + "#{tstat_profile}")
						end 
				   end 
				#modified_tstat_sched_ruleset = adjust_constant_sched_setback(new_htg_tstat_sch, sch_zone_occ, profile_max, setback_value)
				#Set custom days, holidays, and design day schedules 
				#then need to assign back to thermostat 
				zone_thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
				zone_thermostat.setHeatingSchedule(updated_tstat_schedule) #reset the schedule at the thermostat. This will occur for each profile change but it should preserve the previously made changes. 
			    #confirm correct here 
			end 
			if tstat_profile_size == 2 # profile is square wave (2 setpoints, occupied vs unoccupied)
				tstat_profile.values.each_with_index do |value, i| #iterate thru profile and modify values as needed 
				  if value == tstat_profile_min
				     runner.registerInfo("old min: #{value}") 
					 tstat_profile.addValue(time_h[i], tstat_profile_max - setback_value)
					 runner.registerInfo("new min: #{tstat_profile_max - setback_value}") 
                end
				
		    end 
		    end 
		   if tstat_profile_size > 2 #could be optimal start with ramp 
		      tstat_profile.values.each_with_index do |value, i|
			  if value == tstat_profile_min
			      tstat_profile.addValue(time_h[i], tstat_profile_max - setback_value) #set min value back to desired setback 
			  elsif value > tstat_profile_min and value < tstat_profile_max #dealing with optimum start case 
				  if value < tstat_profile_max - setback_value #value now less than new min 
					tstat_profile.addValue(time_h[i], tstat_profile_max - setback_value) 
				   end 
			  end 
			 
			  end 
		   end 
		end 
		end 

		
		#Sizing run
		# standard = Standard.build('90.1-2013')


		#register na if no applicable air loops
		# if overall_sel_air_loops.length() == 0
			# runner.registerNotApplicable('No applicable air loops found in model')
		# end
		return true
	end
	end

# register the measure to be used by the application
HPReducedTstatSetback.new.registerWithApplication
