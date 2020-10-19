# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.


# open the class to add methods to size all HVAC equipment
class OpenStudio::Model::Model
  # Ensure that the version of OpenStudio is 1.6.0 or greater
  # because the HVACSizing .autosizedFoo methods are currently built
  # expecting the EnergyPlus 8.2 syntax.
  min_os_version = '1.6.0'
  if OpenStudio::Model::Model.new.version < OpenStudio::VersionString.new(min_os_version)
    OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "This measure requires a minimum OpenStudio version of #{min_os_version} because the HVACSizing .autosizedFoo methods expect EnergyPlus 8.2 output variable names.")
  end

  # Load the helper libraries for getting the autosized
  # values for each type of model object.

  require_relative 'HVACSizing.PumpConstantSpeed'
  require_relative 'HVACSizing.PumpVariableSpeed'

  # A helper method to run a sizing run and pull any values calculated during
  # autosizing back into the self.
  def runSizingRun(sizing_run_dir = "#{Dir.pwd}/SizingRun")
    # If the sizing run directory is not specified
    # run the sizing run in the current working directory

    # Make the directory if it doesn't exist
    if !Dir.exist?(sizing_run_dir)
      Dir.mkdir(sizing_run_dir)
    end

    # Change the simulation to only run the sizing days
    sim_control = getSimulationControl
    sim_control.setRunSimulationforSizingPeriods(true)
    sim_control.setRunSimulationforWeatherFileRunPeriods(false)

    # Save the model to energyplus idf
    idf_name = 'sizing.idf'
    osm_name = 'sizing.osm'
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Starting sizing run here: #{sizing_run_dir}.")
    forward_translator = OpenStudio::EnergyPlus::ForwardTranslator.new
    idf = forward_translator.translateModel(self)
    idf_path = OpenStudio::Path.new("#{sizing_run_dir}/#{idf_name}")
    osm_path = OpenStudio::Path.new("#{sizing_run_dir}/#{osm_name}")
    idf.save(idf_path, true)
    save(osm_path, true)

    # Set up the sizing simulation
    # Find the weather file
    epw_path = nil
    if weatherFile.is_initialized
      epw_path = weatherFile.get.path
      if epw_path.is_initialized
        if File.exist?(epw_path.get.to_s)
          epw_path = epw_path.get
        else
          # If this is an always-run Measure, need to check a different path
          alt_weath_path = File.expand_path(File.join(File.dirname(__FILE__), '../../../resources'))
          alt_epw_path = File.expand_path(File.join(alt_weath_path, epw_path.get.to_s))
          if File.exist?(alt_epw_path)
            epw_path = OpenStudio::Path.new(alt_epw_path)
          else
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Model has been assigned a weather file, but the file is not in the specified location of '#{epw_path.get}'.")
            return false
          end
        end
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Model has a weather file assigned, but the weather file path has been deleted.')
        return false
      end
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Model has not been assigned a weather file.')
      return false
    end

    # If running on a regular desktop, use RunManager.
    # If running on OpenStudio Server, use WorkFlowMananger
    # to avoid slowdown from the sizing run.
    use_runmanager = true

    begin
      require 'openstudio-workflow'
      use_runmanager = false
    rescue LoadError
      use_runmanager = true
    end

    sql_path = nil
    if use_runmanager
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Running sizing run with RunManager.')

      # Find EnergyPlus
      ep_dir = OpenStudio.getEnergyPlusDirectory
      ep_path = OpenStudio.getEnergyPlusExecutable
      ep_tool = OpenStudio::Runmanager::ToolInfo.new(ep_path)
      idd_path = OpenStudio::Path.new(ep_dir.to_s + '/Energy+.idd')
      output_path = OpenStudio::Path.new("#{sizing_run_dir}/")

      # Make a run manager and queue up the sizing run
      run_manager_db_path = OpenStudio::Path.new("#{sizing_run_dir}/sizing_run.db")
      # HACK: workaround for Mac with Qt 5.4, need to address in the future.
      OpenStudio::Application.instance.application(true)
      run_manager = OpenStudio::Runmanager::RunManager.new(run_manager_db_path, true, false, false, false)
      job = OpenStudio::Runmanager::JobFactory.createEnergyPlusJob(ep_tool,
                                                                   idd_path,
                                                                   idf_path,
                                                                   epw_path,
                                                                   output_path)

      run_manager.enqueue(job, true)

      # Start the sizing run and wait for it to finish.
      while run_manager.workPending
        sleep 1
        OpenStudio::Application.instance.processEvents
      end

      sql_path = OpenStudio::Path.new("#{sizing_run_dir}/Energyplus/eplusout.sql")

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished sizing run.')

    else # Use the openstudio-workflow gem
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Running sizing run with openstudio-workflow gem.')

      # Copy the weather file to this directory
      FileUtils.copy(epw_path.to_s, sizing_run_dir)

      # Run the simulation
      sim = OpenStudio::Workflow.run_energyplus('Local', sizing_run_dir)
      final_state = sim.run

      if final_state == :finished
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished sizing run.')
      end

      sql_path = OpenStudio::Path.new("#{sizing_run_dir}/run/eplusout.sql")

    end

    # TODO: Delete the eplustbl.htm and other files created
    # by the sizing run for cleanliness.

    # Load the sql file created by the sizing run
    if OpenStudio.exists(sql_path)
      sql = OpenStudio::SqlFile.new(sql_path)
      # Check to make sure the sql file is readable,
      # which won't be true if EnergyPlus crashed during simulation.
      if !sql.connectionOpen
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "The sizing run failed, cannot create model.  Look at the eplusout.err file in #{File.dirname(sql_path.to_s)} to see the cause.")
        return false
      end
      # Attach the sql file from the run to the sizing model
      setSqlFile(sql)
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Results for the sizing run couldn't be found here: #{sql_path}.")
      return false
    end

    # Report severe errors in the sizing run
    error_query = "SELECT ErrorMessage
        FROM Errors
        WHERE ErrorType='1'"

    errs = sqlFile.get.execAndReturnVectorOfString(error_query)
    if errs.is_initialized
      errs = errs.get
      if !errs.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "The sizing run had the following severe errors: #{errs.join('\n')}.")
      end
    end

    # Check that the sizing run completed
    completed_query = 'SELECT CompletedSuccessfully FROM Simulations'

    completed = sqlFile.get.execAndReturnFirstDouble(completed_query)
    if completed.is_initialized
      completed = completed.get
      if errs.size == 1
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'The sizing run failed.  See previous severe errors for clues.')
        return false
      end
    end

    # Change the model back to running the weather file
    sim_control.setRunSimulationforSizingPeriods(false)
    sim_control.setRunSimulationforWeatherFileRunPeriods(true)

    return true
  end

  # Takes the values calculated by the EnergyPlus sizing routines
  # and puts them into all objects model in place of the autosized fields.
  # Must have previously completed a run with sql output for this to work.
  def applySizingValues
    # Ensure that the model has a sql file associated with it
    if sqlFile.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Failed to apply sizing values because model is missing sql file containing sizing results.')
      return false
    end

    # TODO: Sizing methods for these types of equipment are
    # currently only stubs that need to be filled in.
    getAirConditionerVariableRefrigerantFlows.sort.each(&:applySizingValues)
    getAirLoopHVACUnitaryHeatCoolVAVChangeoverBypasss.sort.each(&:applySizingValues)
    getAirLoopHVACUnitarySystems.sort.each(&:applySizingValues)
    getAirTerminalSingleDuctConstantVolumeCooledBeams.sort.each(&:applySizingValues)
    getAirTerminalSingleDuctConstantVolumeFourPipeInductions.sort.each(&:applySizingValues)
    getAirTerminalSingleDuctConstantVolumeReheats.sort.each(&:applySizingValues)
    getAirTerminalSingleDuctSeriesPIUReheats.sort.each(&:applySizingValues)
    getAirTerminalSingleDuctVAVHeatAndCoolNoReheats.sort.each(&:applySizingValues)
    getAirTerminalSingleDuctVAVHeatAndCoolReheats.sort.each(&:applySizingValues)
    getBoilerSteams.sort.each(&:applySizingValues)
    getCoilCoolingDXMultiSpeeds.sort.each(&:applySizingValues)
    getCoilCoolingDXVariableRefrigerantFlows.sort.each(&:applySizingValues)
    getCoilCoolingWaterToAirHeatPumpEquationFits.sort.each(&:applySizingValues)
    getCoilHeatingWaterToAirHeatPumpEquationFits.sort.each(&:applySizingValues)
    getCoilHeatingGasMultiStages.sort.each(&:applySizingValues)
    getCoilHeatingDesuperheaters.sort.each(&:applySizingValues)
    getCoilHeatingDXVariableRefrigerantFlows.sort.each(&:applySizingValues)
    getCoilWaterHeatingDesuperheaters.sort.each(&:applySizingValues)
    getCoolingTowerTwoSpeeds.sort.each(&:applySizingValues)
    getCoolingTowerVariableSpeeds.sort.each(&:applySizingValues)
    getEvaporativeCoolerDirectResearchSpecials.sort.each(&:applySizingValues)
    getEvaporativeCoolerIndirectResearchSpecials.sort.each(&:applySizingValues)
    getEvaporativeFluidCoolerSingleSpeeds.sort.each(&:applySizingValues)
    getHeatExchangerFluidToFluids.sort.each(&:applySizingValues)
    getHumidifierSteamElectrics.sort.each(&:applySizingValues)
    getZoneHVACBaseboardConvectiveElectrics.sort.each(&:applySizingValues)
    getZoneHVACBaseboardConvectiveWaters.sort.each(&:applySizingValues)
    getZoneHVACFourPipeFanCoils.sort.each(&:applySizingValues)
    getZoneHVACHighTemperatureRadiants.sort.each(&:applySizingValues)
    getZoneHVACIdealLoadsAirSystems.sort.each(&:applySizingValues)
    getZoneHVACLowTemperatureRadiantElectrics.sort.each(&:applySizingValues)
    getZoneHVACLowTempRadiantConstFlows.sort.each(&:applySizingValues)
    getZoneHVACLowTempRadiantVarFlows.sort.each(&:applySizingValues)
    getZoneHVACPackagedTerminalAirConditioners.sort.each(&:applySizingValues)
    getZoneHVACPackagedTerminalHeatPumps.sort.each(&:applySizingValues)
    getZoneHVACTerminalUnitVariableRefrigerantFlows.sort.each(&:applySizingValues)
    getZoneHVACWaterToAirHeatPumps.sort.each(&:applySizingValues)

    # Zone equipment

    # Air terminals
    getAirTerminalSingleDuctParallelPIUReheats.sort.each(&:applySizingValues)
    getAirTerminalSingleDuctVAVReheats.sort.each(&:applySizingValues)
    getAirTerminalSingleDuctUncontrolleds.sort.each(&:applySizingValues)

    # AirLoopHVAC components
    getAirLoopHVACs.sort.each(&:applySizingValues)
    getSizingSystems.sort.each(&:applySizingValues)

    # Fans
    getFanConstantVolumes.sort.each(&:applySizingValues)
    getFanVariableVolumes.sort.each(&:applySizingValues)
    getFanOnOffs.sort.each(&:applySizingValues)

    # Heating coils
    getCoilHeatingElectrics.sort.each(&:applySizingValues)
    getCoilHeatingGass.sort.each(&:applySizingValues)
    getCoilHeatingWaters.sort.each(&:applySizingValues)
    getCoilHeatingDXSingleSpeeds.sort.each(&:applySizingValues)

    # Cooling coils
    getCoilCoolingDXSingleSpeeds.sort.each(&:applySizingValues)
    getCoilCoolingDXTwoSpeeds.sort.each(&:applySizingValues)
    getCoilCoolingWaters.sort.each(&:applySizingValues)

    # Outdoor air
    getControllerOutdoorAirs.sort.each(&:applySizingValues)
    getHeatExchangerAirToAirSensibleAndLatents.sort.each(&:applySizingValues)

    # PlantLoop components
    getPlantLoops.sort.each(&:applySizingValues)

    # Pumps
    getPumpConstantSpeeds.sort.each(&:applySizingValues)
    getPumpVariableSpeeds.sort.each(&:applySizingValues)

    # Heating equipment
    getBoilerHotWaters.sort.each(&:applySizingValues)

    # Cooling equipment
    getChillerElectricEIRs.sort.each(&:applySizingValues)

    # Condenser equipment
    getCoolingTowerSingleSpeeds.sort.each(&:applySizingValues)

    # Controls
    getControllerWaterCoils.sort.each(&:applySizingValues)

    # VRF components

    # Refrigeration components

    return true
  end

  # Changes all hard-sized HVAC values to Autosized
  def autosize
    # TODO: Sizing methods for these types of equipment are
    # currently only stubs that need to be filled in.
    getAirConditionerVariableRefrigerantFlows.sort.each(&:autosize)
    getAirLoopHVACUnitaryHeatCoolVAVChangeoverBypasss.sort.each(&:autosize)
    getAirLoopHVACUnitarySystems.sort.each(&:autosize)
    getAirTerminalSingleDuctConstantVolumeCooledBeams.sort.each(&:autosize)
    getAirTerminalSingleDuctConstantVolumeFourPipeInductions.sort.each(&:autosize)
    getAirTerminalSingleDuctConstantVolumeReheats.sort.each(&:autosize)
    getAirTerminalSingleDuctSeriesPIUReheats.sort.each(&:autosize)
    getAirTerminalSingleDuctVAVHeatAndCoolNoReheats.sort.each(&:autosize)
    getAirTerminalSingleDuctVAVHeatAndCoolReheats.sort.each(&:autosize)
    getBoilerSteams.sort.each(&:autosize)
    getCoilCoolingDXMultiSpeeds.sort.each(&:autosize)
    getCoilCoolingDXVariableRefrigerantFlows.sort.each(&:autosize)
    getCoilCoolingWaterToAirHeatPumpEquationFits.sort.each(&:autosize)
    getCoilHeatingWaterToAirHeatPumpEquationFits.sort.each(&:autosize)
    getCoilHeatingGasMultiStages.sort.each(&:autosize)
    getCoilHeatingDesuperheaters.sort.each(&:autosize)
    getCoilHeatingDXVariableRefrigerantFlows.sort.each(&:autosize)
    getCoilWaterHeatingDesuperheaters.sort.each(&:autosize)
    getCoolingTowerTwoSpeeds.sort.each(&:autosize)
    getCoolingTowerVariableSpeeds.sort.each(&:autosize)
    getEvaporativeCoolerDirectResearchSpecials.sort.each(&:autosize)
    getEvaporativeCoolerIndirectResearchSpecials.sort.each(&:autosize)
    getEvaporativeFluidCoolerSingleSpeeds.sort.each(&:autosize)
    getHeatExchangerFluidToFluids.sort.each(&:autosize)
    getHumidifierSteamElectrics.sort.each(&:autosize)
    getZoneHVACBaseboardConvectiveElectrics.sort.each(&:autosize)
    getZoneHVACBaseboardConvectiveWaters.sort.each(&:autosize)
    getZoneHVACFourPipeFanCoils.sort.each(&:autosize)
    getZoneHVACHighTemperatureRadiants.sort.each(&:autosize)
    getZoneHVACIdealLoadsAirSystems.sort.each(&:autosize)
    getZoneHVACLowTemperatureRadiantElectrics.sort.each(&:autosize)
    getZoneHVACLowTempRadiantConstFlows.sort.each(&:autosize)
    getZoneHVACLowTempRadiantVarFlows.sort.each(&:autosize)
    getZoneHVACPackagedTerminalAirConditioners.sort.each(&:autosize)
    getZoneHVACPackagedTerminalHeatPumps.sort.each(&:autosize)
    getZoneHVACTerminalUnitVariableRefrigerantFlows.sort.each(&:autosize)
    getZoneHVACWaterToAirHeatPumps.sort.each(&:autosize)

    # Zone equipment

    # Air terminals
    getAirTerminalSingleDuctParallelPIUReheats.sort.each(&:autosize)
    getAirTerminalSingleDuctVAVReheats.sort.each(&:autosize)
    getAirTerminalSingleDuctUncontrolleds.sort.each(&:autosize)

    # AirLoopHVAC components
    getAirLoopHVACs.sort.each(&:autosize)
    getSizingSystems.sort.each(&:autosize)

    # Fans
    getFanConstantVolumes.sort.each(&:autosize)
    getFanVariableVolumes.sort.each(&:autosize)
    getFanOnOffs.sort.each(&:autosize)

    # Heating coils
    getCoilHeatingElectrics.sort.each(&:autosize)
    getCoilHeatingGass.sort.each(&:autosize)
    getCoilHeatingWaters.sort.each(&:autosize)
    getCoilHeatingDXSingleSpeeds.sort.each(&:autosize)

    # Cooling coils
    getCoilCoolingDXSingleSpeeds.sort.each(&:autosize)
    getCoilCoolingDXTwoSpeeds.sort.each(&:autosize)
    getCoilCoolingWaters.sort.each(&:autosize)

    # Outdoor air
    getControllerOutdoorAirs.sort.each(&:autosize)
    getHeatExchangerAirToAirSensibleAndLatents.sort.each(&:autosize)

    # PlantLoop components
    getPlantLoops.sort.each(&:autosize)

    # Pumps
    getPumpConstantSpeeds.sort.each(&:autosize)
    getPumpVariableSpeeds.sort.each(&:autosize)

    # Heating equipment
    getBoilerHotWaters.sort.each(&:autosize)

    # Cooling equipment
    getChillerElectricEIRs.sort.each(&:autosize)

    # Condenser equipment
    getCoolingTowerSingleSpeeds.sort.each(&:autosize)

    # Controls
    getControllerWaterCoils.sort.each(&:autosize)

    # VRF components

    # Refrigeration components

    return true
  end

  # A helper method to get component sizes from the model
  # returns the autosized value as an optional double
  def getAutosizedValue(object, value_name, units)
    result = OpenStudio::OptionalDouble.new

    name = object.name.get.upcase

    object_type = object.iddObject.type.valueDescription.gsub('OS:', '')

    sql = sqlFile

    if sql.is_initialized
      sql = sql.get

      # SELECT * FROM ComponentSizes WHERE CompType = 'Coil:Heating:Gas' AND CompName = "COIL HEATING GAS 3" AND Description = "Design Size Nominal Capacity"
      query = "SELECT Value
              FROM ComponentSizes
              WHERE CompType='#{object_type}'
              AND CompName='#{name}'
              AND Description='#{value_name}'
              AND Units='#{units}'"

      val = sql.execAndReturnFirstDouble(query)

      if val.is_initialized
        result = OpenStudio::OptionalDouble.new(val.get)
      else
        # OpenStudio::logFree(OpenStudio::Warn, "openstudio.model.Model", "Data not found for query: #{query}")
      end

    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Model has no sql file containing results, cannot lookup data.')
    end

    return result
  end
end
