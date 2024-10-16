# ComStock™, Copyright (c) 2024 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# start the measure
class ReplaceBaselineWindows < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # measure name should be the title case of the class name.
    return 'replace_baseline_windows'
  end

  # human readable description
  def description
    return 'Replaces the windows in the baseline based on window type TSV, which details distributions of pane types and corresponding U-value, SHGC, and VLT.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'First gets all building detailed fenestration surfaces. Loops over all detailed fenestration surfaces and checks to see if the surface type is a window. If the surface type is a window then it gets the then get the construction name. With the construction name it determines the simple glazing system object name. With the simple glazing system object name it modifies the U-Value, SHGC, and VLT accordingly.'
  end

  # define the arguments that the user will input
  def arguments(model)
    # make an argument vector
    args = OpenStudio::Measure::OSArgumentVector.new

    # make argument for wall_construction_type
    window_pane_type_choices = OpenStudio::StringVector.new
    window_pane_type_choices << 'Single - No LowE - Clear - Aluminum'
    window_pane_type_choices << 'Single - No LowE - Clear - Wood'
    window_pane_type_choices << 'Single - No LowE - Tinted/Reflective - Aluminum'
    window_pane_type_choices << 'Single - No LowE - Tinted/Reflective - Wood'
    window_pane_type_choices << 'Double - LowE - Clear - Aluminum'
    window_pane_type_choices << 'Double - LowE - Clear - Thermally Broken Aluminum'
    window_pane_type_choices << 'Double - LowE - Tinted/Reflective - Aluminum'
    window_pane_type_choices << 'Double - LowE - Tinted/Reflective - Thermally Broken Aluminum'
    window_pane_type_choices << 'Double - No LowE - Clear - Aluminum'
    window_pane_type_choices << 'Double - No LowE - Tinted/Reflective - Aluminum'
    window_pane_type_choices << 'Triple - LowE - Clear - Thermally Broken Aluminum'
    window_pane_type_choices << 'Triple - LowE - Tinted/Reflective - Thermally Broken Aluminum'
    window_pane_type = OpenStudio::Measure::OSArgument.makeChoiceArgument('window_pane_type', window_pane_type_choices, true)
    window_pane_type.setDisplayName('Window Pane Type')
    window_pane_type.setDescription('Identify window pane type to be applied to entire building')
    window_pane_type.setDefaultValue('Single')
    args << window_pane_type

    # make an argument for window U-Value
    u_value_ip = OpenStudio::Measure::OSArgument.makeDoubleArgument('u_value_ip', true)
    u_value_ip.setDisplayName('Window U-value')
    u_value_ip.setUnits('Btu/ft^2*h*R')
    default_u_val = OpenStudio.convert(3.122, 'W/m^2*K', 'Btu/ft^2*h*R').get
    u_value_ip.setDefaultValue(default_u_val)
    args << u_value_ip

    # make an argument for window SHGC
    shgc = OpenStudio::Measure::OSArgument.makeDoubleArgument('shgc', true)
    shgc.setDisplayName('Window SHGC')
    shgc.setDefaultValue(0.762)
    args << shgc

    # make an argument for window VLT
    vlt = OpenStudio::Measure::OSArgument.makeDoubleArgument('vlt', true)
    vlt.setDisplayName('Window VLT')
    vlt.setDefaultValue(0.812)
    args << vlt

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # create new construction hash
    # key = old construction, value = new construction
    new_construction_hash = {}

    # assign the user inputs to variables
    window_pane_type = runner.getStringArgumentValue('window_pane_type', user_arguments)
    simple_glazing_u_ip = runner.getDoubleArgumentValue('u_value_ip', user_arguments)
    simple_glazing_shgc = runner.getDoubleArgumentValue('shgc', user_arguments)
    simple_glazing_vlt = runner.getDoubleArgumentValue('vlt', user_arguments)

    # convert u-value to SI units
    simple_glazing_u_si = OpenStudio.convert(simple_glazing_u_ip, 'Btu/ft^2*h*R', 'W/m^2*K').get

    # get all fenestration surfaces
    sub_surfaces = []
    constructions = []

    model.getSubSurfaces.each do |sub_surface|
      next unless sub_surface.subSurfaceType.include?('Window')

      sub_surfaces << sub_surface
      constructions << sub_surface.construction.get
    end

    # check to make sure building has fenestration surfaces
    if sub_surfaces.empty?
      runner.registerAsNotApplicable('The building has no windows.')
      return true
    end

    # get all simple glazing system window materials
    simple_glazings = model.getSimpleGlazings
    if simple_glazings.length >= 1
      old_simple_glazing = simple_glazings.first

      # get old values
      old_simple_glazing_u = old_simple_glazing.uFactor
      old_simple_glazing_shgc = old_simple_glazing.solarHeatGainCoefficient
      old_simple_glazing_vlt = old_simple_glazing.visibleTransmittance.get

      # register initial condition
      runner.registerInfo("Existing windows have #{old_simple_glazing_u.round(2)} W/m2-K U-value , #{old_simple_glazing_shgc} SHGC, and #{old_simple_glazing_vlt} VLT.")
    else
      # register initial condition
      runner.registerInfo('Existing windows are not simple glazing; will be swapped with simple glazing object.')
    end

    # make new simple glazing with new properties
    new_simple_glazing = OpenStudio::Model::SimpleGlazing.new(model)
    new_simple_glazing.setName("Simple Glazing #{window_pane_type}")

    # set and register final condition
    new_simple_glazing.setUFactor(simple_glazing_u_si)
    new_simple_glazing.setSolarHeatGainCoefficient(simple_glazing_shgc)
    new_simple_glazing.setVisibleTransmittance(simple_glazing_vlt)

    # define total area changed
    area_changed_m2 = 0.0
    # loop over constructions and simple glazings
    constructions.each do |construction|
      # check if construction has been made
      if new_construction_hash.key?(construction)
        new_construction = new_construction_hash[construction]
      else
        # register final condition
        runner.registerInfo("New window #{new_simple_glazing.name.get} has #{simple_glazing_u_si.round(2)} W/m2-K U-value , #{simple_glazing_shgc.round(2)} SHGC, and #{simple_glazing_vlt.round(2)} VLT.")
        # create new construction with this new simple glazing layer
        new_construction = OpenStudio::Model::Construction.new(model)
        new_construction.setName("Window U-#{simple_glazing_u_ip.round(2)} SHGC #{simple_glazing_shgc.round(2)}")
        new_construction.insertLayer(0, new_simple_glazing)

        # update hash
        new_construction_hash[construction] = new_construction
      end

      # loop over fenestration surfaces and add new construction
      sub_surfaces.each do |sub_surface|
        # assign new construction to fenestration surfaces and add total area changed if construction names match
        next unless sub_surface.construction.get.to_Construction.get.layers[0].name.get == construction.to_Construction.get.layers[0].name.get

        sub_surface.setConstruction(new_construction)
        area_changed_m2 += sub_surface.grossArea
      end
    end

    # summary
    area_changed_ft2 = OpenStudio.convert(area_changed_m2, 'm^2', 'ft^2').get
    runner.registerFinalCondition("Changed #{area_changed_ft2.round(2)} ft2 of window to U-#{simple_glazing_u_ip.round(2)}, SHGC-#{simple_glazing_shgc.round(2)}, VLT-#{simple_glazing_vlt.round(2)}")
    runner.registerValue('env_window_fen_area_ft2', area_changed_ft2.round(2), 'ft2')
    return true
  end
end

# register the measure to be used by the application
ReplaceBaselineWindows.new.registerWithApplication
