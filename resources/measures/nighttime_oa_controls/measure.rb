# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class NighttimeOAControls < OpenStudio::Measure::ModelMeasure
require 'openstudio-standards'
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Nighttime OA Controls'
  end

  # human readable description
  def description
    return 'This measure sets minimum outdoor airflow to zero during extended periods of no occupancy (nighttime). Fans cycle during these unoccupied periods to meet the thermostat setpoints.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure continues to allow for air-side economizing during nighttime hours, since it is only the minimum outdoor air level being modified.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end
   # Determine if the air loop is a unitary system
  #
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
    if sizing_system.allOutdoorAirinCooling && sizing_system.allOutdoorAirinHeating && (NighttimeOAControls.air_loop_res?(air_loop_hvac) == false) && (air_loop_hvac.name.to_s.include?("DOAS") || air_loop_hvac.name.to_s.include?("doas"))
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
    model.getAirLoopHVACs.sort.each do |air_loop_hvac|
      # skip systems that are residential, or are DOAS
      next if NighttimeOAControls.air_loop_res?(air_loop_hvac)
      next if NighttimeOAControls.air_loop_doas?(air_loop_hvac)
      # skip outpatient healthcare and schools 
      next if ['outpatient', 'Outpatient', 'OUTPATIENT', 'school', 'SCHOOL', 'School', 'k12', 'K12', 'education', 'EDUCATION', 'Education'].any? { |word| (air_loop_hvac.name.get).include?(word) }
      # check unitary systems
      if NighttimeOAControls.air_loop_hvac_unitary_system?(air_loop_hvac)
        unitary_system_count += 1
        li_unitary_systems << air_loop_hvac
      else
        li_non_unitary_systems << air_loop_hvac
        non_unitary_system_count += 1
      end
    end

    # report initial condition of model
    #runner.registerInitialCondition("The building has #{unitary_system_count} unitary systems and #{non_unitary_system_count} non-unitary airloop systems applicable for nighttime operation changes. #{rtu_night_mode} is the selected nighttime operation mode.")

    if (non_unitary_system_count + unitary_system_count) < 1
      runner.registerAsNotApplicable('No applicable systems were found.')
      return true
    end

    ##AA take out these counts if not needed 
    oa_schd_1_count = 0
    oa_schd_op_count = 0
    op_schd_1_count = 0
    fan_schd_1_count = 0
    fan_sch_op_count = 0

    # make changes to unitary systems
	#need to deal with non unitary systems, too 
    li_unitary_systems.sort.each do |air_loop_hvac|

      # change night OA schedule to match hvac operation schedule for no night OA
        # Schedule to control whether or not unit ventilates at night - clone hvac availability schedule
        next unless air_loop_hvac.availabilitySchedule.clone.to_ScheduleRuleset.is_initialized
        air_loop_vent_sch = air_loop_hvac.availabilitySchedule.clone.to_ScheduleRuleset.get
        air_loop_vent_sch.setName("#{air_loop_hvac.name}_night_novent_schedule")
        next unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
        air_loop_oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
        next unless air_loop_oa_system.minimumOutdoorAirSchedule.is_initialized
        air_loop_oa_system.setMinimumOutdoorAirSchedule(air_loop_vent_sch)
        oa_schd_op_count += 1
      
	  
	   # change fan operation schedule to new clone of hvac operation schedule to ensure night cycling of fans (removing any constant schedules)
        # Schedule to control whether or not unit ventilates at night - clone hvac availability schedule
        next unless air_loop_hvac.availabilitySchedule.to_ScheduleRuleset.is_initialized
        air_loop_fan_sch = air_loop_hvac.availabilitySchedule.clone.to_ScheduleRuleset.get
        air_loop_fan_sch.setName("#{air_loop_hvac.name}_night_fancycle_schedule")
        # Schedule to control the airloop fan operation schedule
        air_loop_hvac.supplyComponents.each do |component|
          obj_type = component.iddObjectType.valueName.to_s
          case obj_type
          when 'OS_AirLoopHVAC_UnitarySystem'
            component = component.to_AirLoopHVACUnitarySystem.get
            component.setSupplyAirFanOperatingModeSchedule(air_loop_fan_sch)
            fan_sch_op_count += 1
          when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir'
            component = component.to_AirLoopHVACUnitaryHeatPump_AirToAir.get
            component.setSupplyAirFanOperatingModeSchedule(air_loop_fan_sch)
            fan_sch_op_count += 1
          when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed'
            component = component.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
            component.setSupplyAirFanOperatingModeSchedule(air_loop_fan_sch)
            fan_sch_op_count += 1
          when 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
            component = component.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get
            component.setSupplyAirFanOperatingModeSchedule(air_loop_fan_sch)
            fan_sch_op_count += 1
          end
        end
    end 
	
	#handle non-unitary systems 
	li_non_unitary_systems.sort.each do |air_loop_hvac|

      # change night OA schedule to match hvac operation schedule for no night OA
      #case rtu_night_mode
      #when 'night_fancycle_novent'
        # Schedule to control whether or not unit ventilates at night - clone hvac availability schedule
        next unless air_loop_hvac.availabilitySchedule.clone.to_ScheduleRuleset.is_initialized
        air_loop_vent_sch = air_loop_hvac.availabilitySchedule.clone.to_ScheduleRuleset.get
        air_loop_vent_sch.setName("#{air_loop_hvac.name}_night_novent_schedule")
        next unless air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
        air_loop_oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
        next unless air_loop_oa_system.minimumOutdoorAirSchedule.is_initialized
        air_loop_oa_system.setMinimumOutdoorAirSchedule(air_loop_vent_sch)
        oa_schd_op_count += 1
      #end
	  
	  end 
    return true
  end
end

# register the measure to be used by the application
NighttimeOAControls.new.registerWithApplication
