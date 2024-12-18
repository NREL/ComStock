# ComStock™, Copyright (c) 2024 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# start the measure
class FaultHvacEconomizerChangeoverTemperature < OpenStudio::Ruleset::ModelUserScript
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'fault hvac economizer changeover temperature'
  end

  def description
    return 'This is a fault measure that changes normal changeover temperature setpoint of a fixed dry-bulb economizer to lower changeover temperature setpoint (10.88C).'
  end

  def modeler_description
    return "Finds Economizer with fixed dry-bulb control and replaces existing changeover temperature setpoint to the user-defined changeover temperature setpoint if the existing economizer's setpoint is higher than the user-defined setpoint."
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new

    # make choice arguments for economizers
    controlleroutdoorairs = model.getControllerOutdoorAirs
    chs = OpenStudio::StringVector.new
    chs << 'all available economizer'
    controlleroutdoorairs.each do |controlleroutdoorair|
      chs << controlleroutdoorair.name.to_s
    end
    econ_choice = OpenStudio::Ruleset::OSArgument.makeChoiceArgument('econ_choice', chs, true)
    econ_choice.setDisplayName("Choice of economizers. If you want to impose the fault on all economizers, choose 'all available economizer'")
    econ_choice.setDefaultValue('all available economizer')
    args << econ_choice

    # define faulted changeover temperature setpoint
    changeovertemp = OpenStudio::Ruleset::OSArgument.makeDoubleArgument('changeovertemp', false)
    changeovertemp.setDisplayName("'Changeover temperature of the economizer's fixed dry-bulb controller.")
    changeovertemp.setDefaultValue(10.88) # in degree celsius (51.6F)
    args << changeovertemp

    # apply/not-apply measure
    apply_measure = OpenStudio::Measure::OSArgument.makeBoolArgument('apply_measure', true)
    apply_measure.setDisplayName('Apply measure?')
    apply_measure.setDescription('')
    apply_measure.setDefaultValue(true)
    args << apply_measure

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # obtain user inputs
    econ_choice = runner.getStringArgumentValue('econ_choice', user_arguments)
    changeovertemp = runner.getDoubleArgumentValue('changeovertemp', user_arguments)
    apply_measure = runner.getBoolArgumentValue('apply_measure', user_arguments)

    # check if changeover temperature setpoint is reasonable
    if changeovertemp < 4.44 || changeovertemp > 23.89
      runner.registerError("Changeover temperature must be between 4.44C and 23.89C and it is now #{changeovertemp}!")
      return false
    end

    # puts("### adding output variables (for debugging)")
    # ov_eco_status = OpenStudio::Model::OutputVariable.new("debugging_ecostatus",model)
    # ov_eco_status.setKeyValue("*")
    # ov_eco_status.setReportingFrequency("timestep")
    # ov_eco_status.setVariableName("Air System Outdoor Air Economizer Status")

    # ov_oa_fraction = OpenStudio::Model::OutputVariable.new("debugging_ov_oafraction",model)
    # ov_oa_fraction.setKeyValue("*")
    # ov_oa_fraction.setReportingFrequency("timestep")
    # ov_oa_fraction.setVariableName("Air System Outdoor Air Flow Fraction")

    # ov_oa_mdot = OpenStudio::Model::OutputVariable.new("debugging_oamdot",model)
    # ov_oa_mdot.setKeyValue("*")
    # ov_oa_mdot.setReportingFrequency("timestep")
    # ov_oa_mdot.setVariableName("Air System Outdoor Air Mass Flow Rate")

    # ov_oat = OpenStudio::Model::OutputVariable.new("debugging_oat",model)
    # ov_oat.setKeyValue("*")
    # ov_oat.setReportingFrequency("timestep")
    # ov_oat.setVariableName("Site Outdoor Air Drybulb Temperature")

    # ov_coil_cooling = OpenStudio::Model::OutputVariable.new("debugging_cooling",model)
    # ov_coil_cooling.setKeyValue("*")
    # ov_coil_cooling.setReportingFrequency("timestep")
    # ov_coil_cooling.setVariableName("Cooling Coil Total Cooling Rate")

    # applicability check
    # don't apply measure if specified in input
    if apply_measure == false
      runner.registerAsNotApplicable('Measure is not applied based on user input.')
      return true
    end
    no_outdoor_air_loops = 0
    doas_loops = 0
    existing_economizer_loops = 0
    selected_air_loops = []
    model.getAirLoopHVACs.each do |air_loop_hvac|
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem
      if oa_system.is_initialized
        oa_system = oa_system.get
      else
        no_outdoor_air_loops += 1
        runner.registerInfo("Air loop #{air_loop_hvac.name} does not have outdoor air and cannot economize.")
        next
      end

      sizing_system = air_loop_hvac.sizingSystem
      type_of_load = sizing_system.typeofLoadtoSizeOn
      if type_of_load == 'VentilationRequirement'
        doas_loops += 1
        runner.registerInfo("Air loop #{air_loop_hvac.name} is a DOAS system and cannot economize.")
        next
      end

      oa_controller = oa_system.getControllerOutdoorAir
      economizer_type = oa_controller.getEconomizerControlType
      if economizer_type == 'NoEconomizer'
        runner.registerInfo("Air loop #{air_loop_hvac.name} does not have an existing economizer. This measure will skip this air loop.")
      elsif economizer_type != 'FixedDryBulb'
        runner.registerInfo("Air loop #{air_loop_hvac.name} has economizer with #{economizer_type} control instead of fixed dry-bulb control. This measure will skip this air loop.")
      else
        existing_economizer_loops += 1
        runner.registerInfo("Air loop #{air_loop_hvac.name} has an applicable #{economizer_type} economizer. This measure will impose fault to the economizer in this air loop.")
        selected_air_loops << air_loop_hvac
      end
    end

    # report initial condition of model
    runner.registerInitialCondition("Out of #{model.getAirLoopHVACs.size} air loops, #{no_outdoor_air_loops} do not have outdoor air, #{doas_loops} are DOAS systems, and #{existing_economizer_loops} have existing economizers. Leaving #{selected_air_loops.size} economizers applicable.")
    if selected_air_loops.empty?
      runner.registerAsNotApplicable('Model contains no air loops eligible for adding an outdoor air economizer.')
      return true
    end

    # apply fault only to applicable economizers
    count_eco = 0
    selected_air_loops.each do |selected_air_loop|
      controlleroutdoorair = selected_air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
      if controlleroutdoorair.name.to_s.eql?(econ_choice) || econ_choice.eql?('all available economizer')
        controltype = controlleroutdoorair.getEconomizerControlType
        # puts("--- checking for #{controlleroutdoorair.name}: applicable economizer available")
        runner.registerInfo("Found applicable economizer from controlleroutdoorair object: #{controlleroutdoorair.name}")
        changeovertemp_original = controlleroutdoorair.getEconomizerMaximumLimitDryBulbTemperature.to_f.round(3)
        # puts("--- checking for #{controlleroutdoorair.name}: changeover temperature of economizer (original) = #{changeovertemp_original}C")
        if changeovertemp_original > changeovertemp
          controlleroutdoorair.setEconomizerMaximumLimitDryBulbTemperature(changeovertemp)
          changeovertemp_faulted = controlleroutdoorair.getEconomizerMaximumLimitDryBulbTemperature.to_f.round(3)
          # puts("--- checking for #{controlleroutdoorair.name}: changeover temperature of economizer (shifted) = #{changeovertemp_faulted}C")
          count_eco += 1
        end
      end
    end

    # ----------------------------------------------------
    # puts("### finalization")
    # ----------------------------------------------------
    runner.registerFinalCondition("Out of #{model.getAirLoopHVACs.size} air loops, #{no_outdoor_air_loops} do not have outdoor air, #{doas_loops} are DOAS systems, and #{existing_economizer_loops} have existing economizers. From #{selected_air_loops.size} eligible economizers, #{count_eco} economizers are updated with changeover temperature setpoint of #{changeovertemp}C.")

    return true
  end
end

# this allows the measure to be use by the application
FaultHvacEconomizerChangeoverTemperature.new.registerWithApplication
