# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

class UnoccupiedOAControls < OpenStudio::Measure::ModelMeasure
require 'openstudio-standards'
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Unoccupied OA Controls'
  end

  # human readable description
  def description
    return 'This measure sets minimum outdoor airflow to zero during extended periods of no occupancy (nighttime and weekends). Fans cycle during these unoccupied periods to meet the thermostat setpoints.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure ensures that the minimum outdoor air schedule aligns with the occupancy schedule of the building, so that fans cycling during unoccupied hours do not bring in outdoor air for ventilation. If the mininum OA schedule has been changed to a constant schedule through the nighttime operation variability measure, this measure reverts that. This measure continues to allow for air-side economizing during unoccupied hours, since it is only the minimum outdoor air level being modified.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end
  # Determine if the air loop is a unitary system
  # @return [Bool] Returns true if a unitary system is present, false if not.
  def self.air_loop_hvac_unitary_system?(air_loop_hvac)
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
  
 def no_change_zones?(air_loop_hvac)
	selected_air_loops = []
	  space_types_no_change = [
      'Kitchen',
      'kitchen',
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
      'PhysTherapy',
	  'outpatient', 
	  'Outpatient',
	  'Hospital', 
	  'hospital',
	  'epr',
	  'EPR', 
	  'EPr', 
	  'HOSPITAL', 
	  'OUTPATIENT', 
	  'school',
	  'SCHOOL', 
	  'School', 
	  'k12',
	  'K12', 
	  'education', 
	  'EDUCATION', 
	  'Education', 
	  'DOAS', 
	  'doas', 
	  'Hotel',
	  'hotel', 
	  'HOTEL'

    ]
  
      # oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem
      # if oa_system.is_initialized
        # oa_system = oa_system.get
      # else
        # #no_outdoor_air_loops += 1
		# return true
      # end


      # check to see if airloop has applicable space types
      # these space types are often ventilation driven, or generally do not use ventilation rates per person
      # exclude these space types: kitchens, laboratories, patient care rooms
      # TODO - add functionality to add DCV to multizone systems to applicable zones only
      space_types_no_change_count = 0
      air_loop_hvac.thermalZones.sort.each do |zone|
        zone.spaces.each do |space|
          if space_types_no_change.any? { |i| space.spaceType.get.name.to_s.include? i }
            space_types_no_change_count += 1
          else
          end
        end
      end
      if space_types_no_change_count >= 1
        #runner.registerInfo("Air loop '#{air_loop_hvac.name}' serves only ineligible space types. DCV will not be applied.")
        #ineligible_space_types += 1
        return true 
      end
      
      # #runner.registerInfo("Air loop '#{air_loop_hvac.name}' does not have existing demand control ventilation.  This measure will enable it.")
      # selected_air_loops << air_loop_hvac
    # #end

    # # report initial condition of model
    # #runner.registerInitialCondition("Out of #{model.getAirLoopHVACs.size} air loops, #{no_outdoor_air_loops} do not have outdoor air, #{no_per_person_rates_loops} have a zone without per-person OA rates, #{constant_volume_doas_loops} are constant volume DOAS systems, #{ervs} have ERVs, #{ineligible_space_types} serve ineligible space types, and #{existing_dcv_loops} already have demand control ventilation enabled, leaving #{selected_air_loops.size} eligible for demand control ventilation.")

    # if selected_air_loops.size.zero?
      # #runner.registerInfo('Model does not contain air loops eligible for enabling demand control ventilation.')
      # return true
    # end
	
	return false 
