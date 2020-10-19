# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/measures/measure_writing_guide/

# start the measure
class HVACChilledWaterSupplyTemperatureReset < OpenStudio::Ruleset::ModelUserScript
  # human readable name
  def name
    return 'HVAC Chilled Water Supply Temperature Reset'
  end

  # human readable description
  def description
    return 'This energy efficiency measure (EEM) adds a set point reset to all chilled water loops present in the OpenStudio model. The chilled water supply temperature reset will be based on outdoor-air temperature (OAT). The specific sequence is that as outdoor-air temperature (OAT) rises from 60F (15.6C) up to 100F (37.8C), the chilled water supply temperature set point will decrease from 55F (12.8C) down to 45F (7.22C).  This sequence provides a 10F (15.6C) change in the Chilled Water Set Point, over a 40F (22.2C) temperature change in the OAT. '
  end

  # human readable description of modeling approach
  def modeler_description
    return "This EEM applies an OS:SetpointManager:OutdoorAirReset controller to the supply outlet node of all PlantLoop objects where OS:Sizing:Plant.LoopType = 'Cooling'."
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
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Initialize variables for allowing variable scopes within the method
    setpoint_OA_reset_array = []
    setpoint_scheduled_array = []
    setpoint_scheduled_dual_array = []
    setpoint_follow_oa_temp_array = []

    # Create array of all plant loops where plantLoop.SizingPlant.Looptype = "Cooling"
    cooling_plant_loop_array_initial = []
    cooling_plant_loop_array = []
    model.getPlantLoops.each do |plantLoop|
      loop_type = plantLoop.sizingPlant.loopType
      total_loop = plantLoop.sizingPlant.loopType.length
      loop_temp = plantLoop.sizingPlant.designLoopExitTemperature

      if loop_type == 'Cooling' # finding all the 'Cooling' type loops
        cooling_plant_loop_array_initial << plantLoop
      end # end the cooling loop condition
    end # end loop through  plant loops

    if cooling_plant_loop_array_initial.empty?
      runner.registerAsNotApplicable('No Cooling PlantLoop objects found. EEM is not applicable.')
      return false
    end # end the not applicable if condition for cooling plant loop

    eligible_coolingloop_names = cooling_plant_loop_array_initial.collect { |l| l.name.to_s }.join(', ') # to get all the names of cooling array objects

    # Loop through cooling_plant_loop_array to find setpoint objects
    cooling_plant_loop_array_initial.each do |pl| # runner.registerInfo("XXX = #{pl.supplyComponents.length}")
      pl.supplyComponents.each do |sc|
        if sc.iddObjectType.valueDescription == 'OS:Node'
          @setpoint_list = sc.to_Node.get.setpointManagers # runner.registerInfo("list of setpoints = #{@setpoint_list.length}")
        end

        @setpoint_list.each do |managertype|
          # get count of OS:SetpointManagerOutdoorAirReset objects & assign a new setpoint manager:OA reset to the same node the existing one was attached
          if managertype.to_SetpointManagerOutdoorAirReset.is_initialized
            setpoint_OA_reset_array << managertype.to_SetpointManagerOutdoorAirReset.get
            setpoint_OA_reset_array.each do |sp|
              if sp.setpointNode.is_initialized
                set_point_node_oa = sp.setpointNode.get
                new_setpoint_OA_reset = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
                new_setpoint_OA_reset.addToNode(set_point_node_oa)
                new_setpoint_OA_reset.setName("#{managertype.name}_replaced")
                new_setpoint_OA_reset.setOutdoorHighTemperature(37.778)
                new_setpoint_OA_reset.setOutdoorLowTemperature(15.556)
                new_setpoint_OA_reset.setSetpointatOutdoorHighTemperature(7.223)
                new_setpoint_OA_reset.setSetpointatOutdoorLowTemperature(12.778)
                runner.registerInfo("An outdoor air reset setpoint manager object named #{new_setpoint_OA_reset.name} has replaced the existing setpoint manager outdoor reset schedule object serving the chilled water plant loop named #{pl.name}. The setpoint manager resets the chilled water setpoint from 7.23 deg C to 12.8 deg C between outdoor air temps of 37.77 Deg C and 15.56 Deg C.")
              end # end if statement for setpointnode
            end # end loop through setpoint scheduled array
          end # end if block for setpoint manager scheduled object

          # get count of OS:SetpointManagerScheduled objects  & assign a new setpoint manager:OA reset to the same node the existing one was attached
          if managertype.to_SetpointManagerScheduled.is_initialized
            setpoint_scheduled_array << managertype.to_SetpointManagerScheduled.get
            setpoint_scheduled_array.each do |sp1|
              if sp1.setpointNode.is_initialized
                set_point_node_sched = sp1.setpointNode.get
                new_setpoint_sched = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
                new_setpoint_sched.addToNode(set_point_node_sched)
                new_setpoint_sched.setName("#{managertype.name}_replaced")
                new_setpoint_sched.setOutdoorHighTemperature(37.778)
                new_setpoint_sched.setOutdoorLowTemperature(15.556)
                new_setpoint_sched.setSetpointatOutdoorHighTemperature(7.223)
                new_setpoint_sched.setSetpointatOutdoorLowTemperature(12.778)
                runner.registerInfo("An outdoor air reset setpoint manager object named #{new_setpoint_sched.name} has replaced the existing setpoint manager scheduled object serving the chilled water plant loop named #{pl.name}. The setpoint manager resets the chilled water setpoint from 7.23 deg C to 12.8 deg C between outdoor air temps of 37.77 Deg C and 15.56 Deg C.")
              end # end if statement for setpointnode
            end # end loop through setpoint scheduled array
          end # end if block for setpoint manager scheduled object

          # get count of OS:SetpointManagerScheduledDualSetpoint objects  & assign a new setpoint manager:OA reset to the same node the existing one was attached
          if managertype.to_SetpointManagerScheduledDualSetpoint.is_initialized
            setpoint_scheduled_dual_array << managertype.to_SetpointManagerScheduledDualSetpoint.get
            setpoint_scheduled_dual_array.each do |sp2|
              if sp2.setpointNode.is_initialized
                set_point_node_dual = sp2.setpointNode.get
                new_setpoint_dual = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
                new_setpoint_dual.addToNode(set_point_node_dual)
                new_setpoint_dual.setName("#{managertype.name}_replaced")
                new_setpoint_dual.setOutdoorHighTemperature(37.778)
                new_setpoint_dual.setOutdoorLowTemperature(15.556)
                new_setpoint_dual.setSetpointatOutdoorHighTemperature(7.223)
                new_setpoint_dual.setSetpointatOutdoorLowTemperature(12.778)
                runner.registerInfo("An outdoor air reset setpoint manager object named #{new_setpoint_OA_reset.name} has replaced the existing scheduled dual setpoint object serving the chilled water plant loop named #{pl.name}. The setpoint manager resets the chilled water setpoint from 7.23 deg C to 12.8 deg C between outdoor air temps of 37.77 Deg C and 15.56 Deg C.")
              end # end if statement for setpointnode
            end # end loop through setpoint scheduled array
          end # end if block for setpoint manager scheduled object

          # get count of OS:SetpointManagerFollowOutdoorAirTemperature objects & assign a new setpoint manager:OA reset to the same node the existing one was attached
          if managertype.to_SetpointManagerFollowOutdoorAirTemperature.is_initialized
            setpoint_follow_oa_temp_array << managertype.to_SetpointManagerFollowOutdoorAirTemperature.get
            setpoint_follow_oa_temp_array.each do |sp3|
              if sp3.setpointNode.is_initialized
                set_point_node_follow_oa = sp3.setpointNode.get
                new_setpoint_follow_oa = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
                new_setpoint_follow_oa.addToNode(set_point_node_follow_oa)
                new_setpoint_follow_oa.setName("#{managertype.name}_replaced")
                new_setpoint_follow_oa.setOutdoorHighTemperature(37.778)
                new_setpoint_follow_oa.setOutdoorLowTemperature(15.556)
                new_setpoint_follow_oa.setSetpointatOutdoorHighTemperature(7.223)
                new_setpoint_follow_oa.setSetpointatOutdoorLowTemperature(12.778)
                runner.registerInfo("An outdoor air reset setpoint manager object named #{new_setpoint_OA_reset.name} has replaced the existing follow outdoor air temperature setpoint manager object serving the chilled water plant loop named #{pl.name}. The setpoint manager resets the chilled water setpoint from 7.23 deg C to 12.8 deg C between outdoor air temps of 37.77 Deg C and 15.56 Deg C.")
              end # end if statement for setpointnode
            end # end loop through setpoint scheduled array
          end # end if block for setpoint manager scheduled object
        end # end loop through setpoint manager objects
      end # end loop throught supply components

      # report initial condition of model
      runner.registerInitialCondition("There are '#{cooling_plant_loop_array_initial.length}' eligible cooling loops out of '#{model.getPlantLoops.length}' plant loops. \nEligible loops name(s): '#{eligible_coolingloop_names}'")

      # report final condition of model
      runner.registerFinalCondition("Cold Water Supply Temperature Reset has been applied to #{cooling_plant_loop_array_initial.length} plant loop(s). \nPlant Loops affected are: '#{eligible_coolingloop_names}'.")
      runner.registerValue('hvac_number_of_reset_loops', cooling_plant_loop_array_initial.length)

      return true
    end # end the cooling plant do loop
   end # end the run loop
 end # end the class

# register the measure to be used by the application
HVACChilledWaterSupplyTemperatureReset.new.registerWithApplication
