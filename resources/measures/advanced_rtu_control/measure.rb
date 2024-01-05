# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure

class AdvancedRTUControl < OpenStudio::Measure::ModelMeasure

require 'openstudio-standards'
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'AdvancedRTUControl'
  end

  # human readable description
  def description
    return 'This measure implements advanced RTU controls, including a variable-speed fan, with options for economizing and demand-controlled ventilation.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure iterates through airloops, and, where applicable, replaces constant speed fans with variable speed fans, and replaces the existing termianl unit.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new
	
	#economizer option 
    add_econo = OpenStudio::Measure::OSArgument.makeBoolArgument('add_econo', true)
    add_econo.setDisplayName('Economizer to be added?')
    add_econo.setDescription('Add economizer (true) or not (false)')
    args << add_econo
	
	#dcv option 
	add_dcv = OpenStudio::Measure::OSArgument.makeBoolArgument('add_dcv', true)
    add_dcv.setDisplayName('DCV to be added?')
    add_dcv.setDescription('Add DCV (true) or not (false)')
    args << add_dcv

    return args
  end
  
  def air_loop_hvac_unitary_system?(air_loop_hvac)
    is_unitary_system = false
    air_loop_hvac.supplyComponents.each do |component|
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirLoopHVAC_UnitarySystem', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir', 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed', 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
        is_unitary_system = true
      end
    end
    return is_unitary_system
  end
  
   #slightly modified from OS standards to adjust log messages 
   def thermal_zone_outdoor_airflow_rate(thermal_zone)
    tot_oa_flow_rate = 0.0

    spaces = thermal_zone.spaces.sort

    sum_floor_area = 0.0
    sum_number_of_people = 0.0
    sum_volume = 0.0

    # Variables for merging outdoor air
    any_max_oa_method = false
    sum_oa_for_people = 0.0
    sum_oa_for_floor_area = 0.0
    sum_oa_rate = 0.0
    sum_oa_for_volume = 0.0

    # Find common variables for the new space
    spaces.each do |space|
      floor_area = space.floorArea
      sum_floor_area += floor_area

      number_of_people = space.numberOfPeople
      sum_number_of_people += number_of_people

      volume = space.volume
      sum_volume += volume

      dsn_oa = space.designSpecificationOutdoorAir
      next if dsn_oa.empty?

      dsn_oa = dsn_oa.get

      # compute outdoor air rates in case we need them
      oa_for_people = number_of_people * dsn_oa.outdoorAirFlowperPerson
      oa_for_floor_area = floor_area * dsn_oa.outdoorAirFlowperFloorArea
      oa_rate = dsn_oa.outdoorAirFlowRate
      oa_for_volume = volume * dsn_oa.outdoorAirFlowAirChangesperHour / 3600

      # First check if this space uses the Maximum method and other spaces do not
      if dsn_oa.outdoorAirMethod == 'Maximum'
        sum_oa_rate += [oa_for_people, oa_for_floor_area, oa_rate, oa_for_volume].max
      elsif dsn_oa.outdoorAirMethod == 'Sum'
        sum_oa_for_people += oa_for_people
        sum_oa_for_floor_area += oa_for_floor_area
        sum_oa_rate += oa_rate
        sum_oa_for_volume += oa_for_volume
      end
    end

    tot_oa_flow_rate += sum_oa_for_people
    tot_oa_flow_rate += sum_oa_for_floor_area
    tot_oa_flow_rate += sum_oa_rate
    tot_oa_flow_rate += sum_oa_for_volume

    # Convert to cfm
    tot_oa_flow_rate_cfm = OpenStudio.convert(tot_oa_flow_rate, 'm^3/s', 'cfm').get

    #runner.registerInfo("For #{thermal_zone.name}, design min OA = #{tot_oa_flow_rate_cfm.round} cfm.")

    return tot_oa_flow_rate
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)  # Do **NOT** remove this line

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end
	#read in arguments
	add_econo = runner.getBoolArgumentValue('add_econo', user_arguments)
	add_dcv = runner.getBoolArgumentValue('add_dcv', user_arguments)
	
	#Set constants
	fan_tot_eff = 0.63
    fan_mot_eff = 0.29
    fan_static_pressure = 50.0
	
	#set airflow design ratios
	max_flow = 0.9
	min_flow = 0.4 
	
	
	#Sizing run 
	standard = Standard.build('90.1-2013')
    if standard.model_run_sizing_run(model, "#{Dir.pwd}/advanced_rtu_control") == false
      runner.registerError('Sizing run for Hardsize model failed, cannot hard-size model.')
      puts('Sizing run for Hardsize model failed, cannot hard-size model.')
      puts("directory: #{Dir.pwd}")
      return false
    end

    # apply sizing values
    model.applySizingValues
	

   	model.getAirLoopHVACs.sort.each do |air_loop_hvac|
		runner.registerInfo("in air loop") 
	    if air_loop_hvac_unitary_system?(air_loop_hvac) 
		   #set control type
			air_loop_hvac.supplyComponents.each do |component|#more efficient way of doing this? 
				obj_type = component.iddObjectType.valueName.to_s
			    case obj_type
                when 'OS_AirLoopHVAC_UnitarySystem'
					component = component.to_AirLoopHVACUnitarySystem.get
					component.setControlType('SingleZoneVAV') #confirmed that this worked 
					#Set overall flow rates for air loop 
					if air_loop_hvac.autosizedDesignSupplyAirFlowRate.is_initialized
						#puts ("setting airloop flow rates")
						des_supply_airflow = air_loop_hvac.autosizedDesignSupplyAirFlowRate.get
						#puts ("des supply airflow" + "#{air_loop_hvac.name.to_s}" "#{des_supply_airflow}" + "new max" + "#{max_flow*des_supply_airflow}")
						component.setSupplyAirFlowRateDuringCoolingOperation(max_flow*des_supply_airflow)
						component.setSupplyAirFlowRateDuringHeatingOperation(max_flow*des_supply_airflow)
						component.setSupplyAirFlowRateWhenNoCoolingorHeatingisRequired(min_flow*des_supply_airflow)
					end 
				 component.resetSupplyFan()
				 sup_fan = air_loop_hvac.supplyFan
				#Create VS supply fan 
				fan = OpenStudio::Model::FanVariableVolume.new(model)
				fan.setName("#{air_loop_hvac.name} Fan")
				fan.setFanEfficiency(fan_tot_eff) # from PNNL
				fan.setPressureRise(fan_static_pressure)
				fan.setMotorEfficiency(fan_mot_eff) unless fan_mot_eff.nil?
				#Add it to the unitary sys
				component.setSupplyFan(fan) #need to confirm that this worked 
			 end 
			 end 
			 air_loop_hvac.thermalZones.each do |thermal_zone|
			    min_oa_flow_rate = thermal_zone_outdoor_airflow_rate(thermal_zone) 
				runner.registerInfo("min_oa_flow_rate #{min_oa_flow_rate}")
				thermal_zone.equipment.each do |equip|
				if equip.to_AirTerminalSingleDuctConstantVolumeNoReheat.is_initialized
				      #puts ("moding terminal") 
				      term = equip.to_AirTerminalSingleDuctConstantVolumeNoReheat.get 
					  runner.registerInfo("term #{term}")
					  new_term = OpenStudio::Model::AirTerminalSingleDuctVAVHeatAndCoolNoReheat.new(model)
					  if term.autosizedMaximumAirFlowRate.is_initialized
					     #puts ("moding terminal") 
					     des_airflow_rate = term.autosizedMaximumAirFlowRate.get
						 #puts ("tz #{thermal_zone}" + "max term rate" + "#{des_airflow_rate * max_flow}")
						 runner.registerInfo("des airflow #{des_airflow_rate}")
						 new_term.setMaximumAirFlowRate(des_airflow_rate * max_flow) 
						 new_term.setZoneMinimumAirFlowFraction(min_flow)
						 puts ("tz #{thermal_zone}" + "min term rate" + "#{des_airflow_rate * min_flow}")
					  elsif term.maximumAirFlowRate.is_initialized
					      des_airflow_rate = term.maximumAirFlowRate.get
						  runner.registerInfo("des airflow #{des_airflow_rate}")
						  new_term.setMaximumAirFlowRate(des_airflow_rate * max_flow) 
						  #puts ("tz #{thermal_zone}" + "max term rate" + "#{des_airflow_rate * max_flow}")
						  #set minimum based on max of 40% of max flow, or min ventilation level req'd 
						  new_term.setZoneMinimumAirFlowFraction(max(min_flow, min_oa_flow_rate/max_flow ))
						  puts ("tz #{thermal_zone}" + "min term rate" + "#{des_airflow_rate * min_flow}")
					  end 
					  air_loop_hvac.removeBranchForZone(thermal_zone)
					  air_loop_hvac.addBranchForZone(thermal_zone, new_term)
					  end 
					 

			end
	  end
	end
		if add_econo
			oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
			controller_oa = oa_system.getControllerOutdoorAir
			# econ_type = std.model_economizer_type(model, climate_zone)
			# set economizer type
			controller_oa.setEconomizerControlType('DifferentialEnthalpy')
			# set drybulb temperature limit; per 90.1-2013, this is constant 75F for all climates
			drybulb_limit_f=75
			drybulb_limit_c = OpenStudio.convert(drybulb_limit_f, 'F', 'C').get
			controller_oa.setEconomizerMaximumLimitDryBulbTemperature(drybulb_limit_c)
			# set lockout for integrated heating
			 controller_oa.setLockoutType('LockoutWithHeating')
		end 
		 #set up DCV  and check for space types that should not be controlled with DCV
		air_loop_hvac.thermalZones.each do |thermal_zone|
			if add_dcv and not ['kitchen', 'Kitchen', 'dining', 'Dining', 'Laboratory', 'KITCHEN', 'LABORATORY', 'DINING', 'patient', 'PATIENT', 'Patient'].any? { |word| (air_loop_hvac.name.get).include?(word) }
						 oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
						 controller_oa = oa_system.getControllerOutdoorAir
						 controller_mv = controller_oa.controllerMechanicalVentilation
						 controller_mv.setDemandControlledVentilation(true)
						 #Set design OA object attributes 
						 thermal_zone.spaces.each do |space|
							  dsn_oa = space.designSpecificationOutdoorAir
							  next if dsn_oa.empty?
							  dsn_oa = dsn_oa.get
							  puts "design spec oa name #{dsn_oa.name}"
							  # set design specification outdoor air objects to sum
							  dsn_oa.setOutdoorAirMethod('Sum')

							  # Get the space properties
							  floor_area = space.floorArea
							  number_of_people = space.numberOfPeople
							  people_per_m2 = space.peoplePerFloorArea

							  # Sum up the total OA from all sources
							  oa_for_people_per_m2 = people_per_m2 * dsn_oa.outdoorAirFlowperPerson
							  oa_for_floor_area_per_m2 = dsn_oa.outdoorAirFlowperFloorArea
							  tot_oa_per_m2 = oa_for_people_per_m2 + oa_for_floor_area_per_m2
							  tot_oa_cfm_per_ft2 = OpenStudio.convert(OpenStudio.convert(tot_oa_per_m2, 'm^3/s', 'cfm').get, '1/m^2', '1/ft^2').get
							  tot_oa_cfm = floor_area * tot_oa_cfm_per_ft2
							  
							   # # if space is ineligible type, convert all OA to per-area to avoid DCV being applied
						  # if space_types_no_dcv.any? { |i| space.spaceType.get.name.to_s.include? i } & !dsn_oa.outdoorAirFlowperPerson.zero?
							# runner.registerInfo("Space '#{space.name}' is an ineligable space type but is on an air loop that serves other DCV-eligible spaces. Converting all outdoor air to per-area.")
							# dsn_oa.setOutdoorAirFlowperPerson(0.0)
							# dsn_oa.setOutdoorAirFlowperFloorArea(tot_oa_per_m2)
							# next
						  # end

						  # if both per-area and per-person are present, does not need to be modified
						  if !dsn_oa.outdoorAirFlowperPerson.zero? & !dsn_oa.outdoorAirFlowperFloorArea.zero?
							next
						  
						  # if both are zero, skip space
						  elsif dsn_oa.outdoorAirFlowperPerson.zero? & dsn_oa.outdoorAirFlowperFloorArea.zero?
							runner.registerInfo("Space '#{space.name}' has 0 outdoor air per-person and per-area rates. DCV may be still be applied to this air loop, but it will not function on this space.")
							next
						  
						  # if per-person or per-area values are zero, set to 10 cfm / person and allocate the rest to per-area
						  elsif dsn_oa.outdoorAirFlowperPerson.zero? || dsn_oa.outdoorAirFlowperFloorArea.zero?
							puts "========Before Per Person========="
							puts "#{space.name}"
							puts "people per m2", people_per_m2
							puts "Per-person", dsn_oa.outdoorAirFlowperPerson * people_per_m2
							puts "Per-area", dsn_oa.outdoorAirFlowperFloorArea
							puts "Total OA", tot_oa_per_m2

							if dsn_oa.outdoorAirFlowperPerson.zero?
							  runner.registerInfo("Space '#{space.name}' per-person outdoor air rate is 0. Using a minimum of 10 cfm / person and assigning the remaining space outdoor air requirement to per-area.")
							elsif dsn_oa.outdoorAirFlowperFloorArea.zero?
							  runner.registerInfo("Space '#{space.name}' per-area outdoor air rate is 0. Using a minimum of 10 cfm / person and assigning the remaining space outdoor air requirement to per-area.")
							end

							# default ventilation is 10 cfm / person
							per_person_ventilation_rate = OpenStudio.convert(10, 'ft^3/min', 'm^3/s').get

							# assign remaining oa to per-area
							new_oa_for_people_per_m2 = people_per_m2 * per_person_ventilation_rate
							new_oa_for_people_cfm_per_f2 = OpenStudio.convert(OpenStudio.convert(new_oa_for_people_per_m2, 'm^3/s', 'cfm').get, '1/m^2', '1/ft^2').get
							new_oa_for_people_cfm = number_of_people * new_oa_for_people_cfm_per_f2
							remaining_oa_per_m2 = tot_oa_per_m2 - new_oa_for_people_per_m2
							if remaining_oa_per_m2 <= 0
							  runner.registerInfo("Space '#{space.name}' has #{number_of_people.round(1)} people which corresponds to a ventilation minimum requirement of #{new_oa_for_people_cfm.round(0)} cfm at 10 cfm / person, but total zone outdoor air is only #{tot_oa_cfm.round(0)} cfm. Setting all outdoor air as per-person.")
							  per_person_ventilation_rate = tot_oa_per_m2 / people_per_m2
							  dsn_oa.setOutdoorAirFlowperFloorArea(0.0)
							else
							  oa_per_area_per_m2 = remaining_oa_per_m2
							  dsn_oa.setOutdoorAirFlowperFloorArea(oa_per_area_per_m2)
							end
							dsn_oa.setOutdoorAirFlowperPerson(per_person_ventilation_rate)
					  end 
		 end 
		 end 
        end 

    end 

    return true
  end
end

# register the measure to be used by the application
AdvancedRTUControl.new.registerWithApplication
