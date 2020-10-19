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
class SwhGasInstant < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'swh_gas_instant'
  end

  # human readable description
  # human readable description
  def description
    return 'This measure transforms gas storage water heaters into instantaneous gas water heaters.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure goes each water heater, if it finds a natural gas water heater it reduces its UA value to simulate an instantaneous water heater, basically it removes the tank removing any tank skin loss.'
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

    run_sizing = false
    water_heaters_modified = []
    model.getWaterHeaterMixeds.each do |swh|
      unless swh.heaterFuelType == 'NaturalGas'
        runner.registerInfo("Skipping water heater '#{swh.name}'; fuel type is not gas.")
        next
      end

      unless swh.onCycleLossCoefficienttoAmbientTemperature.get > 0 || swh.offCycleLossCoefficienttoAmbientTemperature.get > 0
        runner.registerInfo("Skipping water heater '#{swh.name}'; water heater is already instantaneous tankless.")
        next
      end

      # set tank skin losses to 0 and volume to 10 gallons
      swh.setOnCycleLossCoefficienttoAmbientTemperature(0)
      swh.setOffCycleLossCoefficienttoAmbientTemperature(0)
      swh.setTankVolume(OpenStudio.convert(10.0, 'gal', 'm^3').get)
      swh.setIndirectWaterHeatingRecoveryTime(0)

      runner.registerInfo("Water Heater #{swh.name} has been changed to an instantaneous water heater")
      water_heaters_modified << swh

      # check if sizing run is needed
      unless swh.autosizedHeaterMaximumCapacity.is_initialized || swh.heaterMaximumCapacity.is_initialized
        run_sizing = true
      end
    end

    if water_heaters_modified.empty?
      runner.registerAsNotApplicable('No water heaters has been changed because the fuel is not gas or they are already instantaneous gas water heaters.')
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

    # get capacity of new water heaters
    total_capacity_w = 0
    total_num_changed_water_heaters = 0
    water_heaters_modified.each do |swh|
      if swh.heaterMaximumCapacity.is_initialized
        total_capacity_w += swh.heaterMaximumCapacity.get
      elsif swh.autosizedHeaterMaximumCapacity.is_initialized
        total_capacity_w += swh.autosizedHeaterMaximumCapacity.get
      else
        runner.registerError("Capacity not available for water heater '#{swh.name}' after sizing run.")
        return false
      end

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

    runner.registerFinalCondition("#{water_heaters_modified.size} water heater objects representing #{total_num_changed_water_heaters} water heaters have been changed to instantaneous water heaters.")
    total_capacity_kbtuh = OpenStudio.convert(total_capacity_w, 'W', 'Btu/h').get / 1000
    runner.registerValue('swh_gas_instant_kbtu', total_capacity_kbtuh, 'kbtuh')
    runner.registerValue('swh_gas_instant_number_of_changed_swh', total_num_changed_water_heaters, '#')
    return true
  end
end

# register the measure to be used by the application
SwhGasInstant.new.registerWithApplication
