# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Sustainable Energy, LLC.
# See also https://openstudio.net/license
# *******************************************************************************

# see the URL below for information on how to write OpenStudio measures
# http://openstudio.nrel.gov/openstudio-measure-writing-guide

# see the URL below for information on using life cycle cost objects in OpenStudio
# http://openstudio.nrel.gov/openstudio-life-cycle-examples

# see the URL below for access to C++ documentation on model objects (click on "model" in the main window to view model objects)
# http://openstudio.nrel.gov/sites/openstudio.nrel.gov/files/nv_data/cpp_documentation_it/model/html/namespaces.html

# dependencies
require 'openstudio-standards'

# start the measure
class EnableIdealAirLoadsForAllZones < OpenStudio::Measure::ModelMeasure
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'EnableIdealAirLoadsForAllZones'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # dummy standard to access methods in openstudio-standards
    std = Standard.build('90.1-2013')

    # remove existing HVAC
    runner.registerInfo('Removing existing HVAC systems from the model')
    std.model_remove_prm_hvac(model)

    # array of zones initially using ideal air loads
    startingIdealAir = []

    # remove zone equipment except for exhaust and natural ventilation
    zone_hvac_ideal_found = false
    model.getZoneHVACComponents.each do |component|
      next if component.to_FanZoneExhaust.is_initialized
      component.remove
    end

    thermalZones = model.getThermalZones
    thermalZones.each do |zone|
      # TODO: - need to also look for ZoneHVACIdealLoadsAirSystem
      if zone.useIdealAirLoads
        startingIdealAir << zone
      else

        if zone_hvac_ideal_found == true
          startingIdealAir << zone
        else

          next if !zone.thermostatSetpointDualSetpoint.is_initialized
          ideal_loads = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(model)
          ideal_loads.addToThermalZone(zone)
          # Set the ideal loads properties
          # ideal_loads.setMinimumCoolingTemperature(0.0)
        end

      end
    end

    # remove air and plant loops not used for SWH
    model.getAirLoopHVACs.each(&:remove)

    # see if plant loop is swh or not and take proper action (booter loop doesn't have water use equipment)
    model.getPlantLoops.each do |plant_loop|
      is_swh_loop = false
      plant_loop.supplyComponents.each do |component|
        if component.to_WaterHeaterMixed.is_initialized
          is_swh_loop = true
          next
        end
      end
      if is_swh_loop == false
        plant_loop.remove
      end
    end

    # reporting initial condition of model
    runner.registerInitialCondition("In the initial model #{startingIdealAir.size} zones use ideal air loads.")

    # reporting final condition of model
    finalIdealAir = []
    thermalZones.each do |zone|
      if zone.useIdealAirLoads
        finalIdealAir << zone
      end
    end
    runner.registerFinalCondition("In the final model #{finalIdealAir.size} zones use ideal air loads.")

    return true
  end
end

# this allows the measure to be use by the application
EnableIdealAirLoadsForAllZones.new.registerWithApplication
