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
class RefrigAntisweatControls < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'refrig_antisweat_controls'
  end

  # human readable description
  def description
    return 'This measures checks if the model contains refrigeration cases and changes the AntiSweat heater Control.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure receives the AntiSweat heater Control from the user. Then it looks for refrigerated display cases; it loops through them; it checks the current AntiSweat heater Control of each case and it substitute it with the one chosen by the user.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    choices = OpenStudio::StringVector.new
    choices << 'None'
    choices << 'Constant'
    choices << 'Linear'
    choices << 'DewpointMethod'
    choices << 'HeatBalanceMethod'
    as_heater_control_type = OpenStudio::Measure::OSArgument.makeChoiceArgument('as_heater_control_type', choices, true)
    as_heater_control_type.setDisplayName('Anti-Sweat Heater Control Type:')
    as_heater_control_type.setDefaultValue('None')
    args << as_heater_control_type

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
      return true
    end

    # make choice argument for as heater control type
    as_heater_control_type = runner.getStringArgumentValue('as_heater_control_type', user_arguments)

    total_case_length_m = 0
    numb_of_cases_without_as = 0
    numb_of_cases_already_set = 0
    model.getRefrigerationCases.each do |ref_case|
      if ref_case.caseAntiSweatHeaterPowerperUnitLength == 0
        runner.registerInfo("Anti-sweat heater power for case #{ref_case.name} is set to 0, therefore the Anti-sweat heater control type can only be set to 'None'.")
        numb_of_cases_without_as += 1
      elsif ref_case.antiSweatHeaterControlType == as_heater_control_type
        runner.registerInfo("Anti-sweat heater power for case #{ref_case.name} was already set to #{as_heater_control_type}.")
        numb_of_cases_already_set += 1
      else
        old_asheater_control_type = ref_case.antiSweatHeaterControlType
        ref_case.setAntiSweatHeaterControlType(as_heater_control_type)
        total_case_length_m += ref_case.caseLength
        runner.registerInfo("Anti-sweat heater control type for case #{ref_case.name} was changed from #{old_asheater_control_type} to #{as_heater_control_type}.")
      end
    end

    if total_case_length_m.zero? && ((numb_of_cases_already_set > 0) || (numb_of_cases_without_as > 0))
      runner.registerAsNotApplicable("The refrigeration cases in the current model don't have anti-sweat heater power or the control type is already set to #{as_heater_control_type}.")
      return false
    end

    # reporting final condition of model
    total_case_length_ft = OpenStudio.convert(total_case_length_m, 'm', 'ft').get
    runner.registerFinalCondition("The anti-sweat heater control type for #{total_case_length_ft.round} ft of case was changed to #{as_heater_control_type}.")
    runner.registerValue('refrig_antisweat_controls_ft_of_changed_cases', total_case_length_ft, 'ft')

    return true
  end
end

# register the measure to be used by the application
RefrigAntisweatControls.new.registerWithApplication
