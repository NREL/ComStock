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
require 'json'

# Start the measure
class HVACPlantShutdown < OpenStudio::Measure::ModelMeasure
  # Define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'PlantShutdown'
  end

  # Define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  def pump_control(pump, pumps, runner)
    changed = false
    runner.registerInfo("pump control type #{pump.pumpControlType}")
    if pump.pumpControlType == 'Continuous'
      runner.registerInfo("setting pump #{pump.name} control type to Intermittent")
      pump.setPumpControlType('Intermittent')
      pumps << pump.name
      changed = true
    end
    if pump.pumpFlowRateSchedule.is_initialized
      runner.registerInfo("resetting pump #{pump.name} pumpFlowRateSchedule")
      pump.resetPumpFlowRateSchedule
    end
    return changed
  end

  def check_supply_side(plant_loop, i, pumps, runner)
    changed = false
    plant_loop.supplyComponents.each_with_index do |comp, index|
      pump = comp.to_PumpConstantSpeed
      if pump.is_initialized
        runner.registerInfo("plant loop #{i} has constant pump")
        changed = pump_control(pump.get, pumps, runner)
      end
      pump = comp.to_PumpVariableSpeed
      if pump.is_initialized
        runner.registerInfo("plant loop #{i} has variable pump")
        changed = pump_control(pump.get, pumps, runner)
      end
    end
    return changed
  end

  # Define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    results = []
    skipped = []
    na = []
    pumps = []

    model.getPlantLoops.each_with_index do |plant_loop, index|
      changed = false
      skip = false
      plant_loop.demandComponents.each do |comp|
        if comp.to_WaterUseConnections.is_initialized
          runner.registerInfo("plant loop #{index} uses water, skipping")
          skip = true
          skipped << plant_loop.name
        end
        break if skip == true
      end
      changed = check_supply_side(plant_loop, index, pumps, runner) if skip == false
      if skip == false
        changed == true ? results << plant_loop.name.to_s : na << plant_loop.name.to_s
      end
    end

    # Unique initial conditions based on
    if !results.empty?
      runner.registerInitialCondition("The initial model has #{results.length} pumps set to operate continuously; this measure is applicable.")
    end

    if results.empty?
      runner.registerAsNotApplicable('No continuously operating chilled-water loop, hot-water loop, or condenser loop pumps were found. EEM not applied')
      return false
    end

    # Reporting final condition of model
    runner.registerFinalCondition("The following pumps were set to operate intermittently: #{results} \n The following pumps were skipped: #{skipped} \n The following pumps were not applicable: #{na}")
    runner.registerValue('hvac_plant_shutdown_num_pumps', results.length)

    return true
  end
end

# This allows the measure to be use by the application
HVACPlantShutdown.new.registerWithApplication
