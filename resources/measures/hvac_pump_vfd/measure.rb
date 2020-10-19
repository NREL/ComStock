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
class HVACPumpVFD < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'HVAC Pump VFD'
  end

  # human readable description
  def description
    return 'Add variable frequency drive to existing pumps.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Change existing constant volume pumps to variable volume pumps on non service hot water plant loops.'
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

    # get constant speed pumps eligable for a VFD
    constant_pumps = []
    model.getPumpConstantSpeeds.each { |pump| constant_pumps << pump }
    model.getHeaderedPumpsConstantSpeeds.each { |pump| constant_pumps << pump }

    pumps = []
    # check if pump is on a service hot water or refrigeration loop
    constant_pumps.each do |pump|
      shw_use = false
      if pump.plantLoop.is_initialized
        plant_loop = pump.plantLoop.get
        plant_loop.demandComponents.each do |component|
          if component.to_WaterUseConnections.is_initialized || component.to_CoilWaterHeatingDesuperheater.is_initialized
            shw_use = true
            runner.registerInfo("Pump '#{pump.name}' is on plant loop '#{plant_loop.name}' which is used for SHW or refrigeration heat reclaim. Pump not eligable for a VFD.")
            break
          end
        end
      end
      pumps << pump unless shw_use
    end

    if pumps.size.zero?
      runner.registerAsNotApplicable('Model does not contain constant volume HVAC pumps. Cannot add VFD.')
      return false
    end

    # report initial condition of model
    runner.registerInitialCondition("Model contains #{pumps.size} constant volume HVAC pumps.")

    run_sizing = false
    pumps.each do |pump|
      break if run_sizing
      if pump.to_PumpConstantSpeed.is_initialized
        unless pump.autosizedRatedFlowRate.is_initialized
          unless pump.ratedFlowRate.is_initialized
            run_sizing = true
          end
        end
      elsif pump.to_HeaderedPumpsConstantSpeed.is_initialized
        unless pump.autosizedTotalRatedFlowRate.is_initialized
          unless pump.totalRatedFlowRate.is_initialized
            run_sizing = true
          end
        end
      end
    end

    # build standard to access methods
    template = 'ComStock 90.1-2013'
    std = Standard.build(template)

    if run_sizing
      runner.registerInfo('Fan or pump flow rates not available. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/SizingRun") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    # pumps
    pumps_motor_hp = 0
    pumps_changed = 0
    pumps.each do |pump|
      pumps_motor_hp = std.pump_motor_horsepower(pump)

      # get existing pump properties
      pump_name = pump.name
      rated_pump_head = pump.ratedPumpHead
      motor_eff = pump.motorEfficiency
      control_type = pump.pumpControlType
      design_power_per_flow = pump.designElectricPowerPerUnitFlowRate
      design_power_per_flow_per_head = pump.designShaftPowerPerUnitFlowRatePerUnitHead
      pump_outlet_node = pump.outletModelObject.get.to_Node.get

      # create new variable speed pump and populate fields with old pump data
      variable_pump = OpenStudio::Model::PumpVariableSpeed.new(model)
      pump_name = pump_name.get.gsub('constant', 'variable').gsub('Constant', 'Variable')
      variable_pump.setName(pump_name)
      variable_pump.setRatedPumpHead(rated_pump_head)
      variable_pump.setMotorEfficiency(motor_eff)
      variable_pump.setPumpControlType(control_type)
      variable_pump.setDesignElectricPowerPerUnitFlowRate(design_power_per_flow)
      variable_pump.setDesignShaftPowerPerUnitFlowRatePerUnitHead(design_power_per_flow_per_head)
      variable_pump.addToNode(pump_outlet_node)
      variable_pump.setFractionofMotorInefficienciestoFluidStream(0)
      variable_pump.addToNode(pump_outlet_node)

      # remove existing pump
      pump.remove

      # curve makes it perform like variable speed pump
      variable_pump.setCoefficient1ofthePartLoadPerformanceCurve(0)
      variable_pump.setCoefficient2ofthePartLoadPerformanceCurve(0.0205)
      variable_pump.setCoefficient3ofthePartLoadPerformanceCurve(0.4101)
      variable_pump.setCoefficient4ofthePartLoadPerformanceCurve(0.5753)

      runner.registerInfo("Replaced constant speed pump #{pump_name} with a variable speed pump.")
      pumps_changed += 1
    end

    # report final condition of model
    runner.registerValue('hvac_pump_vfd_motors_hp', pumps_motor_hp)
    runner.registerFinalCondition("Updated #{pumps_changed} pumps from constant volume to variable volume with #{pumps_motor_hp.round(2)} horsepower.")

    return true
  end
end

# register the measure to be used by the application
HVACPumpVFD.new.registerWithApplication