end

  # determine if the air loop is residential (checks to see if there is outdoor air system object)
  def self.air_loop_res?(air_loop_hvac)
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

  # Determine if the system is a DOAS based on
  # whether there is 100% OA in heating and cooling sizing.
  def self.air_loop_doas?(air_loop_hvac)
    is_doas = false
    sizing_system = air_loop_hvac.sizingSystem
    if sizing_system.allOutdoorAirinCooling && sizing_system.allOutdoorAirinHeating && (UnoccupiedOAControls.air_loop_res?(air_loop_hvac) == false) && (air_loop_hvac.name.to_s.include?("DOAS") || air_loop_hvac.name.to_s.include?("doas"))
      is_doas = true
    end
    return is_doas
  end

  # Determine if is evaporative cooler
  def self.air_loop_evaporative_cooler?(air_loop_hvac)
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

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)  # Do **NOT** remove this line

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

	
	template = 'ComStock 90.1-2013'
    std = Standard.build(template)

    # loop through air loops
    unitary_system_count = 0
    li_unitary_systems = []
    non_unitary_system_count = 0
    li_non_unitary_systems = []
	constant_schedules = 0 #Counter for constant schedules in the model 
	#Assess measure applicabilty 
    model.getAirLoopHVACs.sort.each do |air_loop_hvac|
	   puts air_loop_hvac
      # skip systems that are residential, or are DOAS
      next if UnoccupiedOAControls.air_loop_res?(air_loop_hvac)
      next if UnoccupiedOAControls.air_loop_doas?(air_loop_hvac)
      # skip outpatient healthcare, hospitals, and schools 
      next if no_change_zones?(air_loop_hvac) #screen out space types this shouldn't be applied to 
      # check unitary systems
      if UnoccupiedOAControls.air_loop_hvac_unitary_system?(air_loop_hvac)
        unitary_system_count += 1
        li_unitary_systems << air_loop_hvac
      else
        li_non_unitary_systems << air_loop_hvac
        non_unitary_system_count += 1
      end
	  #check min oa for constant schedules 
	  air_loop_oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
      if air_loop_oa_system.minimumOutdoorAirSchedule.get.to_ScheduleConstant.is_initialized 
	        constant_schedules = constant_schedules + 1 
	  end 
	  #check air loop availability for constant schedules 
	  avail_sched = air_loop_hvac.availabilitySchedule #got an error checking this for initialization 
	  if avail_sched.to_ScheduleConstant.is_initialized
	     puts "in schedule constant" 
	     constant_schedules = constant_schedules + 1 
	  end 
	  #among unitary systems, check supply fan operating mode for constant schedules 
	  if UnoccupiedOAControls.air_loop_hvac_unitary_system?(air_loop_hvac)
	      air_loop_hvac.supplyComponents.each do |component|
          obj_type = component.iddObjectType.valueName.to_s
          case obj_type
          when 'OS_AirLoopHVAC_UnitarySystem'
            component = component.to_AirLoopHVACUnitarySystem.get
          when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir'
            component = component.to_AirLoopHVACUnitaryHeatPump_AirToAir.get
          when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed'
            component = component.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
          when 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
            component = component.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get
		  component.getSupplyAirFanOperatingModeSchedule
          if setMinimumOutdoorAirSchedule.to_ScheduleConstant.is_initialized 
			   constant_schedules = constant_schedules + 1 
		  end 
		  end 
        end
	  end
    end
	
	if constant_schedules == 0 
	     runner.registerAsNotApplicable('No constant HVAC operation schedules or no candidate air loops found--measure not applicable.') 
		 return true 
	end 

    # report initial condition of model
    #runner.registerInitialCondition("The building has #{unitary_system_count} unitary systems and #{non_unitary_system_count} non-unitary airloop systems applicable for nighttime operation changes. #{rtu_night_mode} is the selected nighttime operation mode.")

    if (non_unitary_system_count + unitary_system_count) < 1
      runner.registerAsNotApplicable('No applicable systems were found.')
      return true
    end

    # make changes to unitary systems
	#need to deal with non unitary systems, too 
    li_unitary_systems.sort.each do |air_loop_hvac|
        puts "unitary system" 
      # change night OA schedule to match hvac operation schedule for no night OA
        # Schedule to control whether or not unit ventilates at night - clone hvac availability schedule
        if air_loop_hvac.availabilitySchedule.clone.to_ScheduleRuleset.is_initialized
			air_loop_vent_sch = air_loop_hvac.availabilitySchedule.clone.to_ScheduleRuleset.get
			air_loop_vent_sch.setName("#{air_loop_hvac.name}_night_novent_schedule")
		end 
		if air_loop_hvac.availabilitySchedule.clone.to_ScheduleConstant.is_initialized
			sch_ruleset = std.thermal_zones_get_occupancy_schedule(thermal_zones=air_loop_hvac.thermalZones,
															occupied_percentage_threshold:0.05)
			# set air loop availability controls and night cycle manager, after oa system added
			sch_ruleset.setName("#{air_loop_hvac.name}_night_fancycle_novent_schedule")
			air_loop_hvac.setAvailabilitySchedule(sch_ruleset)
			air_loop_hvac.setNightCycleControlType('CycleOnAny')
			air_loop_vent_sch = sch_ruleset  
		end 
        if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
			air_loop_oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
            air_loop_oa_system.setMinimumOutdoorAirSchedule(air_loop_vent_sch)
        end 
		
	   # change fan operation schedule to new clone of hvac operation schedule to ensure night cycling of fans (removing any constant schedules)
        # Schedule to control whether or not unit ventilates at night - clone hvac availability schedule
        # Schedule to control the airloop fan operation schedule
        air_loop_hvac.supplyComponents.each do |component|
          obj_type = component.iddObjectType.valueName.to_s
          case obj_type
          when 'OS_AirLoopHVAC_UnitarySystem'
            component = component.to_AirLoopHVACUnitarySystem.get
            component.setSupplyAirFanOperatingModeSchedule(air_loop_vent_sch)
          when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir'
            component = component.to_AirLoopHVACUnitaryHeatPump_AirToAir.get
            component.setSupplyAirFanOperatingModeSchedule(air_loop_vent_sch)
          when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed'
            component = component.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
            component.setSupplyAirFanOperatingModeSchedule(air_loop_vent_sch)
          when 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
            component = component.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get
            component.setSupplyAirFanOperatingModeSchedule(air_loop_vent_sch)
          end
        end
    end 
	
	#handle non-unitary systems 
	li_non_unitary_systems.sort.each do |air_loop_hvac|
	
      puts "in non unitary list" 
      # change night OA schedule to match hvac operation schedule for no night OA
      #case rtu_night_mode
      #when 'night_fancycle_novent'
        # Schedule to control whether or not unit ventilates at night - clone hvac availability schedule
        if air_loop_hvac.availabilitySchedule.clone.to_ScheduleRuleset.is_initialized
			air_loop_vent_sch = air_loop_hvac.availabilitySchedule.clone.to_ScheduleRuleset.get
			air_loop_vent_sch.setName("#{air_loop_hvac.name}_night_novent_schedule")
		end 
		if air_loop_hvac.availabilitySchedule.clone.to_ScheduleConstant.is_initialized #handle constant schedule 
			sch_ruleset = std.thermal_zones_get_occupancy_schedule(thermal_zones=air_loop_hvac.thermalZones,
															occupied_percentage_threshold:0.05)
			# set air loop availability controls and night cycle manager, after oa system added
			air_loop_hvac.setAvailabilitySchedule(sch_ruleset)
			air_loop_hvac.setNightCycleControlType('CycleOnAny')
			sch_ruleset.setName("#{air_loop_hvac.name}_night_fancycle_novent_schedule")
			air_loop_vent_sch = sch_ruleset  
		end 
	    next unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
		air_loop_oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
	    air_loop_oa_system.setMinimumOutdoorAirSchedule(air_loop_vent_sch) 
	  end 
	  
    return true
  end
end

# register the measure to be used by the application
UnoccupiedOAControls.new.registerWithApplication
