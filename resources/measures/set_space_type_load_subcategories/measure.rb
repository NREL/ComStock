# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
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

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class SetSpaceTypeLoadSubcategories < OpenStudio::Measure::ModelMeasure

  # human readable name
  def name
    return "Set Space Type Load Subcategories"
  end

  # human readable description
  def description
    return "This measure sets subcategory names for internal lighting and equipment loads in a standards space type."
  end

  # human readable description of modeling approach
  def modeler_description
    return "This measure takes the user selected standards space type and sets the interior lighting and equipment load definitions subcategory to match the space type name. "
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

    # can be user input argument in future
    space_type_selected = 'ResPublicArea'
    skip_end_use = 'Elevator'

    # model get standards space types
    model.getSpaceTypes.each do |space_type|
      next unless space_type.standardsSpaceType.is_initialized
      standards_space_type = space_type.standardsSpaceType.get
      next unless standards_space_type == space_type_selected
      runner.registerInfo("Setting lights and equipment to end use subcategory for space type '#{space_type.name}' with standards type '#{space_type_selected}'.")
      space_type.lights.each do |light|
        unless light.endUseSubcategory.include? skip_end_use
          light.setEndUseSubcategory(space_type_selected)
        end
      end
      space_type.electricEquipment.each do |equip|
        unless equip.endUseSubcategory.include? skip_end_use
          equip.setEndUseSubcategory(space_type_selected)
        end
      end
    end

    # check individual spaces and set loads
    model.getSpaces.each do |space|
      next unless space.spaceType.is_initialized
      space_type = space.spaceType.get
      next unless space_type.standardsSpaceType.is_initialized
      standards_space_type = space_type.standardsSpaceType.get
      next unless standards_space_type == space_type_selected
      runner.registerInfo("Space '#{space.name}' has standards type '#{space_type_selected}'. Setting lights and equipment to end use subcategory.")
      space.lights.each do |light|
        unless light.endUseSubcategory.include? skip_end_use
          light.setEndUseSubcategory(space_type_selected)
        end
      end
      space.electricEquipment.each do |equip|
        unless equip.endUseSubcategory.include? skip_end_use
          equip.setEndUseSubcategory(space_type_selected)
        end
      end
    end

    # Report final condition of model
    return true
  end
end

# register the measure to be used by the application
SetSpaceTypeLoadSubcategories.new.registerWithApplication
