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
class CoolRoof < OpenStudio::Measure::ModelMeasure
  # Human readable name
  def name
    return 'Cool Roof'
  end

  # Human readable description
  def description
    return 'Use a reflective roofing material to reduce thermal gain through the roof.'
  end

  # Human readable description of modeling approach
  def modeler_description
    return 'Loop through all roofs and set the reflectance and emissivity values to the user specified values.  The default values come from the LEED advanced energy modeling guide.'
  end

  # Define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Make integer arg to run measure [1 is run, 0 is no run]
    run_measure = OpenStudio::Measure::OSArgument.makeIntegerArgument('run_measure', true)
    run_measure.setDisplayName('Run Measure')
    run_measure.setDescription('integer argument to run measure [1 is run, 0 is no run]')
    run_measure.setDefaultValue(1)
    args << run_measure

    # From LEED Advanced Modeling Guide:
    # Cool roofs' (light-colored roof finishes that have low heat
    # absorption) may be modeled to show reduced heat gain.
    # Model proposed roof with solar reflectance greater than 0.70
    # and emittance greater than 0.75 with reflectivity of 0.45
    # (accounting for degradation in actual reflectivity) versus
    # default reflectivity value of 0.30.

    roof_thermal_emittance = OpenStudio::Measure::OSArgument.makeDoubleArgument('roof_thermal_emittance', true)
    roof_thermal_emittance.setDisplayName('Roof Emittance')
    roof_thermal_emittance.setDefaultValue(0.75)
    args << roof_thermal_emittance

    roof_solar_reflectance = OpenStudio::Measure::OSArgument.makeDoubleArgument('roof_solar_reflectance', true)
    roof_solar_reflectance.setDisplayName('Roof Solar Reflectance')
    roof_solar_reflectance.setDefaultValue(0.45)
    args << roof_solar_reflectance

    roof_visible_reflectance = OpenStudio::Measure::OSArgument.makeDoubleArgument('roof_visible_reflectance', true)
    roof_visible_reflectance.setDisplayName('Roof Visible Reflectance')
    roof_visible_reflectance.setDefaultValue(0.45)
    args << roof_visible_reflectance

    return args
  end

  # Define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Return N/A if not selected to run
    run_measure = runner.getIntegerArgumentValue('run_measure', user_arguments)
    if run_measure == 0
      runner.registerAsNotApplicable("Run Measure set to #{run_measure}.")
      return true
    end

    # Assign the user inputs to variables
    roof_thermal_emittance = runner.getDoubleArgumentValue('roof_thermal_emittance', user_arguments)
    roof_solar_reflectance = runner.getDoubleArgumentValue('roof_solar_reflectance', user_arguments)
    roof_visible_reflectance = runner.getDoubleArgumentValue('roof_visible_reflectance', user_arguments)

    # Translate the user inputs to model inputs
    # Thermal Absorptance: For long wavelength radiant exchange, thermal emissivity
    # and thermal emittance are equal to thermal absorptance.
    thermal_absorptance = roof_thermal_emittance
    # Solar Absorptance: equal to 1.0 minus reflectance (for opaque materials)
    solar_absorptance = 1.0 - roof_solar_reflectance
    # Visible Absorptance: equal to 1.0 minus reflectance
    visible_absorptance = 1.0 - roof_visible_reflectance

    # Loop through surfaces and modify the
    # exterior material of any roof construction
    materials_already_changed = []
    area_changed_si = 0
    model.getSurfaces.each do |surface|
      if surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'RoofCeiling'
        # Skip surfaces with no construction assigned
        next if surface.construction.empty?
        cons = surface.construction.get
        # Skip surfaces that don't use a layered construction
        next if cons.to_LayeredConstruction.empty?
        cons = cons.to_LayeredConstruction.get
        layers = cons.layers
        # Skip surfaces whose construction has no layers
        next if layers.empty?
        outside_material = layers[0]
        # Skip surfaces whose outside material isn't opaque
        next if outside_material.to_StandardOpaqueMaterial.empty?
        # Skip the material if it has already been updated
        next if materials_already_changed.include?(outside_material)
        # Update the material properties
        outside_material = outside_material.to_StandardOpaqueMaterial.get
        outside_material.setThermalAbsorptance(thermal_absorptance)
        outside_material.setSolarAbsorptance(solar_absorptance)
        outside_material.setVisibleAbsorptance(visible_absorptance)
        runner.registerInfo("Change the properties of #{outside_material.name} in #{cons.name} to reflect application of a cool roof.")
        materials_already_changed << outside_material

        area_changed_si += surface.grossArea
      end
    end

    # Convert from SI to IP units
    area_changed_ip = OpenStudio.convert(area_changed_si, 'm^2', 'ft^2').get

    # Summary
    runner.registerFinalCondition("For #{area_changed_ip.round(2)} ft^2 of roofing, the thermal absorptance was set to #{thermal_absorptance.round(2)}, solar absorptance was set to #{solar_absorptance.round(2)} and visible absorptance was set to #{visible_absorptance.round(2)}.")
    runner.registerValue('env_cool_roof_roof_area_ft2', area_changed_ip.round(2), 'ft2')

    return true
  end
end

# register the measure to be used by the application
CoolRoof.new.registerWithApplication
