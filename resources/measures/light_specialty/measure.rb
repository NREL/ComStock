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

# start the measure
class LightingSpecialty < OpenStudio::Measure::ModelMeasure
  # require 'openstudio-standards'

  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'Upgrade all specialty lights.'
  end

  # human readable description
  def description
    return 'Upgrade all specialty lights to user-specified efficiency level (low, medium, high, very high).'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Find the interior lighting template for the building, and assume the existing efficiency level in the model (low, medium, high, very high). Find the LPD and LPD fractions for each space type. Apply the lighting upgrades by reducing the LPD associated with specialty lighting by a percent (depends on starting and target efficiency levels).'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make choice argument for target_efficiency_level
    choices = OpenStudio::StringVector.new
    choices << 'Medium'
    choices << 'High'
    choices << 'Very High'
    target_efficiency_level = OpenStudio::Measure::OSArgument.makeChoiceArgument('target_efficiency_level', choices, true)
    target_efficiency_level.setDisplayName('Target Efficiency Level')
    args << target_efficiency_level

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # get arguments
    target_efficiency_level = runner.getStringArgumentValue('target_efficiency_level', user_arguments)

    # get interior lighting template for model to determine starting efficiency level
    properties = model.getBuilding.additionalProperties
    lighting_template = properties.getFeatureAsString('interior_lighting_template').to_s

    case lighting_template
    when 'DOE Ref Pre-1980', 'DOE Ref 1980-2004', '90.1-2004', 'ComStock DOE Ref Pre-1980', 'ComStock DOE Ref 1980-2004', 'ComStock 90.1-2004'
      starting_efficiency_level = 'Low'
      old_bulb_type = 'Incandescent Lamp (77W)'
      old_bulb_w = 77.0
    when '90.1-2007', '90.1-2010', 'ComStock 90.1-2007', 'ComStock 90.1-2010'
      starting_efficiency_level = 'Medium'
      old_bulb_type = 'Halogen Lamp (55W)'
      old_bulb_w = 55.0
    when '90.1-2013', 'ComStock 90.1-2013'
      starting_efficiency_level = 'High'
      old_bulb_type = 'CFL Lamp (24W)'
      old_bulb_w = 24.0
    else
      runner.registerError("interior_lighting_template '#{lighting_template}' not recognized")
      return false
    end

    runner.registerInitialCondition("Starting efficiency level is '#{starting_efficiency_level}' and target efficiency level is '#{target_efficiency_level}'.")

    # determine if the target efficiency level exceeds the starting efficiency level
    case target_efficiency_level
    when 'Medium'
      new_bulb_type = 'Halogen Lamp (55W)'
      new_bulb_w = 55.0
    when 'High'
      new_bulb_type = 'CFL Lamp (24W)'
      new_bulb_w = 24.0
    when 'Very High'
      new_bulb_type = 'LED Lamp (18W)'
      new_bulb_w = 18.0
    end

    if old_bulb_w <= new_bulb_w
      runner.registerAsNotApplicable("The target efficiency level '#{target_efficiency_level}' is the same or lower than the starting efficiency level '#{starting_efficiency_level}' in the model. Lighting upgrade is not applicable.")
      return false
    end
    runner.registerInitialCondition("Starting efficiency level is '#{starting_efficiency_level}' and target efficiency level is '#{target_efficiency_level}'.")

    # make variable to track total number of fixtures changed when looping through space types
    total_num_fixtures_changed = 0

    # loop through space types and get LPD and LPD fractions
    model.getSpaceTypes.each do |space_type|
      # get space_type floor area and number of people
      floor_area = space_type.floorArea
      num_people = space_type.getNumberOfPeople(floor_area)

      if space_type.lights.size > 1
        runner.registerWarning("Space type '#{space_type.name}' has more than one lights object. LPD adjustment may be inaccurate.")
      end

      space_type.lights.each do |light|
        # get starting lpd for space type and convert to W/ft^2
        lpd_w_per_m2 = light.getPowerPerFloorArea(floor_area, num_people)
        lpd_w_per_ft2 = OpenStudio.convert(lpd_w_per_m2, 'W/m^2', 'W/ft^2').get

        # get LPD fractions from openstudio-standards
        lights_definition = light.lightsDefinition
        lpd_fraction_linear_fluorescent = lights_definition.additionalProperties.getFeatureAsDouble('lpd_fraction_linear_fluorescent')
        lpd_fraction_compact_fluorescent = lights_definition.additionalProperties.getFeatureAsDouble('lpd_fraction_compact_fluorescent')
        lpd_fraction_high_bay = lights_definition.additionalProperties.getFeatureAsDouble('lpd_fraction_high_bay')
        lpd_fraction_specialty_lighting = lights_definition.additionalProperties.getFeatureAsDouble('lpd_fraction_specialty_lighting')
        lpd_fraction_exit_lighting = lights_definition.additionalProperties.getFeatureAsDouble('lpd_fraction_exit_lighting')

        # all light definitions should have a linear fluorescent fraction
        unless lpd_fraction_linear_fluorescent.is_initialized
          runner.registerError("Lights definition '#{lights_definition.name}' is missing lighting type fractions in additional properties.")
          return false
        end

        # skip if light definition does not include specialty lighting
        unless lpd_fraction_specialty_lighting.is_initialized
          runner.registerWarning("Lights definition '#{lights_definition.name}' is missing specialty lighting fraction in additional properties.")
          next
        end

        compact_lpd = 0
        high_bay_lpd = 0
        specialty_lpd = 0
        exit_lpd = 0
        linear_frac = lights_definition.additionalProperties.getFeatureAsDouble('lpd_fraction_linear_fluorescent').get
        linear_lpd = linear_frac * lpd_w_per_ft2
        if lpd_fraction_compact_fluorescent.is_initialized
          compact_frac = lights_definition.additionalProperties.getFeatureAsDouble('lpd_fraction_compact_fluorescent').get
          compact_lpd = compact_frac * lpd_w_per_ft2
        end
        if lpd_fraction_high_bay.is_initialized
          high_bay_frac = lights_definition.additionalProperties.getFeatureAsDouble('lpd_fraction_high_bay').get
          high_bay_lpd = high_bay_frac * lpd_w_per_ft2
        end
        if lpd_fraction_specialty_lighting.is_initialized
          specialty_frac = lights_definition.additionalProperties.getFeatureAsDouble('lpd_fraction_specialty_lighting').get
          specialty_lpd = specialty_frac * lpd_w_per_ft2
        end
        if lpd_fraction_exit_lighting.is_initialized
          exit_frac = lights_definition.additionalProperties.getFeatureAsDouble('lpd_fraction_exit_lighting').get
          exit_lpd = exit_frac * lpd_w_per_ft2
        end

        # calculate high bay lighting power and new lpd
        lighting_power_w = lpd_w_per_m2 * floor_area * specialty_frac
        num_fixtures = (lighting_power_w / old_bulb_w).ceil
        total_num_fixtures_changed += num_fixtures
        reduction_fraction = (old_bulb_w - new_bulb_w) / old_bulb_w
        new_specialty_lpd = specialty_lpd * (1 - reduction_fraction)

        # calculate new total lpd and new lpd fractions
        new_lpd_w_per_ft2 = linear_lpd + compact_lpd + high_bay_lpd + new_specialty_lpd + exit_lpd
        new_lpd_w_per_m2 = OpenStudio.convert(new_lpd_w_per_ft2, 'W/ft^2', 'W/m^2').get
        lights_definition.setWattsperSpaceFloorArea(new_lpd_w_per_m2)
        lights_definition.additionalProperties.setFeature('lpd_fraction_linear_fluorescent', linear_lpd / new_lpd_w_per_ft2)
        lights_definition.additionalProperties.setFeature('lpd_fraction_compact_fluorescent', compact_lpd / new_lpd_w_per_ft2)
        lights_definition.additionalProperties.setFeature('lpd_fraction_high_bay', high_bay_lpd / new_lpd_w_per_ft2)
        lights_definition.additionalProperties.setFeature('lpd_fraction_specialty_lighting', new_specialty_lpd / new_lpd_w_per_ft2)
        lights_definition.additionalProperties.setFeature('lpd_fraction_exit_lighting', exit_lpd / new_lpd_w_per_ft2)
        runner.registerInfo("For lights '#{light.name}' in space type #{space_type.name}, #{num_fixtures} specialty fixtures comprising #{linear_frac.round(2)} of the LPD changed from #{old_bulb_type} to #{new_bulb_type}. The LPD for the lights reduced from #{lpd_w_per_ft2.round(2)} W/ft^2 to #{new_lpd_w_per_ft2.round(2)} W/ft^2.")
      end
    end

    runner.registerValue('light_specialty_num_fixtures_changed', total_num_fixtures_changed)
    runner.registerFinalCondition("A total of #{total_num_fixtures_changed} specialty lamps were upgraded.")
  end
end
LightingSpecialty.new.registerWithApplication
