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
class HVACPTHPEfficiency < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'HVAC PTHP Efficiency'
  end

  # human readable description
  def description
    return 'Adjusts the efficiency of packaged terminal heat pump (PTHP) units.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Adjusts the efficiency of packaged terminal heat pump (PTHP) units.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make choice argument for target_efficiency_level
    choices = OpenStudio::StringVector.new
    choices << 'Code'
    choices << 'Efficient'
    choices << 'Highly Efficient'
    target_efficiency_level = OpenStudio::Measure::OSArgument.makeChoiceArgument('target_efficiency_level', choices, true)
    target_efficiency_level.setDisplayName('Target Efficiency Level')
    args << target_efficiency_level

    return args
  end

  def pthp_cooling_capacity(runner, pthp)
    cooling_coil = pthp.coolingCoil
    cooling_capacity_w = 0
    # CoilCoolingDXSingleSpeed
    if cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized
      coil = cooling_coil.to_CoilCoolingDXSingleSpeed.get
      if coil.ratedTotalCoolingCapacity.is_initialized
        cooling_capacity_w = coil.ratedTotalCoolingCapacity.get
      elsif coil.autosizedRatedTotalCoolingCapacity.is_initialized
        cooling_capacity_w = coil.autosizedRatedTotalCoolingCapacity.get
      end
    # CoilCoolingDXTwoSpeed
    elsif cooling_coil.to_CoilCoolingDXTwoSpeed.is_initialized
      coil = cooling_coil.to_CoilCoolingDXTwoSpeed.get
      if coil.ratedHighSpeedTotalCoolingCapacity.is_initialized
        cooling_capacity_w = coil.ratedHighSpeedTotalCoolingCapacity.get
      elsif coil.autosizedRatedHighSpeedTotalCoolingCapacity.is_initialized
        cooling_capacity_w = coil.autosizedRatedHighSpeedTotalCoolingCapacity.get
      end
    else
      runner.registerError("PTHP unit #{pthp.name} does not have a recognized cooling coil type. Cannot get cooling capacity.")
      return false
    end
    return cooling_capacity_w
  end

  def pthp_heating_capacity(runner, pthp)
    heating_coil = pthp.heatingCoil
    heating_capacity_w = 0
    # CoilHeatingDXSingleSpeed
    if heating_coil.to_CoilHeatingDXSingleSpeed.is_initialized
      coil = heating_coil.to_CoilHeatingDXSingleSpeed.get
      if coil.ratedTotalHeatingCapacity.is_initialized
        heating_capacity_w = coil.ratedTotalHeatingCapacity.get
      elsif coil.autosizedRatedTotalHeatingCapacity.is_initialized
        heating_capacity_w = coil.autosizedRatedTotalHeatingCapacity.get
      end
    else
      runner.registerError("PTHP unit #{pthp.name} does not have a recognized heating coil type. Cannot get heating capacity.")
      return false
    end
    return heating_capacity_w
  end

  def pthp_cooling_cop(runner, pthp)
    cooling_coil = pthp.coolingCoil
    cooling_cop = 0
    # CoilCoolingDXSingleSpeed
    if cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized
      coil = cooling_coil.to_CoilCoolingDXSingleSpeed.get
      if coil.ratedCOP.is_initialized
        cooling_cop = coil.ratedCOP.get
      end
    # CoilCoolingDXTwoSpeed
    elsif cooling_coil.to_CoilCoolingDXTwoSpeed.is_initialized
      coil = cooling_coil.to_CoilCoolingDXTwoSpeed.get
      if coil.ratedHighSpeedCOP.is_initialized
        cooling_cop = coil.ratedHighSpeedCOP.get
      end
    else
      runner.registerError("PTHP unit #{pthp.name} does not have a recognized cooling coil type. Cannot get cooling COP.")
      return false
    end
    return cooling_cop
  end

  def pthp_heating_cop(runner, pthp)
    heating_coil = pthp.heatingCoil
    heating_cop = 0
    # CoilHeatingDXSingleSpeed
    if heating_coil.to_CoilHeatingDXSingleSpeed.is_initialized
      coil = heating_coil.to_CoilHeatingDXSingleSpeed.get
      heating_cop = coil.ratedCOP
    else
      runner.registerError("PTHP unit #{pthp.name} does not have a recognized heating coil type. Cannot get heating cop.")
      return false
    end
    return heating_cop
  end

  def pthp_set_cooling_cop(runner, pthp, cop)
    cooling_coil = pthp.coolingCoil
    # CoilCoolingDXSingleSpeed
    if cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized
      coil = cooling_coil.to_CoilCoolingDXSingleSpeed.get
      coil.setRatedCOP(cop)
    # CoilCoolingDXTwoSpeed
    elsif cooling_coil.to_CoilCoolingDXTwoSpeed.is_initialized
      coil = cooling_coil.to_CoilCoolingDXTwoSpeed.get
      coil.setRatedHighSpeedCOP(cop)
      coil.setRatedLowSpeedCOP(cop)
    else
      runner.registerError("PTHP unit #{pthp.name} does not have a recognized cooling coil type. Cannot set cooling COP.")
      return false
    end
    return true
  end

  def pthp_set_heating_cop(runner, pthp, cop)
    heating_coil = pthp.heatingCoil
    # CoilHeatingDXSingleSpeed
    if heating_coil.to_CoilHeatingDXSingleSpeed.is_initialized
      coil = heating_coil.to_CoilHeatingDXSingleSpeed.get
      coil.setRatedCOP(cop)
    else
      runner.registerError("PTHP unit #{pthp.name} does not have a recognized heating coil type. Cannot set heating cop.")
      return false
    end
    return true
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    target_efficiency_level = runner.getStringArgumentValue('target_efficiency_level', user_arguments)

    # check zones to see if there are PTHP units
    pthps = []
    model.getThermalZones.each do |thermal_zone|
      thermal_zone.equipment.each do |equip|
        next unless equip.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
        pthps << equip.to_ZoneHVACPackagedTerminalHeatPump.get
      end
    end

    # register as not applicable if not
    if pthps.empty?
      runner.registerAsNotApplicable('Model does not contain PTHP units')
      return false
    end

    if target_efficiency_level == 'Code'
      # Code EER 9.5-11.9, =14-0.3*Cap/1000, 7000 Btu/hr min, 15000 Btu/hr max
      base_coeff_cooling = 14
      cap_coeff_cooling = 0.3
      base_coeff_heating = 3.7
      cap_coeff_heating = 0.052
    elsif target_efficiency_level == 'Efficient'
      # Efficient (+5%) EER 10-12.5, =14.7-0.315*Cap/1000, 7000 Btu/hr min, 15000 Btu/hr max
      base_coeff_cooling = 14.7
      cap_coeff_cooling = 0.315
      base_coeff_heating = 3.885
      cap_coeff_heating = 0.0546
    elsif target_efficiency_level == 'Highly Efficient'
      # Highly Efficient (+10%) EER 10.5-13.1, =15.4-0.33*Cap/1000, 7000 Btu/hr min, 15000 Btu/hr max
      base_coeff_cooling = 15.4
      cap_coeff_cooling = 0.33
      base_coeff_heating = 4.07
      cap_coeff_heating = 0.0572
    end

    runner.registerInitialCondition("The model contains #{pthps.size} PTHP units.")

    # build standard to access methods
    template = 'ComStock 90.1-2013'
    std = Standard.build(template)

    run_sizing = false
    pthps.each do |pthp|
      # get sizing
      cooling_capacity_w = pthp_cooling_capacity(runner, pthp)
      run_sizing = true if cooling_capacity_w.zero?
      break if run_sizing
    end

    if run_sizing
      runner.registerInfo('PTHP cooling capacity not sized in at least one PTHP unit. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/SizingRun") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    total_cooling_capacity_w = 0
    total_heating_capacity_w = 0
    pthps.each do |pthp|
      cooling_capacity_w = pthp_cooling_capacity(runner, pthp)
      cooling_capacity_btuh = OpenStudio.convert(cooling_capacity_w, 'W', 'Btu/hr').get
      heating_capacity_w = pthp_heating_capacity(runner, pthp)
      heating_capacity_btuh = OpenStudio.convert(heating_capacity_w, 'W', 'Btu/hr').get

      pthp_old_cooling_cop = pthp_cooling_cop(runner, pthp)
      pthp_old_cooling_eer = pthp_old_cooling_cop * 3.412
      pthp_old_heating_cop = pthp_heating_cop(runner, pthp)
      lookup_cooling_capacity_btuh = cooling_capacity_btuh
      if lookup_cooling_capacity_btuh > 15_000
        lookup_cooling_capacity_btuh = 15_000
      elsif lookup_cooling_capacity_btuh < 7_000
        lookup_cooling_capacity_btuh = 7_000
      end
      pthp_new_cooling_eer = base_coeff_cooling - (cap_coeff_cooling * (lookup_cooling_capacity_btuh / 1000))
      pthp_new_cooling_cop = pthp_new_cooling_eer / 3.412
      # heating cop is a function of rated cooling capacity
      pthp_new_heating_cop = base_coeff_heating - (cap_coeff_heating * (lookup_cooling_capacity_btuh / 1000))

      if pthp_new_cooling_cop > pthp_old_cooling_cop
        total_cooling_capacity_w += cooling_capacity_w
        pthp_set_cooling_cop(runner, pthp, pthp_new_cooling_cop)
        runner.registerInfo("Set PTHP unit '#{pthp.name}' with #{cooling_capacity_btuh.round(2)} Btu/hr cooling capacity from #{pthp_old_cooling_eer.round(2)} EER to #{pthp_new_cooling_eer.round(2)} EER.")
      else
        runner.registerInfo("PTHP unit '#{pthp.name}' with #{cooling_capacity_btuh.round(2)} Btu/hr cooling capacity has an existing cooling efficiency of #{pthp_old_cooling_eer.round(2)} EER which is better than the requested new efficiency #{pthp_new_cooling_eer.round(2)} EER.  Will not change unit.")
      end

      if pthp_new_heating_cop > pthp_old_heating_cop
        total_heating_capacity_w += heating_capacity_w
        pthp_set_heating_cop(runner, pthp, pthp_new_heating_cop)
        runner.registerInfo("Set PTHP unit '#{pthp.name}' with #{cooling_capacity_btuh.round(2)} Btu/hr cooling capacity from #{pthp_old_heating_cop.round(2)} heating COP to #{pthp_new_heating_cop.round(2)} heating COP.")
      else
        runner.registerInfo("PTHP unit '#{pthp.name}' with #{cooling_capacity_btuh.round(2)} Btu/hr cooling capacity has an existing heating efficiency of #{pthp_old_heating_cop.round(2)} COP which is better than the requested new efficiency #{pthp_new_heating_cop.round(2)} COP.  Will not change unit.")
      end
    end

    if total_cooling_capacity_w.zero?
      runner.registerAsNotApplicable('Changed PTHP cooling capacity is zero.')
      return false
    end

    total_cooling_capacity_btuh = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/hr').get
    total_cooling_capacity_tons = total_cooling_capacity_btuh / 12_000
    # report final condition of model
    runner.registerValue('hvac_pthp_eff_cooling_load_in_tons', total_cooling_capacity_tons)
    runner.registerFinalCondition("Adjusted cooling efficiency for #{pthps.size} PTHP units with #{total_cooling_capacity_tons.round(1)} tons of total cooling capacity.")
    return true
  end
end

# register the measure to be used by the application
HVACPTHPEfficiency.new.registerWithApplication
