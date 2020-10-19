# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://openstudio.nrel.gov/openstudio-measure-writing-guide

# start the measure
class HVACDuctRouting < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'Improved Duct Routing'
  end

  # human readable description
  def description
    return 'The more restrictions and bends in the ductwork that air must move through to reach a space, the greater the fan energy required to move the air.  Using larger ducts or routing them to avoid restrictions and bends can decrease fan energy.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'For each AirLoop in the model, reduce the fan pressure drop by the user-specified amount (default 10%).  This default is a conservative estimate; further reductions may be achieved, but may not be practical based on size and cost constraints.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Make an argument for the percent pressure drop reduction
    pressure_drop_reduction_pct = OpenStudio::Measure::OSArgument.makeDoubleArgument('pressure_drop_reduction_pct', true)
    pressure_drop_reduction_pct.setDisplayName('Pressure Drop Reduction Percent')
    pressure_drop_reduction_pct.setUnits('%')
    pressure_drop_reduction_pct.setDefaultValue(10.0)
    args << pressure_drop_reduction_pct

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    pressure_drop_reduction_pct = runner.getDoubleArgumentValue('pressure_drop_reduction_pct', user_arguments)

    # Convert the pressure drop reduction to a multiplier
    pd_mult = (100 - pressure_drop_reduction_pct) / 100

    # Check arguments for reasonableness
    if pressure_drop_reduction_pct <= 0 || pressure_drop_reduction_pct >= 100
      runner.registerError('Pressure drop reduction percent must be between 0 and 100.')
      return false
    end

    # Loop through all air loops, identify multi-zone loops,
    # find the fan, and reduce the pressure drop to model
    # the impact of improved duct routing.
    air_loops_pd_lowered = []
    air_loops = []
    floor_area_affected = 0
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
          new_pd_inh2o = current_pd_inh2o * pd_mult
          new_pd_pa = OpenStudio.convert(new_pd_inh2o, 'inH_{2}O', 'Pa').get
          fan.setPressureRise(new_pd_pa)
          runner.registerInfo("Lowered pressure drop on #{air_loop.name} by #{pressure_drop_reduction_pct}% from #{current_pd_inh2o.round(2)} in W.C to #{new_pd_inh2o.round(2)} in W.C.")
          air_loop.thermalZones.each do |zone|
            zone.spaces.each do |space|
              floor_area_affected += space.floorArea
            end
          end
          air_loops_pd_lowered << air_loop
        end
      end
    end

    # Not applicable if no air loops
    if air_loops.empty?
      runner.registerAsNotApplicable('This measure is not applicable because there were no airloops in the building.')
      return true
    end

    # Not applicable if no airloops were modified
    if air_loops_pd_lowered.empty?
      runner.registerAsNotApplicable('This measure is not applicable because none of the airloops in the model were impacted.')
      return true
    end

    # Report final condition
    runner.registerFinalCondition("Lowered fan static pressure on #{air_loops_pd_lowered.size} air loops to reflect improved duct routing.")
    runner.registerValue('hvac_duct_routing_area_ft2', floor_area_affected, 'ft2')

    return true
  end
end

# register the measure to be used by the application
HVACDuctRouting.new.registerWithApplication
