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

# start the measure
class RefrigCaseLighting < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'refrig_case_lighting'
  end

  # human readable description
  def description
    return 'This measures checks if the model contains refrigeration cases and changes the lighting power density to a custom light level, such as T12, T8, LED.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure receives the power density level from the user. Then it looks for refrigerated display cases; it loops through them; it checks the current power density of each case and it substitute it with the level chosen by the user.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    choices = OpenStudio::StringVector.new
    choices << 'LED'
    choices << 'T8'
    choices << 'T12'
    light_choice = OpenStudio::Measure::OSArgument.makeChoiceArgument('light_choice', choices, true)
    light_choice.setDisplayName('Light Power Density:')
    light_choice.setDefaultValue('LED')
    args << light_choice

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
      runner.registerAsNotApplicable('No refrigerated cases are present in the current model, the model will not be altered.')
      return false
    end

    # get lighting choice argument
    light_choice = runner.getStringArgumentValue('light_choice', user_arguments)
    case light_choice
      when 'LED'
        reach_in_light_w_per_ft = 17.2
        service_cases_light_w_per_ft = 12.42
        other_cases_light_w_per_ft = 12.6
      when 'T8'
        reach_in_light_w_per_ft = 30.2
        service_cases_light_w_per_ft = 21.8
        other_cases_light_w_per_ft = 22.1
      when 'T12'
        reach_in_light_w_per_ft = 45.3
        service_cases_light_w_per_ft = 32.7
        other_cases_light_w_per_ft = 33.15
    end

    # change the lighting power density of selected cases
    new_lights_consumption_w = 0
    old_lights_consumption_w = 0
    total_case_length_m = 0
    total_tube_lighting_ft = 0
    numb_of_changed_cases = 0
    numb_of_cases_without_lights = 0
    model.getRefrigerationCases.each do |ref_case|
      case_category = ref_case.additionalProperties.getFeatureAsString('case_category')
      next unless case_category.is_initialized

      # ft of lighting tube per ft of display case
      case case_category.get
        when 'Ice Cream Reach-Ins', 'Frozen Food Reach-Ins'
          power_density_chosen_by_the_user_w_per_m = OpenStudio.convert(reach_in_light_w_per_ft, 'W/ft', 'W/m').get
          ft_tube_per_ft_case = 3.775
        when 'Service Meat Cases', 'Service Deli Cases', 'Service Bakery Cases'
          power_density_chosen_by_the_user_w_per_m = OpenStudio.convert(service_cases_light_w_per_ft, 'W/ft', 'W/m').get
          ft_tube_per_ft_case = 2.725
        when 'Deli Cases', 'Dairy Cases', 'Meat Cases Med', 'Beverage Cases', 'Salad Cases', 'Produce Cases Med', 'Floral Cases', 'Meat Cases Low', 'Produce Cases Low', 'Prepared Foods Cases'
          power_density_chosen_by_the_user_w_per_m = OpenStudio.convert(other_cases_light_w_per_ft, 'W/ft', 'W/m').get
          ft_tube_per_ft_case = 2.7625
        when 'Produce Islands', 'Ice Cream Coffins'
          power_density_chosen_by_the_user_w_per_m = OpenStudio.convert(other_cases_light_w_per_ft, 'W/ft', 'W/m').get
          ft_tube_per_ft_case = 0.0
      end

      if ref_case.installedCaseLightingPowerperUnitLength.is_initialized
        if ref_case.installedCaseLightingPowerperUnitLength.get.zero?
          numb_of_cases_without_lights += 1
          next
        end
      end

      if ref_case.standardCaseLightingPowerperUnitLength > power_density_chosen_by_the_user_w_per_m
        case_length_m = ref_case.caseLength
        total_case_length_m += case_length_m
        old_lights_consumption_w += case_length_m * ref_case.standardCaseLightingPowerperUnitLength
        new_lights_consumption_w += case_length_m * power_density_chosen_by_the_user_w_per_m
        ref_case.setStandardCaseLightingPowerperUnitLength(power_density_chosen_by_the_user_w_per_m)

        runner.registerInfo("Case #{ref_case.name} was modified.\n #{light_choice} lights were changed for #{OpenStudio.convert(case_length_m, 'm', 'ft').get.round} ft of case.")
        total_tube_lighting_ft += ft_tube_per_ft_case * OpenStudio.convert(case_length_m, 'm', 'ft').get
        numb_of_changed_cases += 1
      end
    end

    if numb_of_changed_cases.zero?
      if numb_of_cases_without_lights > 0
        runner.registerAsNotApplicable("The refrigeration cases in the current model don't have lights, the model will not be altered.")
      else
        runner.registerAsNotApplicable("Either the refrigeration cases in the current model already contain #{light_choice} lights, or they don't have appropriate additionalProperties.\nThe model will not be altered.")
      end
      return false
    end

    runner.registerInitialCondition("The starting power usage from refrigerated cases lights was #{old_lights_consumption_w.round(2)} W.")

    # reporting final condition of model
    total_case_length_ft = OpenStudio.convert(total_case_length_m, 'm', 'ft').get
    runner.registerFinalCondition("#{total_case_length_ft.round(2)} ft of refrigeration display cases were modified, for a total saving of #{(old_lights_consumption_w - new_lights_consumption_w).round(2)} W.")
    runner.registerValue('refrig_case_lighting_ft_lighting_tube', total_tube_lighting_ft.round, 'ft')

    return true
  end
end

# register the measure to be used by the application
RefrigCaseLighting.new.registerWithApplication
