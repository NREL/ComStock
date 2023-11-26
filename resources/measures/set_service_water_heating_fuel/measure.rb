# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
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
class SetServiceWaterHeatingFuel < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'set_service_water_heating_fuel'
  end

  # human readable description
  def description
    return 'Changes natural gas water heaters to either fuel oil or propane, and changes electric water heaters to district heating. Not applicable when the input service_water_heating_fuel is Electricity or Natural Gas, as the fuels for those inputs are already set when the water heaters are added to the model.'
  end

  # human readable description of modeling approach
  def modeler_description
    return ''
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Make argument for HVAC cooling source
    service_water_heating_fuel_chs = OpenStudio::StringVector.new
    service_water_heating_fuel_chs << 'NaturalGas'
    service_water_heating_fuel_chs << 'Electricity'
    service_water_heating_fuel_chs << 'FuelOil'
    service_water_heating_fuel_chs << 'Propane'
    service_water_heating_fuel_chs << 'DistrictHeating'
    service_water_heating_fuel = OpenStudio::Measure::OSArgument.makeChoiceArgument('service_water_heating_fuel', service_water_heating_fuel_chs, true)
    service_water_heating_fuel.setDisplayName('Service Water Heating Fuel')
    service_water_heating_fuel.setDescription('The primary fuel used for service water heating in the model.')
    service_water_heating_fuel.setDefaultValue('NaturalGas')
    args << service_water_heating_fuel
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
    service_water_heating_fuel = runner.getStringArgumentValue('service_water_heating_fuel', user_arguments)

    # If the service_water_heating_fuel is NaturalGas or Electricity,
    # this measure is not applicable because service water heating systems that use those
    # fuel types are built with those fuels when they are originally created.
    if ['NaturalGas', 'Electricity'].include?(service_water_heating_fuel)
      runner.registerAsNotApplicable("Service water heating systems already use #{service_water_heating_fuel} as the fuel.")
      return true
    end

    # Map from input heating fuels to EnergyPlus fuel type enumerations
    eplus_htg_fuels = {
        'NaturalGas' => 'NaturalGas',
        'Propane' => 'Propane',
        'FuelOil' => 'FuelOilNo2',
        'DistrictHeating' => 'DistrictHeatingWater'
    }

    # Compatibility with earlier EnergyPlus versions with
    # inconsistent fuel enumerations between objects.
    if model.version < OpenStudio::VersionString.new('3.0.0')
      eplus_htg_fuels['FuelOil'] = 'FuelOil#2'
      eplus_htg_fuels['Propane'] = 'PropaneGas'
    end

    # If the service_water_heating_fuel is Propane, FuelOil, or DistrictHeating
    # swap all water heater fuels with this fuel type.
    # Efficiencies for Propane and FuelOil assumed to be same as NaturalGas
    # Efficiencies for DistrictHeating assumed to be same as Electricity
    water_heaters_changed = []
    target_fuel = eplus_htg_fuels[service_water_heating_fuel]
    model.getWaterHeaterMixeds.each do |water_heater|
      orig_fuel = water_heater.heaterFuelType
      if orig_fuel == target_fuel
        runner.registerInfo("Fuel for #{water_heater.name} was already #{target_fuel}, no change.")
      else
        water_heater.setHeaterFuelType(target_fuel)
        water_heater.setOffCycleParasiticFuelType(target_fuel)
        water_heater.setOnCycleParasiticFuelType(target_fuel)
        unless water_heater.heaterFuelType == target_fuel
          runner.registerError("Failed to set fuel for #{water_heater.name} to #{target_fuel}, check E+ fuel enumerations.")
          return false
        end
        water_heaters_changed << water_heater
      end
    end

    # If no water heaters were changed, measure is not applicable
    if water_heaters_changed.size.zero?
      runner.registerAsNotApplicable("No water heater fuels needed to be changed.")
      return true
    end

    # report final condition of model
    runner.registerInfo("Changed heating fuel to #{service_water_heating_fuel} in #{water_heaters_changed.size} water heaters.")

    return true
  end
end

# register the measure to be used by the application
SetServiceWaterHeatingFuel.new.registerWithApplication
