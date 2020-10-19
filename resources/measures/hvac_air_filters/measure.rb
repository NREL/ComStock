# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://openstudio.nrel.gov/openstudio-measure-writing-guide

# start the measure
class HVACAirFilters < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'Low Pressure Drop Air Filters'
  end

  # human readable description
  def description
    return 'Filters are commonly used to remove particulate from the airstream in an HVAC system.  Because of their design, filters commonly introduce a pressure drop of 0.5-2.0 inches of water that the fan must overcome to move the air.  Low pressure drop filters can eliminate much of this pressure drop, saving fan energy.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'For each AirLoop, find the constant or variable volume fan and reduce the pressure drop by the specified amount. The default reduction is 0.5 inches of water. Note that this measure does not impact zone HVAC equipment or unitary equipment on an airloop.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Make an argument for the percent pressure drop reduction
    pressure_drop_reduction_inh2o = OpenStudio::Measure::OSArgument.makeDoubleArgument('pressure_drop_reduction_inh2o', true)
    pressure_drop_reduction_inh2o.setDisplayName('Pressure Drop Reduction')
    pressure_drop_reduction_inh2o.setUnits('in W.C.')
    pressure_drop_reduction_inh2o.setDefaultValue(0.5)
    args << pressure_drop_reduction_inh2o

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    pressure_drop_reduction_inh2o = runner.getDoubleArgumentValue('pressure_drop_reduction_inh2o', user_arguments)

    # Check arguments for reasonableness
    if pressure_drop_reduction_inh2o >= 4
      runner.registerError('Pressure drop reduction must be less than 4 in W.C. to be reasonable.')
      return false
    end

    # Loop through all air loops, identify multi-zone loops,
    # find the fan, and reduce the pressure drop to model
    # the impact of improved duct routing.
    air_loops_pd_lowered = []
    air_loops = []
    air_loop_m3_s = 0
    model.getAirLoopHVACs.each do |air_loop|
      next unless air_loop.thermalZones.size > 1
      air_loops << air_loop
      air_loop.supplyComponents.each do |supply_comp|
        fan = nil
        if supply_comp.to_FanConstantVolume.is_initialized
          fan = supply_comp.to_FanConstantVolume.get
        elsif supply_comp.to_FanVariableVolume.is_initialized
          fan = supply_comp.to_FanVariableVolume.get
        end
        if !fan.nil?
          current_pd_pa = fan.pressureRise
          current_pd_inh2o = OpenStudio.convert(current_pd_pa, 'Pa', 'inH_{2}O').get
          new_pd_inh2o = current_pd_inh2o - pressure_drop_reduction_inh2o
          if new_pd_inh2o <= 0
            runner.registerWarning("Initial pressure drop of #{air_loop.name} was #{current_pd_inh2o.round(1)}, less than the requested pressure drop reduction of #{pressure_drop_reduction_inh2o.round(1)}.  Pressure drop for this loop was unchanged.")
            next # Next airloop
          end
          new_pd_pa = OpenStudio.convert(new_pd_inh2o, 'inH_{2}O', 'Pa').get
          fan.setPressureRise(new_pd_pa)
          runner.registerInfo("Lowered pressure drop on #{air_loop.name} by #{pressure_drop_reduction_inh2o} in W.C. from #{current_pd_inh2o.round(2)} in W.C to #{new_pd_inh2o.round(2)} in W.C.")
          air_loops_pd_lowered << air_loop
        end

        if air_loop.designSupplyAirFlowRate.is_initialized
          air_loop_m3_s += air_loop.designSupplyAirFlowRate.get
        elsif air_loop.autosizedDesignSupplyAirFlowRate.is_initialized
          air_loop_m3_s += air_loop.autosizedDesignSupplyAirFlowRate.get
        end
      end
    end

    # Convert total airflow from m3/s to cfm
    air_loop_cfm = OpenStudio.convert(air_loop_m3_s, 'm^3/s', 'ft^3/min').get

    # Not applicable if no air loops
    if air_loops.empty?
      runner.registerAsNotApplicable('This measure is not applicable because there were no multizone airloops in the building.')
      return false
    end

    # Not applicable if no airloops were modified
    if air_loops_pd_lowered.empty?
      runner.registerAsNotApplicable('This measure is not applicable because none of the airloops in the model were impacted.')
      return false
    end

    # Report final condition
    runner.registerFinalCondition("Lowered fan static pressure on #{air_loops_pd_lowered.size} air loops to reflect improved duct routing.")
    runner.registerValue('hvac_air_filters_cfm', air_loop_cfm, 'cfm')

    return true
  end
end

# register the measure to be used by the application
HVACAirFilters.new.registerWithApplication
