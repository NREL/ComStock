# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class FanStaticPressureReset < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Fan Static Pressure Reset'
  end

  # human readable description
  def description
    return 'Replace this text with an explanation of what the measure does in terms that can be understood by a general building professional audience (building owners, architects, engineers, contractors, etc.).  This description will be used to create reports aimed at convincing the owner and/or design team to implement the measure in the actual building design.  For this reason, the description may include details about how the measure would be implemented, along with explanations of qualitative benefits associated with the measure.  It is good practice to include citations in the measure if the description is taken from a known source or if specific benefits are listed.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Replace this text with an explanation for the energy modeler specifically.  It should explain how the measure is modeled, including any requirements about how the baseline model must be set up, major assumptions, citations of references to applicable modeling resources, etc.  The energy modeler should be able to read this description and understand what changes the measure is making to the model and why these changes are being made.  Because the Modeler Description is written for an expert audience, using common abbreviations for brevity is good practice.'
  end
  
 def vav_terminals?(air_loop_hvac)
    air_loop_hvac.thermalZones.each do |thermal_zone| #iterate thru thermal zones and modify zone-level terminal units
	  thermal_zone.equipment.each do |equip|
	    if equip.to_AirTerminalSingleDuctVAVHeatAndCoolNoReheat.is_initialized
          return true
		elsif equip.to_AirTerminalSingleDuctVAVHeatAndCoolReheat.is_initialized
          return true
		elsif equip.to_AirTerminalSingleDuctVAVReheat.is_initialized
          return true
		elsif equip.to_AirTerminalSingleDuctVAVNoReheat.is_initialized
          return true
	    elsif equip.to_AirTerminalDualDuctVAV.is_initialized
	      return true
		elsif equip.to_AirTerminalDualDuctVAVOutdoorAir.is_initialized
		  return true
		else
		  next
		end
	    end
	end
	  return false #if no VAV terminals found on the air loop
  end
  
   def air_loop_res?(air_loop_hvac)
    is_res_system = true
    air_loop_hvac.supplyComponents.each do |component|
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirLoopHVAC_OutdoorAirSystem'
        is_res_system = false
      end
    end
    return is_res_system
  end

  # Determine if is evaporative cooler
  def air_loop_evaporative_cooler?(air_loop_hvac)
    is_evap = false
    air_loop_hvac.supplyComponents.each do |component|
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_EvaporativeCooler_Direct_ResearchSpecial', 'OS_EvaporativeCooler_Indirect_ResearchSpecial', 'OS_EvaporativeFluidCooler_SingleSpeed', 'OS_EvaporativeFluidCooler_TwoSpeed'
        is_evap = true
      end
    end
    return is_evap
  end
  
 def air_loop_doas?(air_loop_hvac)
    is_doas = false
    sizing_system = air_loop_hvac.sizingSystem
    if sizing_system.allOutdoorAirinCooling && sizing_system.allOutdoorAirinHeating && (air_loop_res?(air_loop_hvac) == false) && (air_loop_hvac.name.to_s.include?("DOAS") || air_loop_hvac.name.to_s.include?("doas"))
      is_doas = true
    end
    return is_doas
end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # the name of the space to add to the model
    space_name = OpenStudio::Measure::OSArgument.makeStringArgument('space_name', true)
    space_name.setDisplayName('New space name')
    space_name.setDescription('This name will be used as the name of the new space.')
    args << space_name

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)  # Do **NOT** remove this line

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    space_name = runner.getStringArgumentValue('space_name', user_arguments)
	
	#Create a hash for air loops 
	overall_sel_air_loops =[]

	model.getAirLoopHVACs.sort.each do |air_loop_hvac|
	  next if ((air_loop_hvac.thermalZones.length() == 1) || air_loop_res?(air_loop_hvac) || air_loop_evaporative_cooler?(air_loop_hvac)|| (air_loop_hvac.name.to_s.include?("DOAS")) || (air_loop_hvac.name.to_s.include?("doas"))) || air_loop_doas?(air_loop_hvac)
	  #skip based on residential being in name, or if a DOAS, or a single zone system 
	  sizing_system = air_loop_hvac.sizingSystem
	  next if ((air_loop_hvac.name.to_s.include?("residential")) || (air_loop_hvac.name.to_s.include?("Residential")) || (sizing_system.allOutdoorAirinCooling && sizing_system.allOutdoorAirinHeating))
	  #skip non-VAV systems
	  next if ! ['VAV', 'PVAV'].any? { |word| (air_loop_hvac.name.get).include?(word) } and !vav_terminals?(air_loop_hvac)
	  overall_sel_air_loops << air_loop_hvac
	end

	#register na if no applicable air loops
	if overall_sel_air_loops.length() == 0
	  runner.registerAsNotApplicable('No applicable air loops found in model')
	end
	
	overall_sel_air_loops.sort.each do |air_loop_hvac|
       sup_fan = air_loop_hvac.supplyFan()
	   if sup_fan.is_initialized #Replace constant speed with variable speed fan objects
		    sup_fan = sup_fan.get
			#handle FanVariableVolume
            if sup_fan.to_FanVariableVolume.is_initialized
			  sup_fan = sup_fan.to_FanVariableVolume.get
			  sup_fan.setFanPowerCoefficient1(0.040759894)
			  sup_fan.setFanPowerCoefficient2(0.08804497)
			  sup_fan.setFanPowerCoefficient3(-0.07292612)
			  sup_fan.setFanPowerCoefficient4(0.943739823)
			  #minimum speed
			end
	    end 
	end 

    return true
  end
end

# register the measure to be used by the application
FanStaticPressureReset.new.registerWithApplication
