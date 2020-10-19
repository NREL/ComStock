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
class ElectrochromicWindows < OpenStudio::Measure::ModelMeasure

  #define the name that a user will see, this method may be deprecated as
  #the display name in PAT comes from the name field in measure.xml
  def name
    return "Electrochromic Windows"
  end

  # human readable description
  def description
    return "Electrochromic windows are windows whose light transmittance can be changed from clear to very dark at will.  These windows may save energy and reduce peak demand by decreasing unwanted solar gains."
  end

  # human readable description of modeling approach
  def modeler_description
    return "Each window in the building is assigned a thermochromic window construction and a shading control.  The shading control is set to increase the window tint to meet the daylighting setpoint in the zone.  If the zone already has daylighting controls, the setpoints from those controls are used.  If the zone does not have controls, new controls are added at the center of the zone with a setpoint of 500 lux.  These controls are only used for changing the window tint; they are not used to control the interior lighting."
  end
  
  #define the arguments that the user will input
  def arguments(workspace)
    args = OpenStudio::Measure::OSArgumentVector.new
    
    #make integer arg to run measure [1 is run, 0 is no run]
    run_measure = OpenStudio::Measure::OSArgument::makeIntegerArgument("run_measure",true)
    run_measure.setDisplayName("Run Measure")
    run_measure.setDescription("integer argument to run measure [1 is run, 0 is no run]")
    run_measure.setDefaultValue(1)
    args << run_measure
    return args
  end #end the arguments method

  #define what happens when the measure is run
  def run(workspace, runner, user_arguments)
    super(workspace, runner, user_arguments)

    #use the built-in error checking 
    if not runner.validateUserArguments(arguments(workspace), user_arguments)
      return false
    end
    
    run_measure = runner.getIntegerArgumentValue("run_measure",user_arguments)
    if run_measure == 0
      runner.registerAsNotApplicable("Run Measure set to #{run_measure}.")
      return true     
    end
    
    require 'json'
    
    # Get the last openstudio model
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError("Could not load last OpenStudio model, cannot apply measure.")
      return false
    end
    model = model.get
    
    # Method to add objects from an IDF string to the workspace
    def add_objects_from_string(workspace, idf_string)
      idf_file = OpenStudio::IdfFile::load(idf_string, 'EnergyPlus'.to_IddFileType).get
      workspace.addObjects(idf_file.objects)
    end
    
    # Find all zones in the model with daylighting controls,
    # which are required for the desired type of electrochromic controls
    zones_with_ctrls = []
    model.getThermalZones.each do |zone|
      zone_name = zone.name.get
      # Skip zones with no windows
      has_window = false
      zone.spaces.each do |space|
        space.surfaces.each do |surface|
          if surface.subSurfaces.size > 0
            has_window = true
          end
        end
      end
      next unless has_window
      # Find existing daylighting sensors or add a new one
      if zone.primaryDaylightingControl.is_initialized
        zones_with_ctrls << zone_name
        runner.registerInfo("Zone #{zone_name} already has a daylighting sensor.")
      else
        # Get the centroid of the zone's floor
        # for placement of daylight sensors to control
        # electrochromic if no daylight sensor exists.
        centroid = nil
        zone.spaces[0].surfaces.sort.each do |surf|
          next unless surf.surfaceType == 'Floor'
          centroid = OpenStudio.getCentroid(surf.vertices).get
          break
        end
        if centroid.nil?
          runner.registerWarning("Could not find a floor in #{zone_name}, cannot place daylight sensor to control electrochromics in this zone.")
        else
          zones_with_ctrls << zone_name
          daylt_controls = "
          Daylighting:Controls,
            #{zone_name},                           !- Zone Name
            1,                                      !- Total Daylighting Reference Points
            #{centroid.x},                          !- X-Coordinate of First Reference Point {m}
            #{centroid.y},                          !- Y-Coordinate of First Reference Point {m}
            #{centroid.z},                          !- Z-Coordinate of First Reference Point {m}
            ,                                       !- X-Coordinate of Second Reference Point {m}
            ,                                       !- Y-Coordinate of Second Reference Point {m}
            ,                                       !- Z-Coordinate of Second Reference Point {m}
            0,                                      !- Fraction of Zone Controlled by First Reference Point
            ,                                       !- Fraction of Zone Controlled by Second Reference Point
            500,                                    !- Illuminance Setpoint at First Reference Point {lux}
            ,                                       !- Illuminance Setpoint at Second Reference Point {lux}
            2,                                      !- Lighting Control Type
            -0,                                     !- Glare Calculation Azimuth Angle of View Direction Clockwise from Zone y-Axis {deg}
            ,                                       !- Maximum Allowable Discomfort Glare Index
            ,                                       !- Minimum Input Power Fraction for Continuous Dimming Control
            ,                                       !- Minimum Light Output Fraction for Continuous Dimming Control
            3,                                      !- Number of Stepped Control Steps
            ;                                       !- Probability Lighting will be Reset When Needed in Manual Stepped Control"
          
          add_objects_from_string(workspace, daylt_controls)          
          
          runner.registerInfo("Zone #{zone_name} does not have a daylighting sensor; added one to control the electrochromic windows.")
        end
      end
    end
    
    # Not applicable if no zones have daylighting controls
    if zones_with_ctrls.size == 0
      runner.registerAsNotApplicable("Not Applicable - no zones in the model have daylighting controls or could have daylighting controls added to control the electrochromic glazing.")
      return true
    end
    
    # Add a shading controls object and the clear and tinted
    # electrochromic constructions to the IDF.
    # Electrochromic window properties from Center of Glass (COG)
    # from: https://windows.lbl.gov/comm_perf/electrochromic/refs/LBNL-54966.pdf
    bleached_glass_name = 'Fully Transparent Electrochromic'
    tinted_glass_name =   'Fully Tinted Electrochromic'
    shading_ctrl_name =   'Electrochromic Controls'
    controls_string = ""
    controls_string << "
    WindowMaterial:SimpleGlazingSystem,
      Bleached Glass,          !- Name
      1.87382679,              !- U-Factor {W/m2-K}
      0.42,                    !- Solar Heat Gain Coefficient
      0.56;                    !- Visible Transmittance

    WindowMaterial:SimpleGlazingSystem,
      Tinted Glass,            !- Name
      1.87382679,              !- U-Factor {W/m2-K}
      0.09,                    !- Solar Heat Gain Coefficient
      0.02;                    !- Visible Transmittance
 
    Construction,
      #{bleached_glass_name},       !- Name
      Bleached Glass;               !- Outside Layer

    Construction,
      #{tinted_glass_name},         !- Name
      Tinted Glass;                 !- Outside Layer

    WindowProperty:ShadingControl,
      #{shading_ctrl_name},             !- Name
      SwitchableGlazing,                !- Shading Type
      #{tinted_glass_name},             !- Construction with Shading Name
      MeetDaylightIlluminanceSetpoint,  !- Shading Control Type
      ,                                 !- Schedule Name
      0.0,                              !- Setpoint {W/m2, W or deg C}
      NO,                               !- Shading Control Is Scheduled
      NO,                               !- Glare Control Is Active
      ,                                 !- Shading Device Material Name
      FixedSlatAngle,                   !- Type of Slat Angle Control for Blinds
      ;                                 !- Slat Angle Schedule Name"
    
    add_objects_from_string(workspace, controls_string)
    
    # Loop through all subsurfaces and
    # add shading controls to any whose zones
    # have daylighting controls.
    windows_modified = []
    zones_impacted = []
    area_changed_si = 0
    workspace.getObjectsByType("FenestrationSurface:Detailed".to_IddObjectType).sort.each do |sub_surf|
      next unless sub_surf.getString(1).get == 'Window'
      # Get the parent surface
      parent_surf_name = sub_surf.getString(3).get
      parent_surf = workspace.getObjectByTypeAndName("BuildingSurface:Detailed".to_IddObjectType, parent_surf_name).get
      # Get the zone
      parent_zone_name = parent_surf.getString(3).get
      if zones_with_ctrls.include?(parent_zone_name)
        # Assign a shading controls and 
        # change the construction to the bleached state
        sub_surf.setString(2, bleached_glass_name)
        sub_surf.setString(6, shading_ctrl_name)
        windows_modified << sub_surf.getString(0).get
        zones_impacted << parent_zone_name
        
        area_changed_si += sub_surf.grossArea
      end
    end
   
    # Debugging variables
    # debug_vars = "
    # Output:Variable,*,Daylighting Reference Point 1 Illuminance,hourly; !- Zone Average [lux]
    # Output:Variable,*,Surface Shading Device Is On Time Fraction,hourly; !- Zone Average []
    # Output:Variable,*,Surface Window Transmitted Solar Radiation Energy,hourly; !- Zone Sum [J]
    # Output:Variable,*,Surface Window Switchable Glazing Visible Transmittance,hourly; !- Zone Average []
    # Output:Variable,*,Surface Window Switchable Glazing Switching Factor,hourly; !- Zone Sum [J]"
   
    # add_objects_from_string(workspace, debug_vars)

    # Convert from SI to IP units
    area_changed_ip = OpenStudio.convert(area_changed_si, 'm^2', 'ft^2').get
   
    # Not applicable if none of the zones had windows
    if windows_modified.size == 0
      runner.registerAsNotApplicable("Not Applicable - no zones in the model with daylighting controls have windows.")
    else
      runner.registerFinalCondition("Applied electrochromic windows to #{windows_modified.size} windows in #{zones_impacted.uniq.size} zones.")
      runner.registerValue('window_area_changed_ft2', area_changed_ip.round(2), 'ft2')
    end
    
    return true

  end #end the run method

end #end the measure

#this allows the measure to be use by the application
ElectrochromicWindows.new.registerWithApplication