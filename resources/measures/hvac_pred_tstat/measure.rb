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
class HVACPredictiveThermostats < OpenStudio::Measure::ModelMeasure
  # Human readable name
  def name
    return 'Predictive Thermostats'
  end

  # Human readable description
  def description
    return 'Predictive thermostats adapt over time to learn when occupants are going to be present or not, and widen the heating and cooling deadband when the space is unoccupied.'
  end

  # Human readable description of modeling approach
  def modeler_description
    return 'For each zone in the model, determine the current heating and cooling setback and setup temperatures.  Compare the thermostat schedule to the occupancy schedule.  Whenever the occupancy level is below the threshold, change the thermostat to the setback/setup temperature.  This modeling approach assumes very good, very granular predictive capabilities.'
  end

  # Define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Make an argument for reduction percentage
    occ_threshold = OpenStudio::Measure::OSArgument.makeDoubleArgument('occ_threshold', true)
    occ_threshold.setDisplayName('Occupancy Threshold For Setback')
    occ_threshold.setUnits('%')
    occ_threshold.setDefaultValue(10.0)
    args << occ_threshold

    return args
  end

  # Method to find the maximum profile value for a schedule, not including values from the summer and winter design days.
  def get_min_max_val(sch_ruleset)
    # Skip non-ruleset schedules
    return false if sch_ruleset.to_ScheduleRuleset.empty?
    sch_ruleset = sch_ruleset.to_ScheduleRuleset.get

    # Gather profiles
    profiles = []
    default_profile = sch_ruleset.to_ScheduleRuleset.get.defaultDaySchedule
    profiles << default_profile
    sch_ruleset.scheduleRules.each do |rule|
      profiles << rule.daySchedule
    end

    # Search all the profiles for the min and max
    min = nil
    max = nil
    profiles.each do |profile|
      profile.values.each do |value|
        if min.nil?
          min = value
        else
          if min > value then min = value end
        end
        if max.nil?
          max = value
        else
          if max < value then max = value end
        end
      end
    end
    return { 'min' => min, 'max' => max }
  end

  # Method to increase the setpoint values in a day schedule by a specified amount
  def adjust_pred_tstat_day_sch(day_sch, occ_times, occ_values, occ_threshold_pct, occ_temp_c, unocc_temp_c)
    day_sch.clearValues
    new_times = []
    new_values = []
    for i in 0..(occ_values.length - 1)
      occ_val = occ_values[i]
      if occ_val >= occ_threshold_pct
        new_values << occ_temp_c
        new_times << occ_times[i]
      else
        new_values << unocc_temp_c
        new_times << occ_times[i]
      end
    end

    for i in 0..(new_values.length - 1)
      day_sch.addValue(new_times[i], new_values[i])
    end
  end

  # Method to increase the setpoint values for all day schedules in a ruleset by a specified amount
  def create_pred_tstat_ruleset_sch(model, tstat_sch, occ_sch, occ_threshold_pct, occ_temp_c, unocc_temp_c)
    # Skip non-ruleset schedules
    return false if occ_sch.to_ScheduleRuleset.empty?
    occ_sch = occ_sch.to_ScheduleRuleset.get

    # Clone thermostat schedule
    tstat_sch = tstat_sch.to_ScheduleRuleset.get
    pred_tstat_sch = tstat_sch.clone(model).to_ScheduleRuleset.get

    # Create array containing occupancy values and times
    occ_times = occ_sch.defaultDaySchedule.times.dup
    occ_values = occ_sch.defaultDaySchedule.values.dup

    # Default day schedule
    adjust_pred_tstat_day_sch(pred_tstat_sch.defaultDaySchedule, occ_times, occ_values, occ_threshold_pct, occ_temp_c, unocc_temp_c)

    # All other day profiles
    pred_tstat_sch.scheduleRules.each do |sch_rule|
      adjust_pred_tstat_day_sch(sch_rule.daySchedule, occ_times, occ_values, occ_threshold_pct, occ_temp_c, unocc_temp_c)
    end

    # Winter design day
    adjust_pred_tstat_day_sch(pred_tstat_sch.winterDesignDaySchedule, occ_times, occ_values, occ_threshold_pct, occ_temp_c, occ_temp_c)

    # Summer design day
    adjust_pred_tstat_day_sch(pred_tstat_sch.summerDesignDaySchedule, occ_times, occ_values, occ_threshold_pct, occ_temp_c, occ_temp_c)

    # Set the schedule type limits
    type_limits = nil
    if model.getScheduleTypeLimitsByName('Temperature').is_initialized
      type_limits = model.getScheduleTypeLimitsByName('Temperature').get
    else
      type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
      type_limits.setName('Temperature')
      type_limits.setLowerLimitValue(0.0)
      type_limits.setUpperLimitValue(100.0)
      type_limits.setNumericType('Continuous')
      type_limits.setUnitType('Temperature')
    end
    pred_tstat_sch.setScheduleTypeLimits(type_limits)

    return pred_tstat_sch
  end

  # Define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    occ_threshold = runner.getDoubleArgumentValue('occ_threshold', user_arguments)
    occ_threshold_mult = occ_threshold / 100

    # Loop through all zones in the model, get their thermostats,
    # and determine the heating and cooling setback and normal values.
    # Then, go through the occupancy schedule for each zone and set the
    # thermostat setpoint to the setback value for any hour where the
    # occupancy is less than the threshold.  If the original thermostat
    # has no setback, make the setback 5 F and warn the user.
    default_setback_delta_f = 5
    default_setback_delta_c = OpenStudio.convert(default_setback_delta_f, 'R', 'K').get.round(1)

    zones_changed = []
    occ_sch_to_htg_sch_map = {}
    occ_sch_to_clg_sch_map = {}
    old_clg_profiles = []
    old_htg_profiles = []
    old_clg_values = []
    old_htg_values = []
    new_clg_profiles = []
    new_htg_profiles = []
    new_clg_values = []
    new_htg_values = []

    model.getThermalZones.each do |zone|
      # Skip zones that have no occupants or have occupants with no schedule
      people = []
      zone.spaces.each do |space|
        people += space.people
        if space.spaceType.is_initialized
          people += space.spaceType.get.people
        end
      end

      if people.empty?
        runner.registerInfo("Zone #{zone.name} has no people, predictive thermostat not applicable.")
        next
      end

      occ = people[0]
      if occ.numberofPeopleSchedule.empty?
        runner.registerInfo("Zone #{zone.name} has people but no occupancy schedule, predictive thermostat not applicable.")
        next
      end

      occ_sch = occ.numberofPeopleSchedule.get

      # Skip zones with no thermostat or no dual-setpoint thermostat
      next if zone.thermostat.empty?
      if zone.thermostat.get.to_ThermostatSetpointDualSetpoint.empty?
        runner.registerInfo("Zone #{zone.name} has people but no thermostat, predictive thermostat not applicable.")
        next
      end
      tstat = zone.thermostat.get.to_ThermostatSetpointDualSetpoint.get

      # Skip thermostats that don't have both heating and cooling schedules
      if tstat.heatingSetpointTemperatureSchedule.empty? || tstat.coolingSetpointTemperatureSchedule.empty?
        runner.registerInfo("Zone #{zone.name} is missing either a heating or cooling schedule, predictive thermostat not applicable.")
        next
      end
      htg_sch = tstat.heatingSetpointTemperatureSchedule.get
      clg_sch = tstat.coolingSetpointTemperatureSchedule.get

      # Skip the zone if the heating setpoint goes below 13 C or cooling setpoint goes above 30 C
      if get_min_max_val(htg_sch)['min'] < 13 || get_min_max_val(clg_sch)['max'] > 30
        tstat.setHeatingSetpointTemperatureSchedule(htg_sch)
        tstat.setCoolingSetpointTemperatureSchedule(clg_sch)
        next
      else
        # Find the heating setup and setback temps
        htg_occ = get_min_max_val(htg_sch)['max']
        htg_unocc = get_min_max_val(htg_sch)['min']
        htg_setback = (htg_occ - htg_unocc).round(1)
        if htg_setback <= 1
          htg_unocc = htg_occ - htg_setback
          runner.registerWarning("Zone #{zone.name} had an insignificant/no heating setback of #{htg_setback} delta C.  Setback was changed to #{default_setback_delta_c} delta C because a predictive thermostat doesn't make sense without a setback.")
        end

        # Find the cooling setup and setback temps
        clg_occ = get_min_max_val(clg_sch)['min']
        clg_unocc = get_min_max_val(clg_sch)['max']
        clg_setback = (clg_unocc - clg_occ).round(1)
        if clg_setback <= 1
          clg_unocc = clg_occ + default_setback_delta_c
          runner.registerWarning("Zone #{zone.name} had an insignificant/no cooling setback of #{clg_setback} delta C.  Setback was changed to #{default_setback_delta_c} delta C because a predictive thermostat doesn't make sense without a setback.")
        end

        # Create predicitive thermostat schedules that go to
        # setback when occupancy is below the specified threshold
        # (or retrieve one previously created).
        # Heating schedule
        pred_htg_sch = nil
        if occ_sch_to_htg_sch_map[occ_sch]
          pred_htg_sch = occ_sch_to_htg_sch_map[occ_sch]
        else
          pred_htg_sch = create_pred_tstat_ruleset_sch(model, htg_sch, occ_sch, occ_threshold_mult, htg_occ, htg_unocc)
          pred_htg_sch.setName("#{occ_sch.name} Predictive Htg Sch")
          occ_sch_to_htg_sch_map[occ_sch] = pred_htg_sch
        end
        # Cooling schedule
        pred_clg_sch = nil
        if occ_sch_to_clg_sch_map[occ_sch]
          pred_clg_sch = occ_sch_to_clg_sch_map[occ_sch]
        else
          pred_clg_sch = create_pred_tstat_ruleset_sch(model, clg_sch, occ_sch, occ_threshold_mult, clg_occ, clg_unocc)
          pred_clg_sch.setName("#{occ_sch.name} Predictive Clg Sch")
          occ_sch_to_clg_sch_map[occ_sch] = pred_clg_sch
        end

        tstat.setHeatingSetpointTemperatureSchedule(pred_htg_sch)
        tstat.setCoolingSetpointTemperatureSchedule(pred_clg_sch)

        zones_changed << zone
        runner.registerInfo("Applied a predictive thermostat to #{zone.name}.")
      end
    end

    # Report if the measure is not applicable
    if zones_changed.empty?
      runner.registerAsNotApplicable('This measure is not applicable because none of the zones had both occupants and a thermostat.')
      return false
    end

    # Report final condition
    runner.registerFinalCondition("Added predictive thermostats to #{zones_changed.size} zones in the building by setting the thermostat to a setback temperature if occupancy level was below #{occ_threshold}%.")
    runner.registerValue('hvac_pred_tstat_num_zones', zones_changed.size)

    return true
  end
end

# Register the measure to be used by the application
HVACPredictiveThermostats.new.registerWithApplication
