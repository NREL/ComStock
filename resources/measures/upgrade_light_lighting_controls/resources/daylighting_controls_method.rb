# method for adding daylighting controls
def model_add_daylighting_controls(runner, model, template)
  remove_existing_controls = false
  draw_daylight_areas_for_debugging = false

  # Make a standard that follows 90.1-2019 (the code year that will be used for lighting controls assumptions)
  standard = Standard.build('ComStock 90.1-2019')

  model.getSpaces.sort.each do |space|
    runner.registerInfo("******For #{space.name}, adding daylight controls.")

    # Get the space thermal zone
    zone = space.thermalZone
    if zone.empty?
      runner.registerError("Space #{space.name} has no thermal zone; cannot set daylighting controls for zone.")
    else
      zone = zone.get
    end

    # Check for existing daylighting controls
    # and remove if specified in the input
    existing_daylighting_controls = space.daylightingControls
    unless existing_daylighting_controls.empty?
      if remove_existing_controls
        space_remove_daylighting_controls(space)
        zone.resetFractionofZoneControlledbyPrimaryDaylightingControl
        zone.resetFractionofZoneControlledbySecondaryDaylightingControl
      else
        runner.registerInfo("For #{space.name}, daylight controls were already present, no additional controls added.")
        next
      end
    end

    # Skip this space if it has no exterior windows or skylights
    ext_fen_area_m2 = 0
    space.surfaces.each do |surface|
      next unless surface.outsideBoundaryCondition == 'Outdoors'

      surface.subSurfaces.each do |sub_surface|
        next unless %w[FixedWindow OperableWindow Skylight
                       GlassDoor].include?(sub_surface.subSurfaceType)

        ext_fen_area_m2 += sub_surface.netArea
      end
    end
    if ext_fen_area_m2.zero?
      runner.registerInfo("For #{space.name}, daylighting control not applicable because no exterior fenestration is present.")
      next
    end

    # Get the daylighting areas
    areas = standard.space_daylighted_areas(space, draw_daylight_areas_for_debugging)

    # Determine the type of daylighting controls required
    req_top_ctrl, req_pri_ctrl, req_sec_ctrl = standard.space_daylighting_control_required?(space, areas)

    # # Stop here if no controls are required
    # if !req_top_ctrl && !req_pri_ctrl && !req_sec_ctrl
    #   runner.registerInfo("For #{space.name}, no daylighting control is required.")
    #   return false
    # end

    # # Output the daylight control requirements
    # runner.registerInfo("For #{space.name}, toplighting control required = #{req_top_ctrl}")
    # runner.registerInfo("For #{space.name}, primary sidelighting control required = #{req_pri_ctrl}")
    # runner.registerInfo("For #{space.name}, secondary sidelighting control required = #{req_sec_ctrl}")

    # Record a floor in the space for later use
    floor_surface = nil
    space.surfaces.sort.each do |surface|
      if surface.surfaceType == 'Floor'
        floor_surface = surface
        break
      end
    end

    # Find all exterior windows/skylights in the space and record their azimuths and areas
    windows = {}
    skylights = {}
    space.surfaces.sort.each do |surface|
      next unless surface.outsideBoundaryCondition == 'Outdoors' && %w[Wall
                                                                       RoofCeiling].include?(surface.surfaceType)

      # Skip non-vertical walls and non-horizontal roofs
      straight_upward = OpenStudio::Vector3d.new(0, 0, 1)
      surface_normal = surface.outwardNormal
      if surface.surfaceType == 'Wall'
        # @todo stop skipping non-vertical walls
        if !(surface_normal.z.abs < 0.001) && !surface.subSurfaces.empty?
          runner.registerWarning("Cannot currently handle non-vertical walls; skipping windows on #{surface.name} in #{space.name} for daylight sensor positioning.")
          next
        end
      elsif surface.surfaceType == 'RoofCeiling'
        # @todo stop skipping non-horizontal roofs
        if !(surface_normal.to_s == straight_upward.to_s) && !surface.subSurfaces.empty?
          runner.registerWarning("Cannot currently handle non-horizontal roofs; skipping skylights on #{surface.name} in #{space.name} for daylight sensor positioning.")
          runner.registerInfo("---Surface #{surface.name} has outward normal of #{surface_normal.to_s.gsub(
            /\[|\]/, '|'
          )}; up is #{straight_upward.to_s.gsub(/\[|\]/, '|')}.")
          next
        end
      end

      # Find the azimuth of the facade
      facade = nil
      group = surface.planarSurfaceGroup
      # The surface is not in a group; should not hit, since called from Space.surfaces
      next unless group.is_initialized

      group = group.get
      site_transformation = group.buildingTransformation
      site_vertices = site_transformation * surface.vertices
      site_outward_normal = OpenStudio.getOutwardNormal(site_vertices)
      if site_outward_normal.empty?
        runner.registerError("Could not compute outward normal for #{surface.name.get}")
        next
      end
      site_outward_normal = site_outward_normal.get
      north = OpenStudio::Vector3d.new(0.0, 1.0, 0.0)
      azimuth = if site_outward_normal.x < 0.0
                  360.0 - OpenStudio.radToDeg(OpenStudio.getAngle(site_outward_normal, north))
                else
                  OpenStudio.radToDeg(OpenStudio.getAngle(site_outward_normal, north))
                end

      # @todo modify to work for buildings in the southern hemisphere?
      if azimuth >= 315.0 || azimuth < 45.0
        facade = '4-North'
      elsif azimuth >= 45.0 && azimuth < 135.0
        facade = '3-East'
      elsif azimuth >= 135.0 && azimuth < 225.0
        facade = '1-South'
      elsif azimuth >= 225.0 && azimuth < 315.0
        facade = '2-West'
      end

      # Label the facade as "Up" if it is a skylight
      facade = '0-Up' if surface_normal.to_s == straight_upward.to_s

      # Loop through all subsurfaces and
      surface.subSurfaces.sort.each do |sub_surface|
        next unless sub_surface.outsideBoundaryCondition == 'Outdoors' && %w[FixedWindow OperableWindow
                                                                             Skylight].include?(sub_surface.subSurfaceType)

        # Find the area
        net_area_m2 = sub_surface.netArea

        # Find the head height and sill height of the window
        vertex_heights_above_floor = []
        sub_surface.vertices.each do |vertex|
          vertex_on_floorplane = floor_surface.plane.project(vertex)
          vertex_heights_above_floor << (vertex - vertex_on_floorplane).length
        end
        head_height_m = vertex_heights_above_floor.max
        # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.Space", "---head height = #{head_height_m}m, sill height = #{sill_height_m}m")

        # Log the window properties to use when creating daylight sensors
        properties = { facade: facade, area_m2: net_area_m2, handle: sub_surface.handle,
                       head_height_m: head_height_m, name: sub_surface.name.get.to_s }
        if facade == '0-Up'
          skylights[sub_surface] = properties
        else
          windows[sub_surface] = properties
        end
      end
    end

    # Determine the illuminance setpoint for the controls based on space type
    daylight_stpt_lux = 375

    # find the specific space_type properties
    space_type = space.spaceType
    if space_type.empty?
      runner.registerWarning("Space #{space_type} is an unknown space type, assuming #{daylight_stpt_lux} Lux daylight setpoint")
    else
      space_type = space_type.get
      standards_building_type = nil
      standards_space_type = nil
      data = nil
      standards_building_type = space_type.standardsBuildingType.get if space_type.standardsBuildingType.is_initialized
      standards_space_type = space_type.standardsSpaceType.get if space_type.standardsSpaceType.is_initialized

      unless standards_building_type.nil? || standards_space_type.nil?
        # use the building type (standards_building_type) and space type (standards_space_type)
        # as well as template to locate the space type data
        search_criteria = {
          'template' => template,
          'building_type' => standards_building_type,
          'space_type' => standards_space_type
        }
        data = standard.model_find_object(standard.standards_data['space_types'], search_criteria)
      end

      if standards_building_type.nil? || standards_space_type.nil?
        runner.registerWarning("Unable to determine standards building type and standards space type for space '#{space.name}' with space type '#{space_type.name}'. Assign a standards building type and standards space type to the space type object. Defaulting to a #{daylight_stpt_lux} Lux daylight setpoint.")
      elsif data.nil?
        runner.registerWarning("Unable to find target illuminance setpoint data for space type '#{space_type.name}' with #{template} space type '#{standards_space_type}' in building type '#{standards_building_type}'. Defaulting to a #{daylight_stpt_lux} Lux daylight setpoint.")
        if daylight_stpt_lux == 'na'
          runner.registerInfo("For #{space.name}: daylighting is not appropriate for #{template} #{standards_building_type} #{standards_space_type}.")
          return true
        end
        # If a setpoint is specified, use that.  Otherwise use a default.
        daylight_stpt_lux = daylight_stpt_lux.to_f
        if daylight_stpt_lux.zero?
          daylight_stpt_lux = 375
          runner.registerInfo('openstudio.standards.Space',
                              "For #{space.name}: no specific illuminance setpoint defined for #{template} #{standards_building_type} #{standards_space_type}, assuming #{daylight_stpt_lux} Lux.")
        else
          runner.registerInfo("For #{space.name}: illuminance setpoint = #{daylight_stpt_lux} Lux")
        end
      # for the office prototypes where core and perimeter zoning is used,
      # # there are additional assumptions about how much of the daylit area can be used.
      # if standards_building_type == 'Office' && standards_space_type.include?('WholeBuilding')
      #   psa_nongeo_frac = standard.data['psa_nongeometry_fraction'].to_f
      #   ssa_nongeo_frac = standard.data['ssa_nongeometry_fraction'].to_f
      #   runner.registerInfo("For #{space.name}: assuming only #{(psa_nongeo_frac * 100).round}% of the primary sidelit area is daylightable based on typical design practice.")
      #   runner.registerInfo("For #{space.name}: assuming only #{(ssa_nongeo_frac * 100).round}% of the secondary sidelit area is daylightable based on typical design practice.")
      # end
      else
        # Read the illuminance setpoint value
        # If 'na', daylighting is not appropriate for this space type for some reason
        daylight_stpt_lux = data['target_illuminance_setpoint']
        if daylight_stpt_lux == 'na'
          runner.registerInfo("For #{space.name}: daylighting is not appropriate for #{template} #{standards_building_type} #{standards_space_type}.")
          return true
        end
        # If a setpoint is specified, use that.  Otherwise use a default.
        daylight_stpt_lux = daylight_stpt_lux.to_f
        if daylight_stpt_lux.zero?
          daylight_stpt_lux = 375
          runner.registerInfo('openstudio.standards.Space',
                              "For #{space.name}: no specific illuminance setpoint defined for #{template} #{standards_building_type} #{standards_space_type}, assuming #{daylight_stpt_lux} Lux.")
        else
          runner.registerInfo("For #{space.name}: illuminance setpoint = #{daylight_stpt_lux} Lux")
        end
        # for the office prototypes where core and perimeter zoning is used,
        # there are additional assumptions about how much of the daylit area can be used.
        if standards_building_type == 'Office' && standards_space_type.include?('WholeBuilding')
          psa_nongeo_frac = data['psa_nongeometry_fraction'].to_f
          ssa_nongeo_frac = data['ssa_nongeometry_fraction'].to_f
          runner.registerInfo("For #{space.name}: assuming only #{(psa_nongeo_frac * 100).round}% of the primary sidelit area is daylightable based on typical design practice.")
          runner.registerInfo("For #{space.name}: assuming only #{(ssa_nongeo_frac * 100).round}% of the secondary sidelit area is daylightable based on typical design practice.")
        end
      end

      # Sort by priority; first by facade, then by area,
      # then by name to ensure deterministic in case identical in other ways
      sorted_windows = windows.sort_by { |_window, vals| [vals[:facade], vals[:area], vals[:name]] }
      sorted_skylights = skylights.sort_by { |_skylight, vals| [vals[:facade], vals[:area], vals[:name]] }

      # Report out the sorted skylights for debugging
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, Skylights:")
      sorted_skylights.each do |sky, p|
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space',
                           "---#{sky.name} #{p[:facade]}, area = #{p[:area_m2].round(2)} m^2")
      end

      # Report out the sorted windows for debugging
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space', "For #{space.name}, Windows:")
      sorted_windows.each do |win, p|
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Space',
                           "---#{win.name} #{p[:facade]}, area = #{p[:area_m2].round(2)} m^2")
      end

      # Determine the sensor fractions and the attached windows
      sensor_1_frac, sensor_2_frac, sensor_1_window, sensor_2_window = standard.space_daylighting_fractions_and_windows(space,
                                                                                                                        areas,
                                                                                                                        sorted_windows,
                                                                                                                        sorted_skylights,
                                                                                                                        req_top_ctrl,
                                                                                                                        req_pri_ctrl,
                                                                                                                        req_sec_ctrl)

      # Further adjust the sensor controlled fraction for the three
      # office prototypes based on assumptions about geometry that is not explicitly
      # defined in the model.
      if standards_building_type == 'Office' && standards_space_type.include?('WholeBuilding')
        sensor_1_frac *= psa_nongeo_frac unless psa_nongeo_frac.nil?
        sensor_2_frac *= ssa_nongeo_frac unless ssa_nongeo_frac.nil?
      end

      # Ensure that total controlled fraction
      # is never set above 1 (100%)
      sensor_1_frac = sensor_1_frac.round(3)
      sensor_2_frac = sensor_2_frac.round(3)
      sensor_1_frac = 1.0 - 0.001 if sensor_1_frac >= 1.0
      if sensor_1_frac + sensor_2_frac >= 1.0
        # Lower sensor_2_frac so that the total
        # is just slightly lower than 1.0
        sensor_2_frac = 1.0 - sensor_1_frac - 0.001
      end

      # Sensors
      if sensor_1_frac > 0.0
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space',
                           "For #{space.name}: sensor 1 controls #{(sensor_1_frac * 100).round}% of the zone lighting.")
      end
      if sensor_2_frac > 0.0
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Space',
                           "For #{space.name}: sensor 2 controls #{(sensor_2_frac * 100).round}% of the zone lighting.")
      end

      # First sensor
      if sensor_1_window
        # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.Space", "For #{self.name}, calculating daylighted areas.")
        # runner.registerInfo("Daylight sensor 1 inside of #{sensor_1_frac.name}")
        sensor_1 = OpenStudio::Model::DaylightingControl.new(space.model)
        sensor_1.setName("#{space.name} Daylt Sensor 1")
        sensor_1.setSpace(space)
        sensor_1.setIlluminanceSetpoint(daylight_stpt_lux)
        sensor_1.setLightingControlType(standard.space_daylighting_control_type(space))
        # all sensors 3-step per design
        sensor_1.setNumberofSteppedControlSteps(3) unless standard.space_daylighting_control_type(space) != 'Stepped'
        sensor_1.setMinimumInputPowerFractionforContinuousDimmingControl(standard.space_daylighting_minimum_input_power_fraction(space))
        sensor_1.setMinimumLightOutputFractionforContinuousDimmingControl(0.2)
        sensor_1.setProbabilityLightingwillbeResetWhenNeededinManualSteppedControl(1.0)
        sensor_1.setMaximumAllowableDiscomfortGlareIndex(22.0)

        # Place sensor depending on skylight or window
        sensor_vertex = nil
        if sensor_1_window[1][:facade] == '0-Up'
          sub_surface = sensor_1_window[0]
          outward_normal = sub_surface.outwardNormal
          centroid = OpenStudio.getCentroid(sub_surface.vertices).get
          ht_above_flr = OpenStudio.convert(2.5, 'ft', 'm').get
          outward_normal.setLength(sensor_1_window[1][:head_height_m] - ht_above_flr)
          sensor_vertex = centroid + outward_normal.reverseVector
        else
          sub_surface = sensor_1_window[0]
          window_outward_normal = sub_surface.outwardNormal
          window_centroid = OpenStudio.getCentroid(sub_surface.vertices).get
          window_outward_normal.setLength(sensor_1_window[1][:head_height_m] * 0.66)
          vertex = window_centroid + window_outward_normal.reverseVector
          vertex_on_floorplane = floor_surface.plane.project(vertex)
          floor_outward_normal = floor_surface.outwardNormal
          floor_outward_normal.setLength(OpenStudio.convert(2.5, 'ft', 'm').get)
          sensor_vertex = vertex_on_floorplane + floor_outward_normal.reverseVector
        end
        sensor_1.setPosition(sensor_vertex)

        # @todo rotate sensor to face window (only needed for glare calcs)
        zone.setPrimaryDaylightingControl(sensor_1)
        if zone.fractionofZoneControlledbyPrimaryDaylightingControl + sensor_1_frac > 1
          zone.resetFractionofZoneControlledbySecondaryDaylightingControl
        end
        zone.setFractionofZoneControlledbyPrimaryDaylightingControl(sensor_1_frac)
      end

      # Second sensor
      if sensor_2_window
        # OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.Space", "For #{self.name}, calculating daylighted areas.")
        # runner.registerInfo("Daylight sensor 2 inside of #{sensor_2_frac.name}")
        sensor_2 = OpenStudio::Model::DaylightingControl.new(space.model)
        sensor_2.setName("#{space.name} Daylt Sensor 2")
        sensor_2.setSpace(space)
        sensor_2.setIlluminanceSetpoint(daylight_stpt_lux)
        sensor_2.setLightingControlType(standard.space_daylighting_control_type(space))
        # all sensors 3-step per design
        sensor_2.setNumberofSteppedControlSteps(3) unless standard.space_daylighting_control_type(space) != 'Stepped'
        sensor_2.setMinimumInputPowerFractionforContinuousDimmingControl(standard.space_daylighting_minimum_input_power_fraction(space))
        sensor_2.setMinimumLightOutputFractionforContinuousDimmingControl(0.2)
        sensor_2.setProbabilityLightingwillbeResetWhenNeededinManualSteppedControl(1.0)
        sensor_2.setMaximumAllowableDiscomfortGlareIndex(22.0)

        # Place sensor depending on skylight or window
        sensor_vertex = nil
        if sensor_2_window[1][:facade] == '0-Up'
          sub_surface = sensor_2_window[0]
          outward_normal = sub_surface.outwardNormal
          centroid = OpenStudio.getCentroid(sub_surface.vertices).get
          ht_above_flr = OpenStudio.convert(2.5, 'ft', 'm').get
          outward_normal.setLength(sensor_2_window[1][:head_height_m] - ht_above_flr)
          sensor_vertex = centroid + outward_normal.reverseVector
        else
          sub_surface = sensor_2_window[0]
          window_outward_normal = sub_surface.outwardNormal
          window_centroid = OpenStudio.getCentroid(sub_surface.vertices).get
          window_outward_normal.setLength(sensor_2_window[1][:head_height_m] * 1.33)
          vertex = window_centroid + window_outward_normal.reverseVector
          vertex_on_floorplane = floor_surface.plane.project(vertex)
          floor_outward_normal = floor_surface.outwardNormal
          floor_outward_normal.setLength(OpenStudio.convert(2.5, 'ft', 'm').get)
          sensor_vertex = vertex_on_floorplane + floor_outward_normal.reverseVector
        end
        sensor_2.setPosition(sensor_vertex)

        # @todo rotate sensor to face window (only needed for glare calcs)
        zone.setSecondaryDaylightingControl(sensor_2)
        if zone.fractionofZoneControlledbySecondaryDaylightingControl + sensor_2_frac > 1
          zone.resetFractionofZoneControlledbyPrimaryDaylightingControl
        end
        zone.setFractionofZoneControlledbySecondaryDaylightingControl(sensor_2_frac)
      end
    end
  end
end
