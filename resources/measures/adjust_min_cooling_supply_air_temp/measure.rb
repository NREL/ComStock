# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class AdjustSupplyAirTemperature < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'adjust_min_cooling_supply_air_temperature'
  end

  # human readable description
  def description
    return 'adjusts the minimum supply air temperature for cooling'
  end

  # human readable description of modeling approach
  def modeler_description
    return ''
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument for minimum damper position
    sat = OpenStudio::Measure::OSArgument.makeDoubleArgument('sat', true)
    sat.setDisplayName('Minimum Cooling Supply Air Temperature')
    sat.setDefaultValue(55.0)
    sat.setMinValue(40.0)
    args << sat

    # apply/not apply measure
    apply_measure = OpenStudio::Ruleset::OSArgument.makeBoolArgument('apply_measure', true)
    apply_measure.setDisplayName('Apply Measure')
    apply_measure.setDefaultValue(true)
    args << apply_measure

    # argument for whether to apply minimum to sizing system
    apply_to_sizing = OpenStudio::Measure::OSArgument.makeBoolArgument('apply_to_sizing', true)
    apply_to_sizing.setDisplayName('Apply to system sizing')
    apply_to_sizing.setDefaultValue(true)
    args << apply_to_sizing
    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)  # Do **NOT** remove this line

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    sat = runner.getDoubleArgumentValue('sat', user_arguments)
    apply_to_sizing = runner.getBoolArgumentValue('apply_to_sizing', user_arguments)
    apply_measure = runner.getBoolArgumentValue('apply_measure', user_arguments)

    if !apply_measure
      runner.registerAsNotApplicable('Measure not applied based on user input.')
      return true
    end
    require 'openstudio-standards'
    std = Standard.build('90.1-2013')

    applicable_cz = []
    (1..4).each do |num|
      applicable_cz << "#{num}A"
      applicable_cz << "#{num}B"
      applicable_cz << "#{num}C"
    end

    props = model.getBuilding.additionalProperties
    ct = 0
    climate_zone_feature = props.getFeatureAsString('climate_zone')

    if climate_zone_feature.is_initialized && applicable_cz.any? { |cz| climate_zone_feature.get.include?(cz) }
      # Code to be executed if climate zone is included in applicable_cz list
      model.getAirLoopHVACs.each do |air_loop|
        # Get all setpoint managers for the current air loop
        setpoint_managers = air_loop.supplyOutletNode.setpointManagers

        # Filter for SetpointManagerScheduled
        setpoint_managers.each do |setpoint_manager|
            if setpoint_manager.to_SetpointManagerScheduled.is_initialized
            sat_sch = OpenStudio::Model::ScheduleRuleset.new(model)
            sat_sch.setName('Supply Air Temp')
            sat_sch.defaultDaySchedule.setName(air_loop.name.to_s + " Setpoint Manager #{sat}F")
            sat_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), sat)
            scheduled_setpoint_manager = setpoint_manager.to_SetpointManagerScheduled.get
            scheduled_setpoint_manager.setSchedule(sat_sch)
            ct+= 1
            if apply_to_sizing
              sizing_system = air_loop.sizingSystem
              sizing_system.setCentralCoolingDesignSupplyAirTemperature(sat)
            end
            # Do something with the scheduled_setpoint_manager
            # For example, print its name
            puts "Found SetpointManagerScheduled: #{scheduled_setpoint_manager.name}"

            # If you want to access the schedule of the setpoint manager
            schedule = scheduled_setpoint_manager.schedule
            puts "Schedule Name: #{schedule.name}"
          end
        end
      end
    else
      runner.registerAsNotApplicable('Climate zone is not applicable. Measure not applied.')
      return true
    end
    runner.registerFinalCondition("#{ct} Air Loops Cooling Supply Air Temperature set to #{sat}F.")
    return true
  end
end
# register the measure to be used by the application
AdjustSupplyAirTemperature.new.registerWithApplication
