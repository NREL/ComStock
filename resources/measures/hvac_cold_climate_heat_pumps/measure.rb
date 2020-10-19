# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/measures/measure_writing_guide/

# start the measure
class HVACColdClimateHeatPumps < OpenStudio::Ruleset::ModelUserScript
  # The modified dx heating coil object replacement object will follow the decriptions from page 19 (of 45) from here:
  # http://apps1.eere.energy.gov/buildings/publications/pdfs/building_america/minisplit_multifamily_retrofit.pdf
  # Because BEopt does not currently model MSHPs, the closest approximation (central variable-speed heat pump without ducts) was used
  # on the advice of BEopt developers. The performance of the variable-speed heat pump was left unchanged: SEER 22 and HSPF 10
  # . These values are slightly conservative when compared to MSHP testing data from NREL (Winkler, 2011). Additional modeling
  # assumptions are shown in Table 7 and Table 8...." We will use the 3rd stage performance for our measure.
  # Stage 3 from BeOpt item #11 from the space conditioning category, air source heat pump type,(SEER 22, HSPF 10), is the item we will mimic to represent
  # a low temp MSHP

  # human readable name
  def name
    return 'HVAC Cold Climate Heat Pumps'
  end

  # human readable description
  def description
    return 'This energy efficiency measure (EEM) adds cold-climate Air-Source Heat Pumps (ccASHP) to all air loops in a model having heat pump heating coils. The measure modifies all existing CoilHeatingDXSingleSpeed coils in a model by replacing performance curves with those representing the heating performance of a cold-climate Air-Source Heat Pumps (ccASHP).  ccASHP are defined as ducted or ductless, air-to-air, split system heat pumps serving either single-zone or multi-zone, best suited to heat efficiently in cold climates (IECC climate zone 4 and higher). ccASHP DOES NOT include ground-source or air-to-water heat pump systems. This measure also sets the Min. OADB Temperature for ccASHP operation to -4F. '
  end

  # human readable description of modeling approach
  def modeler_description
    return "This measure replaces the coefficients for OS:PerformanceCurve objects associated with all OS:CoilHeatingDXSingleSpeed objects. These performance curve objects are modified:
