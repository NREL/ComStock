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

# It was assumed doors can added only to the following case types:
# 'Deli Cases', 'Dairy Cases', 'Beverage Cases', 'Produce Cases Med', 'Meat Cases Med', 'Salad Cases', 'Floral Cases'
# Hussman D5L cases (no door) and Hussman DD5X-LP cases (with door) were used as a reference for existing and efficient cases.
# Cases cut-sheets are available in the measure folder.

# start the measure
class RefrigAddCaseDoors < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'refrig_add_case_doors'
  end

  # human readable description
  def description
    return 'This measure swaps Hussman D5L cases (no door) with Hussman DD5X-LP cases (with door)'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure swaps Hussman D5L cases with Hussman DD5X-LP cases'
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

    if model.getRefrigerationCases.empty?
      runner.registerAsNotApplicable('No refrigerated cases are present in the current model, it will not be altered.')
      return false
    end

    case_types_without_doors = ['Deli Cases', 'Dairy Cases', 'Beverage Cases', 'Produce Cases Med', 'Meat Cases Med', 'Salad Cases', 'Floral Cases'] # Hussman D5L model
    cooling_capacity_with_door_btuh_per_ft = 271.0
    lighting_level_with_door_w_per_ft = 14.75
    operating_temperature_with_door_F = 39.0
    evaporator_temperature_with_door_F = 34.0
    fan_power_with_door_w_per_ft = 4.5
    antisweat_heater_power_with_door = 0.0
    defrost_power_with_door = 0.0
    numb_defrosts_per_day = 1
    minutes_defrost = 60
    minutes_dripdown = 60

    cases_changed = 0
    total_case_length_m = 0
    model.getRefrigerationCases.each_with_index do |ref_case, def_start_hr_iterator|
      case_category = ref_case.additionalProperties.getFeatureAsString('case_category')
      next unless case_category.is_initialized
      next unless case_types_without_doors.include? case_category.get
      next unless ref_case.ratedTotalCoolingCapacityperUnitLength > OpenStudio.convert(OpenStudio.convert(cooling_capacity_with_door_btuh_per_ft, 'Btu/h', 'W').get, '1/ft', '1/m').get
      next unless ref_case.standardCaseLightingPowerperUnitLength > OpenStudio.convert(lighting_level_with_door_w_per_ft, '1/ft', '1/m').get

      ref_case.setCaseOperatingTemperature(OpenStudio.convert(operating_temperature_with_door_F, 'F', 'C').get)
      ref_case.setDesignEvaporatorTemperatureorBrineInletTemperature(OpenStudio.convert(evaporator_temperature_with_door_F, 'F', 'C').get)
      ref_case.setRatedTotalCoolingCapacityperUnitLength(OpenStudio.convert(OpenStudio.convert(cooling_capacity_with_door_btuh_per_ft, 'Btu/h', 'W').get, '1/ft', '1/m').get)
      ref_case.setOperatingCaseFanPowerperUnitLength(OpenStudio.convert(fan_power_with_door_w_per_ft, '1/ft', '1/m').get)
      ref_case.setStandardCaseLightingPowerperUnitLength(OpenStudio.convert(lighting_level_with_door_w_per_ft, '1/ft', '1/m').get)
      ref_case.setCaseAntiSweatHeaterPowerperUnitLength(antisweat_heater_power_with_door)
      ref_case.setMinimumAntiSweatHeaterPowerperUnitLength(antisweat_heater_power_with_door)
      ref_case.setCaseDefrostPowerperUnitLength(defrost_power_with_door)
      ref_case.setCaseDefrostType('OffCycle')

      old_schedule_defrost = ref_case.caseDefrostSchedule.get
      old_schedule_dripdown = ref_case.caseDefrostDripDownSchedule.get

      # new defrost schedule
      minutes_defrost = 59 if minutes_defrost > 59 # Just to make sure to remain in the same hour
      minutes_dripdown = 59 if minutes_dripdown > 59 # Just to make sure to remain in the same hour

      # add defrost and dripdown schedules
      defrost_sch_case = OpenStudio::Model::ScheduleRuleset.new(model)
      defrost_sch_case.setName('Refrigeration Defrost Schedule')
      defrost_sch_case.defaultDaySchedule.setName("Refrigeration Defrost Schedule Default - #{ref_case.name}")
      dripdown_sch_case = OpenStudio::Model::ScheduleRuleset.new(model)
      dripdown_sch_case.setName('Refrigeration Dripdown Schedule')
      dripdown_sch_case.defaultDaySchedule.setName("Refrigeration Dripdown Schedule Default - #{ref_case.name}")

      # stagger the defrosts for cases by 1 hr
      interval_defrost = (24 / numb_defrosts_per_day).floor # Hour interval between each defrost period
      if (def_start_hr_iterator + interval_defrost * numb_defrosts_per_day) > 23
        first_def_start_hr = 0 # Start over again at midnight when time reaches 23hrs
      else
        first_def_start_hr = def_start_hr_iterator
      end

      # add the specified number of defrost periods to the daily schedule
      (1..numb_defrosts_per_day).each do |defrost_of_day|
        def_start_hr = first_def_start_hr + ((1 - defrost_of_day) * interval_defrost)
        defrost_sch_case.defaultDaySchedule.addValue(OpenStudio::Time.new(0, def_start_hr, 0, 0), 0)
        defrost_sch_case.defaultDaySchedule.addValue(OpenStudio::Time.new(0, def_start_hr, minutes_defrost.to_int, 0), 0)
        dripdown_sch_case.defaultDaySchedule.addValue(OpenStudio::Time.new(0, def_start_hr, 0, 0), 0) # Dripdown is synced with defrost
        dripdown_sch_case.defaultDaySchedule.addValue(OpenStudio::Time.new(0, def_start_hr, minutes_dripdown.to_int, 0), 0)
      end
      defrost_sch_case.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)
      dripdown_sch_case.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0)

      # assign the defrost and dripdown schedules
      ref_case.setCaseDefrostSchedule(defrost_sch_case)
      ref_case.setCaseDefrostDripDownSchedule(dripdown_sch_case)
      unless old_schedule_defrost.directUseCount > 0
        old_schedule_defrost.remove
      end
      unless old_schedule_dripdown.directUseCount > 0
        old_schedule_dripdown.remove
      end

      # log case length
      total_case_length_m += ref_case.caseLength
      cases_changed += 1
      runner.registerInfo("Case #{ref_case.name} was swapped with a similar case equipped with a door.")
    end

    if total_case_length_m.zero?
      runner.registerAsNotApplicable('The refrigeration cases in the current model already contain doors or they are not suitable for having doors.')
      return false
    end

    # report final condition of model
    total_case_length_ft = OpenStudio.convert(total_case_length_m, 'm', 'ft').get
    runner.registerFinalCondition("#{cases_changed} refrigerated cases with length #{total_case_length_ft.round} ft have been swapped with more efficient cases that contain doors.")
    runner.registerValue('refrig_add_case_ft_of_cases_modified', total_case_length_ft.round, 'ft')

    return true
  end
end

# register the measure to be used by the application
RefrigAddCaseDoors.new.registerWithApplication
