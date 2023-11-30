# insert your copyright here

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class AdjustVavMinDamperPosition < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'adjust_vav_min_damper_position'
  end

  # human readable description
  def description
    return 'adjusts VAV terminal minimum damper position'
  end

  # human readable description of modeling approach
  def modeler_description
    return ''
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument for minimum damper position
    mdp = OpenStudio::Measure::OSArgument.makeDoubleArgument('mdp', true)
    mdp.setDisplayName('VAV Terminal Minimum Damper Position')
    mdp.setDefaultValue(0.3)
    mdp.setMinValue(0)
    mdp.setMaxValue(1.0)
    args << mdp

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

    mdp = runner.getDoubleArgumentValue('mdp', user_arguments)
    apply_to_sizing = runner.getBoolArgumentValue('apply_to_sizing', user_arguments)
    apply_measure = runner.getBoolArgumentValue('apply_measure', user_arguments)

    if !apply_measure
      runner.registerAsNotApplicable('Measure not applied based on user input.')
      return true
    end
    
    ct = 0
    # get all air loops
    model.getAirLoopHVACs.each do |air_loop|
      
      air_loop.thermalZones.each do |zone|
        zone.airLoopHVACTerminals.each do |terminal|
          if ["AirTerminalSingleDuctVAVNoReheat","AirTerminalSingleDuctVAVReheat"].include?(terminal.iddObjectType.valueName.gsub(/(OS_|_)/,''))
            terminal = terminal.method("to_#{terminal.iddObjectType.valueName.gsub(/(OS_|_)/,'')}").call.get
            terminal.setConstantMinimumAirFlowFraction(mdp)
            terminal.setZoneMinimumAirFlowInputMethod("Constant")
            ct += 1
          end
        end

      end

      if apply_to_sizing
        sizing_system = air_loop.sizingSystem
        sizing_system.setCentralHeatingMaximumSystemAirFlowRatio(mdp)
      end
    end

    runner.registerFinalCondition("#{ct} Air Terminals Minimum Damper Positions set to #{mdp * 100}%.")
    # get all terminals on loop 

    # if VAV single duct, set minimum damper position
    
    # calculate total and minimum system flow 

    return true
  end
end

# register the measure to be used by the application
AdjustVavMinDamperPosition.new.registerWithApplication