1)	TotalHeatingCapacityFunctionofTemperature
2)	TotalHeatingCapacityFunctionofFlowFraction
3)	EnergyInputRatioFunctionofTemperature
4)	EnergyInputRatioFunctionofFlowFraction
5)	PartLoadFractionCorrelationCurve.
In addition, the setting for the MinimumOutdoorDryBulbTemperatureforCompressorOperation will be changed to -4F.
The replacement curves have been developed by using the 3rd stage of a 4 stage heat pump description of performance curve data used in BeOpt v2.4 for low temperature dx heat pump heating coils.
"
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new

    # # Make integer arg to run measure [1 is run, 0 is no run]
    # run_measure = OpenStudio::Ruleset::OSArgument.makeIntegerArgument('run_measure', true)
    # run_measure.setDisplayName('Run Measure')
    # run_measure.setDescription('integer argument to run measure [1 is run, 0 is no run]')
    # run_measure.setDefaultValue(1)
    # args << run_measure

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # initialize counter variables for SingleSpeedDXHeatingCoil objects at the global level
    dx_htg_coil_count = 0

    model.getObjectsByType(OpenStudio::Model::CoilHeatingDXSingleSpeed.iddObjectType).each do |dx_htg_coil| # getting DX_heating_coil
      dx_htg_coil = dx_htg_coil.to_CoilHeatingDXSingleSpeed.get
      dx_htg_coil_count += 1
      # @initial_cop = dx_htg_coil.ratedCOP # calling the existing COP
      dx_htg_coil.setName("#{dx_htg_coil.name}-modified") # new name for coil
      dx_htg_coil.setRatedCOP(4.07762) # modified COP
      comp_t_initial = dx_htg_coil.minimumOutdoorDryBulbTemperatureforCompressorOperation
      dx_htg_coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-20) # temperature to -4F for compressor operation of coil
      runner.registerInfo "MinimumOutdoorDryBulbTemperatureforCompressorOperation for OS:CoilHeatingDXSingleSpeed object = '#{dx_htg_coil.name}' has been changed from #{((comp_t_initial * 1.8) + 32)}F to -4F."

      # Create a new Heating Capacity Function of Temperature Curve
      # Curve:Biquadratic,
      #   HP_Heat-Cap-fT3,   !- Name
      #   0.9620542196000001,-0.00949277772,0.000109212948,0.0247078314,0.000034225092,-0.000125697744,   !- Coefficients (list)
      #   -100,              !- Minimum Value of x
      #   100,               !- Maximum Value of x
      #   -100,              !- Minimum Value of y
      #   100;               !- Maximum Value of y

      exist_hp_heat_cap_ft3_name = dx_htg_coil.totalHeatingCapacityFunctionofTemperatureCurve.name
      hp_heat_cap_ft3 = OpenStudio::Model::CurveBiquadratic.new(model)
      hp_heat_cap_ft3.setName("#{exist_hp_heat_cap_ft3_name}-modified")
      hp_heat_cap_ft3.setCoefficient1Constant(0.962054)
      hp_heat_cap_ft3.setCoefficient2x(-0.009493)
      hp_heat_cap_ft3.setCoefficient3xPOW2(0.0001092)
      hp_heat_cap_ft3.setCoefficient4y(0.024708)
      hp_heat_cap_ft3.setCoefficient5yPOW2(0.00003423)
      hp_heat_cap_ft3.setCoefficient6xTIMESY(-0.0001257)
      hp_heat_cap_ft3.setMinimumValueofx(-100)
      hp_heat_cap_ft3.setMaximumValueofx(100)
      hp_heat_cap_ft3.setMinimumValueofy(-100)
      hp_heat_cap_ft3.setMaximumValueofy(100)

      # Create a new EIR function of temperature curve
      # Curve:Biquadratic,
      #   hp_heat_eir_ft3,   !- Name
      #   0.5725180114,0.02289624912,0.000266018904,-0.0106675434,0.00049092156,-0.00068136876,   !- Coefficients (List)
      #   -100,              !- Minimum Value of x
      #   100,               !- Maximum Value of x
      #   -100,              !- Minimum Value of y
      #   100;               !- Maximum Value of y

      exist_hp_heat_eir_ft3_name = dx_htg_coil.energyInputRatioFunctionofTemperatureCurve.name
      hp_heat_eir_ft3 = OpenStudio::Model::CurveBiquadratic.new(model)
      hp_heat_eir_ft3.setName("#{exist_hp_heat_eir_ft3_name}-modified")
      hp_heat_eir_ft3.setCoefficient1Constant(0.57252)
      hp_heat_eir_ft3.setCoefficient2x(0.0229)
      hp_heat_eir_ft3.setCoefficient3xPOW2(0.00026602)
      hp_heat_eir_ft3.setCoefficient4y(-0.010668)
      hp_heat_eir_ft3.setCoefficient5yPOW2(0.000491)
      hp_heat_eir_ft3.setCoefficient6xTIMESY(-0.0006814)
      hp_heat_eir_ft3.setMinimumValueofx(-100)
      hp_heat_eir_ft3.setMaximumValueofx(100)
      hp_heat_eir_ft3.setMinimumValueofy(-100)
      hp_heat_eir_ft3.setMaximumValueofy(100)

      # Create a new part load function correlation curve
      # Curve:Quadratic,
      #   hp_heat_plf_fplr3,   !- Name
      #   0.76,0.24,0,         !- Coefficients (List)
      #   0,                   !- Minimum Value of x
      #   1,                   !- Maximum Value of x
      #   0.7,                 !- Minimum Value of y
      #   1;                   !- Maximum Value of y

      exist_hp_heat_plf_fplr3_name = dx_htg_coil.partLoadFractionCorrelationCurve.name
      hp_heat_plf_fplr3 = OpenStudio::Model::CurveQuadratic.new(model)
      hp_heat_plf_fplr3.setName("#{exist_hp_heat_plf_fplr3_name}-modified")
      hp_heat_plf_fplr3.setCoefficient1Constant(0.76)
      hp_heat_plf_fplr3.setCoefficient2x(0.24)
      hp_heat_plf_fplr3.setCoefficient3xPOW2(0.0)
      hp_heat_plf_fplr3.setMinimumValueofx(0)
      hp_heat_plf_fplr3.setMaximumValueofx(1)

      # Create a new heating capacity of flow fraction curve
      # Curve:Quadratic,
      #   hp_heat_cap_fff3,   !- Name
      #   1,0,0,              !- Coefficients (List)
      #   0,                  !- Minimum Value of x
      #   2,                  !- Maximum Value of x
      #   0,                  !- Minimum Value of y
      #   2;                  !- Maximum Value of y
      exist_hp_heat_cap_fff3_name = dx_htg_coil.totalHeatingCapacityFunctionofFlowFractionCurve.name
      hp_heat_cap_fff3 = OpenStudio::Model::CurveQuadratic.new(model)
      hp_heat_cap_fff3.setName("#{exist_hp_heat_cap_fff3_name}-modified")
      hp_heat_cap_fff3.setCoefficient1Constant(1)
      hp_heat_cap_fff3.setCoefficient2x(0.0)
      hp_heat_cap_fff3.setCoefficient3xPOW2(0.0)
      hp_heat_cap_fff3.setMinimumValueofx(0)
      hp_heat_cap_fff3.setMaximumValueofx(2)

      # Create a new EIR of flow fraction curve
      # Curve:Quadratic,
      #   hp_heat_eir_fff3,   !- Name
      #   1,0,0,              !- Coefficients (List)
      #   0,                  !- Minimum Value of x
      #   2,                  !- Maximum Value of x
      #   0,                  !- Minimum Value of y
      #   2;                  !- Maximum Value of y
      exist_hp_heat_eir_fff3_name = dx_htg_coil.energyInputRatioFunctionofFlowFractionCurve.name
      hp_heat_eir_fff3 = OpenStudio::Model::CurveQuadratic.new(model)
      hp_heat_eir_fff3.setName("#{exist_hp_heat_eir_fff3_name}-modified")
      hp_heat_eir_fff3.setCoefficient1Constant(1)
      hp_heat_eir_fff3.setCoefficient2x(0.0)
      hp_heat_eir_fff3.setCoefficient3xPOW2(0.0)
      hp_heat_eir_fff3.setMinimumValueofx(0)
      hp_heat_eir_fff3.setMaximumValueofx(2)

      # Assigning the existing curves with new ones
      dx_htg_coil.setTotalHeatingCapacityFunctionofTemperatureCurve(hp_heat_cap_ft3)
      dx_htg_coil.setTotalHeatingCapacityFunctionofFlowFractionCurve hp_heat_cap_fff3
      dx_htg_coil.setEnergyInputRatioFunctionofTemperatureCurve(hp_heat_eir_ft3)
      dx_htg_coil.setEnergyInputRatioFunctionofFlowFractionCurve(hp_heat_eir_fff3)
      dx_htg_coil.setPartLoadFractionCorrelationCurve hp_heat_plf_fplr3
      runner.registerInfo("Info about curve changes for OS:CoilHeatingDXSingleSpeed object = '#{dx_htg_coil.name}':
      \n1. Heating Capacity Function of Temperature Curve from '#{exist_hp_heat_cap_ft3_name}' to '#{exist_hp_heat_cap_ft3_name}-modified',
      \n2. EIR function of temperature curve from '#{exist_hp_heat_eir_ft3_name}' to '#{exist_hp_heat_eir_ft3_name}-modified',
      \n3. Part load function correlation curve from '#{exist_hp_heat_plf_fplr3_name}' to '#{exist_hp_heat_plf_fplr3_name}-modified',
      \n4. Heating capacity of flow fraction curve from '#{exist_hp_heat_cap_fff3_name}' to '#{exist_hp_heat_cap_fff3_name}-modified',
      \n5. EIR of flow fraction curve from '#{exist_hp_heat_eir_fff3_name}' to '#{exist_hp_heat_eir_fff3_name}-modified'.")
    end # end the do loop through single stage dx heating coil objects

    # not applicable message if there is no valid heating coil
    if
      dx_htg_coil_count == 0
      runner.registerAsNotApplicable("The measure is not applicable due to absence of valid object 'OS:CoilHeatingDXSingleSpeed'.")
      return false
    end # end the not applicable if condition for heating plant loop

    # getting zone equipment PTHP objects
    model.getObjectsByType(OpenStudio::Model::ZoneHVACPackagedTerminalHeatPump.iddObjectType).each do |zone_pthp|
      if zone_pthp.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
        a_1 = zone_pthp.to_ZoneHVACPackagedTerminalHeatPump.get
        initial_comp_temp_zone = a_1.minimumOutdoorDryBulbTemperatureforCompressorOperation
        a_1.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(-20) # changing the temp to -20C (-4F)
        runner.registerInfo("MinimumOutdoorDryBulbTemperatureforCompressorOperation attribute for PTHP ZoneHVACEquipment object named #{a_1.name} has been changed from #{((initial_comp_temp_zone * 1.8) + 32)}F to -4F.")
       end # end if statement
    end # end the do loop

    # report initial condition of model
    runner.registerInitialCondition("The initial model contains #{dx_htg_coil_count} applicable 'OS:CoilHeatingDXSingleSpeed' objects for which this measure is applicable.")

    # report final condition of model
    runner.registerFinalCondition("Performance curves representing 'ccASHP heating technology' has been applied to #{dx_htg_coil_count} OS:CoilHeatingDXSingleSpeed objects in the model.")
    runner.registerValue('hvac_number_of_ashp_affected', dx_htg_coil_count)
    return true
  end # end run method
end # end class

# register the measure to be used by the application
HVACColdClimateHeatPumps.new.registerWithApplication
