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

# dependencies
require 'openstudio-standards'

# start the measure
class HVACChiller < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'hvac_chiller'
  end

  # human readable description
  def description
    return 'This measure gets an AFUE from the user, it compares it with current chillers in the model and increases the chillers AFUE in case it is lower than the chosen one.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure gets a value from the use, it loops through each chiller, it gets the thermal efficiency of each chiller.
            It is assumed AFUE = ThermalEfficiency, as indicated in the OpenStudio Standards.
            For each chiller, If the chosen AFUE is higher than the current chiller thermal efficiency, the latter is upgraded with the chosen AFUE.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    choices = OpenStudio::StringVector.new
    choices << '2019 Code Compliant Chiller'
    choices << 'Efficient Chiller (Future Code)'
    efficiency_level = OpenStudio::Measure::OSArgument.makeChoiceArgument('efficiency_level', choices, true)
    efficiency_level.setDisplayName('Chiller Efficiency Level')
    efficiency_level.setDefaultValue('Efficient Chiller (Future Code)')
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

    if model.getChillerElectricEIRs.empty?
      runner.registerAsNotApplicable('No electric chillers are present in the model.')
      return false
    end

    # assign the user inputs to variables
    efficiency_level = runner.getStringArgumentValue('efficiency_level', user_arguments)
    case efficiency_level
      when '2019 Code Compliant Chiller'
        template = 'ComStock 90.1-2013'
      when 'Efficient Chiller (Future Code)'
        template = 'ComStock DEER 2035'
    end

    # check if sizing run is needed
    run_sizing = false
    model.getChillerElectricEIRs.each do |chiller|
      break if run_sizing
      unless chiller.autosizedReferenceCapacity.is_initialized || chiller.referenceCapacity.is_initialized
        run_sizing = true
      end
    end

    # build standard to access methods
    std = Standard.build(template)

    # Check if sizing run is necessary
    if run_sizing
      runner.registerInfo('Chiller capacity not available. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/chiller_sizing_run") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    total_chiller_capacity_w = 0
    upgraded_chiller_count = 0
    model.getChillerElectricEIRs.each do |chiller|
      capacity_w = 0
      if chiller.referenceCapacity.is_initialized
        capacity_w = chiller.referenceCapacity.get
      elsif chiller.autosizedReferenceCapacity.is_initialized
        capacity_w = chiller.autosizedReferenceCapacity.get
      else
        runner.registerError("Capacity not available for chiller '#{chiller.name}' after sizing run.")
        return false
      end
      existing_cop = chiller.referenceCOP
      template_cop = std.chiller_electric_eir_standard_minimum_full_load_efficiency(chiller)
      capacity_tons = OpenStudio.convert(capacity_w, 'W', 'ton').get

      if existing_cop > template_cop
        runner.registerInfo("Chiller '#{chiller.name}' with a capacity of #{capacity_tons.round(0)} tons has an existing cop #{existing_cop.round(3)} which is greater than template cop #{template_cop.round(3)}.  Will not change chiller cop.")
      else
        std.chiller_electric_eir_apply_efficiency_and_curves(chiller, nil)
        runner.registerInfo("Chiller '#{chiller.name}' with a capacity of #{capacity_tons.round(0)} tons had an existing cop #{existing_cop.round(3)} and has new cop #{template_cop.round(3)}.")
        # rename chiller
        cop_kw_per_ton = std.cop_to_kw_per_ton(template_cop)
        chiller.setName("Chiller #{capacity_tons} tons #{cop_kw_per_ton} kW/ton")
        total_chiller_capacity_w += capacity_w
        upgraded_chiller_count += 1
      end
    end

    if upgraded_chiller_count.zero?
      runner.registerAsNotApplicable('No chiller has been upgraded. The current chillers in the model have an efficiency higher or equal to the chosen template.')
      return false
    end

    runner.registerFinalCondition("#{upgraded_chiller_count} chillers have been upgraded to #{efficiency_level}.")
    total_chiller_capacity_tons = OpenStudio.convert(total_chiller_capacity_w, 'W', 'ton').get
    runner.registerValue('hvac_chiller_capacity_tons', total_chiller_capacity_tons, 'tons')
    return true
  end
end

# register the measure to be used by the application
HVACChiller.new.registerWithApplication
