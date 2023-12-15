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

    # # the name of the space to add to the model
    # space_name = OpenStudio::Measure::OSArgument.makeStringArgument('space_name', true)
    # space_name.setDisplayName('New space name')
    # space_name.setDescription('This name will be used as the name of the new space.')
    # args << space_name

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
				      term = equip.to_AirTerminalSingleDuctConstantVolumeNoReheat.get 
					  runner.registerInfo("term #{term}")
					  new_term = OpenStudio::Model::AirTerminalSingleDuctVAVHeatAndCoolNoReheat.new(model)
					  if term.autosizedMaximumAirFlowRate.is_initialized
					     des_airflow_rate = term.autosizedMaximumAirFlowRate.get
						 runner.registerInfo("des airflow #{des_airflow_rate}")
						 new_term.setMaximumAirFlowRate(des_airflow_rate * max_flow) 
						 new_term.setZoneMinimumAirFlowFraction(min_flow)
					  elsif term.maximumAirFlowRate.is_initialized
					      des_airflow_rate = term.maximumAirFlowRate.get
						  runner.registerInfo("des airflow #{des_airflow_rate}")
						  new_term.setMaximumAirFlowRate(des_airflow_rate * max_flow) 
						  new_term.setZoneMinimumAirFlowFraction(max(min_flow, min_oa_flow_rate/max_flow ))
					  end 
					  air_loop_hvac.removeBranchForZone(thermal_zone)
					  air_loop_hvac.addBranchForZone(thermal_zone, new_term)

			end
	  end
	end
	            #set up economizer
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
				 #set up DCV        
                 controller_mv = controller_oa.controllerMechanicalVentilation
                 controller_mv.setDemandControlledVentilation(true)
			 # air_loop_hvac.demandComponents.each do |component|
			     # runner.registerInfo("demand component #{component}")
				 # # if ['Diffuser Inlet Air Node'].any? { |word| (component.name.get).include?(word) }
					# # inlet_node = component 
					# # runner.registerInfo("inlet node selected #{component}")
				 # # end 
	 
				 # if component.to_AirTerminalSingleDuctConstantVolumeNoReheat.is_initialized
				    # new_term = OpenStudio::Model::AirTerminalSingleDuctVAVHeatAndCoolNoReheat.new(model)
				    # air_loop_hvac.removeBranchForZone() #remove branch + terminal 
				     # air_loop_hvac.addBranchForZone(zone, new terminal)
				    # term = component.to_AirTerminalSingleDuctConstantVolumeNoReheat.get
				    # inlet_node = term.inletModelObject.get.to_Node.get
					# runner.registerInfo("inlet node selected #{inlet_node}")
				    
					# #new_term.addToNode(inlet_node) 
					# #component.remove()
				 # end 
				 # #diffusers are the object we want to manipulate. 
				 # #could take the new one and instantiate/add to node 
			 # end 
		  end
    end 
	
	  
	  #include this in earlier loop? add this back in, per andrew 

     
	
	#need to replace TUs
	
	
   #iterate thru air loops associated with packaged single zone systems 
	#AirLoopHVACUnitarySystem #confirm that this isn't casting a broader net than intended 
	#restore for those that aren't unitary systems 
	# model.getAirLoopHVACs.sort.each do |air_loop_hvac|
	      # runner.registerInfo("in air loop") 
	      # #if air_loop_hvac_unitary_system?(air_loop_hvac) #need to revisit this later 
		  # #if applicable, replace CS fan with VS, change control type to VAV, and replace terminal unit 
		  # sup_fan = air_loop_hvac.supplyFan.get() #might need to convert to unitary sys 
		  # #check if fan CS
		  # #runner.registerInfo("in unitary sys") 
		  # runner.registerInfo("fan: #{sup_fan.class}")
		  # runner.registerInfo("fan: #{sup_fan}")
		  # if sup_fan.to_FanConstantVolume.is_initialized  
			# runner.registerInfo("fan being removed")
			# sup_fan = sup_fan.to_FanConstantVolume.get()
		    # fan_inlet_node = sup_fan.inletNode()
		    # runner.registerInfo("fan inlet node: #{fan_inlet_node}")
			# sup_fan.remove() #this seems to be working 
		  # end   
		  # #identify the node and connect a new VS supply fan there 
		  # #might need to modify the overall approach for unitary systems

		  # #end 
		  
	# end 

    # # assign the user inputs to variables
    # space_name = runner.getStringArgumentValue('space_name', user_arguments)

    # # check the space_name for reasonableness
    # if space_name.empty?
      # runner.registerError('Empty space name was entered.')
      # return false
    # end
	
	#iterate thru air loops
	
	#if applicable change control type to VAV, replace CS fan with variable, and replace terminal unit 

    # # report initial condition of model
    # runner.registerInitialCondition("The building started with #{model.getSpaces.size} spaces.")

    # # add a new space to the model
    # new_space = OpenStudio::Model::Space.new(model)
    # new_space.setName(space_name)

    # # echo the new space's name back to the user
    # runner.registerInfo("Space #{new_space.name} was added.")

    # # report final condition of model
    # runner.registerFinalCondition("The building finished with #{model.getSpaces.size} spaces.")

    return true
  end
end

# register the measure to be used by the application
AdvancedRTUControl.new.registerWithApplication
