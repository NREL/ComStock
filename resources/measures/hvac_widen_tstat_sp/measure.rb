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

# Start the measure
class HVACWidenThermostatSetpoint < OpenStudio::Measure::ModelMeasure
  # Human readable name
  def name
    return 'Widen Thermostat Setpoint'
  end

  # Human readable description
  def description
    return 'It is well understood that for many HVAC systems, significant energy can be saved by increasing the thermostat deadband-the range of zone temperatures at which neither heating nor cooling systems are needed. While saving energy, it is important to acknowledge that large or aggressive deadbands can result in occupant comfort issues and complaints. ASHRAE Standard 55 defines an envelope for thermal comfort, and predictions of thermal comfort should be analyzed to determine an appropriate balance between energy conservation and occupant comfort/productivity. This measure analyzes the heating and cooling setpoint schedules associated with each thermal zone in the model, and widens the temperature deadband of all schedule run period profiles from their existing value by 1.5 degrees F.'
  end

  # Human readable description of modeling approach
  def modeler_description
    return 'The measure loops through the heating and cooling thermostat schedules associated each thermal zone. The existing heating and cooling schedules are cloned, and the all run period profiles are then modified by adding a +1.5 deg F shift to the all values of the cooling thermostat schedule and a -1.5 degree F shift to all values of the heating thermostat schedule.  Design Day profiles are not modified. The modified thermostat schedules are then assigned to the thermal zone.  For each Thermal Zone, ASHRAE 55 Thermal Comfort Warnings is also enabled. Zone Thermal Comfort ASHRAE 55 Adaptive Model 90% Acceptability Status output variables is also added to the model.'
  end

  # Define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new
    return args
  end

  # Define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Use the built-in error checking
    unless runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Write 'As Not Applicable' message
    if model.getThermalZones.empty?
      runner.registerAsNotApplicable('There are no conditioned thermal zones in the model. Measure is not applicable.')
      return false
    end

    # Initialize variables
    zone_count = 0
    edited_clg_tstat_schedules = []
    edited_htg_tstat_schedules = []

    # Get the thermal zones and loop through them
    model.getThermalZones.each do |thermal_zone|
      next unless thermal_zone.thermostatSetpointDualSetpoint.is_initialized
      zone_thermostat = thermal_zone.thermostatSetpointDualSetpoint.get
      zone_count += 1

      if zone_thermostat.coolingSetpointTemperatureSchedule.is_initialized
        clg_tstat_schedule = zone_thermostat.coolingSetpointTemperatureSchedule.get

        # check if already edited
        unless edited_clg_tstat_schedules.include? "#{clg_tstat_schedule.name}"
          if clg_tstat_schedule.to_ScheduleRuleset.is_initialized
            clg_tstat_schedule = clg_tstat_schedule.to_ScheduleRuleset.get

            # Gather schedule profiles
            schedule_profiles = []
            default_profile = clg_tstat_schedule.to_ScheduleRuleset.get.defaultDaySchedule
            schedule_profiles << default_profile
            clg_tstat_schedule.scheduleRules.each { |rule| schedule_profiles << rule.daySchedule }

            # Adjust profiles by + 1.5 deg F (0.833 C)
            schedule_profiles.each do |profile|
              time_h = profile.times
              i=0
              profile.values.each do |value|
                new_value = value + OpenStudio.convert(1.5, 'R', 'K').get
                profile.addValue(time_h[i], new_value)
                i+=1
              end
            end

            old_name = clg_tstat_schedule.name
            clg_tstat_schedule.setName("#{clg_tstat_schedule.name}+1.5F")
            runner.registerInfo("The existing cooling thermostat '#{old_name}' has been changed to #{clg_tstat_schedule.name}.")
            edited_clg_tstat_schedules << "#{clg_tstat_schedule.name}"
          end
        end
      else
        runner.registerInfo("The dual setpoint thermostat object named #{zone_thermostat.name} serving thermal zone #{thermal_zone.name} did not have a cooling setpoint temperature schedule associated with it.")
      end

      if zone_thermostat.heatingSetpointTemperatureSchedule.is_initialized
        htg_tstat_schedule = zone_thermostat.heatingSetpointTemperatureSchedule.get

        # check if already edited
        unless edited_htg_tstat_schedules.include? "#{htg_tstat_schedule.name}"
          if htg_tstat_schedule.to_ScheduleRuleset.is_initialized
            htg_tstat_schedule = htg_tstat_schedule.to_ScheduleRuleset.get

            # Gather schedule profiles
            schedule_profiles = []
            default_profile = htg_tstat_schedule.to_ScheduleRuleset.get.defaultDaySchedule
            schedule_profiles << default_profile
            htg_tstat_schedule.scheduleRules.each { |rule| schedule_profiles << rule.daySchedule }

            # Adjust profiles by - 1.5 deg F (0.833 C)
            schedule_profiles.each do |profile|
              time_h = profile.times
              i=0
              profile.values.each do |value|
                new_value = value - OpenStudio.convert(1.5, 'R', 'K').get
                profile.addValue(time_h[i], new_value)
                i+=1
              end
            end

            old_name = htg_tstat_schedule.name
            htg_tstat_schedule.setName("#{htg_tstat_schedule.name}-1.5F")
            runner.registerInfo("The existing heating thermostat '#{old_name}' has been changed to #{htg_tstat_schedule.name}.")
            edited_htg_tstat_schedules << "#{htg_tstat_schedule.name}"
          end
        end
      else
        runner.registerInfo("The dual setpoint thermostat object named #{zone_thermostat.name} serving thermal zone #{thermal_zone.name} did not have a heating setpoint temperature schedule associated with it.")
      end
    end

    # Add ASHRAE 55 Comfort Warnings are applied to people objects
    # Get people objects and people definitions in model
    people_defs = model.getPeopleDefinitions

    # Loop through people objects
    people_defs.sort.each do |people_def|
      next unless people_def.instances.empty?
      people_def.setEnableASHRAE55ComfortWarnings(true)
    end

    reporting_frequency = 'Timestep'
    output_variable = OpenStudio::Model::OutputVariable.new('Zone Thermal Comfort ASHRAE 55 Adaptive Model 90% Acceptability Status []', model)
    output_variable.setReportingFrequency(reporting_frequency)
    runner.registerInfo("Adding output variable for 'Zone Thermal Comfort ASHRAE 55 Adaptive Model 90% Acceptability Status' reporting '#{reporting_frequency}'")

    # Report final condition of model
    num_edited_schedules = [edited_clg_tstat_schedules.length, edited_htg_tstat_schedules.length]
    runner.registerFinalCondition("Widened #{num_edited_schedules[0]} cooling thermostat setpoint schedules by +1.5F and #{num_edited_schedules[1]} heating thermostat setpoint schedules by -1.5F serving #{zone_count} thermal zones.")
    runner.registerValue('hvac_widen_tstat_sp_num_zones', zone_count)

    return true
  end
end

# Register the measure to be used by the application
HVACWidenThermostatSetpoint.new.registerWithApplication
