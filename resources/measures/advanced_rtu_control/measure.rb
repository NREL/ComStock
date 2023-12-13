# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
#make sure testing on 3.7 models! 
class AdvancedRTUControl < OpenStudio::Measure::ModelMeasure
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
				thermal_zone.equipment.each do |equip|
				if equip.to_AirTerminalSingleDuctConstantVolumeNoReheat.is_initialized
					  new_term = OpenStudio::Model::AirTerminalSingleDuctVAVHeatAndCoolNoReheat.new(model)
					  air_loop_hvac.removeBranchForZone(thermal_zone)
					  air_loop_hvac.addBranchForZone(thermal_zone, new_term)
				  # Do something
				  
				  #remove branch for zone and add back with terminal 
			end
	  end
	end
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
