# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************
# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# Dependencies
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'openstudio-standards'
require 'fileutils'
require "#{File.dirname(__FILE__)}/resources/Standards.ThermalZoneHVAC"
require "#{File.dirname(__FILE__)}/resources/Standards.AirLoopHVAC"
require "#{File.dirname(__FILE__)}/resources/Standards.ScheduleRuleset"
require "#{File.dirname(__FILE__)}/resources/Standards.ScheduleConstant"

# Start the measure
class HVACOperationsSchedule < OpenStudio::Measure::ModelMeasure
  # Human readable name
  def name
    return 'Correct HVAC Operations Schedule'
  end

  # Human readable description
  def description
    return 'This energy efficiency measure (EEM) modifies the availability schedules of HVAC fans, pumps, chillers, and zone thermostats to represent a movement to an occupancy based scheduling of HVAC equipment, allowing the building to coast towards its unoccupied state while it is still partially occupied. An AirLoop occupancy threshold value of lower than 5 percent of peak occupancy is considered to define when HVAC equipment should not operate.  Energy can be saved by shutting down cooling equipment when it is not needed, as soon as occupants leave the building and prior to their arrival. While this measure may save energy, unmet hours and occupant thermal comfort conditions during transient startup periods should be closely monitored. The measure also adds heating and cooling unmet hours and Simplified ASHRAE Standard 55 Thermal Comfort warning reporting variable to each thermal zone. '
  end

  # Human readable description of modeling approach
  def modeler_description
    return 'The measure loops through the AirLoops associated with the model, and determines an occupancy weighted schedule with values of 1 or 0 based on the percent of peak occupancy at the timestep being above or below a set threshold value of 5 percent. The resulting occupancy schedule is applied to the airloop attribute for the availability schedule.  The measure then loops through all thermal zones, examining if there are zone equipment objects attached. If there are one or more zone equipment object attached to the zone, a thermal zone occupancy weighted schedule with values of 1 or 0 based on the percent of peak occupancy at the timestep being above or below a set threshold value of 5 percent is generated. The schedule is then assigned to the availability schedule of the associated zone equipment. To prevent energy use by any corresponding plant loops, the pump control type attribute of Constant or Variable speed pump objects in the model are set to intermittent. The measure them adds heating and cooling unmet hours and Simplified ASHRAE Standard 55 warning reporting variable to each thermal zone. '
  end

  # Define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new
    return args
  end

  # Method to decide whether or not to change the operation schedule,
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
      runner.registerInfo("The new occupancy-tracking HVAC operation schedule, #{new_sch.name} (#{new_eflh.round} EFLH) is more aggressive than the existing schedule #{old_sch.name} (#{old_eflh.round} EFLH).")
      return true
    elsif new_eflh == old_eflh
      runner.registerWarning("The existing HVAC operation schedule, #{old_sch.name} (#{old_eflh.round} EFLH), is equally as aggressive as the new occupancy-tracking schedule #{new_sch.name} (#{new_eflh.round} EFLH).  Not applying new schedule.")
      return false
    elsif new_eflh > old_eflh
      runner.registerWarning("The existing HVAC operation schedule, #{old_sch.name} (#{old_eflh.round} EFLH), is more aggressive than the new occupancy-tracking schedule #{new_sch.name} (#{new_eflh.round} EFLH).  Not applying new schedule.")
      return false
    end
  end

  # Method to set the availability schedule of zone equipment,
  # first checking to make sure the new schedule has less EFLH
  # than the old schedule.
  def set_equip_availability_schedule(runner, thermal_zone, new_sch, zone_equip)
    old_schedule = zone_equip.availabilitySchedule
    if compare_eflh(runner, old_schedule, new_sch)
      zone_equip.setAvailabilitySchedule(new_sch)
      runner.registerInfo("The availability schedule named #{old_schedule.name} for the #{zone_equip.iddObjectType.valueName} named #{zone_equip.name} has been replaced with a new schedule named #{new_sch.name} representing the occupancy profile of the thermal zone named #{thermal_zone.name}.")
      return true
    else
      return false
    end
  end

  # Define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)
    # Use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Initialize variables
    zone_hvac_count = 0
    pump_count = 0
    air_loop_count = 0
    model.getAirLoopHVACs.each do |air_loop|
      air_loop.thermalZones.each do |zone|
        zone.spaces.each do |space|
          space_type = space.spaceType.get
          space_type.people.each do |occ|
            occ_sch = nil
            if occ.numberofPeopleSchedule.is_initialized
              # Call the method to generate a new occupancy schedule based on a 5% threshold
              occ_sch = occ.numberofPeopleSchedule.get
              old_sch = air_loop.availabilitySchedule
              if occ_sch == old_sch
                runner.registerInfo("The schedule for '#{air_loop.name}' is already set to match that of the building occupancy.  No changes were made to this object.")
                next
              end
              next unless compare_eflh(runner, old_sch, occ_sch)
              # Set the availability schedule of the airloop to the newly generated  schedule
              air_loop.setAvailabilitySchedule(occ_sch)
              runner.registerInfo("The availability schedule named '#{old_sch.name}' for '#{air_loop.name}' was replaced with a new schedule named '#{occ_sch.name}' which tracks the occupancy profile of the thermal zones on this airloop.")
              air_loop_count += 1
            end
            if occ_sch.nil?
              runner.registerInfo("Space '#{space.name.get}' does not have an occupancy schedule; will not apply occupancy schedule to associated air loop.")
            end
          end
        end
      end
    end

    # Loop through each thermal zone
    model.getAirLoopHVACs.each do |air_loop|
      air_loop.thermalZones.each do |thermal_zone|
        thermal_zone.spaces.each do |space|
          space_type = space.spaceType.get
          space_type.people.each do |occ|
            next unless occ.numberofPeopleSchedule.is_initialized
            # Zone equipments assigned to thermal zones
            thermal_zone_equipment = thermal_zone.equipment
            if thermal_zone_equipment.size >= 1
              # Run schedule method to create a new schedule ruleset, routines
              occ_sch = occ.numberofPeopleSchedule.get
              # Loop through Zone HVAC Equipment
              thermal_zone_equipment.each do |equip|
                # Getting the fan exhaust object & getting relevant information for it
                if equip.to_FanZoneExhaust.is_initialized
                  zone_equip = equip.to_FanZoneExhaust.get
                  old_schedule = zone_equip.availabilitySchedule.get
                  next unless compare_eflh(runner, old_schedule, occ_sch)
                  # Assign the 'occ_sch' here as exhaust's availability schedule
                  zone_equip.setAvailabilitySchedule(occ_sch)
                  runner.registerInfo("The availability schedule named '#{old_schedule.name}' for the OS_Fan_ZoneExhaust named '#{zone_equip.name}' was replaced with a new schedule named '#{occ_sch.name}' representing the occupancy profile of the thermal zone named '#{thermal_zone.name}'.")
                  zone_hvac_count += 1
                elsif equip.to_RefrigerationAirChiller.is_initialized
                  zone_equip = equip.to_RefrigerationAirChiller.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_WaterHeaterHeatPump.is_initialized
                  zone_equip = equip.to_WaterHeaterHeatPump.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACBaseboardConvectiveElectric.is_initialized
                  zone_equip = equip.to_ZoneHVACBaseboardConvectiveElectric.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACBaseboardConvectiveWater.is_initialized
                  zone_equip = equip.to_ZoneHVACBaseboardConvectiveWater.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACBaseboardRadiantConvectiveElectric.is_initialized
                  zone_equip = equip.to_ZoneHVACBaseboardRadiantConvectiveElectric.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACBaseboardRadiantConvectiveWater.is_initialized
                  zone_equip = equip.to_ZoneHVACBaseboardRadiantConvectiveWater.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACDehumidifierDX.is_initialized
                  zone_equip = equip.to_ZoneHVACDehumidifierDX.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACEnergyRecoveryVentilator.is_initialized
                  zone_equip = equip.to_ZoneHVACEnergyRecoveryVentilator.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACFourPipeFanCoil.is_initialized
                  zone_equip = equip.to_ZoneHVACFourPipeFanCoil.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACHighTemperatureRadiant.is_initialized
                  zone_equip = equip.to_ZoneHVACHighTemperatureRadiant.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACIdealLoadsAirSystem.is_initialized
                  zone_equip = equip.to_ZoneHVACIdealLoadsAirSystem.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACLowTemperatureRadiantElectric.is_initialized
                  zone_equip = equip.to_ZoneHVACLowTemperatureRadiantElectric.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACLowTempRadiantConstFlow.is_initialized
                  zone_equip = equip.to_ZoneHVACLowTempRadiantConstFlow.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACLowTempRadiantVarFlow.is_initialized
                  zone_equip = equip.to_ZoneHVACLowTempRadiantVarFlow.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
                  zone_equip = equip.to_ZoneHVACPackagedTerminalAirConditioner.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
                  zone_equip = equip.to_ZoneHVACPackagedTerminalHeatPump.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized
                  old_schedule = equip.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.get.terminalUnitAvailabilityschedule
                  next unless compare_eflh(runner, old_schedule, occ_sch)
                  equip.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.get.setTerminalUnitAvailabilityschedule(occ_sch)
                  runner.registerInfo("The availability schedule for the Zone HVAC Terminal Unit Variable Refrigerant Flow Object has been replaced with a new schedule named #{occ_sch.name} representing the occupancy profile of the thermal zone named #{thermal_zone.name}.")
                  zone_hvac_count += 1
                elsif equip.to_ZoneHVACUnitHeater.is_initialized
                  zone_equip = equip.to_ZoneHVACUnitHeater.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneHVACUnitVentilator.is_initialized
                  zone_equip = equip.to_ZoneHVACUnitVentilator.get
                  zone_hvac_count += 1 if set_equip_availability_schedule(runner, thermal_zone, occ_sch, zone_equip)
                elsif equip.to_ZoneVentilationDesignFlowRate.is_initialized
                  runner.registerInfo("Thermal Zone named #{thermal_zone.name} has a Zone Ventilation Design Flow Rate object attached as a ZoneHVACEquipment object. No modification were made to this object.")
                end
              end
            else
              runner.registerInfo("Thermal Zone named #{thermal_zone.name} has no Zone HVAC Equipment objects attached - therefore no schedule objects have been altered.")
            end
          end
        end
      end
    end

    # Change pump control status if any airloops or zone equipment were changed
    if air_loop_count > 0 || zone_hvac_count > 0
      model.getPlantLoops.each do |plant_loop|
        # Loop through each plant loop demand component
        plant_loop.demandComponents.each do |dc|
          if dc.to_PumpConstantSpeed.is_initialized
            cs_pump = dc.to_PumpConstantSpeed.get
            if cs_pump.pumpControlType == 'Intermittent'
              runner.registerInfo("Demand side Constant Speed Pump object named #{cs_pump.name} on the plant loop named #{dc.name} had a pump control type attribute already set to intermittent. No changes will be made to this object.")
            else
              cs_pump.setPumpControlType('Intermittent')
              runner.registerInfo("Pump Control Type attribute of Demand side Constant Speed Pump object named #{cs_pump.name} on the plant loop named #{dc.name} was changed from continuous to intermittent.")
              pump_count += 1
            end
          end

          if dc.to_PumpVariableSpeed.is_initialized
            vs_pump = dc.to_PumpVariableSpeed.get
            if vs_pump.pumpControlType == 'Intermittent'
              runner.registerInfo("Demand side Variable Speed Pump named #{vs_pump.name} on the plant loop named #{dc.name} had a pump control type attribute already set to intermittent. No changes will be made to this object.")
            else
              cs_pump.setPumpControlType('Intermittent')
              runner.registerInfo("Demand side Pump Control Type attribute of Variable Speed Pump named #{vs_pump.name} on the plant loop named #{dc.name} was changed from continuous to intermittent.")
              pump_count += 1
            end
          end
        end

        # Loop through each plant loop supply component
        plant_loop.supplyComponents.each do |sc|
          if sc.to_PumpConstantSpeed.is_initialized
            cs_pump = sc.to_PumpConstantSpeed.get
            if cs_pump.pumpControlType == 'Intermittent'
              runner.registerInfo("Supply side Constant Speed Pump object named #{cs_pump.name} on the plant loop named #{sc.name} had a pump control type attribute already set to intermittent. No changes will be made to this object.")
            else
              cs_pump.setPumpControlType('Intermittent')
              runner.registerInfo("Supply Side Pump Control Type atteribute of Constant Speed Pump named #{cs_pump.name} on the plant loop named #{sc.name} was changed from continuous to intermittent.")
              pump_count += 1
              end
          end

          if sc.to_PumpVariableSpeed.is_initialized
            vs_pump = sc.to_PumpVariableSpeed.get
            if vs_pump.pumpControlType == 'Intermittent'
              runner.registerInfo("Supply side Variable Speed Pump object named #{vs_pump.name} on the plant loop named #{sc.name} had a pump control type attribute already set to intermittent. No changes will be made to this object.")
            else
              vs_pump.setPumpControlType('Intermittent')
              runner.registerInfo("Pump Control Type attribute of Supply Side Variable Speed Pump named #{vs_pump.name} on the plant loop named #{sc.name} was changed from continuous to intermittent.")
              pump_count += 1
            end
          end
        end
      end
    end

    # Write N/A message
    if (air_loop_count + zone_hvac_count + pump_count).zero?
      runner.registerAsNotApplicable('The model did not contain any Airloops, Thermal Zones having ZoneHVACEquipment objects or associated plant loop pump objects to act upon. The measure is not applicable.')
      return false
    end

    # Report initial condition of model
    runner.registerInitialCondition("The model started with #{air_loop_count} AirLoops, #{zone_hvac_count} Zone HVAC Equipment Objects and #{pump_count} pump objects subject to modifications.")

    # Report final condition of model
    runner.registerFinalCondition("The measure modified the availability schedules of #{air_loop_count} AirLoops and #{zone_hvac_count} Zone HVAC Equipment objects. #{pump_count} pump objects had control settings modified.")
    runner.registerValue('hvac_op_sch_num_air_loops', air_loop_count)

    # Add ASHRAE Standard 55 warnings
    reporting_frequency = 'Timestep'
    outputVariable = OpenStudio::Model::OutputVariable.new('Zone Thermal Comfort ASHRAE 55 Adaptive Model 90% Acceptability Status []', model)
    outputVariable.setReportingFrequency(reporting_frequency)
    runner.registerInfo("Adding output variable for 'Zone Thermal Comfort ASHRAE 55 Adaptive Model 90% Acceptability Status' reporting at the model timestep.")

    return true
  end
end

# register the measure to be used by the application
HVACOperationsSchedule.new.registerWithApplication
