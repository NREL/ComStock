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
class SwhGasStorageEff < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'swh_gas_storage_eff'
  end

  # human readable description
  def description
    return 'This measure improves the Energy Factor of small gas water heaters with a value defined by the user.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure goes each water heater, if it finds a small (<75BTU/h, <50gal, as defined on the MICS database), natural gas water heater it checks its Energy Factor (using calculate_ef(ua_btu_h_per_F, q_btu_h)).
            The equations for calculating EF through UA and vice-versa are listed here:
            http://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf (Appendix A: Service Water Heating).
            If the current EF is lower than the chosen one, UA is changed accordingly to increase the EF of the water heater (using calculate_ua(ef, q_btu_h)).
            The RE formula has been taken from here:
            https://github.com/NREL/openstudio-standards/blob/95fe2261b63e5b3db2a230c9712f1dac224e1b67/lib/openstudio-standards/standards/necb/NECB2011/service_water_heating.rb '
  end

  def calculate_ef(ua_btu_h_per_F, q_btu_h)
    burner_efficiency = 0.8
    thermal_efficiency = 0.82
    c1 = 67.5
    c2 = 0.0005840268652
    p_on = q_btu_h / burner_efficiency
    re = (p_on * thermal_efficiency - ua_btu_h_per_F * c1) / p_on
    energy_factor = 1 / (ua_btu_h_per_F * c1 * (c2 - 1 / re / p_on) + 1 / re)
    return energy_factor
  end

  def calculate_ua(ef, q_btu_h)
    thermal_efficiency = 0.82
    # This is the original
    # re = -0.1137 * ef**2 + 0.1997 * ef + 0.731
    # This re formula has been taken from:
    # /lib/openstudio-standards/standards/necb/NECB2011/service_water_heating.rb
    # It has been tested and it is more precise.
    re = (Math.sqrt(6724.0 * ef**2 * q_btu_h**2 + 40_409_100.0 * ef**2 * q_btu_h - 28_080_900.0 * ef * q_btu_h + 29_318_000_625.0 * ef**2 - 58_636_001_250.0 * ef + 29_318_000_625.0) + 82.0 * ef * q_btu_h + 171_225.0 * ef - 171_225.0) / (200.0 * ef * q_btu_h)
    ua_btu_per_hr_per_f = (thermal_efficiency - re) * q_btu_h / 0.8 / 67.5
    return ua_btu_per_hr_per_f
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    choices = OpenStudio::StringVector.new
    choices << '0.57'
    choices << '0.67'
    choices << '0.70'
    choices << '0.82'
    ef_choice = OpenStudio::Measure::OSArgument.makeChoiceArgument('ef_choice', choices, true)
    ef_choice.setDisplayName('Energy Factor Choice:')
    ef_choice.setDefaultValue('0.82')
    args << ef_choice

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    ef_choice = runner.getStringArgumentValue('ef_choice', user_arguments).to_f

    small_swh_volume_gal = 50
    small_swh_capacity_btuh = 75_000
    run_sizing = false
    water_heaters_to_modify = []
    model.getWaterHeaterMixeds.each do |swh|
      unless swh.heaterFuelType == 'NaturalGas'
        runner.registerInfo("Skipping water heater '#{swh.name}'; fuel type is not gas.")
        next
      end

      swh_vol_m3 = swh.tankVolume.get
      swh_vol_gal = OpenStudio.convert(swh_vol_m3, 'm^3', 'gal').get
      if swh.additionalProperties.getFeatureAsInteger('component_quantity').is_initialized
        comp_qty = swh.additionalProperties.getFeatureAsInteger('component_quantity').get
        if comp_qty > 1
          runner.registerInfo("Water heater '#{swh.name}' with volume #{swh_vol_gal.round(0)} gal is representing #{comp_qty} water heaters.")
          swh_vol_gal /= comp_qty.to_f
        end
      else
        comp_qty = 1
      end

      unless swh_vol_gal <= small_swh_volume_gal
        runner.registerInfo("Skipping water heater '#{swh.name}'; water heater volume #{swh_vol_gal.round(1)} gal is greater than small capacity limit of #{small_swh_volume_gal} gal.")
        next
      end

      water_heaters_to_modify << swh

      # check if sizing run is needed
      unless swh.autosizedHeaterMaximumCapacity.is_initialized || swh.heaterMaximumCapacity.is_initialized
        run_sizing = true
      end
    end

    if water_heaters_to_modify.empty?
      runner.registerAsNotApplicable('No water heaters are gas storage water heaters that can be upgraded.')
      return false
    end

    # sizing run if necessary
    if run_sizing
      # build standard to access methods
      std = Standard.build('ComStock DEER 2020')

      runner.registerInfo('Water heater capacity not available. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/swh_sizing_run") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    total_capacity_w = 0
    water_heaters_modified = []
    total_num_changed_water_heaters = 0
    water_heaters_to_modify.each do |swh|
      # get water heater capacity
      if swh.heaterMaximumCapacity.is_initialized
        swh_capacity_w = swh.heaterMaximumCapacity.get
      elsif swh.autosizedHeaterMaximumCapacity.is_initialized
        swh_capacity_w = swh.autosizedHeaterMaximumCapacity.get
      else
        runner.registerError("Capacity not available for water heater '#{swh.name}' after sizing run.")
        return false
      end
      swh_capacity_btuh = OpenStudio.convert(swh_capacity_w, 'Btu/h', 'W').get

      if swh.additionalProperties.getFeatureAsInteger('component_quantity').is_initialized
        comp_qty = swh.additionalProperties.getFeatureAsInteger('component_quantity').get
        if comp_qty > 1
          runner.registerInfo("Water heater '#{swh.name}' with capacity #{swh_capacity_btuh.round} Btu/h is representing #{comp_qty} water heaters.")
        end
      else
        comp_qty = 1
      end

      swh_capacity_per_unit_btuh = swh_capacity_btuh / comp_qty.to_f
      unless swh_capacity_per_unit_btuh <= small_swh_capacity_btuh
        runner.registerInfo("Skipping water heater '#{swh.name}'; capacity #{swh_capacity_per_unit_btuh.round} Btu/h is over small capacity limit of #{small_swh_capacity_btuh.round} Btu/h.")
        next
      end

      # get parameters to calculate energy factor
      ua_btu_per_hr_per_f = OpenStudio.convert(swh.onCycleLossCoefficienttoAmbientTemperature.get, 'W/K', 'Btu/h*R').get
      energy_factor = calculate_ef(ua_btu_per_hr_per_f, swh_capacity_btuh)
      # re_orig = calculate_re(ua_btu_per_hr_per_f, q_max_btu_h)
      # other = calculate_other(ua_btu_per_hr_per_f, q_max_btu_h)
      runner.registerInfo("Exsting water heater '#{swh.name}' has an EF=#{energy_factor.round(3)} and UA=#{ua_btu_per_hr_per_f.round(3)} Btu/hr*R")
      unless energy_factor < ef_choice
        runner.registerInfo("Skipping water heater '#{swh.name}'; energy factor #{energy_factor.round(3)} is already greater than selected #{ef_choice}.")
        next
      end

      # set new parameters for new energy factor
      new_ua_btu_per_hr_per_f = calculate_ua(ef_choice, swh_capacity_btuh)
      new_ua_w_per_k = OpenStudio.convert(new_ua_btu_per_hr_per_f, 'Btu/h*R', 'W/K').get
      swh.setOnCycleLossCoefficienttoAmbientTemperature(new_ua_w_per_k)
      swh.setOffCycleLossCoefficienttoAmbientTemperature(new_ua_w_per_k)
      # 40gal NaturalGas Water Heater - 27kBtu/hr 0.82 Therm Eff
      old_name = swh.name
      new_ef = calculate_ef(new_ua_btu_per_hr_per_f, swh_capacity_btuh)
      runner.registerInfo("For '#{swh.name}', intended EF=#{ef_choice} actual new EF=#{new_ef.round(1)}, old UA=#{ua_btu_per_hr_per_f.round(3)} Btu/hr*R and new UA=#{new_ua_btu_per_hr_per_f.round(3)} Btu/hr*R")
      tank_vol = OpenStudio.convert(swh.tankVolume.get, 'm^3', 'gal').get / comp_qty.to_f
      swh.setName("#{comp_qty}X #{tank_vol.round(0)} gal NaturalGas Water Heater #{swh_capacity_per_unit_btuh.round} Btu/hr #{ef_choice} EF")
      runner.registerInfo("Changed water name from '#{old_name}' to '#{swh.name}'")
      total_capacity_w += swh_capacity_w
      water_heaters_modified << swh
      total_num_changed_water_heaters += comp_qty
    end

    if water_heaters_modified.empty?
      runner.registerAsNotApplicable('No water heaters are small gas storage water heaters with lower energy factor than requested.')
      return false
    end

    runner.registerFinalCondition("#{water_heaters_modified.size} water heater objects representing #{total_num_changed_water_heaters} water heaters have been modified.")
    capacity_kbtuh = OpenStudio.convert(total_capacity_w, 'W', 'Btu/h').get / 1000.0
    runner.registerValue('swh_gas_storage_eff_kbtuh', capacity_kbtuh, 'kbtuh')

    return true
  end
end

# register the measure to be used by the application
SwhGasStorageEff.new.registerWithApplication
