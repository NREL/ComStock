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
class HVACThermoelasticHeatPump < OpenStudio::Measure::ModelMeasure
  # Define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'Thermoelastic Heat Pump'
  end

  # Human readable description
  def description
    return 'When a shape-memory alloy is mechanically stressed it undergoes a solid-to-solid phase transformation and rejects heat to the surroundings.  When exposed to the surroundings, it absorbs heat and returns to the original shape.  Researchers have prototyped air conditioning equipment based on this concept.  It is estimated that cooling equipment based on this technology can realistically achieve a COP of around 6, which is roughly twice as good as existing vapor compression technologies.'
  end

  # Human readable description of modeling approach
  def modeler_description
    return 'For each model, find every DX cooling and heating coil and increase the COP to 6.  Since very little information about this technology is available, do not change performance curves or upper/lower operating temperature limits.'
  end

  # Define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new
    return args
  end

  # Define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    results = {}
    dx_name = []
    # Get all DX coils in model
    dx_single = model.getCoilCoolingDXSingleSpeeds
    dx_two = model.getCoilCoolingDXTwoSpeeds
    dx_heat = model.getCoilHeatingDXSingleSpeeds
    total_cooling_capacity_w = 0

    if !dx_single.empty?
      dx_single.each do |dx|
        runner.registerInfo("DX coil: #{dx.name.get} Initial COP: #{dx.ratedCOP.get}")
        dx.setRatedCOP(OpenStudio::OptionalDouble.new(6.0))
        runner.registerInfo("DX coil: #{dx.name.get} Final COP: #{dx.ratedCOP.get}")
        dx_name << dx.name.get
        if dx.ratedTotalCoolingCapacity.is_initialized
          total_cooling_capacity_w += dx.ratedTotalCoolingCapacity.get
        else runner.registerInfo("DX coil '#{dx.name}' does not have a rated cooling capacity and will not be considered in the total cooling load.")
        next
        end
      end
    end

    if !dx_two.empty?
      dx_two.each do |dx|
        runner.registerInfo("DX coil: #{dx.name.get} Initial High COP: #{dx.ratedHighSpeedCOP.get} Low COP: #{dx.ratedLowSpeedCOP.get}")
        dx.setRatedHighSpeedCOP(6.0)
        dx.setRatedLowSpeedCOP(6.0)
        runner.registerInfo("DX coil: #{dx.name.get} Final High COP: #{dx.ratedHighSpeedCOP.get} Final COP: #{dx.ratedLowSpeedCOP.get}")
        dx_name << dx.name.get
        if dx.ratedHighSpeedTotalCoolingCapacity.is_initialized && dx.ratedLowSpeedTotalCoolingCapacity.is_initialized
          high_cooling_capacity_w = dx.ratedHighSpeedTotalCoolingCapacity.to_i
          low_cooling_capacity_w = dx.ratedLowSpeedTotalCoolingCapacity.to_i
          cooling_capacity_w = 0.5 * (high_cooling_capacity_w + low_cooling_capacity_w)
          total_cooling_capacity_w += cooling_capacity_w
        else runner.registerInfo("DX coil '#{dx.name}' does not have a rated cooling capacity and will not be considered in the total cooling load.")
        next
        end
      end
    end

    if !dx_heat.empty?
      dx_heat.each do |dx|
        runner.registerInfo("DX coil: #{dx.name.get} Initial COP: #{dx.ratedCOP}")
        dx.setRatedCOP(6.0)
        runner.registerInfo("DX coil: #{dx.name.get} Final COP: #{dx.ratedCOP}")
        dx_name << dx.name.get
        runner.registerInfo("DX coil '#{dx.name}' is a heating coil and will not be considered in the total cooling load.")
      end
    end

    total_cooling_capacity_btuh = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/hr').get
    total_cooling_capacity_tons = total_cooling_capacity_btuh / 12_000

    if dx_name.empty?
      runner.registerAsNotApplicable('No DX coils are appropriate for this measure')
      return false
    end

    # Report initial conditions of model
    runner.registerInitialCondition("The building has #{dx_name.size} DX coils for which this measure is applicable.")

    # Reporting final condition of model
    runner.registerFinalCondition("The COP of the following coils was increased to 6: #{dx_name}")
    runner.registerValue('hvac_thermoelastic_hp_cooling_load_in_tons', total_cooling_capacity_tons, 'tons')
    return true
  end
end

# This allows the measure to be use by the application
HVACThermoelasticHeatPump.new.registerWithApplication
