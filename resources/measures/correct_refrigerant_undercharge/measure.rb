# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/measures/measure_writing_guide/

# start the measure
class CorrectRefrigerantUndercharge < OpenStudio::Ruleset::ModelUserScript
  # human readable name
  def name
    return 'Model 30% Refrigerant UnderCharge Scenario'
  end

  # human readable description
  def description
    return "This energy efficiency degradation measure applies a performance degradation factor to all existing DX heating and cooling coils in a model, representing the estimated impact of a 30 percent refrigerant undercharge scenario. An estimated degradation of the coil's rated COP equal to 11.02 percent for cooling and 8.24 percent for heating is applied. The values for the degradation factors are based on research work recently performed by NIST in collaboration with ACCA and published under IEA Annex 36 in 2015. NOTE: This measure WILL NOT CONSERVE ENERGY, but will rather the modified objects will use MORE ENERGY then the base systems."
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This energy efficiency measure (EEM) loops through all DX Coil objects of these types: 1) OS:CoilCoolingDXMultiSpeed, 2) OS:CoilCoolingDXSingleSpeed, 3) OS:CoilCoolingDXTwoSpeed, 4) OS:CoilCoolingDXTwoStageWithHumidityControlMode and 5) OS:CoilHeatingDXSingleSpeed. For each DX Cooling Coil object type, the initial Rated COP is modified (reduced) by 11.02%, representing a 30% refrigerant undercharge scenario. For each DX Heating Coil object type, the initial Rated COP is modified (reduced) by 8.24%, representing a 30% refrigerant undercharge scenario.'
  end

  # Define the arguments that the user will input
  # No arguments for this measure
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new

    # Make integer arg to run measure [1 is run, 0 is no run]
    run_measure = OpenStudio::Ruleset::OSArgument.makeIntegerArgument('run_measure', true)
    run_measure.setDisplayName('Run Measure')
    run_measure.setDescription('integer argument to run measure [1 is run, 0 is no run]')
    run_measure.setDefaultValue(1)
    args << run_measure

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Report that this is an anti-measure
    runner.registerValue('anti_measure', true)

    # Return N/A if not selected to run
    run_measure = runner.getIntegerArgumentValue('run_measure', user_arguments)
    if run_measure == 0
      runner.registerAsNotApplicable("Run Measure set to #{run_measure}.")
      return true
    end

    # initilaize variables

    number_of_coil_cooling_dx_single_speed = 0
    number_of_coil_cooling_dx_two_speed = 0
    number_of_coil_cooling_dx_two_speed_with_humidity_control = 0
    number_of_coil_heating_dx_single_speed = 0
    number_of_coil_cooling_dx_multi_speed = 0
    number_of_water_to_air_heat_pump_cooling_coil = 0
    number_of_water_to_air_heat_pump_heating_coil = 0

    # start the do loop for model objects
    model.getModelObjects.each do |model_object|
      # if statement to get single speed Water to Air Heat Pump DX Cooling Coils
      if model_object.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized
        water_to_air_heat_pump_cooling_coil = model_object.to_CoilCoolingWaterToAirHeatPumpEquationFit.get
        coil_name = water_to_air_heat_pump_cooling_coil.name
        # getting the COP
        initial_cop = water_to_air_heat_pump_cooling_coil.ratedCoolingCoefficientofPerformance

        # Modified COP values are determined from recent NIST published report for quantifying the effect of refrigerant
        # undercharging - Sensitivity Analysis of Installation Faults on Heat Pump Performance
        # http://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1848.pdf
        # Spreadsheet analysis of the regression coefficiencts for modeling heating and cooling annual COP
        # degredation were performed. The result predict a degradation of 11.02% of annual COP (for cooling)

        # modify the COPs
        modified_cop = (initial_cop * (1 - 0.1102))
        # setting the new name
        water_to_air_heat_pump_cooling_coil.setName("#{coil_name} +30 Percent undercharge")
        # assign the new COP to single speed DX
        water_to_air_heat_pump_cooling_coil.setRatedCoolingCoefficientofPerformance(modified_cop)
        number_of_water_to_air_heat_pump_cooling_coil += 1
        runner.registerInfo("Coil Cooling Water To Air Heat Pump Equation Fit object renamed #{coil_name} +30 Percent undercharge has had initial COP value of #{initial_cop} derated to a COP value of #{modified_cop} representing a 30 percent by volume refrigerant undercharge scenario.")
      end # end the if loop for Water to Air Heat Pump Cooling Coils.

      # if statement to get Single Speed Water to Air Heat Pump DX Heating Coils
      if model_object.to_CoilHeatingWaterToAirHeatPumpEquationFit.is_initialized
        water_to_air_heat_pump_heating_coil = model_object.to_CoilHeatingWaterToAirHeatPumpEquationFit.get
        coil_name = water_to_air_heat_pump_heating_coil.name
        # getting the COP
        initial_cop = water_to_air_heat_pump_heating_coil.ratedHeatingCoefficientofPerformance

        # Modified COP values are determined from recent NIST published report for quantifying the effect of refrigerant
        # undercharging - Sensitivity Analysis of Installation Faults on Heat Pump Performance
        # http://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1848.pdf
        # Spreadsheet analysis of the regression coefficiencts for modeling heating and cooling annual COP
        # degredation were performed. The result predict a degradation of 11.02% of annual COP (for cooling)

        # modify the COPs
        modified_cop = (initial_cop * (1 - 0.0824))
        # setting the new name
        water_to_air_heat_pump_heating_coil.setName("#{coil_name} +30 Percent undercharge")
        # assign the new COP to single speed DX
        water_to_air_heat_pump_heating_coil.setRatedHeatingCoefficientofPerformance(modified_cop)
        number_of_water_to_air_heat_pump_heating_coil += 1
        runner.registerInfo("Coil Heating Water To Air Heat Pump Equation Fit object renamed #{coil_name} +30 Percent undercharge has had initial COP value of #{initial_cop} derated to a COP value of #{modified_cop} representing a 30 percent by volume refrigerant undercharge scenario.")
      end # end the if loop for Water to Air Heat Pump Cooling Coils.

      # if statement to get single speed DX coils
      if model_object.to_CoilCoolingDXSingleSpeed.is_initialized
        coil_cooling_dx_single_speed = model_object.to_CoilCoolingDXSingleSpeed.get
        coil_name = coil_cooling_dx_single_speed.name
        if coil_cooling_dx_single_speed.ratedCOP.is_initialized
          # getting the COP
          initial_cop = coil_cooling_dx_single_speed.ratedCOP.get
        end # end the if loop for COP

        # Modified COP values are determined from recent NIST published report for quantifying the effect of refrigerant
        # undercharging - Sensitivity Analysis of Installation Faults on Heat Pump Performance
        # http://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1848.pdf
        # Spreadsheet analysis of the regression coefficiencts for modeling heating and cooling annual COP
        # degredation were performed. The result predict a degradation of 11.02% of annual COP (for cooling)

        # modify the COPs
        modified_cop = (initial_cop * (1 - 0.1102))
        # setting the new name
        coil_cooling_dx_single_speed.setName("#{coil_name} +30 Percent undercharge")
        # assign the new COP to single speed DX
        coil_cooling_dx_single_speed.setRatedCOP(OpenStudio::OptionalDouble.new(modified_cop))
        number_of_coil_cooling_dx_single_speed += 1
        runner.registerInfo("Single Speed DX Cooling Coil object renamed #{coil_name} +30 Percent undercharge had initial COP value of #{initial_cop} derated to a COP value of #{modified_cop} representing a 30 percent by volume refrigerant undercharge scenario.")
      end # end the if loop for DX single speed cooling coils

      # if statement to get 2 speed DX coils
      if model_object.to_CoilCoolingDXTwoSpeed.is_initialized
        coil_cooling_dx_two_speed = model_object.to_CoilCoolingDXTwoSpeed.get
        coil_name = coil_cooling_dx_two_speed.name
        if coil_cooling_dx_two_speed.ratedHighSpeedCOP.is_initialized
          # get high speed COP
          initial_high_speed_cop = coil_cooling_dx_two_speed.ratedHighSpeedCOP.get
        end # end if statement for high speed COP
        if coil_cooling_dx_two_speed.ratedLowSpeedCOP.is_initialized
          # get low speed COP
          initial_low_speed_cop = coil_cooling_dx_two_speed.ratedLowSpeedCOP.get
        end # end if statement for low speed COP

        # modify high & low speed COP
        modified_high_speed_cop = (initial_high_speed_cop * (1 - 0.1102))
        modified_low_speed_cop = (initial_low_speed_cop * (1 - 0.1102))

        # set the new COPs
        coil_cooling_dx_two_speed.setName("#{coil_name} +30 Percent undercharge")
        coil_cooling_dx_two_speed.setRatedHighSpeedCOP(modified_high_speed_cop)
        coil_cooling_dx_two_speed.setRatedLowSpeedCOP(modified_low_speed_cop)

        number_of_coil_cooling_dx_two_speed += 1
        runner.registerInfo("Two Speed DX Cooling Coil object renamed #{coil_name} +30 Percent undercharge had initial high speed COP value of #{initial_high_speed_cop} derated to a COP value of #{modified_high_speed_cop} and an initial lowspeed COP value of #{initial_low_speed_cop} derated to a COP value of #{modified_low_speed_cop} representing a 30 percent by volume refrigerant undercharge scenario.")
      end # end 2 speed cooling coil if statement

      # if statement for heating coil single speed
      if model_object.to_CoilHeatingDXSingleSpeed.is_initialized
        coil_heating_dx_single_speed = model_object.to_CoilHeatingDXSingleSpeed.get
        coil_name = coil_heating_dx_single_speed.name
        # get the initial COP
        initial_cop = coil_heating_dx_single_speed.ratedCOP

        # Modified COP values are determined from recent NIST published report for quantifying the effect of refrigerant
        # undercharging - Sensitivity Analysis of Installation Faults on Heat Pump Performance
        # http://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.1848.pdf
        # Spreadsheet analysis of the regression coefficiencts for modeling heating and cooling annual COP
        # degredation were performed. The result predict a degradation of 11.02% of annual COP (for cooling)

        # modify the COP
        modified_cop = (initial_cop * (1 - 0.0824))
        coil_heating_dx_single_speed.setName("#{coil_name} +30 Percent undercharge")
        coil_heating_dx_single_speed.setRatedCOP(modified_cop)
        number_of_coil_heating_dx_single_speed += 1
        runner.registerInfo("Single Speed DX Heating Coil object renamed #{coil_name} +30 Percent undercharge had initial COP value of #{initial_cop} derated to a COP value of #{modified_cop} representing a 30 percent by volume refrigerant undercharge scenario.")
      end # end if statemen for heating coil single speed

      # if statement for cooling coil DX 2 stage with humidity control mode
      if model_object.to_CoilCoolingDXTwoStageWithHumidityControlMode.is_initialized
        coil_cooling_two_stage_with_humidity_control_mode = model_object.to_CoilCoolingDXTwoStageWithHumidityControlMode.get
        coil_name = coil_cooling_two_stage_with_humidity_control_mode.name

        # modification of the coil
        if coil_cooling_two_stage_with_humidity_control_mode.normalModeStage1CoilPerformance.is_initialized
          normal_mode_stage_1 = coil_cooling_two_stage_with_humidity_control_mode.normalModeStage1CoilPerformance.get
          normal_mode_stage_1_initial_COP = normal_mode_stage_1.grossRatedCoolingCOP
          normal_mode_stage_1_modified_COP = (normal_mode_stage_1_initial_COP * (1 - 0.1102))
          normal_mode_stage_1.setGrossRatedCoolingCOP(normal_mode_stage_1_modified_COP)
        end # end the modification if statement

        # if statement for plus 2 coil performance
        if coil_cooling_two_stage_with_humidity_control_mode.normalModeStage1Plus2CoilPerformance.is_initialized
          normal_mode_stage_1_plus_2 = coil_cooling_two_stage_with_humidity_control_mode.normalModeStage1Plus2CoilPerformance.get
          normal_mode_stage_1_plus_2_initial_COP = normal_mode_stage_1_plus_2.grossRatedCoolingCOP
          normal_mode_stage_1_plus_2_modified_COP = (normal_mode_stage_1_plus_2_initial_COP * (1 - 0.1102))
          normal_mode_stage_1_plus_2.setGrossRatedCoolingCOP(normal_mode_stage_1_plus_2_modified_COP)
        end # end of plus 2 coil performance if statement

        # if statement for dehumidificationMode1Stage1CoilPerformance
        if coil_cooling_two_stage_with_humidity_control_mode.dehumidificationMode1Stage1CoilPerformance.is_initialized
          dehumid_mode_stage_1 = coil_cooling_two_stage_with_humidity_control_mode.dehumidificationMode1Stage1CoilPerformance.get
          dehumid_mode_stage_1_initial_COP = normal_mode_stage_1_plus_2.grossRatedCoolingCOP
          dehumid_mode_stage_1_modified_COP = (dehumid_mode_stage_1_initial_COP * (1 - 0.1102))
          dehumid_mode_stage_1.setGrossRatedCoolingCOP(dehumid_mode_stage_1_modified_COP)
        end # end of dehumidificationMode1Stage1CoilPerformance

        # if statement for dehumidificationMode1Stage1Plus2CoilPerformance
        if coil_cooling_two_stage_with_humidity_control_mode.dehumidificationMode1Stage1Plus2CoilPerformance.is_initialized
          dehumid_mode_stage_1_plus_2 = coil_cooling_two_stage_with_humidity_control_mode.dehumidificationMode1Stage1Plus2CoilPerformance.get
          dehumid_mode_stage_1_plus_2_initial_COP = normal_mode_stage_1_plus_2.grossRatedCoolingCOP
          dehumid_mode_stage_1_plus_2_modified_COP = (dehumid_mode_stage_1_plus_2_initial_COP * (1 - 0.1102))
          dehumid_mode_stage_1_plus_2.setGrossRatedCoolingCOP(dehumid_mode_stage_1_plus_2_modified_COP)
        end # end for dehumidificationMode1Stage1Plus2CoilPerformance

        # info messages
        runner.registerInfo("Two Stage DX Cooling Coil with humidity control renamed #{coil_name} + 30 percent undercharge.")
        runner.registerInfo("Normal Mode Stage 1 modified with initial COP value of #{normal_mode_stage_1_initial_COP} derated to a COP value of #{normal_mode_stage_1_modified_COP}.")
        runner.registerInfo("Normal Mode Stage 1 plus 2 modified with initial COP value of #{normal_mode_stage_1_plus_2_initial_COP} derated to a COP value of #{normal_mode_stage_1_plus_2_modified_COP}.")
        runner.registerInfo("Dehumidification Mode Stage 1 modified with initial COP value of #{dehumid_mode_stage_1_initial_COP} derated to a COP value of #{dehumid_mode_stage_1_modified_COP}.")
        runner.registerInfo("Dehumidification Mode Stage 1 plus 2 modified with initial COP value of #{dehumid_mode_stage_1_plus_2_initial_COP} derated to a value of #{dehumid_mode_stage_1_plus_2_modified_COP}.")

        number_of_coil_cooling_dx_two_speed_with_humidity_control += 1

      end # end the cooling coil DX 2 stage with humidity control loop

      # if statement for Cooling coil multispeed coil
      if model_object.to_CoilCoolingDXMultiSpeed.is_initialized
        coil_cooling_dx_multispeed = model_object.to_CoilCoolingDXMultiSpeed.get
        coil_name = coil_cooling_dx_multispeed.name
        dx_stages = coil_cooling_dx_multispeed.stages
        # do loop for getting COP
        dx_stages.each do |dx_stage|
          count += 1
          initial_cop = dx_stage.grossRatedCoolingCOP
          modified_cop = (initial_cop * (1 - 0.1102)) # modify the COP
          dx_stage.setGrossRatedCoolingCOP(modified_cop)
          runner.registerInfo("Stage #{count} of Multispeed DX Cooling coil named #{coil_name} had the initial COP value of #{initial_cop} derated to a value of #{final_cop} to represent a 30 percent refrigerant undercharge scenario.")
        end # end loop through dx stages
        number_of_coil_cooling_dx_multi_speed += 1
      end # end loop through to_CoilCoolingDXMultiSpeed objects
    end # end loop through all model objects

    # total number of coils in the model
    total = number_of_water_to_air_heat_pump_heating_coil + number_of_water_to_air_heat_pump_cooling_coil + number_of_coil_cooling_dx_single_speed + number_of_coil_cooling_dx_two_speed + number_of_coil_cooling_dx_two_speed_with_humidity_control + number_of_coil_heating_dx_single_speed + number_of_coil_cooling_dx_multi_speed = 0

    # non applicable message
    if total == 0
      runner.registerAsNotApplicable('No qualified DX cooling or heating objects are present in this model. The measure is not applicable.')
      return true
    end
    runner.registerInitialCondition("The measure began with #{total} objects which can be modified to represent a 30% refrigerant undercharge condition.")
    runner.registerFinalCondition("The measure modified #{number_of_coil_cooling_dx_single_speed} Coil Cooling DX Single Speed Objects, #{number_of_coil_cooling_dx_two_speed} Coil Cooling DX Two Speed Objects, #{number_of_coil_cooling_dx_two_speed_with_humidity_control} Coil Cooling DX Two Speed with Humidity Control Objects, #{number_of_coil_heating_dx_single_speed} Coil Heating DX Single Speed Objects, #{number_of_water_to_air_heat_pump_heating_coil} Water to Air Heat Puump DX heating coils, #{number_of_water_to_air_heat_pump_cooling_coil} Water to Air Heat Pump cooling coils and #{number_of_coil_cooling_dx_multi_speed} Coil Cooling DX MultiSpeed objects.")
		runner.registerValue('number_of_modified_coils', air_loops_modified.size)
		return true
  end # end of run method
end # end of class

# register the measure to be used by the application
CorrectRefrigerantUndercharge.new.registerWithApplication
