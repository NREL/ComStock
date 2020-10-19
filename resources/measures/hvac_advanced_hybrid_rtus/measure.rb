# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# start the measure
class HVACAdvancedHybridRTUs < OpenStudio::Ruleset::ModelUserScript
  # define the name that a user will see
  def name
    return 'Advanced Hybrid RTUs'
  end

  # human readable description
  def description
    return 'Advanced hybrid RTUs combine traditional DX cooling with indirect evaporative cooling and variable-speed drive fans to achieve energy and peak demand savings, particularly in hot dry climates.  The increased fan power due to the indirect evaporative cooler may increase energy consumption in humid or heating-dominated climates.  However, this penalty is often outweighed by the benefit of the reduced flow rate possible because of the variable speed drive.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Each packaged single zone system (PSZ-AC, not heat pumps) in the model will be replaced with an advanced hybrid RTU consisting of a 100% effective indirect evaporative cooler, a two speed DX cooling coil, the existing heating coil, and a variable speed fan.  Fan power will be increased by 0.5 inches of water column above the current fan pressure rise to represent the addition of the indirect evaporative cooler.'
  end

  # Set the VSD supply fan and increase pressure rise
  def add_vsd_fan_curve(fan, pressure_rise_pa, motor_eff, fan_eff)
    pressure_rise_increase_in_h2o = 0.5
    pressure_rise_increase_pa = OpenStudio.convert(pressure_rise_increase_in_h2o, 'inH_{2}O', 'Pa').get
    new_pressure_rise_pa = pressure_rise_pa + pressure_rise_increase_pa
    fan.setPressureRise(new_pressure_rise_pa)
    fan.setName("#{fan.name} with VSD and IDEC")
    fan.setMotorEfficiency(motor_eff)
    fan.setFanEfficiency(fan_eff)
    fan.setFanPowerMinimumFlowRateInputMethod('Fraction')
    fan.setFanPowerMinimumFlowFraction(0.3)
    fan.setFanPowerCoefficient1(0.0013)
    fan.setFanPowerCoefficient2(0.147)
    fan.setFanPowerCoefficient3(0.9506)
    fan.setFanPowerCoefficient4(-0.0988)
    fan.setFanPowerCoefficient5(0.0)
  end

  # Set up the DX cooling coil
  def modify_cooling_coil(clg_coil)
    # clg_cap_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    # clg_cap_f_of_temp.setCoefficient1Constant(0.42415)
    # clg_cap_f_of_temp.setCoefficient2x(0.04426)
    # clg_cap_f_of_temp.setCoefficient3xPOW2(-0.00042)
    # clg_cap_f_of_temp.setCoefficient4y(0.00333)
    # clg_cap_f_of_temp.setCoefficient5yPOW2(-0.00008)
    # clg_cap_f_of_temp.setCoefficient6xTIMESY(-0.00021)
    # clg_cap_f_of_temp.setMinimumValueofx(17.0)
    # clg_cap_f_of_temp.setMaximumValueofx(22.0)
    # clg_cap_f_of_temp.setMinimumValueofy(13.0)
    # clg_cap_f_of_temp.setMaximumValueofy(46.0)

    # clg_cap_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
    # clg_cap_f_of_flow.setCoefficient1Constant(0.77136)
    # clg_cap_f_of_flow.setCoefficient2x(0.34053)
    # clg_cap_f_of_flow.setCoefficient3xPOW2(-0.11088)
    # clg_cap_f_of_flow.setMinimumValueofx(0.75918)
    # clg_cap_f_of_flow.setMaximumValueofx(1.13877)

    # clg_energy_input_ratio_f_of_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    # clg_energy_input_ratio_f_of_temp.setCoefficient1Constant(1.23649)
    # clg_energy_input_ratio_f_of_temp.setCoefficient2x(-0.02431)
    # clg_energy_input_ratio_f_of_temp.setCoefficient3xPOW2(0.00057)
    # clg_energy_input_ratio_f_of_temp.setCoefficient4y(-0.01434)
    # clg_energy_input_ratio_f_of_temp.setCoefficient5yPOW2(0.00063)
    # clg_energy_input_ratio_f_of_temp.setCoefficient6xTIMESY(-0.00038)
    # clg_energy_input_ratio_f_of_temp.setMinimumValueofx(17.0)
    # clg_energy_input_ratio_f_of_temp.setMaximumValueofx(22.0)
    # clg_energy_input_ratio_f_of_temp.setMinimumValueofy(13.0)
    # clg_energy_input_ratio_f_of_temp.setMaximumValueofy(46.0)

    # clg_energy_input_ratio_f_of_flow = OpenStudio::Model::CurveQuadratic.new(model)
    # clg_energy_input_ratio_f_of_flow.setCoefficient1Constant(1.20550)
    # clg_energy_input_ratio_f_of_flow.setCoefficient2x(-0.32953)
    # clg_energy_input_ratio_f_of_flow.setCoefficient3xPOW2(0.12308)
    # clg_energy_input_ratio_f_of_flow.setMinimumValueofx(0.75918)
    # clg_energy_input_ratio_f_of_flow.setMaximumValueofx(1.13877)

    # clg_part_load_ratio = OpenStudio::Model::CurveQuadratic.new(model)
    # clg_part_load_ratio.setCoefficient1Constant(0.77100)
    # clg_part_load_ratio.setCoefficient2x(0.22900)
    # clg_part_load_ratio.setCoefficient3xPOW2(0.0)
    # clg_part_load_ratio.setMinimumValueofx(0.0)
    # clg_part_load_ratio.setMaximumValueofx(1.0)

    # clg_cap_f_of_temp_low_spd = OpenStudio::Model::CurveBiquadratic.new(model)
    # clg_cap_f_of_temp_low_spd.setCoefficient1Constant(0.42415)
    # clg_cap_f_of_temp_low_spd.setCoefficient2x(0.04426)
    # clg_cap_f_of_temp_low_spd.setCoefficient3xPOW2(-0.00042)
    # clg_cap_f_of_temp_low_spd.setCoefficient4y(0.00333)
    # clg_cap_f_of_temp_low_spd.setCoefficient5yPOW2(-0.00008)
    # clg_cap_f_of_temp_low_spd.setCoefficient6xTIMESY(-0.00021)
    # clg_cap_f_of_temp_low_spd.setMinimumValueofx(17.0)
    # clg_cap_f_of_temp_low_spd.setMaximumValueofx(22.0)
    # clg_cap_f_of_temp_low_spd.setMinimumValueofy(13.0)
    # clg_cap_f_of_temp_low_spd.setMaximumValueofy(46.0)

    # clg_energy_input_ratio_f_of_temp_low_spd = OpenStudio::Model::CurveBiquadratic.new(model)
    # clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient1Constant(1.23649)
    # clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient2x(-0.02431)
    # clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient3xPOW2(0.00057)
    # clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient4y(-0.01434)
    # clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient5yPOW2(0.00063)
    # clg_energy_input_ratio_f_of_temp_low_spd.setCoefficient6xTIMESY(-0.00038)
    # clg_energy_input_ratio_f_of_temp_low_spd.setMinimumValueofx(17.0)
    # clg_energy_input_ratio_f_of_temp_low_spd.setMaximumValueofx(22.0)
    # clg_energy_input_ratio_f_of_temp_low_spd.setMinimumValueofy(13.0)
    # clg_energy_input_ratio_f_of_temp_low_spd.setMaximumValueofy(46.0)

    # clg_coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(model,
    # model.alwaysOnDiscreteSchedule,
    # clg_cap_f_of_temp,
    # clg_cap_f_of_flow,
    # clg_energy_input_ratio_f_of_temp,
    # clg_energy_input_ratio_f_of_flow,
    # clg_part_load_ratio,
    # clg_cap_f_of_temp_low_spd,
    # clg_energy_input_ratio_f_of_temp_low_spd)

    clg_coil.setRatedLowSpeedSensibleHeatRatio(OpenStudio::OptionalDouble.new(0.69))
    clg_coil.setBasinHeaterCapacity(10)
    clg_coil.setBasinHeaterSetpointTemperature(2.0)
    cop = 3.9
    clg_coil.setRatedLowSpeedCOP(cop)
    clg_coil.setRatedHighSpeedCOP(cop)
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # # Make integer arg to run measure [1 is run, 0 is no run]
    # run_measure = OpenStudio::Ruleset::OSArgument::makeIntegerArgument("run_measure",true)
    # run_measure.setDisplayName("Run Measure")
    # run_measure.setDescription("integer argument to run measure [1 is run, 0 is no run]")
    # run_measure.setDefaultValue(1)
    # args << run_measure

    return args
  end # end the arguments method

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Debugging variables
    # vars = []
    # vars << ['System Node Relative Humidity', 'timestep']
    # vars << ['System Node Temperature', 'timestep']
    # vars << ['System Node Setpoint Temperature', 'timestep']
    # vars << ['Air System Outdoor Air Economizer Status','timestep']
    # vars << ['Air System Outdoor Air Flow Fraction','timestep']
    # vars << ['Air System Outdoor Air Minimum Flow Fraction','timestep']
    # vars << ['Air System Outdoor Air Mass Flow Rate','timestep']
    # vars << ['Air System Mixed Air Mass Flow Rate','timestep']
    # vars << ['Fan Electric Power','timestep']
    # vars << ['Evaporative Cooler Total Stage Effectiveness','timestep']
    # vars << ['Evaporative Cooler Electric Power','timestep']
    # vars << ['Evaporative Cooler Operating Mode Status','timestep']
    # vars << ['Evaporative Cooler Part Load Ratio','timestep']
    # vars << ['Cooling Coil Total Cooling Rate','timestep']
    # vars << ['Cooling Coil Electric Power','timestep']
    # vars << ['Air System Evaporative Cooler Total Cooling Energy','timestep']
    # vars << ['Air System Cooling Coil Total Cooling Energy','timestep']
    # vars << ['Air System DX Cooling Coil Electric Energy','timestep']
    # vars << ['Air System Evaporative Cooler Electric Energy','timestep']
    # vars << ['Air System Total Cooling Energy','timestep']
    #
    # vars.each do |var, freq|
    #   outputVariable = OpenStudio::Model::OutputVariable.new(var, model)
    #   outputVariable.setReportingFrequency(freq)
    # end

    # puts outputVariable

    # Check to make sure the model has single zone RTU air loops, skipping multi-zone systems, heat pump systems, and unitary systems
    single_zone_dx_rtus = []
    model.getAirLoopHVACs.each do |air_loop|
      next if air_loop.thermalZones.size > 1
      next unless air_loop.name.get.include?('PSZ-AC') || air_loop.name.get.include?('PVAV')
      single_zone_dx_rtus << air_loop
    end

    if single_zone_dx_rtus.empty?
      runner.registerAsNotApplicable('Not Applicable.  No packaged single zone DX RTU systems could be found to replace.')
      return false
    end

    # Modify all packaged single zone systems
    air_loops_modified = []
    single_zone_dx_rtus.each do |air_loop|

      # Add the indirect evaporative cooler
      oa_sys = air_loop.airLoopHVACOutdoorAirSystem
      if oa_sys.is_initialized
        oa_sys = oa_sys.get
        oa_ctrl = oa_sys.getControllerOutdoorAir
        oa_ctrl.setEconomizerControlType('FixedDryBulb')
        oa_ctrl.setEconomizerMaximumLimitDryBulbTemperature(OpenStudio.convert(140, 'F', 'C').get)
        oa_ctrl.setLockoutType('NoLockout')

        idec = OpenStudio::Model::EvaporativeCoolerIndirectResearchSpecial.new(model)
        idec.setName("#{air_loop.name} IDEC")
        idec.setSecondaryFanTotalEfficiency(0.4)
        secondary_fan_pressure_rise_in_h2o = 1.5
        secondary_fan_pressure_rise_pa = OpenStudio.convert(secondary_fan_pressure_rise_in_h2o, 'inH_{2}O', 'Pa').get
        idec.autosizeSecondaryAirFanDesignPower
        idec.setSecondaryFanDeltaPressure(secondary_fan_pressure_rise_pa)
        idec.addToNode(oa_sys.outboardOANode.get)
        idec.setRecirculatingWaterPumpPowerConsumption(0) # No pump for 100% effectiveness
        idec.autosizeSecondaryFanFlowRate
        idec.autosizePrimaryDesignAirFlowRate
        idec.setCoolerMaximumEffectiveness(1.0)

        # VSD on secondary fan
        fan_vsd_curve = OpenStudio::Model::CurveCubic.new(model)
        fan_vsd_curve.setCoefficient1Constant(0.0013)
        fan_vsd_curve.setCoefficient2x(0.147)
        fan_vsd_curve.setCoefficient3xPOW2(0.9506)
        fan_vsd_curve.setCoefficient4xPOW3(-0.0988)
        idec.setSecondaryAirFanPowerModifierCurve(fan_vsd_curve)

        # IDEC outlet control
        idec_temp_sch = OpenStudio::Model::ScheduleRuleset.new(model)
        idec_temp_c = OpenStudio.convert(55, 'F', 'C').get
        idec_temp_sch.setName("#{air_loop.name} IDEC Temp")
        idec_temp_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), idec_temp_c)
        idec_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, idec_temp_sch)
        idec_stpt_manager.addToNode(idec.outletModelObject.get.to_Node.get)

        runner.registerInfo("Air loop #{air_loop.name} had an indirect evaporative cooler added.")
      else
        runner.registerWarning("Did not find an outdoor intake on #{air_loop.name}, system will not be modified.")
        next
      end

      # Modify the fan
      pressure_rise_pa = nil
      if air_loop.supplyFan.is_initialized
        fan = air_loop.supplyFan.get
        # Already a variable speed fan
        if fan.to_FanVariableVolume.is_initialized
          fan = fan.to_FanVariableVolume.get
          pressure_rise_pa = fan.pressureRise
          add_vsd_fan_curve(fan, pressure_rise_pa, fan.motorEfficiency, fan.fanEfficiency)
        elsif fan.to_FanConstantVolume.is_initialized
          fan = fan.to_FanConstantVolume.get
          pressure_rise_pa = fan.pressureRise
          fan.remove
          new_fan = OpenStudio::Model::FanVariableVolume.new(model)
          add_vsd_fan_curve(new_fan, pressure_rise_pa, fan.motorEfficiency, fan.fanEfficiency)
          new_fan.addToNode(air_loop.supplyOutletNode)
          new_fan.setName("#{air_loop.name} Fan")
          runner.registerInfo("Air loop #{air_loop.name} had a constant volume fan replaced by a variable speed fan.")
        elsif fan.to_FanOnOff.is_initialized
          fan = fan.to_FanOnOff.get
          pressure_rise_pa = fan.pressureRise
          fan.remove
          new_fan = OpenStudio::Model::FanVariableVolume.new(model)
          add_vsd_fan_curve(new_fan, pressure_rise_pa, fan.motorEfficiency, fan.fanEfficiency)
          new_fan.addToNode(air_loop.supplyOutletNode)
          new_fan.setName("#{air_loop.name} Fan")
          runner.registerInfo("Air loop #{air_loop.name} had a cycling constat volume fan replaced by a variable speed fan.")
        end
      else
        runner.registerWarning("Did not find a supply fan on #{air_loop.name}, system will not be modified.")
        next
      end
      pressure_rise_in_h2o = OpenStudio.convert(pressure_rise_pa, 'Pa', 'inH_{2}O').get

      # Modify the cooling coil
      clg_coil = nil
      air_loop.supplyComponents.each do |sc|
        if sc.to_CoilCoolingDXTwoSpeed.is_initialized
          clg_coil = sc.to_CoilCoolingDXTwoSpeed.get
          modify_cooling_coil(clg_coil)
          runner.registerInfo("Air loop #{air_loop.name} already has a two speed DX cooling coil.  Only the COP will be modified.")
        elsif sc.to_CoilCoolingDXSingleSpeed.is_initialized
          clg_coil = sc.to_CoilCoolingDXSingleSpeed.get
          node = clg_coil.inletModelObject.get.to_Node.get
          new_clg_coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(model)
          modify_cooling_coil(new_clg_coil)
          new_clg_coil.addToNode(node)
          new_clg_coil.setName("#{air_loop.name} 2spd DX Clg Coil")
          clg_coil.remove
          runner.registerInfo("Air loop #{air_loop.name} had a single speed DX cooling coil replaced by a two speed DX cooling coil.")
        elsif sc.to_CoilCoolingWater.is_initialized
          clg_coil = sc.to_CoilCoolingWater.get
          node = clg_coil.airInletModelObject.get.to_Node.get
          new_clg_coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(model)
          modify_cooling_coil(new_clg_coil)
          new_clg_coil.addToNode(node)
          new_clg_coil.setName("#{air_loop.name} 2spd DX Clg Coil")
          clg_coil.remove
          runner.registerInfo("Air loop #{air_loop.name} had a chilled water cooling coil replaced by a two speed DX cooling coil.")
        end
      end
      if clg_coil.nil?
        runner.registerWarning("Did not find a cooling coil on #{air_loop.name}, system will not be modified.")
        next
      end

      # Modify the system minimum airflow fraction
      sizing = air_loop.sizingSystem
      sizing.setMinimumSystemAirFlowRatio(0.3) # For VSD fan
      sizing.setAllOutdoorAirinCooling(true)

      # Modify the terminal to a zero capacity VAV terminal
      zone = air_loop.thermalZones[0]
      zone.equipment.each do |equip|
        if equip.to_AirTerminalSingleDuctUncontrolled.is_initialized
          diffuser = equip.to_AirTerminalSingleDuctUncontrolled.get
          diffuser_outlet_node = diffuser.outletModelObject.get.to_Node.get
          diffuser.remove
          rht_coil = OpenStudio::Model::CoilHeatingElectric.new(model, model.alwaysOnDiscreteSchedule)
          rht_coil.setNominalCapacity(0)
          vav_term = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, model.alwaysOnDiscreteSchedule, rht_coil)
          vav_term.addToNode(diffuser_outlet_node)
          # vav_term.addToNode(zone.inletModelObject.get.to_Node.get)
          # puts air_loop.addBranchForZone(zone)#, vav_term)
        end
      end

      air_loops_modified << air_loop
    end

    runner.registerFinalCondition("#{air_loops_modified.size} packaged single zone systems were replaced with advanced hybrid RTUs.")
    runner.registerValue('hvac_avanced_hybrid_rtus', air_loops_modified.size)

    return true
  end # end the run method
end # end the measure

# this allows the measure to be used by the application
HVACAdvancedHybridRTUs.new.registerWithApplication
