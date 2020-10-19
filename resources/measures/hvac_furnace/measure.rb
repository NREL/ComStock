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
class HVACFurnace < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'hvac_furnace'
  end

  # human readable description
  def description
    return 'This measure gets an AFUE from the user, it compares it with current furnaces in the model and increases the furnace AFUE in case it is lower than the chosen one.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure gets a value from the user for the desired AFUE, it loops through each furnace, and it gets the thermal efficiency of each gas coil.
            It is assumed AFUE = ThermalEfficiency, as indicated in the OpenStudio Standards.
            For each furnace, if the chosen AFUE is higher than the current furnace thermal efficiency, the latter is upgraded with the chosen AFUE.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    choices = OpenStudio::StringVector.new
    choices << '81 (2019 Code Compliant Furnace)'
    choices << '92 (High Efficiency Furnace)'
    choices << '98 (Condensing Efficiency Furnace)'
    afue = OpenStudio::Measure::OSArgument.makeChoiceArgument('afue', choices, true)
    afue.setDisplayName('Annual Fuel Use Efficiency')
    afue.setDefaultValue('98 (Condensing Efficiency Furnace)')
    args << afue

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    if model.getAirLoopHVACUnitarySystems.empty?
      runner.registerAsNotApplicable('Model does not contain unitary systems.')
      return false
    end

    # assign the user inputs to variables
    afue_user_string = runner.getStringArgumentValue('afue', user_arguments)
    case afue_user_string
      when '81 (2019 Code Compliant Furnace)'
        afue_user = 0.81
      when '92 (High Efficiency Furnace)'
        afue_user = 0.92
      when '98 (Condensing Efficiency Furnace)'
        afue_user = 0.98
    end

    furnace_upgraded = []
    total_furnace_capacity_w = 0
    run_sizing = false
    model.getAirLoopHVACUnitarySystems.each do |unitary_system|
      next unless unitary_system.heatingCoil.is_initialized
      heating_coil = unitary_system.heatingCoil.get
      next unless heating_coil.to_CoilHeatingGas.is_initialized
      heating_coil = heating_coil.to_CoilHeatingGas.get
      existing_efficiency = heating_coil.gasBurnerEfficiency
      if existing_efficiency > afue_user
        runner.registerInfo("Furnace #{heating_coil.name} existing efficiency #{existing_efficiency.round(2)} is greater than selected AFUE #{afue_user}.")
        next
      end
      heating_coil.setGasBurnerEfficiency(afue_user)
      runner.registerInfo("Furnace #{heating_coil.name} existing AFUE changed from #{existing_efficiency.round(2)} to #{afue_user}.")
      furnace_upgraded << unitary_system

      # get furnace sizing
      next if run_sizing
      if heating_coil.nominalCapacity.is_initialized
        total_furnace_capacity_w += heating_coil.nominalCapacity.get
      elsif heating_coil.autosizedNominalCapacity.is_initialized
        total_furnace_capacity_w += heating_coil.autosizedNominalCapacity.get
      else
        run_sizing = true
      end
    end

    if furnace_upgraded.empty?
      runner.registerAsNotApplicable("No furnace has been upgraded, either because no furnaces are present in the model or all the furnaces have an AFUE already higher than the chosen one (#{afue_user_string}). ")
      return false
    end

    # standard template
    template = 'ComStock 90.1-2013'
    std = Standard.build(template)

    # perform a sizing run if needed
    if run_sizing
      runner.registerInfo('At least one furnace design capacity is not available. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/SizingRun") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end

      # get capacity of all furnaces
      total_furnace_capacity_w = 0
      furnace_upgraded.each do |furnace|
        heating_coil = furnace.heatingCoil.get.to_CoilHeatingGas.get
        if heating_coil.nominalCapacity.is_initialized
          total_furnace_capacity_w += heating_coil.nominalCapacity.get
        elsif heating_coil.autosizedNominalCapacity.is_initialized
          total_furnace_capacity_w += heating_coil.autosizedNominalCapacity.get
        else
          runner.registerError("Unable to get furnace '#{heating_coil.name}' design sizing.")
          return false
        end
      end
    end

    runner.registerFinalCondition("#{furnace_upgraded.size} furnaces upgraded to #{afue_user_string}.")
    total_furnace_capacity_btuh = OpenStudio.convert(total_furnace_capacity_w, 'W', 'Btu/hr').get
    runner.registerValue('hvac_furnace_nominal_capacity_of_upgraded_furnaces', total_furnace_capacity_btuh / 1000, 'kBtu/h')

    return true
  end
end

# register the measure to be used by the application
HVACFurnace.new.registerWithApplication
