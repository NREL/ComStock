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
class HVACRTUDXEfficiency < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'HVAC RTU DX Efficiency'
  end

  # human readable description
  def description
    return 'Adjusts the efficiency of rooftop DX units.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Adjusts the efficiency of rooftop DX units.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make choice argument for target_efficiency_level
    choices = OpenStudio::StringVector.new
    choices << 'IEER 14.0'
    choices << 'IEER 15.5'
    choices << 'IEER 17.0'
    target_efficiency_level = OpenStudio::Measure::OSArgument.makeChoiceArgument('target_efficiency_level', choices, true)
    target_efficiency_level.setDisplayName('Target Efficiency Level')
    args << target_efficiency_level

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    target_efficiency_level = runner.getStringArgumentValue('target_efficiency_level', user_arguments)

    # check air loops to see if any are DX RTUs (PSZ-AC, PVAV)
    selected_air_loops = []
    model.getAirLoopHVACs.each do |air_loop_hvac|
      # PVAV air loop name is VAV
      next unless (air_loop_hvac.name.get.include?('PSZ-AC') || air_loop_hvac.name.get.include?('VAV'))
      air_loop_hvac.supplyComponents.each do |component|
        # CoilCoolingDXSingleSpeed
        if component.to_CoilCoolingDXSingleSpeed.is_initialized
          selected_air_loops << air_loop_hvac
          break
        # CoilCoolingDXTwoSpeed
        elsif component.to_CoilCoolingDXTwoSpeed.is_initialized
          selected_air_loops << air_loop_hvac
          break
        end
      end
    end

    # register as not applicable if not
    if selected_air_loops.empty?
      runner.registerAsNotApplicable('Model does not contain DX RTUs.')
      return false
    end

    # measure costs are given per IEER
    # used T24-2019 efficiency table to estimate EER from IEER
    # EER = (IEER - 1.2604) / 1.0276
    if target_efficiency_level == 'IEER 14.0'
      # IEER 14.0
      # equivalent EER 12.4, SEER 14.75
      # approximately equal to Unitary AC Single Package DEER 2025 (SEER 14.66)
      template = 'ComStock DEER 2025'
    elsif target_efficiency_level == 'IEER 15.5'
      # IEER 15.5
      # equivalent EER 13.86, SEER 17.56
      # approximately equal to Unitary AC Single Package ComStock DEER 2035 (SEER 17.39)
      template = 'ComStock DEER 2050'
    elsif target_efficiency_level == 'IEER 17.0'
      # IEER 17.0
      # equivalent EER 15.32, SEER 21.17
      # approximately equal to Unitary AC Single Package ComStock DEER 2050 (SEER 20.12)
      template = 'ComStock DEER 2075'
    end

    runner.registerInitialCondition("The model contains #{selected_air_loops.size} DX RTU units.")

    # build standard to access methods
    std = Standard.build(template)

    run_sizing = false
    selected_air_loops.each do |air_loop_hvac|
      # get sizing
      cooling_capacity_w = std.air_loop_hvac_total_cooling_capacity(air_loop_hvac)
      run_sizing = true if cooling_capacity_w.zero?
      break if run_sizing
    end

    if run_sizing
      runner.registerInfo('DX RTU cooling capacity not sized in at least one unit. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/SizingRun") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    total_cooling_capacity_w = 0
    changed_dx_units = 0
    selected_air_loops.each do |air_loop_hvac|
      air_loop_hvac.supplyComponents.each do |component|
        # CoilCoolingDXSingleSpeed
        if component.to_CoilCoolingDXSingleSpeed.is_initialized
          coil_cooling_dx_single_speed = component.to_CoilCoolingDXSingleSpeed.get
          cooling_capacity_w = std.coil_cooling_dx_single_speed_find_capacity(coil_cooling_dx_single_speed)
          if cooling_capacity_w.zero?
            runner.registerError("Unable to find cooling capacity for '#{coil_cooling_dx_single_speed.name.get}' after sizing run.")
            return false
          end
          cooling_capacity_btuh = OpenStudio.convert(cooling_capacity_w, 'W', 'Btu/hr').get
          old_cop = 3.0 # EnergyPlus IDD default
          if coil_cooling_dx_single_speed.ratedCOP.is_initialized
            old_cop = coil_cooling_dx_single_speed.ratedCOP.get
          end
          new_cop = std.coil_cooling_dx_single_speed_standard_minimum_cop(coil_cooling_dx_single_speed)
          if new_cop > old_cop
            std.coil_cooling_dx_single_speed_apply_efficiency_and_curves(coil_cooling_dx_single_speed, {})
            # reset coil name after applying new efficiency
            coil_cooling_dx_single_speed.setName("#{air_loop_hvac.name.get} 1spd DX AC Clg Coil #{(cooling_capacity_btuh / 1000).round(1)} kBtu/hr")
            runner.registerInfo("Set DX unit '#{coil_cooling_dx_single_speed.name}' with #{cooling_capacity_btuh.round(0)} Btu/hr cooling capacity from #{old_cop.round(2)} COP to #{new_cop.round(2)} COP.")
            total_cooling_capacity_w += cooling_capacity_w
            changed_dx_units += 1
          else
            runner.registerInfo("DX RTU unit '#{coil_cooling_dx_single_speed.name}' with #{cooling_capacity_btuh.round(0)} Btu/hr cooling capacity has an existing efficiency of #{old_cop.round(2)} COP which is better than the requested new efficiency #{new_cop.round(2)} COP.  Will not change unit.")
          end
        # CoilCoolingDXTwoSpeed
        elsif component.to_CoilCoolingDXTwoSpeed.is_initialized
          coil_cooling_dx_two_speed = component.to_CoilCoolingDXTwoSpeed.get
          cooling_capacity_w = std.coil_cooling_dx_two_speed_find_capacity(coil_cooling_dx_two_speed)
          if cooling_capacity_w.zero?
            runner.registerError("Unable to find cooling capacity for '#{coil_cooling_dx_single_speed.name.get}' after sizing run.")
            return false
          end
          cooling_capacity_btuh = OpenStudio.convert(cooling_capacity_w, 'W', 'Btu/hr').get
          old_cop = 3.0 # EnergyPlus IDD default
          if coil_cooling_dx_two_speed.ratedHighSpeedCOP.is_initialized
            old_cop = coil_cooling_dx_two_speed.ratedHighSpeedCOP.get
          end
          new_cop = std.coil_cooling_dx_two_speed_standard_minimum_cop(coil_cooling_dx_two_speed)
          if new_cop > old_cop
            std.coil_cooling_dx_two_speed_apply_efficiency_and_curves(coil_cooling_dx_two_speed, {})
            # reset coil name after applying new efficiency
            coil_cooling_dx_two_speed.setName("#{air_loop_hvac.name.get} 2spd DX AC Clg Coil #{(cooling_capacity_btuh / 1000).round(1)} kBtu/hr")
            runner.registerInfo("Set DX unit '#{coil_cooling_dx_two_speed.name}' with #{cooling_capacity_btuh.round(0)} Btu/hr cooling capacity from #{old_cop.round(2)} COP to #{new_cop.round(2)} COP.")
            total_cooling_capacity_w += cooling_capacity_w
            changed_dx_units += 1
          else
            runner.registerInfo("DX RTU unit '#{coil_cooling_dx_two_speed.name}' with #{cooling_capacity_btuh.round(0)} Btu/hr cooling capacity has an existing efficiency of #{old_cop.round(2)} COP which is better than the requested new efficiency #{new_cop.round(2)} COP.  Will not change unit.")
          end
        end
      end
    end

    if total_cooling_capacity_w.zero?
      runner.registerAsNotApplicable('Changed DX RTU cooling capacity is zero.')
      return false
    end

    total_cooling_capacity_btuh = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/hr').get
    total_cooling_capacity_tons = total_cooling_capacity_btuh / 12_000
    # report final condition of model
    runner.registerValue('hvac_rtu_dx_eff_cooling_load_in_tons', total_cooling_capacity_tons)
    runner.registerFinalCondition("Adjusted cooling efficiency for #{changed_dx_units.size} DX RTU units with #{total_cooling_capacity_tons.round(1)} tons of total cooling capacity.")
    return true
  end
end

# register the measure to be used by the application
HVACRTUDXEfficiency.new.registerWithApplication
