# ComStock™, Copyright (c) 2024 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# start the measure
class SetHeatingFuel < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'set_heating_fuel'
  end

  # human readable description
  def description
    return 'Changes natural-gas-fired heating coils to either fuel oil or propane.  Not applicable when the input heating_fuel is NaturalGas, Electricity, DistrictHeating, or NoHeating, as the fuels for those systems are predetermined based on the HVAC system selection.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Should eventually be replaced by allowing specification of all fuels in create_typical_building_from_model'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Make argument for HVAC cooling source
    heating_fuel_chs = OpenStudio::StringVector.new
    heating_fuel_chs << 'NaturalGas'
    heating_fuel_chs << 'Electricity'
    heating_fuel_chs << 'FuelOil'
    heating_fuel_chs << 'Propane'
    heating_fuel_chs << 'DistrictHeating'
    heating_fuel_chs << 'NoHeating'
    heating_fuel = OpenStudio::Measure::OSArgument.makeChoiceArgument('heating_fuel', heating_fuel_chs, true)
    heating_fuel.setDisplayName('Heating Fuel')
    heating_fuel.setDescription('The primary fuel used for space heating in the model.')
    heating_fuel.setDefaultValue('NaturalGas')
    args << heating_fuel
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
    heating_fuel = runner.getStringArgumentValue('heating_fuel', user_arguments)

    # If the heating_fuel is NaturalGas, Electricity, or NoHeating
    # this measure is not applicable because HVAC systems that use those
    # fuel types are built with those fuels when the HVAC is originally created.
    if ['NaturalGas', 'Electricity', 'DistrictHeating', 'NoHeating'].include?(heating_fuel)
      runner.registerAsNotApplicable("HVAC systems already use #{heating_fuel} as the heating fuel.")
      return true
    end

    # If the heating_fuel is Propane or FuelOil,
    # assign this fuel to all boilers and gas heating coils in the model.

    # Map from input heating fuels to EnergyPlus fuel type enumerations
    # for EnergyPlus 9.3.0 / OpenStudio 3.0.0 or higher.
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
    if model.version < OpenStudio::VersionString.new('3.7.0')
      eplus_htg_fuels['DistrictHeating'] = 'DistrictHeating'
    end

    # Heating coils
    htg_coils_changed = []
    target_fuel = eplus_htg_fuels[heating_fuel]
    model.getCoilHeatingGass.each do |htg_coil|
      orig_fuel = htg_coil.fuelType
      if orig_fuel == target_fuel
        runner.registerInfo("Fuel for #{htg_coil.name} was already #{target_fuel}, no change.")
      else
        htg_coil.setFuelType(target_fuel)
        unless htg_coil.fuelType == target_fuel
          runner.registerError("Failed to set fuel for #{htg_coil.name} to #{target_fuel}, check E+ fuel enumerations.")
          return false
        end
        htg_coils_changed << htg_coil
      end
    end

    # Boilers
    boilers_changed = []
    target_fuel = eplus_htg_fuels[heating_fuel]
    model.getBoilerHotWaters.each do |boiler|
      orig_fuel = boiler.fuelType
      if orig_fuel == target_fuel
        runner.registerInfo("Fuel for #{boiler.name} was already #{target_fuel}, no change.")
      else
        boiler.setFuelType(target_fuel)
        unless boiler.fuelType == target_fuel
          runner.registerError("Failed to set fuel for #{boiler.name} to #{target_fuel}, check E+ fuel enumerations.")
          return false
        end
        boilers_changed << boiler
      end
    end

    # If no heating coils or boilers were changed, measure is not applicable
    if htg_coils_changed.empty? && boilers_changed.empty?
      runner.registerAsNotApplicable('No heating coil or boiler fuels needed to be changed.')
      return true
    end

    # report final condition of model
    runner.registerInfo("Changed heating fuel to #{heating_fuel} in #{htg_coils_changed.size} heating coils and #{boilers_changed.size} boilers.")

    return true
  end
end

# register the measure to be used by the application
SetHeatingFuel.new.registerWithApplication
