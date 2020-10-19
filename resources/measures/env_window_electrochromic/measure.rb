# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

# Start the measure
class ElectrochromicWindows < OpenStudio::Measure::ModelMeasure

  # Define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return "Electrochromic Windows"
  end

  # Human readable description
  def description
    return "Electrochromic windows are windows whose light transmittance can be changed from clear to very dark at will.  These windows may save energy and reduce peak demand by decreasing unwanted solar gains."
  end

  # Human readable description of modeling approach
  def modeler_description
    return "Each window in the building is assigned a thermochromic window construction and a shading control.  The shading control is set to increase the window tint to meet the daylighting setpoint in the zone.  If the zone already has daylighting controls, the setpoints from those controls are used.  If the zone does not have controls, new controls are added at the center of the zone with a setpoint of 500 lux.  These controls are only used for changing the window tint; they are not used to control the interior lighting."
  end
  
  # Define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new
    
    # Make integer arg to run measure [1 is run, 0 is no run]
    run_measure = OpenStudio::Measure::OSArgument::makeIntegerArgument('run_measure', true)
    run_measure.setDisplayName('Run Measure')
    run_measure.setDescription('integer argument to run measure [1 is run, 0 is no run]')
    run_measure.setDefaultValue(1)
    args << run_measure

    # Make choice argument to select which window material to use
    # (Bleached Glass = Fully Transparent Electrochromic)
    # (Tinted Glass = Fully Tinted Electrochromic)
    choice = OpenStudio::StringVector.new
    choice << 'BleachedGlass'
    choice << 'TintedGlass'
    choice = OpenStudio::Measure::OSArgument::makeChoiceArgument('choice', choice, true)
    choice.setDisplayName('Glass Type')
    choice.setDefaultValue('BleachedGlass')
    args << choice
    
    return args
  end # end the arguments method

  # Define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Use the built-in error checking 
    if not runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Assign the user input to a variable that can be accessed across the measure
    choice = runner.getStringArgumentValue('choice', user_arguments)
    
    run_measure = runner.getIntegerArgumentValue('run_measure', user_arguments)
    if run_measure == 0
      runner.registerAsNotApplicable("Run Measure set to #{run_measure}.")
      return true     
    end

    # Create new construction hash
    # key = old construction, value = new construction
    new_construction_hash = {}

    # Get all fenestration surfaces
    sub_surfaces = []
    constructions = []

    model.getSubSurfaces.each do |sub_surface|
      next unless sub_surface.subSurfaceType.include?('Window')
      sub_surfaces << sub_surface
      constructions << sub_surface.construction.get
    end

    # Check to make sure building has fenestration surfaces
    if sub_surfaces.empty?
      runner.registerAsNotApplicable('The building has no windows.')
      return true
    end

#    zones_with_ctrls = []
#    model.getThermalZones.each do |zone|
#      zone_name = zone.name.get
#      # Skip zones without windows
#      has_window = false
#      zone.spaces.each do |space|
#        space.surfaces.each do |surface|
#          if surface.subSurfaces.size > 0
#            has_window = true
#          end
#        end
#     next unless has_window
#        # Find existing daylighting sensors or add a new one
#        if zone.primaryDaylightingControl.is_initialized
#          zones_with_ctrls << zone_name
#          runner.registerInfo("Zone #{zone_name} already has a daylighting sensor.")
#        else
#          # Get the centroid of the zone's floor for placement of daylight sensors to control electrochromic if no daylight sensor exists
#          centroid = nil
#          space.surfaces.each do |surface|
#            next unless surface.surfaceType == 'Floor'
#            centroid = OpenStudio.getCentroid(surface.vertices).get
#            if centroid.nil?
#              runner.registerWarning("Could not find a floor in #{zone_name}, cannot place daylight sensor to control electrochromics in this zone.")
#            else
#              zones_with_ctrls << zone_name
#              
#              # Add daylighting controls
#              sensor = OpenStudio::Model::DaylightingControl.new(model)
#              sensor.setName("#{space.name} daylighting control")
#              new_point = OpenStudio::Point3d.new(centroid.x, centroid.y, centroid.z)
#              sensor.setPosition(new_point)
#              sensor.setIlluminanceSetpoint(500)
#              sensor.setNumberofSteppedControlSteps(3)
#              sensor.setLightingControlType('Continuous/Off')
#              sensor.setSpace(space)
#              
#              runner.registerInfo("Zone #{zone_name} does not have a daylighting sensor - one was added to control the electrochromic windows.")
#            end
#          end
#        end
#      end
#    end

    # Not applicable if no zones have daylighting controls
