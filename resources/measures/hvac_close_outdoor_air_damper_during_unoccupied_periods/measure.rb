# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/measures/measure_writing_guide/

require_relative 'resources/Standards.ThermalZoneHVAC'
require_relative 'resources/Standards.AirLoopHVAC'
require_relative 'resources/Standards.ScheduleRuleset'
require_relative 'resources/Standards.ScheduleConstant'

# start the measure
class HVACCloseOutdoorAirDamperDuringUnoccupiedPeriods < OpenStudio::Ruleset::ModelUserScript
  # human readable name
  def name
    return 'Close Outdoor Air Damper During Unoccupied Periods'
  end

  # human readable description
  def description
    return 'This energy efficiency measure (EEM) changes the minimum outdoor air flow requirement of all Controller:OutdoorAir objects associated with airloops and present in a model to represent a value equal to 0 cfm during unoccupied periods. For single zone air systems, unoccupied periods are defined as periods when the any connected thermal zone has less than 5% of the peak specified occupancy.  For multi zone air systems, unoccupied periods are defined as periods when the average occupancy of all connected thermal zones is less than 5% of the peak specified occupancy.  In addition to outdoor air controller objects attached to airloops, the measure also limits the outdoor air of Four Pipe Fan Coil Units and Unit Ventilator objects if they are present as Zone HVAC equipment objects. '
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure loops through all Thermal zones connected to Airloops having an Outdoor Air Controller object, and determines a space-weighted occupancy schedule for each attached thermal zone. The resulting occupancy schedules for each thermal zone are stepped through from hour 0 to hour 24. An airloop is considered occupied during a time period if all thermal zones representing occupancy associated with an air loop have a current occupancy value that is greater than 5% of the annual peak occupancy value. The measure generates a new minimum outdoor air schedule having values of 0 where the all connected thermal zones have less than 5% occupancy and values of 1.0 for all other hours. Finally, the measure examines all Zone HVAC Equipment objects associated with an airloop. If Zone HVAC equipment object of type Four Pipe Fan Coil Unit or Unit Ventilator are found, the occupancy patterns associated with the thermal zone are analyzed and outside air schedules are assigned to allow design outside air levels when the thermal zone is occupied by more than 5 percent of thermal zone peak occupancy, otherwise shit the outside air damper of the Zone HVAC Equipment object completely.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    return args
  end

  # Method to decide whether or not to change the exhaust fan schedule,
  # in case the new schedule is less aggressive than the existing schedule.
  def compare_eflh(runner, old_sch, new_sch)
    if old_sch.to_ScheduleRuleset.is_initialized
      old_sch = old_sch.to_ScheduleRuleset.get
    elsif old_sch.to_ScheduleConstant.is_initialized
      old_sch = old_sch.to_ScheduleConstant.get
    else
      runner.registerWarning("Can only calculate equivalent full load hours for ScheduleRuleset or ScheduleConstant schedules. #{old_sch.name} is neither.")
      return false
    end

    if new_sch.to_ScheduleRuleset.is_initialized
      new_sch = new_sch.to_ScheduleRuleset.get
    elsif new_sch.to_ScheduleConstant.is_initialized
      new_sch = new_sch.to_ScheduleConstant.get
    else
      runner.registerWarning("Can only calculate equivalent full load hours for ScheduleRuleset or ScheduleConstant schedules. #{new_sch.name} is neither.")
      return false
    end

    new_eflh = new_sch.annual_equivalent_full_load_hrs
    old_eflh = old_sch.annual_equivalent_full_load_hrs
    if new_eflh < old_eflh
      runner.registerInfo("The new exhaust fan schedule, #{new_sch.name} (#{new_eflh.round} EFLH) is more aggressive than the existing schedule #{old_sch.name} (#{old_eflh.round} EFLH).")
      return true
    elsif new_eflh == old_eflh
      runner.registerWarning("The existing exhaust fan schedule, #{old_sch.name} (#{old_eflh.round} EFLH), is equally as aggressive as the new occupancy-tracking schedule #{new_sch.name} (#{new_eflh.round} EFLH).  Not applying new schedule.")
      return false
    elsif
      runner.registerWarning("The existing exhaust fan schedule, #{old_sch.name} (#{old_eflh.round} EFLH), is more aggressive than the new occupancy-tracking schedule #{new_sch.name} (#{new_eflh.round} EFLH).  Not applying new schedule.")
      return false
    end
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # initialize variables
    airloop_count = 0
    thermal_zone_equipment_count = 0
    oa_system_count = 0
    oa_system_no_exg_sch_count = 0
    airloop_no_oa_system_count = 0
    fan_coil_count = 0
    pthp_count = 0
    ptac_count = 0
    vrf_count = 0
    unit_ventilator_count = 0

    # loop through each air loop in the model
    model.getAirLoopHVACs.each do |air_loop|
      if air_loop.airLoopHVACOutdoorAirSystem.is_initialized
        air_loop_hvac_system = air_loop.airLoopHVACOutdoorAirSystem.get
        controller_outdoor_air = air_loop_hvac_system.getControllerOutdoorAir
        if controller_outdoor_air.minimumOutdoorAirSchedule.is_initialized
          exg_schedule = controller_outdoor_air.minimumOutdoorAirSchedule.get
          oa_damper_schedule = air_loop.get_occupancy_schedule(0.05)
          # Skip if the new schedule is less aggressive than the existing schedule
          next unless compare_eflh(runner, exg_schedule, oa_damper_schedule)

          controller_outdoor_air.setMinimumOutdoorAirSchedule(oa_damper_schedule)

          runner.registerInfo("The airloop named #{air_loop.name} has an outdoor air controller named #{controller_outdoor_air.name}. The minimum outdoor air schedule name of #{exg_schedule.name} has been replaced with a new schedule named #{oa_damper_schedule.name}.")
          airloop_count += 1
          oa_system_count += 1
        else
          runner.registerInfo("The outdoor air controller object named #{controller_outdoor_air.name} on the airloop named #{air_loop.name} did not have an existing minimum outdoor air schedule name assigned. No changes will be made to this outdoor air controller object.")
          airloop_count += 1
          oa_system_no_exg_sch_count += 1
          end # end if statement
      else
        runner.registerInfo("The Airloop named #{air_loop.name} does not have an AirLoopHVACOutdoorAirSystem and appears to be a recirculating AirLoop. No changes will be made to thw outdoor air controller associated with this AirLoop.")
        airloop_count += 1
        airloop_no_oa_system_count += 1
       end # end if statement
    end # end loop through airloops

    # loop through ZoneHVACequipment objects having outdoor air management capabilities
    model.getThermalZones.sort.each do |thermal_zone|
      thermal_zone_equipment = thermal_zone.equipment # get zone equipments assigned to thermal zones
      if thermal_zone_equipment.size >= 1
        # run schedule method to create a new schedule ruleset, routines
        occ_sch = thermal_zone.get_occupancy_schedule(0.05)

        # loop through Zone HVAC Equipment
        thermal_zone_equipment.each do |equip|
          thermal_zone_equipment_count = + 1
          equip_type = equip.iddObjectType

          if equip_type == OpenStudio::Model::ZoneHVACFourPipeFanCoil.iddObjectType
            zone_equip_hvac_obj = equip.to_ZoneHVACFourPipeFanCoil.get
            if zone_equip_hvac_obj.outdoorAirSchedule.is_initialized
              exg_outdoor_air_schedule = zone_equip_hvac_obj.outdoorAirSchedule.get
              # Skip if the new schedule is less aggressive than the existing schedule
              next unless compare_eflh(runner, exg_outdoor_air_schedule, occ_sch)
              zone_equip_hvac_obj.setOutdoorAirSchedule(occ_sch)
              runner.registerInfo("The outdoor air schedule named #{exg_outdoor_air_schedule.name} associated with the Four Pipe Fan Coil Unit named #{zone_equip_hvac_obj.name} has been replaced with a new schedule named #{occ_sch.name} representing closing the outdoor air damper when less than 5 percent of peak people are present in the thermal zone.")
              fan_coil_count += 1
            else
              runner.registerInfo("No outdoor air schedule was associated with the Zone HVAC Equipment 4-Pipe FCU object named #{zone_equip_hvac_obj.name}. A new schedule named #{occ_sch.name} has been assigned representing closing the outdoor air damper when less than 5 percent of peak people are present in the thermal zone.")
              fan_coil_count += 1
            end # end if
          end

          if equip_type == OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.iddObjectType
            zone_equip_hvac_obj = equip.to_ZoneHVACPackagedTerminalAirConditioner.get
            runner.registerWarning("Any outside air damper controls associated with the Zone HVAC Equipment PTAC object named #{zone_equip_hvac_obj.name} serving the thermal zone named #{thermal_zone.name} are fixed position dampers and cannot be changed.")
            ptac_count += 1
          end # end PTAC block

          if equip_type == OpenStudio::Model::ZoneHVACPackagedTerminalHeatPump.iddObjectType
            zone_equip_hvac_obj = equip.to_ZoneHVACPackagedTerminalHeatPump.get
            runner.registerWarning("Any outside air damper controls associated with the Zone HVAC Equipment PTHP object named #{zone_equip_hvac_obj.name} serving the thermal zone named #{thermal_zone.name} are fixed position dampers and cannot be changed.")
            pthp_count += 1
          end # end PTHP block

          if equip_type == OpenStudio::Model::ZoneHVACTerminalUnitVariableRefrigerantFlow.iddObjectType
            zone_equip_hvac_obj = equip.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.get
            runner.registerWarning("Any outside air damper controls associated with the Zone HVAC Equipment VRF object named #{zone_equip_hvac_obj.name} serving the thermal zone named #{thermal_zone.name} are fixed position dampers and cannot be changed.")
            vrf_count += 1
          end # end PTHP block

          if equip_type == OpenStudio::Model::ZoneHVACUnitVentilator.iddObjectType
            zone_equip_hvac_obj = equip.to_ZoneHVACUnitVentilator.get
            exg_control_method = zone_equip_hvac_obj.outdoorAirControlType
            exg_min_outdoor_air_sch = zone_equip_hvac_obj.minimumOutdoorAirSchedule
            zone_equip_hvac_obj.setMinimumOutdoorAirSchedule(occ_sch)
            zone_equip_hvac_obj.setOutdoorAirControlType('FixedTemperature')
            runner.registerInfo("The Zone HVAC Equipment Unit Ventilator object named #{zone_equip_hvac_obj.name} had the outside air control type attribute changed from #{exg_control_method} to Fixed Temperature the and minimum outdoor air schedule name changed from #{exg_min_outdoor_air_sch.name} to #{occ_sch.name}.")
            unit_ventilator_count += 1
          end # end Unit Ventilator block

          if equip_type == OpenStudio::Model::ZoneHVACWaterToAirHeatPump.iddObjectType
            zone_equip_hvac_obj = equip.to_ZoneHVACWaterToAirHeatPump.get
            runner.registerWarning("Any outside air damper controls associated with the Zone HVAC Equipment Water to Air Heat Pump object named #{zone_equip_hvac_obj.name} serving the thermal zone named #{thermal_zone.name} are fixed position dampers and cannot be changed.")
            pthp_count += 1
          end # end WAHP block
        end # end do loop throught thermal zone equipment objects associated with a zone
      end # end if statement for thermal zone equipment size > 1
    end # end loop through thermal zones

    # report not applicible message
    if (oa_system_count == 0) && (fan_coil_count == 0) && (unit_ventilator_count == 0)
      runner.registerAsNotApplicable('The model did not contain any airloops with outdoor air controllers, fan coil units or unit ventilator objects which this measure could consider modifying. The measure is not applicable.')
      return false
  end

    # report initial condition of model
    zone_equipment_total = fan_coil_count + unit_ventilator_count
    runner.registerInitialCondition("The measure began with #{airloop_count} airloop objects, #{oa_system_count} outdoor air controller objects and #{zone_equipment_total} Zone HVAC Equipment objects suitable for modifying.")

    # report final condition of model
    runner.registerFinalCondition("The measure completed by changing schedules to alter the minimum outdoor air damper controls for #{oa_system_count} outdoor air controller objects, #{fan_coil_count} four-pipe fan coil unit objects, and #{unit_ventilator_count} unit ventilator objects.")
    runner.registerValue('hvac_number_of_affected_systems', oa_system_count + fan_coil_count + unit_ventilator_count)
    return true
  end
end

# register the measure to be used by the application
HVACCloseOutdoorAirDamperDuringUnoccupiedPeriods.new.registerWithApplication
