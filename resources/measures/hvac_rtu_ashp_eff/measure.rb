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
class HVACRTUASHPEfficiency < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'HVAC RTU ASHP Efficiency'
  end

  # human readable description
  def description
    return 'Adjusts the efficiency of rooftop air-source heat pumps.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Adjusts the efficiency of rooftop air-source heat pumps.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make choice argument for target_efficiency_level
    choices = OpenStudio::StringVector.new
    choices << 'IEER 13.3'
    choices << 'IEER 15.0'
    choices << 'IEER 16.5'
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

    # check air loops to see if any are ASHP RTUs (PSZ-HP)
    selected_air_loops = []
    model.getAirLoopHVACs.each do |air_loop_hvac|
      next unless air_loop_hvac.name.get.include?('PSZ-HP')
      air_loop_hvac.supplyComponents.each do |component|
        # CoilHeatingDXSingleSpeed
        if component.to_CoilHeatingDXSingleSpeed.is_initialized
          selected_air_loops << air_loop_hvac
          break
        end
      end
    end

    # register as not applicable if not
    if selected_air_loops.empty?
      runner.registerAsNotApplicable('Model does not contain ASHP RTUs.')
      return false
    end

    # measure costs are given per IEER
    # used T24-2019 efficiency table to estimate EER from IEER
    # EER = (IEER - 0.7564) / 1.0331
    if target_efficiency_level == 'IEER 13.3'
      # IEER 13.3
      # equivalent EER 12.14
      # approximately equal to Heat Pump Single Package DEER 2030 (EER 12.26)
      template = 'ComStock DEER 2030'
    elsif target_efficiency_level == 'IEER 15.0'
      # IEER 15.0
      # equivalent EER 13.79
      # approximately equal to Heat Pump Single Package ComStock DEER 2050 (EER 13.82)
      template = 'ComStock DEER 2050'
    elsif target_efficiency_level == 'IEER 16.5'
      # IEER 16.5
      # equivalent EER 15.24
      # approximately equal to Heat Pump Single Package ComStock DEER 2070 (EER 15.38)
      template = 'ComStock DEER 2070'
    end

    runner.registerInitialCondition("The model contains #{selected_air_loops.size} ASHP RTU units.")

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
      runner.registerInfo('ASHP RTU cooling capacity not sized in at least one unit. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/SizingRun") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    total_cooling_capacity_w = 0
    changed_dx_units = 0
    selected_air_loops.each do |air_loop_hvac|
      changed_dx_unit = false
      # heating coil efficiency is determined by cooling capacity, which needs to look up cooling coil capacity
      # set the efficiency for the heating coils first so the cooling coil names are present in the capacity lookup
      air_loop_hvac.supplyComponents.each do |component|
        # CoilHeatingDXSingleSpeed
        if component.to_CoilHeatingDXSingleSpeed.is_initialized
          coil_heating_dx_single_speed = component.to_CoilHeatingDXSingleSpeed.get
          cooling_capacity_w = std.coil_heating_dx_single_speed_find_capacity(coil_heating_dx_single_speed)
          if cooling_capacity_w.zero?
            runner.registerError("Unable to find heating capacity for '#{coil_heating_dx_single_speed.name.get}' after sizing run.")
            return false
          end
          cooling_capacity_btuh = OpenStudio.convert(cooling_capacity_w, 'W', 'Btu/hr').get
          old_cop = coil_heating_dx_single_speed.ratedCOP
          new_cop = std.coil_heating_dx_single_speed_standard_minimum_cop(coil_heating_dx_single_speed)

          if new_cop > old_cop
            std.coil_heating_dx_single_speed_apply_efficiency_and_curves(coil_heating_dx_single_speed, {})
            # reset coil name after applying new efficiency
            coil_heating_dx_single_speed.setName("#{air_loop_hvac.name.get} 1spd DX HP Htg Coil #{(cooling_capacity_btuh / 1000).round(1)} Clg kBtu/hr")
            runner.registerInfo("Set ASHP RTU unit '#{coil_heating_dx_single_speed.name}' with #{cooling_capacity_btuh.round(0)} Btu/hr paired cooling capacity from #{old_cop.round(2)} COP to #{new_cop.round(2)} COP.")
            changed_dx_unit = true
          else
            runner.registerInfo("ASHP RTU unit '#{coil_heating_dx_single_speed.name}' with #{cooling_capacity_btuh.round(0)} Btu/hr paired cooling capacity has an existing efficiency of #{old_cop.round(2)} COP which is better than the requested new efficiency #{new_cop.round(2)} COP.  Will not change unit.")
          end
        end
      end

      # change cooling coil efficiency
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
            coil_cooling_dx_single_speed.setName("#{air_loop_hvac.name.get} 1spd DX HP Clg Coil #{(cooling_capacity_btuh / 1000).round(1)} kBtu/hr")
            runner.registerInfo("Set ASHP RTU unit '#{coil_cooling_dx_single_speed.name}' with #{cooling_capacity_btuh.round(0)} Btu/hr cooling capacity from #{old_cop.round(2)} COP to #{new_cop.round(2)} COP.")
            total_cooling_capacity_w += cooling_capacity_w
            changed_dx_unit = true
          else
            runner.registerInfo("ASHP RTU unit '#{coil_cooling_dx_single_speed.name}' with #{cooling_capacity_btuh.round(0)} Btu/hr cooling capacity has an existing efficiency of #{old_cop.round(2)} COP which is better than the requested new efficiency #{new_cop.round(2)} COP.  Will not change unit.")
          end
        # CoilCoolingDXTwoSpeed
        elsif component.to_CoilCoolingDXTwoSpeed.is_initialized
          coil_cooling_dx_two_speed = component.to_CoilCoolingDXTwoSpeed.get
          cooling_capacity_w = std.coil_cooling_dx_two_speed_find_capacity(coil_cooling_dx_two_speed)
          if cooling_capacity_w.zero?
            runner.registerError("Unable to find cooling capacity for '#{coil_cooling_dx_two_speed.name.get}' after sizing run.")
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
            coil_cooling_dx_two_speed.setName("#{air_loop_hvac.name.get} 2spd DX HP Clg Coil #{(cooling_capacity_btuh / 1000).round(1)} kBtu/hr")
            runner.registerInfo("Set ASHP RTU unit '#{coil_cooling_dx_two_speed.name}' with #{cooling_capacity_btuh.round(0)} Btu/hr cooling capacity from #{old_cop.round(2)} COP to #{new_cop.round(2)} COP.")
            total_cooling_capacity_w += cooling_capacity_w
            changed_dx_unit = true
          else
            runner.registerInfo("ASHP RTU unit '#{coil_cooling_dx_two_speed.name}' with #{cooling_capacity_btuh.round(0)} Btu/hr cooling capacity has an existing efficiency of #{old_cop.round(2)} COP which is better than the requested new efficiency #{new_cop.round(2)} COP.  Will not change unit.")
          end
        end
      end
      changed_dx_units += 1 if changed_dx_unit
    end

    if total_cooling_capacity_w.zero?
      runner.registerAsNotApplicable('Changed ASHP RTU cooling capacity is zero.')
      return false
    end

    total_cooling_capacity_btuh = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/hr').get
    total_cooling_capacity_tons = total_cooling_capacity_btuh / 12_000
    # report final condition of model
    runner.registerValue('hvac_rtu_ashp_eff_cooling_load_in_tons', total_cooling_capacity_tons)
    runner.registerFinalCondition("Adjusted heating and cooling efficiency for #{changed_dx_units.size} ASHP RTU units with #{total_cooling_capacity_tons.round(1)} tons of total cooling capacity.")
    return true
  end
end

# register the measure to be used by the application
HVACRTUASHPEfficiency.new.registerWithApplication
