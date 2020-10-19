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

# start the measure
class RefrigFloatingHeadPressure < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'refrig_floating_head_pressure'
  end

  # human readable description
  def description
    return 'This measure adds the floating head pressure control'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'The floating head pressure control can be simulated in EnergyPlus by reducing the minimum condenser temperature in each refrigeration system object from 26.7°C to 15.6°C, and by switching from constant-speed control of the air-cooled refrigeration condensers to variable-speed control.'
  end

  # add floating heat pressure
  def add_fhpc(system)
    minimum_condensing_temperature_fhpc_f = 60.0
    if system.refrigerationCondenser.get.to_RefrigerationCondenserAirCooled.is_initialized
      system.refrigerationCondenser.get.to_RefrigerationCondenserAirCooled.get.setCondenserFanSpeedControlType('VariableSpeed')
    elsif system.refrigerationCondenser.get.to_RefrigerationCondenserEvaporativeCooled.is_initialized
      system.refrigerationCondenser.get.to_RefrigerationCondenserEvaporativeCooled.get.fanSpeedControlType('VariableSpeed')
    end
    system.setMinimumCondensingTemperature(OpenStudio.convert(minimum_condensing_temperature_fhpc_f, 'F', 'C').get)
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

    if model.getRefrigerationSystems.empty?
      runner.registerAsNotApplicable('No refrigeration systems are present in the model, the measure is not applicable.')
      return false
    end

    total_cooling_load_w = 0
    systems_modified = []
    minimum_condensing_temperature_fhpc_f = 60.0
    model.getRefrigerationSystems.each do |system|
      # Case there is no condenser or it is not AirCooled/EvaporativeCooled
      unless system.refrigerationCondenser.is_initialized
        condenser_object = system.refrigerationCondenser.get
        unless condenser_object.to_RefrigerationCondenserAirCooled.is_initialized || condenser_object.to_RefrigerationCondenserEvaporativeCooled.is_initialized
          runner.registerInfo("The measure is not applicable for the system #{system.name}.")
          next
        end
      end

      # case FHP already set
      condenser_object = system.refrigerationCondenser.get
      minimum_condensing_temperature_f = OpenStudio.convert(system.minimumCondensingTemperature, 'C', 'F').get
      if (minimum_condensing_temperature_f - minimum_condensing_temperature_fhpc_f).abs < 0.1
        if condenser_object.to_RefrigerationCondenserAirCooled.is_initialized && (condenser_object.to_RefrigerationCondenserAirCooled.get.condenserFanSpeedControlType == 'VariableSpeed')
          runner.registerInfo("The measure is not applicable for the system #{system.name}, floating head pressure control already set.")
          next
        elsif condenser_object.to_RefrigerationCondenserEvaporativeCooled.is_initialized && (condenser_object.to_RefrigerationCondenserEvaporativeCooled.get.fanSpeedControlType != 'VariableSpeed')
          runner.registerInfo("The measure is not applicable for the system #{system.name}, floating head pressure control already set.")
          next
        end
      else
        add_fhpc(system)
        systems_modified << system
        runner.registerInfo("System #{system.name} has been modified with FHP.")

        # loop through and get cooling loads
        system.cases.each do |ref_case|
          total_cooling_load_w += ref_case.ratedTotalCoolingCapacityperUnitLength * ref_case.caseLength
        end
        system.walkins.each do |walkin|
          total_cooling_load_w += walkin.ratedCoilCoolingCapacity
        end
      end
    end

    if systems_modified.empty?
      runner.registerAsNotApplicable('The measure is not applicable for any refrigeration system on the model or the systems already contain floating head pressure control')
      return false
    end

    # report final condition of model
    total_cooling_load_tons = OpenStudio.convert(total_cooling_load_w, 'W', 'ton').get
    runner.registerFinalCondition("#{systems_modified.size} refrigeration systems with #{total_cooling_load_tons.round(1)} tons of cooling have been modified with floating head pressure controls")
    runner.registerValue('refrig_floating_head_pressure_ton_refrigeration', total_cooling_load_tons, 'ton')

    return true
  end
end

# register the measure to be used by the application
RefrigFloatingHeadPressure.new.registerWithApplication
