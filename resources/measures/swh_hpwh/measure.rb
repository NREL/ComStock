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
class SwhHpwh < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'swh_hpwh'
  end

  # human readable description
  def description
    return 'This measure swaps electric water heaters with HeatPump water heaters.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure goes each water heater, if it finds a small (<50gal, as defined on the MICS database), electric non-heatpump water heater, it calculates the COP corresponding to a EF=3.5

            The equations for calculating EF and UA are listed here:
            http://www.energycodes.gov/sites/default/files/documents/PrototypeModelEnhancements_2014_0.pdf (Appendix A: Service Water Heating).
            https://github.com/NREL/openstudio-standards/blob/master/lib/openstudio-standards/standards/Standards.WaterHeaterMixed.rb#L90-L102
            First a UA corresponding to a high EF for a standard electric SWH is calculated.
            With that UA value and a EF=3.5 (as listed in common commercially available HP water heaters), the water heater thermal efficiency (corresponding to the COP in this case) is calculated,
            through eq. on line 102 in the github page.
            This number is used for the COP in the partial-load curve assigned to the new HP water heater.
            https://www.energystar.gov/productfinder/product/certified-water-heaters/?formId=0d5ff0a5-d583-4bb4-a6d5-76436de5b169&scrollTo=9&search_text=&fuel_filter=&type_filter=Heat+Pump&brand_name_isopen=&input_rate_thousand_btu_per_hour_isopen=&markets_filter=United+States&zip_code_filter=&product_types=Select+a+Product+Category&sort_by=uniform_energy_factor_uef&sort_direction=DESC&currentZipCode=80401&page_number=0&lastpage=0'
  end

  def calculate_ua(ef)
    ua_btu_per_hr_per_f = (41_094.0 * (1.0 / ef - 1.0)) / (24.0 * 67.5)
    return ua_btu_per_hr_per_f
  end

  def calculate_cop(ua_btu_per_hr_per_f, q_btu_h, ef)
    c1 = 67.5
    c2 = 24.0 / 41_094.0
    burner_efficiency = 0.8
    re = (ua_btu_per_hr_per_f * c1 * burner_efficiency / q_btu_h - 1) / (ua_btu_per_hr_per_f * c1 * c2 - 1 / ef)
    cop = (ua_btu_per_hr_per_f * c1 * burner_efficiency / q_btu_h + re)
    return cop
  end

  def calculate_ef_from_cop(ua_btu_h_per_f, q_btu_h, cop)
    c1 = 67.5
    c2 = 24.0 / 41_094.0
    burner_efficiency = 0.8
    re = cop - ua_btu_h_per_f * c1 * burner_efficiency / q_btu_h
    ef = 1 / (ua_btu_h_per_f * c1 * (c2 - burner_efficiency / q_btu_h / re) + 1 / re)
    return ef
  end

  def create_part_load_curve(model, cop, name)
    part_load_curve = OpenStudio::Model::CurveCubic.new(model)
    part_load_curve.setName(name)
    part_load_curve.setCoefficient1Constant(cop.to_f)
    part_load_curve.setCoefficient2x(0)
    part_load_curve.setCoefficient3xPOW2(0)
    part_load_curve.setCoefficient4xPOW3(0)
    part_load_curve.setMinimumValueofx(0)
    part_load_curve.setMaximumValueofx(1)
    return part_load_curve
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

    if model.getWaterHeaterMixeds.empty?
      runner.registerAsNotApplicable('No water heaters are present in the model.')
      return false
    end

    # heat pump water heater default energy factor
    ef_hp = 3.5

    small_swh_volume_gal = 50
    run_sizing = false
    water_heaters_to_modify = []
    model.getWaterHeaterMixeds.each do |swh|
      unless swh.heaterFuelType == 'Electricity'
        runner.registerInfo("Skipping water heater '#{swh.name}'; fuel type is not electric.")
        next
      end

      if swh.name.get.include? 'Booster'
        runner.registerInfo("Skipping water heater '#{swh.name}'; name indicates a tankless booster water heater.")
        next
      end

      swh_vol_m3 = swh.tankVolume.get
      swh_vol_gal = OpenStudio.convert(swh_vol_m3, 'm^3', 'gal').get
      if swh.additionalProperties.getFeatureAsInteger('component_quantity').is_initialized
        comp_qty = swh.additionalProperties.getFeatureAsInteger('component_quantity').get
        if comp_qty > 1
          runner.registerInfo("Water heater '#{swh.name}' with volume  #{swh_vol_gal.round(1)} gal is representing #{comp_qty} water heaters.")
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
      runner.registerAsNotApplicable('No water heaters are small electric or heat pump storage water heaters that can be upgraded.')
      return false
    end

    # sizing run if necessary
    if run_sizing
      # build standard to access methods
      std = Standard.build('ComStock 90.1-2013')

      runner.registerInfo('Water heater capacity not available. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/swh_sizing_run") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    # alter water heaters
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

      # check energy factor of water heater if labeled as a heat pump water heater
      if swh.name.get.include? 'HeatPump'
        ua_btu_h_per_f_current = OpenStudio.convert(swh.onCycleLossCoefficienttoAmbientTemperature.get, 'W/K', 'Btu/h*R').get
        q_max_btu_h_current = OpenStudio.convert(swh_capacity_w, 'W', 'Btu/h').get
        cop_current = swh.partLoadFactorCurve.get.coefficient1Constant.to_f
        ef_current = calculate_ef_from_cop(ua_btu_h_per_f_current, q_max_btu_h_current, cop_current)

        unless ef_current < ef_hp
          runner.registerInfo("Skipping water heater '#{swh.name}'; energy factor #{ef_current.round(3)} is already greater than #{ef_hp}.")
          next
         end
      end

      # calculate UA
      ua_btu_per_hr_per_f = calculate_ua(0.93)
      swh.setOnCycleLossCoefficienttoAmbientTemperature(OpenStudio.convert(ua_btu_per_hr_per_f, 'Btu/h*R', 'W/K').get)
      swh.setOffCycleLossCoefficienttoAmbientTemperature(OpenStudio.convert(ua_btu_per_hr_per_f, 'Btu/h*R', 'W/K').get)

      # use gas water heater equations for calculating the "thermal efficiency" for this UA and EF.
      # Even though the HPWH is electric, we could not use this approach with the corresponding equations for Electric WH, because the thermal efficiency would be equal to 1 by definition.
      # No equation for electric WH contains, therefore, any thermal efficiency. In order to swap it with COP and backcalculate it, we need to employ gas WH equations.
      q_max_btu_h = OpenStudio.convert(swh_capacity_w, 'W', 'Btu/h').get
      cop = calculate_cop(ua_btu_per_hr_per_f, q_max_btu_h, ef_hp)
      swh.setPartLoadFactorCurve(create_part_load_curve(model, cop, "HPWH_COP_#{cop}"))
      old_name = swh.name
      swh.setName(OpenStudio.convert(swh.tankVolume.get, 'm^3', 'gal').get.round(0).to_s + 'gal HeatPump Water Heater - ' + (q_max_btu_h / 1000).round(0).to_s + 'kBtu/hr')
      runner.registerInfo("Water heater '#{old_name}' has been swapped with a heat pump water heater '#{swh.name}'.")
      water_heaters_modified << swh

      if swh.additionalProperties.getFeatureAsInteger('component_quantity').is_initialized
        comp_qty = swh.additionalProperties.getFeatureAsInteger('component_quantity').get
        if comp_qty > 1
          runner.registerInfo("Water heater '#{swh.name}' is representing #{comp_qty} water heaters.")
          total_num_changed_water_heaters += comp_qty
        end
      else
        total_num_changed_water_heaters += 1
      end
    end

    runner.registerFinalCondition("#{water_heaters_modified.size} water heater objects representing #{total_num_changed_water_heaters} water heaters have been modified.")
    runner.registerValue('swh_hpwh_number_of_changed_swh', total_num_changed_water_heaters, '#')

    return true
  end
end

# register the measure to be used by the application
SwhHpwh.new.registerWithApplication
