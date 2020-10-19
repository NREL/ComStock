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

# Hussman cases were upgraded with 2017 code compliant Hussman cases and even more efficient Hussman cases.
# Each case is substituted with another one in the same category, with the same purpose.
# Cases cut-sheets are available in the measure folder.

require 'json'

# start the measure
class RefrigCaseUpgrades < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'refrig_case_upgrades'
  end

  # human readable description
  def description
    return 'This measure swaps old cases with 2017 code compliant cases and more efficient ones.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure swaps old cases with 2017 code compliant cases and more efficient ones.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    choices = OpenStudio::StringVector.new
    choices << '2017 Code Compliant'
    choices << 'State of the Art Efficiency'
    efficiency_level = OpenStudio::Measure::OSArgument.makeChoiceArgument('efficiency_level', choices, true)
    efficiency_level.setDisplayName('elect the level of efficiency')
    efficiency_level.setDefaultValue('2017 Code Compliant')
    args << efficiency_level

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

    # make choice argument for efficiency level
    efficiency_level = runner.getStringArgumentValue('efficiency_level', user_arguments)
    reference_cases_data = JSON.parse(File.read(File.dirname(__FILE__) + '/resources/cases.json'))

    cases_changed = 0
    total_case_length_m = 0
    model.getRefrigerationCases.each_with_index do |individual_case, def_start_hr_iterator|
      case_category = individual_case.additionalProperties.getFeatureAsString('case_category')
      next unless case_category.is_initialized
      case_category = case_category.get
      reference_cases_data.each do |reference_case|
        reference_case_category = reference_case['case_category']
        next unless reference_case_category == case_category
        next unless reference_case['efficiency_level'] == efficiency_level
        next unless OpenStudio.convert(OpenStudio.convert(reference_case['cooling_capacity_per_length'].to_f, 'Btu/h', 'W').get, '1/ft', '1/m').get <= individual_case.ratedTotalCoolingCapacityperUnitLength
        next unless OpenStudio.convert(reference_case['lighting_per_ft'].to_f, '1/ft', '1/m').get <= individual_case.standardCaseLightingPowerperUnitLength
        individual_case.setCaseOperatingTemperature(OpenStudio.convert(reference_case['operating temperature'], 'F', 'C').get)
        individual_case.setDesignEvaporatorTemperatureorBrineInletTemperature(OpenStudio.convert(reference_case['evaporator temperature'], 'F', 'C').get)
        individual_case.setRatedTotalCoolingCapacityperUnitLength(OpenStudio.convert(OpenStudio.convert(reference_case['cooling_capacity_per_length'], 'Btu/h', 'W').get, '1/ft', '1/m').get)
        individual_case.setOperatingCaseFanPowerperUnitLength(OpenStudio.convert(reference_case['evap_fan_power_per_length'], '1/ft', '1/m').get)
        individual_case.setStandardCaseLightingPowerperUnitLength(OpenStudio.convert(reference_case['lighting_per_ft'], '1/ft', '1/m').get)
        individual_case.setCaseAntiSweatHeaterPowerperUnitLength(OpenStudio.convert(reference_case['anti_sweat_power'], '1/ft', '1/m').get)
        individual_case.setMinimumAntiSweatHeaterPowerperUnitLength(OpenStudio.convert(reference_case['minimum_anti_sweat_heater_power_per_unit_length'], '1/ft', '1/m').get)
        individual_case.setCaseDefrostPowerperUnitLength(OpenStudio.convert(reference_case['defrost_power_per_length'], '1/ft', '1/m').get)
        individual_case.setCaseDefrostType(reference_case['defrost_type'])

        # adjust defrost schedule if present
        if individual_case.caseDefrostSchedule.is_initialized && individual_case.caseDefrostDripDownSchedule.is_initialized
          old_schedule_defrost = individual_case.caseDefrostSchedule.get
          old_schedule_dripdown = individual_case.caseDefrostDripDownSchedule.get

          # new defrost schedule
          numb_defrosts_per_day = reference_case['defrost_per_day'].to_f
          minutes_defrost = reference_case['defrost_duration'].to_f
          minutes_dripdown = reference_case['defrost_duration'].to_f
          minutes_defrost = 59 if minutes_defrost > 59 # Just to make sure to remain in the same hour
          minutes_dripdown = 59 if minutes_dripdown > 59 # Just to make sure to remain in the same hour

          # add defrost and dripdown schedules
          defrost_sch_case = OpenStudio::Model::ScheduleRuleset.new(model)
          defrost_sch_case.setName('Refrigeration Defrost Schedule')
          defrost_sch_case.defaultDaySchedule.setName("Refrigeration Defrost Schedule Default - #{individual_case.name}")
          dripdown_sch_case = OpenStudio::Model::ScheduleRuleset.new(model)
          dripdown_sch_case.setName('Refrigeration Dripdown Schedule')
          dripdown_sch_case.defaultDaySchedule.setName("Refrigeration Dripdown Schedule Default - #{individual_case.name}")

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
          individual_case.setCaseDefrostSchedule(defrost_sch_case)
          individual_case.setCaseDefrostDripDownSchedule(dripdown_sch_case)
          unless old_schedule_defrost.directUseCount > 0
            old_schedule_defrost.remove
          end
          unless old_schedule_dripdown.directUseCount > 0
            old_schedule_dripdown.remove
          end
        end

        # log case length
        total_case_length_m += individual_case.caseLength.to_f
        cases_changed += 1
        runner.registerInfo("Case #{individual_case.name} was swapped with a case with the following level of efficiency: #{efficiency_level}.")
      end
    end

    # check if there are no cases
    if total_case_length_m.zero?
      runner.registerAsNotApplicable("The refrigeration cases in the current model don't have proper additional properties\n or the level of efficiency is equal/grater than the chosen one.")
      return false
    end

    # report final condition of model
    total_case_length_ft = OpenStudio.convert(total_case_length_m, 'm', 'ft').get
    runner.registerFinalCondition("#{cases_changed} cases with length #{total_case_length_ft.round} ft were upgraded to #{efficiency_level}.")
    runner.registerValue('refrig_case_upgrades_ft_of_cases_modified', total_case_length_ft.round, 'ft')

    return true
  end
end

# register the measure to be used by the application
RefrigCaseUpgrades.new.registerWithApplication
