# ComStock™, Copyright (c) 2024 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

require 'openstudio-standards'

# start the measure
class HardsizeModel < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Hardsize Model'
  end

  # human readable description
  def description
    return 'Sets the HVAC capacities and flow rates in the model.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Runs a sizing run and applies EnerygyPlus autosized values into the model.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Daylight Savings Time
    apply_hardsize = OpenStudio::Measure::OSArgument.makeBoolArgument('apply_hardsize', true)
    apply_hardsize.setDisplayName('Hardsize model')
    apply_hardsize.setDescription('Set to true to hardsize model HVAC, set to false to leave model autosized')
    apply_hardsize.setDefaultValue(true)
    args << apply_hardsize

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Assign the user inputs to variables
    apply_hardsize = runner.getBoolArgumentValue('apply_hardsize', user_arguments)

    unless apply_hardsize
      runner.registerAsNotApplicable("Leaving model autosized per argument: apply_hardsize = #{apply_hardsize}")
      return true
    end

    reset_log
    standard = Standard.build('ComStock DOE Ref Pre-1980') # Actual standard doesn't matter

    # Collect equipment capacities and flow rates that are hard-sized by OpenStudio-Standards.
    # These fields need to keep the hard-sized values and not be replaced with the
    # autosized values determined by EnergyPlus.
    # The eventual goal is to have OpenStudio-Standards rely entirely on EnergyPlus autosizing,
    # such that all of this code can be removed.

    # TODO: remove this after feature https://github.com/NREL/openstudio-standards/issues/1391 is implemented
    # Get the terminal minimum damper positions and preserve them after the hard-sizing
    # because damper position is hard-sized by openstudio-standards, not autosized
    # Min OA flow rate at these damper positions is also hard-sized.
    vav_damper_posits = {}
    vav_max_rht_fracs = {}
    model.getAirTerminalSingleDuctVAVReheats.each do |term|
      if (term.zoneMinimumAirFlowInputMethod == 'Constant') && !term.isConstantMinimumAirFlowFractionAutosized
        vav_damper_posits[term] = term.constantMinimumAirFlowFraction.get
      end
      unless term.isMaximumFlowFractionDuringReheatAutosized
        vav_max_rht_fracs[term] = term.maximumFlowFractionDuringReheat.get
      end
    end
    vav_max_htg_flows = {}
    vav_min_oas = {}
    model.getSizingSystems.each do |sizing_system|
      unless sizing_system.isCentralHeatingMaximumSystemAirFlowRatioAutosized
        vav_max_htg_flows[sizing_system] = sizing_system.centralHeatingMaximumSystemAirFlowRatio.get
      end
      unless sizing_system.isDesignOutdoorAirFlowRateAutosized
        vav_min_oas[sizing_system] = sizing_system.designOutdoorAirFlowRate.get
      end
    end

    # Run a sizing run to determine equipment capacities and flow rates
    if standard.model_run_sizing_run(model, "#{Dir.pwd}/hardsize_model_SR") == false
      runner.registerError('Sizing run for Hardsize model failed, cannot hard-size model.')
      puts('Sizing run for Hardsize model failed, cannot hard-size model.')
      return false
    end

    # Apply the capacities and flow rates from the sizing run to the model
    runner.registerInfo('Hard-sizing HVAC equipment to capacities and flows used to set efficiencies and controls.')
    model.applySizingValues

    # Reset some fields to the previously-collected hard-sized values
    model.getAirLoopHVACUnitarySystems.each do |unitary|
      if model.version < OpenStudio::VersionString.new('3.7.0')
        unitary.setSupplyAirFlowRateMethodDuringCoolingOperation('SupplyAirFlowRate')
        unitary.setSupplyAirFlowRateMethodDuringHeatingOperation('SupplyAirFlowRate')
      else
        unitary.applySizingValues
      end
    end

    # TODO: remove once this functionality is added to the OpenStudio C++ for hard sizing Sizing:System
    model.getSizingSystems.each do |sizing_system|
      next if sizing_system.isDesignOutdoorAirFlowRateAutosized

      sizing_system.setSystemOutdoorAirMethod('ZoneSum')
    end

    # TODO: remove once this functionality is added to the OpenStudio C++ for hard sizing
    model.getAirTerminalSingleDuctVAVReheats.each do |term|
      next unless term.damperHeatingAction == 'Normal'

      term.autosizeMaximumFlowFractionDuringReheat
      term.autosizeMaximumFlowPerZoneFloorAreaDuringReheat
    end

    # TODO: remove this after feature https://github.com/NREL/openstudio-standards/issues/1391 is implemented
    # Re-apply hardsized VAV damper positions
    model.getAirTerminalSingleDuctVAVReheats.each do |term|
      if vav_damper_posits.key?(term)
        term.setConstantMinimumAirFlowFraction(vav_damper_posits[term])
      end
      if vav_max_rht_fracs.key?(term)
        term.setMaximumFlowFractionDuringReheat(vav_max_rht_fracs[term])
      end
    end

    return true
  end
end

# register the measure to be used by the application
HardsizeModel.new.registerWithApplication
