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
class HVACMotors < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'HVACMotors'
  end

  # human readable description
  def description
    return 'Replaces motors in the model with ECM motors motors matched to ComStock DEER 2020 efficiency level. Does not adjust pump motors on service water or refrigeration loops.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Replaces motors in the model with ECM motors motors matched to ComStock DEER 2020 efficiency level. Does not adjust pump motors on service water or refrigeration loops.'
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

    # fans
    fans = []
    model.getFanVariableVolumes.each { |fan| fans << fan }
    model.getFanConstantVolumes.each { |fan| fans << fan }
    model.getFanOnOffs.each { |fan| fans << fan }
    model.getFanZoneExhausts.each { |fan| fans << fan }

    # pumps
    all_pumps = []
    model.getPumpConstantSpeeds.each { |pump| all_pumps << pump }
    model.getPumpVariableSpeeds.each { |pump| all_pumps << pump }
    model.getHeaderedPumpsConstantSpeeds.each { |pump| all_pumps << pump }
    model.getHeaderedPumpsVariableSpeeds.each { |pump| all_pumps << pump }

    pumps = []
    # check if pump is on a service hot water or refrigeration loop
    all_pumps.each do |pump|
      shw_use = false
      if pump.plantLoop.is_initialized
        plant_loop = pump.plantLoop.get
        plant_loop.demandComponents.each do |component|
          if component.to_WaterUseConnections.is_initialized || component.to_CoilWaterHeatingDesuperheater.is_initialized
            shw_use = true
            runner.registerInfo("Pump '#{pump.name}' is on plant loop '#{plant_loop.name}' which is used for SHW or refrigeration heat reclaim. Pump motor efficiency will not be adjusted.")
            break
          end
        end
      end
      pumps << pump unless shw_use
    end

    if (fans.size + pumps.size).zero?
      runner.registerAsNotApplicable('Model does not contain HVAC fans or pumps. Cannot adjust motor efficiency.')
      return false
    end

    # report initial condition of model
    runner.registerInitialCondition("Model contains #{fans.size} HVAC fans and #{pumps.size} HVAC pumps.")

    # check if sizing run is needed
    run_sizing = false
    fans.each do |fan|
      break if run_sizing
      unless fan.maximumFlowRate.is_initialized
        if fan.to_FanZoneExhaust.empty?
          unless fan.autosizedMaximumFlowRate.is_initialized
            run_sizing = true
          end
        else
          run_sizing = true
        end
      end
    end

    pumps.each do |pump|
      break if run_sizing
      if pump.to_PumpVariableSpeed.is_initialized || pump.to_PumpConstantSpeed.is_initialized
        unless pump.autosizedRatedFlowRate.is_initialized
          unless pump.ratedFlowRate.is_initialized
            run_sizing = true
          end
        end
      elsif pump.to_HeaderedPumpsVariableSpeed.is_initialized || pump.to_HeaderedPumpsConstantSpeed.is_initialized
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

    # fans
    fans_motor_initial_hp = 0
    fans_motor_final_hp = 0
    fans.each do |fan|
      fans_motor_initial_hp += std.fan_motor_horsepower(fan)
      fan_bhp = std.fan_brake_horsepower(fan)
      new_motor_eff, nominal_hp = std.fan_standard_minimum_motor_efficiency_and_size(fan, fan_bhp)
      existing_motor_eff = 0.7
      if fan.to_FanZoneExhaust.empty?
        existing_motor_eff = fan.motorEfficiency
      end
      if existing_motor_eff >= new_motor_eff
        runner.registerInfo("Fan '#{fan.name}' has existing motor efficiency #{existing_motor_eff} which is greater than requested new motor efficiency #{new_motor_eff}.  Will not change.")
      else
        # apply minimum motor efficiency
        std.fan_apply_standard_minimum_motor_efficiency(fan, fan_bhp)
        fans_motor_final_hp += std.fan_motor_horsepower(fan)
      end
    end

    # pumps
    pumps_motor_initial_hp = 0
    pumps_motor_final_hp = 0
    pumps.each do |pump|
      pumps_motor_initial_hp = std.pump_motor_horsepower(pump)
      pump_bhp = std.pump_brake_horsepower(pump)
      existing_motor_eff = pump.motorEfficiency
      new_motor_eff, nominal_hp = std.pump_standard_minimum_motor_efficiency_and_size(pump, pump_bhp)
      if existing_motor_eff >= new_motor_eff
        runner.registerInfo("Pump '#{pump.name}' has existing motor efficiency #{existing_motor_eff} which is greater than requested new motor efficiency #{new_motor_eff}.  Will not change.")
      else
        # apply minimum motor efficiency
        std.pump_standard_minimum_motor_efficiency_and_size(pump, pump_bhp)
        pumps_motor_final_hp += std.pump_motor_horsepower(pump)
      end
    end

    # report final condition of model
    total_motor_final_hp = fans_motor_final_hp + pumps_motor_final_hp
    runner.registerValue('hvac_motors_motors_hp', total_motor_final_hp)
    unless fans_motor_final_hp.zero?
      runner.registerInfo("Fan motors started with #{fans_motor_initial_hp.round(2)} horsepower and finished with #{fans_motor_final_hp.round(2)} horsepower.")
    end
    unless pumps_motor_final_hp.zero?
      runner.registerInfo("Pump motors started with #{pumps_motor_initial_hp.round(2)} horsepower and finished with #{pumps_motor_final_hp.round(2)} horsepower.")
    end
    runner.registerFinalCondition("Updated motor efficiencies for #{fans_motor_final_hp.round(2)} horsepower of fans and #{pumps_motor_final_hp.round(2)} horsepower of pumps (#{total_motor_final_hp.round(2)} horsepower total).")

    return true
  end
end

# register the measure to be used by the application
HVACMotors.new.registerWithApplication
