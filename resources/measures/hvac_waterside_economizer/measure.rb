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
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'openstudio-standards'
require 'fileutils'

# start the measure
class HVACIntegratedWatersideEconomizer < OpenStudio::Measure::ModelMeasure
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'IntegratedWatersideEconomizer'
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

    # register as not applicable if there are no chilled or condenser water loops in the model

    # check to see if the model has a condenser loop
    has_condenser_loop = false
    model.getPlantLoops.each { |plant_loop| has_condenser_loop = true if plant_loop.sizingPlant.loopType == 'Condenser' }
    unless has_condenser_loop
      runner.registerAsNotApplicable('The model is missing a condenser loop. Waterside economizer not applicable.')
      return false
    end

    # check if sizing run is needed
    run_sizing = false
    model.getChillerElectricEIRs.each do |chiller|
      next unless chiller.condenserType == 'WaterCooled'
      break if run_sizing
      unless chiller.autosizedReferenceCapacity.is_initialized || chiller.referenceCapacity.is_initialized
        run_sizing = true
      end
    end

    # build standard to access methods
    template = 'ComStock 90.1-2013'
    std = Standard.build(template)

    # check if sizing run is necessary
    if run_sizing
      runner.registerInfo('Plant loop capacity not available. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/SizingRun") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    # add waterside economizer and log chiller capacity
    capacity_tons = 0
    model.getChillerElectricEIRs.each do |chiller|
      next unless chiller.condenserType == 'WaterCooled'

      # add waterside economizer
      chilled_water_loop = chiller.plantLoop.get
      condenser_water_loop = chiller.secondaryPlantLoop.get
      std.model_add_waterside_economizer(model, chilled_water_loop, condenser_water_loop, integrated: true)

      # log chiller capacity
      capacity_w = 0
      if chiller.referenceCapacity.is_initialized
        capacity_w = chiller.referenceCapacity.get
      elsif chiller.autosizedReferenceCapacity.is_initialized
        capacity_w = chiller.autosizedReferenceCapacity.get
      else
        runner.registerError("Capacity not available for chiller '#{chiller.name}' after sizing run.")
        return false
      end
      capacity_tons += OpenStudio.convert(capacity_w, 'W', 'ton').get.to_f
    end

    # reporting final condition of model
    runner.registerFinalCondition("A waterside economizer was applied to the model.")
    runner.registerValue('hvac_waterside_economizer_cooling_load_in_tons', capacity_tons, 'tons')
    return true
  end
end

# this allows the measure to be use by the application
HVACIntegratedWatersideEconomizer.new.registerWithApplication
