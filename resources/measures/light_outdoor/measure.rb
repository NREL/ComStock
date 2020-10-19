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
class LightingOutdoor < OpenStudio::Measure::ModelMeasure
  # require 'openstudio-standards'

  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    return 'Upgrade all exterior lights.'
  end

  # human readable description
  def description
    return 'Upgrade all exterior lights to user-specified efficiency level (medium, high).'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Find the exterior lighting template for the building, and assume the existing efficiency level in the model (low, medium, high). Find the desing level and multiplier for each category of the exterior lighting definition. Apply the lighting upgrades by reducing the design level associated with each outdoor lighting category by a percent (depends on starting and target efficiency levels).'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make choice argument for target_efficiency_level
    choices = OpenStudio::StringVector.new
    choices << 'Medium'
    choices << 'High'
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
    ext_lighting_template = properties.getFeatureAsString('exterior_lighting_template').to_s

    case ext_lighting_template
    when 'DOE Ref Pre-1980', 'DOE Ref 1980-2004', 'ComStock DOE Ref Pre-1980', 'ComStock DOE Ref 1980-2004'
      starting_efficiency_level = 'Very Low'
      old_large_fixture_type = 'Metal Halide Fixture (458W)'
      old_large_fixture_w = 458.0
      old_small_fixture_type = 'Incandescent Fixture (114W)'
      old_small_fixture_w = 114.0
    when '90.1-2004', '90.1-2007', 'ComStock 90.1-2004', 'ComStock 90.1-2007'
      starting_efficiency_level = 'Low'
      old_large_fixture_type = 'Metal Halide Fixture (458W)'
      old_large_fixture_w = 458.0
      old_small_fixture_type = 'Halogen Fixture (82W)'
      old_small_fixture_w = 82.0
    when '90.1-2010', '90.1-2013', 'ComStock 90.1-2010', 'ComStock 90.1-2013'
      starting_efficiency_level = 'Medium'
      old_large_fixture_type = 'Pulse Start Metal Halide Fixture (365W)'
      old_large_fixture_w = 365.0
      old_small_fixture_type = 'CFL Fixture (28W)'
      old_small_fixture_w = 28.0
    else
      runner.registerError("interior_lighting_template '#{ext_lighting_template}' not recognized")
      return false
    end

    runner.registerInitialCondition("Starting efficiency level is '#{starting_efficiency_level}' and target efficiency level is '#{target_efficiency_level}'.")

    # determine if the target efficiency level exceeds the starting efficiency level
    case target_efficiency_level
    when 'Medium'
      new_large_fixture_type = 'Pulse Start Metal Halide Fixture (365W)'
      new_large_fixture_w = 365.0
      new_small_fixture_type = 'CFL Fixture (28W)'
      new_small_fixture_w = 28.0
    when 'High'
      new_large_fixture_type = 'LED Fixture (220W)'
      new_large_fixture_w = 220.0
      new_small_fixture_type = 'LED Fixture (20W)'
      new_small_fixture_w = 20.0
    end

    if old_small_fixture_w <= new_small_fixture_w
      runner.registerAsNotApplicable("The target efficiency level '#{target_efficiency_level}' is the same or lower than the starting efficiency level '#{starting_efficiency_level}' in the model. Lighting upgrade is not applicable.")
      return false
    end
    runner.registerInitialCondition("Starting efficiency level is '#{starting_efficiency_level}' and target efficiency level is '#{target_efficiency_level}'.")

    # make variable to track total number of fixtures changed when looping through space types
    total_num_large_fixtures_changed = 0
    total_num_small_fixtures_changed = 0

    # loop through exterior lights definitions and get design level and multiplier
    model.getFacility.exteriorLights.each do |ext_lights|
      old_design_level = ext_lights.exteriorLightsDefinition.designLevel
      multiplier = ext_lights.multiplier
      next if multiplier.zero?
      lighting_power_w = old_design_level * multiplier

      # determine old and new bulbs by separate exterior lighting categories by units
      if ['Parking Areas and Drives'].include?(ext_lights.name.to_s)
        old_fixture_type = old_large_fixture_type
        old_fixture_w = old_large_fixture_w
        new_fixture_type = new_large_fixture_type
        new_fixture_w = new_large_fixture_w
        fixture_class = 'large'
      elsif ['Building Facades', 'Entry Canopies', 'Emergency Canopies', 'Main Entries', 'Other Doors', 'Drive Through Windows'].include?(ext_lights.name.to_s)
        old_fixture_type = old_small_fixture_type
        old_fixture_w = old_small_fixture_w
        new_fixture_type = new_small_fixture_type
        new_fixture_w = new_small_fixture_w
        fixture_class = 'small'
      else
        runner.registerWarning("Exterior lights '#{ext_lights.name}' is not a recognized exterior lighting type.  Cannot determine if large or small fixture.")
        next
      end

      # calculate power reduction
      num_fixtures = (lighting_power_w / old_fixture_w).ceil
      total_num_large_fixtures_changed += num_fixtures if fixture_class == 'large'
      total_num_small_fixtures_changed += num_fixtures if fixture_class == 'small'
      reduction_fraction = (old_fixture_w - new_fixture_w) / old_fixture_w
      new_design_level = old_design_level * (1 - reduction_fraction)
      ext_lights.exteriorLightsDefinition.setDesignLevel(new_design_level)
      runner.registerInfo("For '#{ext_lights.name}' exterior lighting, #{num_fixtures} fixtures were changed from #{old_fixture_type} to #{new_fixture_type}. The exterior lighting design level for #{ext_lights.name} was reduced from #{old_design_level.round(4)} to #{new_design_level.round(4)}.")
    end

    runner.registerValue('light_outdoor_num_large_fixtures_changed', total_num_large_fixtures_changed)
    runner.registerValue('light_outdoor_num_small_fixtures_changed', total_num_small_fixtures_changed)
    runner.registerFinalCondition("A total of #{total_num_large_fixtures_changed} large and #{total_num_small_fixtures_changed} small outdoor fixtures and were upgraded.")
  end
end
LightingOutdoor.new.registerWithApplication
