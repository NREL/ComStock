# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
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

require 'openstudio-standards'

# start the measure
class HardsizeModel < OpenStudio::Measure::ModelMeasure

  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Hardsize Model'
  end

  # human readable description
  def description
    return 'Sets the HVAC capacities and flow rates in the model.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Runs a sizing run and applies EnerygyPlus autosized values into the model.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Daylight Savings Time
    apply_hardsize = OpenStudio::Measure::OSArgument.makeBoolArgument('apply_hardsize', true)
    apply_hardsize.setDisplayName('Hardsize model')
    apply_hardsize.setDescription('Set to true to hardsize model HVAC, set to false to leave model autosized')
    apply_hardsize.setDefaultValue(true)
    args << apply_hardsize

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Assign the user inputs to variables
    apply_hardsize = runner.getBoolArgumentValue('apply_hardsize', user_arguments)

    unless apply_hardsize
      runner.registerAsNotApplicable("Leaving model autosized per argument: apply_hardsize = #{apply_hardsize}")
      return true
    end

    reset_log
    standard = Standard.build('ComStock DOE Ref Pre-1980') # Actual standard doesn't matter

    # Collect equipment capacities and flow rates that are hard-sized by OpenStudio-Standards.
    # These fields need to keep the hard-sized values and not be replaced with the
    # autosized values determined by EnergyPlus.
    # The eventual goal is to have OpenStudio-Standards rely entirely on EnergyPlus autosizing,
    # such that all of this code can be removed.

    # TODO remove this after feature https://github.com/NREL/openstudio-standards/issues/1391 is implemented
    # Get the terminal minimum damper positions and preserve them after the hard-sizing
    # because damper position is hard-sized by openstudio-standards, not autosized
    # Min OA flow rate at these damper positions is also hard-sized.
    vav_damper_posits = {}
    vav_max_rht_fracs = {}
    model.getAirTerminalSingleDuctVAVReheats.each do |term|
      if term.zoneMinimumAirFlowInputMethod == 'Constant'
        unless term.isConstantMinimumAirFlowFractionAutosized
          vav_damper_posits[term] = term.constantMinimumAirFlowFraction.get
        end
      end
      unless term.isMaximumFlowFractionDuringReheatAutosized
        vav_max_rht_fracs[term] = term.maximumFlowFractionDuringReheat.get
      end
    end
    vav_max_htg_flows = {}
    vav_min_oas = {}
    model.getSizingSystems.each do |sizing_system|
      unless sizing_system.isCentralHeatingMaximumSystemAirFlowRatioAutosized
        vav_max_htg_flows[sizing_system] = sizing_system.centralHeatingMaximumSystemAirFlowRatio.get
      end
      unless sizing_system.isDesignOutdoorAirFlowRateAutosized
        vav_min_oas[sizing_system] = sizing_system.designOutdoorAirFlowRate.get
      end
    end

    # Run a sizing run to determine equipment capacities and flow rates
    if standard.model_run_sizing_run(model, "#{Dir.pwd}/hardsize_model_SR") == false
      runner.registerError("Sizing run for Hardsize model failed, cannot hard-size model.")
      puts("Sizing run for Hardsize model failed, cannot hard-size model.")
      return false
    end

    # Apply the capacities and flow rates from the sizing run to the model
    runner.registerInfo("Hard-sizing HVAC equipment to capacities and flows used to set efficiencies and controls.")
    model.applySizingValues

    # Reset some fields to the previously-collected hard-sized values

    # TODO remove once this functionality is added to the OpenStudio C++ for hard sizing UnitarySystems
    model.getAirLoopHVACUnitarySystems.each do |unitary|
      if model.version < OpenStudio::VersionString.new('3.7.0')
        unitary.setSupplyAirFlowRateMethodDuringCoolingOperation('SupplyAirFlowRate')
        unitary.setSupplyAirFlowRateMethodDuringHeatingOperation('SupplyAirFlowRate')
      else
        # unitary.applySizingValues
      end

    end
    # TODO remove once this functionality is added to the OpenStudio C++ for hard sizing Sizing:System
    model.getSizingSystems.each do |sizing_system|
      next if sizing_system.isDesignOutdoorAirFlowRateAutosized
      sizing_system.setSystemOutdoorAirMethod('ZoneSum')
    end
    # TODO remove once this functionality is added to the OpenStudio C++ for hard sizing
    model.getAirTerminalSingleDuctVAVReheats.each do |term|
      next unless term.damperHeatingAction == 'Normal'
      term.autosizeMaximumFlowFractionDuringReheat
      term.autosizeMaximumFlowPerZoneFloorAreaDuringReheat
    end
    # TODO remove this after feature https://github.com/NREL/openstudio-standards/issues/1391 is implemented
    # Re-apply hardsized VAV damper positions
    model.getAirTerminalSingleDuctVAVReheats.each do |term|
      if vav_damper_posits.has_key?(term)
        term.setConstantMinimumAirFlowFraction(vav_damper_posits[term])
      end
      if vav_max_rht_fracs.has_key?(term)
        term.setMaximumFlowFractionDuringReheat(vav_max_rht_fracs[term])
      end
    end

    return true
  end
end

# register the measure to be used by the application
HardsizeModel.new.registerWithApplication
