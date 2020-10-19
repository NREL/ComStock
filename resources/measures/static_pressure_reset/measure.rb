# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

#see the URL below for information on how to write OpenStudio measures
# http://openstudio.nrel.gov/openstudio-measure-writing-guide

#see your EnergyPlus installation or the URL below for information on EnergyPlus objects
# http://apps1.eere.energy.gov/buildings/energyplus/pdfs/inputoutputreference.pdf

#see the URL below for information on using life cycle cost objects in OpenStudio
# http://openstudio.nrel.gov/openstudio-life-cycle-examples

#see the URL below for access to C++ documentation on workspace objects (click on "workspace" in the main window to view workspace objects)
# http://openstudio.nrel.gov/sites/openstudio.nrel.gov/files/nv_data/cpp_documentation_it/utilities/html/idf_page.html

require 'json'

#start the measure
# class StaticPressureReset < OpenStudio::Ruleset::WorkspaceUserScript
class StaticPressureReset < OpenStudio::Ruleset::ModelUserScript

  #define the name that a user will see, this method may be deprecated as
  #the display name in PAT comes from the name field in measure.xml
  def name
    return "Static Pressure Reset"
  end

  # human readable description
  def description
    return "When a building's supply fan(s) system is operational, the supply fan's static pressure set point can be automatically adjusted to load conditions that will allow the supply fan to operate more efficiently. The variable frequency drive (VFD) of the supply fan is modulated to maintain a dynamically reset static pressure set point. This can be done by sorting all variable-air-volume (VAV) box dampers by position; if the average of the highest (most open) 10% of VAV boxes are open less that 70%, the reset control will decrease the static pressure set point in 0.1 W.C. (inches of water column) increments until the set point achieves the low operation limit (30% of the original value). If the average of the highest 10% of VAV boxes is greater than 90% open, the reset control will increase the static pressure set point in 0.1 W.C. increments until the set point achieves the original set point."
  end

  # human readable description of modeling approach
  def modeler_description
    return "At each simulation time step, check the damper position for each VAV terminal on the airloop.  Reset the fan pressure rise to the max damper position divided by 0.95, down to a minimum of 50% of the design pressure rise."
  end  
  
  #define the arguments that the user will input
  def arguments(workspace)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    return args
  end #end the arguments method

  #define what happens when the measure is run
  def run(workspace, runner, user_arguments)
    super(workspace, runner, user_arguments)

    #use the built-in error checking 
    if not runner.validateUserArguments(arguments(workspace), user_arguments)
      return false
    end
    
    # Get the last openstudio model
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError("Could not load last OpenStudio model, cannot apply measure.")
      return false
    end
    model = model.get
    
    require 'json'
    
    results = {}
    airloop_name = []
    # Loop over the airloops to find valid ones for this measure
    model.getAirLoopHVACs.each do |air_loop|
      found_fan = 0   #have not found any fans 
      found_reheat_term = 0 
      num_zones = 0
      temp = {}
      reheat_terms = []
      
      #get number of thermalzones on airloop
      num_zones = air_loop.thermalZones.size
      runner.registerInfo("found #{num_zones} thermalzones on airloop: #{air_loop.name}")
      if num_zones <= 1 
        runner.registerInfo("Only found #{num_zones} thermalzones on airloop: #{air_loop.name}, skipping")
        next
      end 
      
      #loop over supply components and find any variable volume fans
      air_loop.supplyComponents.each do |component|
        # Get the unitary equipment
        if component.to_AirLoopHVACUnitarySystem.is_initialized
          unitary = component.to_AirLoopHVACUnitarySystem.get
          # get the supply fan from inside the unitary equipment
          if unitary.supplyFan.to_FanVariableVolume.is_initialized
            supply_fan = unitary.supplyAirFan.to_FanVariableVolume.get
            runner.registerInfo("Found #{supply_fan.name} on #{air_loop.name}")
            found_fan += 1  #found necessary Fan object
            temp[:fan] = "#{supply_fan.name}"
            temp[:fan_pressure] = "#{supply_fan.pressureRise}"
          else
            runner.registerInfo("No Variable Volume Fan in the Unitary system on #{air_loop.name}")
          end
        end  
        # get the supply fan directly from the airloop
        if component.to_FanVariableVolume.is_initialized
          supply_fan = component.to_FanVariableVolume.get
          runner.registerInfo("Found #{supply_fan.name} on #{air_loop.name}")
          found_fan += 1  #found necessary Fan object
          temp[:fan] = "#{supply_fan.name}"
          temp[:fan_pressure] = "#{supply_fan.pressureRise}"
        end
      end
      if found_fan != 1
        runner.registerInfo("No Variable Volume Fan on airloop: #{air_loop.name}, skipping")
        next
      end
      if found_fan > 1
        runner.registerWarning("warning more than one supply fan")
      end
      
      #find if any AirTerminalSingleDuctVAVReheat terminals
      air_loop.demandComponents.each do |component|
        if component.to_AirTerminalSingleDuctVAVReheat.is_initialized
          reheat_term = component.to_AirTerminalSingleDuctVAVReheat.get
          runner.registerInfo("Found #{reheat_term.name} on #{air_loop.name}")
          found_reheat_term += 1  #found necessary reheat terminal
          reheat_terms << "#{reheat_term.name}"
        end
      end
      if found_reheat_term == 0
        runner.registerInfo("No AirTerminalSingleDuctVAVReheat terminals on #{air_loop.name}, skipping")
        next
      end
      temp[:reheat_terms] = reheat_terms
      runner.registerInfo("found #{found_reheat_term} AirTerminalSingleDuctVAVReheat terminals on: #{air_loop.name} which has #{num_zones} thermalzones and variable volume fan: #{temp[:fan]}, adding")
      results["#{air_loop.name}"] = temp
    end 
    #save airloop parsing results to ems_results.json
    runner.registerInfo("Saving ems_results.json")
    FileUtils.mkdir_p(File.dirname("ems_results.json")) unless Dir.exist?(File.dirname("ems_results.json"))
    File.open("ems_results.json", 'w') {|f| f << JSON.pretty_generate(results)}
    
    if results.empty?
       runner.registerWarning("No Airloops are appropriate for this measure")
       runner.registerAsNotApplicable("No Airloops are appropriate for this measure")
       #save blank ems_ems_static_pressure_reset.ems file so Eplus measure does not crash
       ems_string = ""
       runner.registerInfo("Saving blank ems_static_pressure_reset file")
       FileUtils.mkdir_p(File.dirname("ems_static_pressure_reset.ems")) unless Dir.exist?(File.dirname("ems_static_pressure_reset.ems"))
       File.open("ems_static_pressure_reset.ems", "w") do |f|
         f.write(ems_string)
       end
       return true
    end
    
    runner.registerInfo("Making EMS string for Advanced RTU Controls")
    #start making the EMS code
    ems_string = ""  #clear out the ems_string
    # ems_string << "Output:EnergyManagementSystem," + "\n"
    # ems_string << "   Verbose, ! Actuator Availability Dictionary Reporting" + "\n"
    # ems_string << "   Verbose, ! Internal Variable Availability Dictionary Reporting" + "\n"
    # ems_string << "   Verbose; ! EnergyPlus Runtime Language Debug Output Level" + "\n"
    # ems_string << "\n"
    results.each_with_index do |(key, value), i|
      value[:reheat_terms].each_with_index do |term, j|
        ems_string << "\n"
        ems_string << "EnergyManagementSystem:Sensor," + "\n"
        ems_string << "    VAV_#{i}_#{j},                  !- Name" + "\n"
        ems_string << "    #{term},  !- Output:Variable or Output:Meter Index Key Name" + "\n"
        ems_string << "    Zone Air Terminal VAV Damper Position;  !- Output:Variable or Output:Meter Name" + "\n"
      end 
      ems_string << "\n"
      ems_string << "EnergyManagementSystem:Actuator," + "\n"
      ems_string << "    FANPRESS_#{i},                   !- Name" + "\n"
      ems_string << "    #{value[:fan]},        !- Actuated Component Unique Name" + "\n"
      ems_string << "    Fan,                     !- Actuated Component Type" + "\n"
      ems_string << "    Fan Pressure Rise;       !- Actuated Component Control Type" + "\n"
      ems_string << "\n"
      ems_string << "EnergyManagementSystem:ProgramCallingManager," + "\n"
      ems_string << "    SP_Reset_Manager_#{i},        !- Name" + "\n"
      ems_string << "    InsideHVACSystemIterationLoop,  !- EnergyPlus Model Calling Point" + "\n"
      ems_string << "    SP_Reset_#{i};                !- Program Name 1" + "\n"
      ems_string << "\n"
      ems_string << "EnergyManagementSystem:Program," + "\n"
      ems_string << "    SP_Reset_#{i}," + "\n"
      ems_string << "    SET FPRMax=#{value[:fan_pressure]}," + "\n"
      ems_string << "    SET VAVMax= 0," + "\n"
      value[:reheat_terms].each_with_index do |term, j|
        ems_string << "    SET VAVMax= @Max VAVMax VAV_#{i}_#{j}," + "\n"
      end
      ems_string << "    SET FANPRESS_#{i}= FPRMax*VAVMax/0.95, ! Reset the fan power" + "\n"
      ems_string << "    SET FANPRESS_#{i}= @Max FANPRESS_#{i} FPRMax*0.5, ! Limit to 50% reduction" + "\n"
      ems_string << "    SET FANPRESS_#{i}= @Min FANPRESS_#{i} FPRMax;  ! Don’t reset upward beyond design" + "\n"
      ems_string << "\n"
      # ems_string << "EnergyManagementSystem:OutputVariable," + "\n"
      # ems_string << "    VAV_#{i} Fan Pressure Rise,  !- Name" + "\n"
      # ems_string << "    FANPRESS_#{i},                 !- EMS Variable Name" + "\n"
      # ems_string << "    Averaged,                !- Type of Data in Variable" + "\n"
      # ems_string << "    SystemTimestep,          !- Update Frequency" + "\n"
      # ems_string << "    SP_Reset_#{i};                !- EMS Program or Subroutine Name" + "\n"
      # ems_string << "Output:Variable," + "\n"
      # ems_string << "   *,                       !- Key Value" + "\n"
      # ems_string << "   VAV_#{i} Fan Pressure Rise, !- Variable Name" + "\n"
      # ems_string << "   Detailed;                  !- Reporting Frequency" + "\n"
      # ems_string << "EnergyManagementSystem:OutputVariable," + "\n"
      # ems_string << "    VAV_#{i} Max Damper Position,  !- Name" + "\n"
      # ems_string << "    VAVMax,                 !- EMS Variable Name" + "\n"
      # ems_string << "    Averaged,                !- Type of Data in Variable" + "\n"
      # ems_string << "    SystemTimestep,          !- Update Frequency" + "\n"
      # ems_string << "    SP_Reset_#{i};                !- EMS Program or Subroutine Name" + "\n"
      # ems_string << "Output:Variable," + "\n"
      # ems_string << "   *,                       !- Key Value" + "\n"
      # ems_string << "   VAV_#{i} Max Damper Position, !- Variable Name" + "\n"
      # ems_string << "   Detailed;                  !- Reporting Frequency" + "\n"
    end
    #save EMS snippet
    runner.registerInfo("Saving ems_static_pressure_reset file")
    FileUtils.mkdir_p(File.dirname("ems_static_pressure_reset.ems")) unless Dir.exist?(File.dirname("ems_static_pressure_reset.ems"))
    File.open("ems_static_pressure_reset.ems", "w") do |f|
      f.write(ems_string)
    end
    
    
    ems_path = '../StaticPressureReset/ems_static_pressure_reset.ems'
    json_path = '../StaticPressureReset/ems_results.json'
    if File.exist? ems_path
      ems_string = File.read(ems_path)
      if File.exist? json_path
        json = JSON.parse(File.read(json_path))
      end
    else
      ems_path2 = Dir.glob('../../**/ems_static_pressure_reset.ems')
      ems_path1 = ems_path2[0]
      json_path2 = Dir.glob('../../**/ems_results.json')
      json_path1 = json_path2[0]
      if ems_path2.size > 1
        runner.registerWarning("more than one ems_static_pressure_reset.ems file found.  Using first one found.")
      end
      if !ems_path1.nil? 
        if File.exist? ems_path1
          ems_string = File.read(ems_path1)
          if File.exist? json_path1
            json = JSON.parse(File.read(json_path1))
          else
            runner.registerError("ems_results.json file not located") 
          end  
        else
          runner.registerError("ems_static_pressure_reset.ems file not located")
        end  
      else
        runner.registerError("ems_static_pressure_reset.ems file not located")    
      end
    end
    if json.nil?
      runner.registerError("ems_results.json file not located")
      return false
    end

    ##testing code
    # ems_string1 = "EnergyManagementSystem:Actuator,
    # PSZ0_FanPressure, ! Name 
    # Perimeter_ZN_4 ZN PSZ-AC Fan, ! Actuated Component Unique Name
    # Fan, ! Actuated Component Type
    # Fan Pressure Rise; ! Actuated Component Control Type"
    
    # idf_file1 = OpenStudio::IdfFile::load(ems_string1, 'EnergyPlus'.to_IddFileType).get
    # runner.registerInfo("Adding test EMS code to workspace")
    # workspace.addObjects(idf_file1.objects)
    
    if json.empty?
      runner.registerWarning("No Airloops are appropriate for this measure")
      return true
    end
       
    idf_file = OpenStudio::IdfFile::load(ems_string, 'EnergyPlus'.to_IddFileType).get
    runner.registerInfo("Adding EMS code to workspace")
    workspace.addObjects(idf_file.objects)
    
    #unique initial conditions based on
    #runner.registerInitialCondition("The building has #{emsProgram.size} EMS objects.")

    #reporting final condition of model
    #runner.registerFinalCondition("The building finished with #{emsProgram.size} EMS objects.")
    return true

  end #end the run method

end #end the measure

#this allows the measure to be use by the application
StaticPressureReset.new.registerWithApplication