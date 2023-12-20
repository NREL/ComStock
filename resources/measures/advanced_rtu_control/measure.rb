# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
#make sure testing on 3.7 models! 
#also need to add in DCV and economizing! 
#design limitations for htg + coolign coils 
#dial in economizer params more 
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
	#confirm that these are appropriate 
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
					  elsif term.maximumAirFlowRate.is_initialized
					      des_airflow_rate = term.maximumAirFlowRate.get
						  runner.registerInfo("des airflow #{des_airflow_rate}")
						  new_term.setMaximumAirFlowRate(des_airflow_rate * max_flow) 
						  #puts ("tz #{thermal_zone}" + "max term rate" + "#{des_airflow_rate * max_flow}")
						  #set minimum based on max of 40% of max flow, or min ventilation level req'd 
						  new_term.setZoneMinimumAirFlowFraction(max(min_flow, min_oa_flow_rate/max_flow ))
					  end 
					  air_loop_hvac.removeBranchForZone(thermal_zone)
					  air_loop_hvac.addBranchForZone(thermal_zone, new_term)

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
				 #set up DCV  
				 if add_dcv
					 controller_mv = controller_oa.controllerMechanicalVentilation
					 controller_mv.setDemandControlledVentilation(true)
				 end 

		  end
    end 

    return true
  end
end

# register the measure to be used by the application
AdvancedRTUControl.new.registerWithApplication
