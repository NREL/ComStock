# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://openstudio.nrel.gov/openstudio-measure-writing-guide

# start the measure
class HVACBrushlessDCCompressorMotors < OpenStudio::Ruleset::ModelUserScript
  # human readable name
  def name
    return 'HVAC Brushless DC Compressor Motors'
  end

  # human readable description
  def description
    return 'Permanent magnet brushless DC motors can be 10% more efficient than their brushed counterparts (1).  Using these motors in the compressors of DX cooling systems has the potential to increase their efficiency.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'For each DX cooling coil in the model, increase the COP by the user-defined amount (default 2%).  The default is not well supported, but since the motor efficiency increase is 10%, the overall increase in COP should be lower because the compressor motor is only one of the energy-consuming parts of the system.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # # Make integer arg to run measure [1 is run, 0 is no run]
    # run_measure = OpenStudio::Ruleset::OSArgument.makeIntegerArgument('run_measure', true)
    # run_measure.setDisplayName('Run Measure')
    # run_measure.setDescription('integer argument to run measure [1 is run, 0 is no run]')
    # run_measure.setDefaultValue(1)
    # args << run_measure

    # Make an argument for the percent COP increase
    cop_increase_percentage = OpenStudio::Ruleset::OSArgument.makeDoubleArgument('cop_increase_percentage', true)
    cop_increase_percentage.setDisplayName('COP Increase Percentage')
    cop_increase_percentage.setUnits('%')
    cop_increase_percentage.setDefaultValue(2.0)
    args << cop_increase_percentage

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    cop_increase_percentage = runner.getDoubleArgumentValue('cop_increase_percentage', user_arguments)

    # Convert the percent COP increase to a multiplier
    cop_mult = (100 + cop_increase_percentage) / 100

    # Check arguments for reasonableness
    if cop_increase_percentage <= 0 || cop_increase_percentage >= 100
      runner.registerError('COP Increase Percentage must be between 0 and 100')
      return false
    end

    # Loop through all single speed and two speed DX coils
    # and increase their COP by the specified percentage
    # to reflect higher efficiency compressor motors.
    dx_coils = []

    # Two Speed DX Coils
    model.getCoilCoolingDXTwoSpeeds.each do |dx_coil|
      dx_coils << dx_coil
      # Change the high speed COP
      initial_high_cop = dx_coil.ratedHighSpeedCOP
      if initial_high_cop.is_initialized
        initial_high_cop = initial_high_cop.get
        new_high_cop = initial_high_cop * cop_mult
        dx_coil.setRatedHighSpeedCOP(new_high_cop)
        runner.registerInfo("Increased the high speed COP of #{dx_coil.name} from #{initial_high_cop} to #{new_high_cop}.")
      end
      # Change the low speed COP
      initial_low_cop = dx_coil.ratedLowSpeedCOP
      if initial_low_cop.is_initialized
        initial_low_cop = initial_low_cop.get
        new_low_cop = initial_low_cop * cop_mult
        dx_coil.setRatedLowSpeedCOP(new_low_cop)
        runner.registerInfo("Increased the low speed COP of #{dx_coil.name} from #{initial_low_cop} to #{new_low_cop}.")
      end
    end

    # Single Speed DX Coils
    model.getCoilCoolingDXSingleSpeeds.each do |dx_coil|
      dx_coils << dx_coil
      # Change the COP
      initial_cop = dx_coil.ratedCOP
      if initial_cop.is_initialized
        initial_cop = initial_cop.get
        new_cop = OpenStudio::OptionalDouble.new(initial_cop * cop_mult)
        dx_coil.setRatedCOP(new_cop)
        runner.registerInfo("Increased the COP of #{dx_coil.name} from #{initial_cop} to #{new_cop}.")
      end
    end

    # Not applicable if no dx coils
    if dx_coils.empty?
      runner.registerAsNotApplicable('This measure is not applicable because there were no DX cooling coils in the building.')
      return false
    end

    # Report final condition
    runner.registerFinalCondition("Increased the COP in #{dx_coils.size} DX cooling coils by #{cop_increase_percentage}% to reflect the increased efficiency of Brushless DC Motors.")
    runner.registerValue('hvac_brushless_dc_compressor_percent_increase', cop_increase_percentage)
    return true
  end
end

# register the measure to be used by the application
HVACBrushlessDCCompressorMotors.new.registerWithApplication