#    if zones_with_ctrls.size == 0
#      runner.registerAsNotApplicable("Not Applicable - no zones in the model have daylighting controls or could have daylighting controls added to control the electrochromic glazing.")
#      return true
#    end
    
    # Get all simple glazing system window materials
    simple_glazings = model.getSimpleGlazings

    # Define total area change, U-value, SHGC, and VLT float
    area_changed_m2 = 0.0
    if choice == 'BleachedGlass'
      new_simple_glazing_u = 1.87382679         # [W/m2-K]
      new_simple_glazing_shgc = 0.42
      new_simple_glazing_vlt = 0.56
    elsif choice == 'TintedGlass'
      new_simple_glazing_u = 1.87382679         # [W/m2-K]
      new_simple_glazing_shgc = 0.09
      new_simple_glazing_vlt = 0.02
    end

    # Loop over constructions and simple glazings
    constructions.each do |construction|
      simple_glazings.each do |simple_glazing|
        # Check if construction layer name matches simple glazing name
        next unless construction.to_Construction.get.layers[0].name.get == simple_glazing.name.get

        # Get old values
        old_simple_glazing_u = simple_glazing.uFactor
        old_simple_glazing_shgc = simple_glazing.solarHeatGainCoefficient
        old_simple_glazing_vlt = simple_glazing.visibleTransmittance.get
        
        # Register initial condition
        runner.registerInfo("Existing window '#{simple_glazing.name.get}' has #{old_simple_glazing_u.round(2)} W/m2-K U-value , #{old_simple_glazing_shgc.round(2)} SHGC, and #{old_simple_glazing_vlt.round(2)} VLT.")

        # Check if construction has been made
        if new_construction_hash.has_key?(construction)
          new_construction = new_construction_hash[construction]
        else
          # Make new simple glazing with new properties
          new_simple_glazing = OpenStudio::Model::SimpleGlazing.new(model)
          new_simple_glazing.setName("Simple Glazing U-#{new_simple_glazing_u.round(2)} SHGC #{new_simple_glazing_shgc.round(2)}")

          # Set and register final condition
          new_simple_glazing.setUFactor(new_simple_glazing_u)
          new_simple_glazing.setSolarHeatGainCoefficient(new_simple_glazing_shgc)
          new_simple_glazing.setVisibleTransmittance(new_simple_glazing_vlt)

          # Register final condition
          runner.registerInfo("New window '#{new_simple_glazing.name.get}' has #{new_simple_glazing_u.round(2)} W/m2-K U-value , #{new_simple_glazing_shgc.round(2)} SHGC, and #{new_simple_glazing_vlt.round(2)} VLT.")
          
          # Create new construction with this new simple glazing layer
          new_construction = OpenStudio::Model::Construction.new(model)
          new_construction.setName("Window U-#{new_simple_glazing_u.round(2)} SHGC #{new_simple_glazing_shgc} VLT #{new_simple_glazing_vlt}")
          new_construction.insertLayer(0, new_simple_glazing)
          
#          # Loop through lights that are used in the model to populate schedule hash
#          schedules = []
#          model.getLightss.each do |light|
#            # Check if this instance is used in the model
#            if light.spaceType.is_initialized
#              next if light.spaceType.get.spaces.empty?
#            end
#            # Find schedule
#            if light.schedule.is_initialized && light.schedule.get.to_ScheduleRuleset.is_initialized
#              schedules << light.schedule.get.to_ScheduleRuleset.get
#            else
#              runner.registerWarning("#{light.name} does not have a schedule or schedule is not a schedule ruleset assigned.")
#            end
#          end

          # Add shading controls
          shading = OpenStudio::Model::ShadingControl.new(new_construction)
          shading.setName('Switchable Glazing')
          shading.setShadingType('SwitchableGlazing')
          shading.setShadingControlType('OnIfHighSolarOnWindow')
          shading.setSetpoint(0.0)

          # Update hash
          new_construction_hash[construction] = new_construction
        end

        # Loop over applicable fenestration surfaces and add new construction to zones with daylighting controls
        model.getThermalZones.each do |zone|
          #next unless zones_with_ctrls.include?(zone.name.get)
          sub_surfaces.each do |sub_surface|
            # Assign new construction to fenestration surfaces and add total area changed if construction names match
            next unless sub_surface.construction.get.to_Construction.get.layers[0].name.get == construction.to_Construction.get.layers[0].name.get
            sub_surface.setConstruction(new_construction)
            sub_surface.setShadingControl(shading)
            area_changed_m2 += sub_surface.grossArea
          end
        end
      end
    end

    # Summary
    area_changed_ft2 = OpenStudio.convert(area_changed_m2, 'm^2', 'ft^2').get
    runner.registerFinalCondition("Changed #{area_changed_ft2.round(2)} ft2 of window to U-#{new_simple_glazing_u.round(2)}, SHGC-#{new_simple_glazing_shgc}, VLT-#{new_simple_glazing_vlt}.")
    runner.registerValue('env_window_electrochromic_fen_area_ft2', area_changed_ft2.round(2), 'ft^2')
    return true
  end
end

# This allows the measure to be use by the application
ElectrochromicWindows.new.registerWithApplication
