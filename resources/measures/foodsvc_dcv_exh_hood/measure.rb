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

# start the measure
class FoodSvcDcvExhaustHood < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'Kitchen Exhaust Demand Control Ventilation'
  end

  # human readable description
  def description
    return 'Kitchen exhaust fans are operated at maximum power for long periods of time, even when there is low kitchen activity. With DCV, a variable frequency drive allows the motor speed and outdoor air intake of an exhaust fan to be reduced below maximum when there is low cooking activity. DCV systems typically incorporate sensors on and around the exhaust hood to detect cooking activity either by temperature or the presence of smoke, steam, or other cooking byproducts. This measure adjusts the exhaust fan schedule based on the kitchen occupancy schedule, such that the fan power is reduced when kitchen occupancy (and thus cooking activity) is low.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'For building with a kitchen space type, find the kitchen occupancy schedule. Clone and rename. Loop through the schedule values and generate a new DCV Exhaust Fan Schedule based on the following logic: if occ=0, exh=0; if occ=0.01-0.49, exh=0.83; if occ=0.5-0.79, exh=0.9; if occ=0.8-0.94, exh=0.95; if occ=0.95-1, exh=1. The exhaust fan schedule represents the fraction of maximum fan speed, which is proportional to the cubic root of fan power (i.e. a 10% reduction in fan speed = 28% reduction in power). Replace the existing exhaust fan schedule with the new DCV Exhaust Fan Schedule.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # loop through space types to determine if building has a kitchen
    kitchen_space_types = []
    model.getSpaceTypes.each do |space_type|
      next if !space_type.standardsSpaceType.is_initialized
      kitchen_space_types << space_type if space_type.standardsSpaceType.get.to_s == 'Kitchen'
    end

    # not applicable if model does not have a kitchen
    if kitchen_space_types.empty?
      runner.registerAsNotApplicable('Model does not have a kitchen space type')
      return false
    end

    # make sure the model has zone exhaust fans
    exhaust_fans_present = false
    kitchen_space_types.each do |space_type|
      space_type.spaces.each do |space|
        space.thermalZone.get.equipment.each do |zone_equip|
          next unless zone_equip.to_FanZoneExhaust.is_initialized
          exhaust_fans_present = true
          break
        end
      end
    end

    # not applicable if there are not exhaust fans in kitchens
    unless exhaust_fans_present
      runner.registerAsNotApplicable('Model has kitchen space types but not exhaust fans.')
      return false
    end

    runner.registerInitialCondition("Model has #{kitchen_space_types.size} kitchen space types.")

    # loop through space types and apply DCV control to the exhaust fans
    total_exhaust_fan_hp = 0
    exhaust_fans_changed = 0
    kitchen_space_types.each do |space_type|
      # check that the space type is occupied
      if space_type.people.empty?
        runner.registerInfo("Space type '#{space_type}' does not have people; will not apply DCV control")
        next
      end

      # get the occupancy schedule for the first people object
      kitchen_occ_schedule = nil
      space_type.people.each do |occ|
        if occ.numberofPeopleSchedule.is_initialized
          kitchen_occ_schedule = occ.numberofPeopleSchedule.get
          break
        end
      end
      if kitchen_occ_schedule.nil?
        runner.registerInfo("Space type '#{space_type}' does not have an occupancy schedule; will not apply DCV control")
        next
      end

      # clone the kitchen occupancy schedule and rename as DCV kitchen exhaust schedule
      dcv_kitchen_exh_sch = kitchen_occ_schedule.clone(model).to_ScheduleRuleset.get
      dcv_kitchen_exh_sch.setName("#{space_type.name} Exhaust Fan Schedule with DCV")

      # adjust schedule profiles to model DCV control
      profiles = []
      profiles << dcv_kitchen_exh_sch.to_ScheduleRuleset.get.defaultDaySchedule
      dcv_kitchen_exh_sch.scheduleRules.each do |rule|
        profiles << rule.daySchedule
      end
      profiles.each do |profile|
        times = profile.times
        new_values = []
        profile.values.each do |value|
          if value == 0
            new_value = 0
            new_values << new_value
          elsif value > 0 && value < 0.5
            new_value = 0.83
            new_values << new_value
          elsif value >= 0.5 && value < 0.8
            new_value = 0.9
            new_values << new_value
          elsif value >= 0.8 && value < 0.95
            new_value = 0.95
            new_values << new_value
          elsif value >= 0.95 && value <= 1
            new_value = 1
            new_values << new_value
          end
        end
        profile.clearValues
        times.each_with_index do |time, i|
          profile.addValue(time, new_values[i])
        end
      end

      # apply new exhaust fan schedule to exhaust fans
      space_type.spaces.each do |space|
        space.thermalZone.get.equipment.each do |zone_equip|
          next unless zone_equip.to_FanZoneExhaust.is_initialized
          exhaust_fan = zone_equip.to_FanZoneExhaust.get
          exhaust_fan.setFlowFractionSchedule(dcv_kitchen_exh_sch)
          # get fan properties and log fan power
          fan_efficiency = exhaust_fan.fanEfficiency
          pressure_rise_pa = exhaust_fan.pressureRise
          air_flow_m3_per_s = exhaust_fan.maximumFlowRate.get
          air_flow_cfm = OpenStudio.convert(air_flow_m3_per_s, 'm^3/s', 'cfm').get
          fan_power_w = pressure_rise_pa.to_f * air_flow_m3_per_s.to_f / fan_efficiency.to_f
          exhaust_fan_hp = fan_power_w / 745.7 # 745.7 W/HP
          total_exhaust_fan_hp += exhaust_fan_hp
          runner.registerInfo("Set new DCV exhaust fan schedule '#{dcv_kitchen_exh_sch.name}' for fan '#{exhaust_fan.name}' with fan efficiency #{fan_efficiency.round(2)}, pressure rise #{pressure_rise_pa.round} Pa, and air flow rate #{air_flow_cfm.round} cfm.")
          exhaust_fans_changed += 1
        end
      end
    end

    runner.registerValue('foodsvc_dcv_exh_hood_fan_hp', total_exhaust_fan_hp, 'hp')
    runner.registerFinalCondition("Set new DCV schedules for #{exhaust_fans_changed} kitchen exhaust fans.")
    return true
  end
end
FoodSvcDcvExhaustHood.new.registerWithApplication
