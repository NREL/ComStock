# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
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

	
   #iterate thru air loops associated with packaged single zone systems 
	#AirLoopHVACUnitarySystem #confirm that this isn't casting a broader net than intended 
	model.getAirLoopHVACs.sort.each do |air_loop_hvac|
	      runner.registerInfo("in air loop") 
	      #if air_loop_hvac_unitary_system?(air_loop_hvac) #need to revisit this later 
		  #if applicable, replace CS fan with VS, change control type to VAV, and replace terminal unit 
		  sup_fan = air_loop_hvac.supplyFan.get() #might need to convert to unitary sys 
		  #check if fan CS
		  #runner.registerInfo("in unitary sys") 
		  runner.registerInfo("fan: #{sup_fan.class}")
		  runner.registerInfo("fan: #{sup_fan}")
		  if sup_fan.to_FanConstantVolume.is_initialized  
			runner.registerInfo("fan being removed")
			sup_fan.remove() #this seems to be working 
		  end   

		  #end 
		  
	end 

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
