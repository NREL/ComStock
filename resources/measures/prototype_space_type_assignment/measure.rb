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

require 'csv'

# start the measure
class PrototypeSpaceTypeAssignment < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'Prototype Space Type Assignment'
  end

  # human readable description
  def description
    return 'This measure adds prototype space type information to space types based on the original standards building type and standards space type fields.'
  end

  # human readable description of modeling approach
  def modeler_description
    return "This measure adds a 'prototype_space_type' additional properties to the OS:SpaceType object for each space type based on a lookup by the 'standardsBuildingType' and 'standardsSpaceType' fields."
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

    # load lookup file and convert to hash table
    prototype_space_type_lookup_csv = "#{File.dirname(__FILE__)}/resources/prototype_space_type_lookup.csv"
    if !File.file?(prototype_space_type_lookup_csv)
      runner.registerError("Unable to find file: #{prototype_space_type_lookup_csv}")
      return nil
    end
    prototype_space_type_lookup = CSV.table(prototype_space_type_lookup_csv)
    prototype_space_type_lookup_hsh = prototype_space_type_lookup.map(&:to_hash)

    # load space type properties lookup
    prototype_space_type_properties_lookup_csv = "#{File.dirname(__FILE__)}/resources/prototype_space_type_properties_lookup.csv"
    if !File.file?(prototype_space_type_properties_lookup_csv)
      runner.registerError("Unable to find file: #{prototype_space_type_properties_lookup_csv}")
      return nil
    end
    prototype_space_type_properties_lookup = CSV.table(prototype_space_type_properties_lookup_csv)
    prototype_space_type_properties_lookup_hsh = prototype_space_type_properties_lookup.map(&:to_hash)

    # model get standards space types
    model.getSpaceTypes.each do |space_type|
      next unless space_type.standardsBuildingType.is_initialized
      next unless space_type.standardsSpaceType.is_initialized

      standards_building_type = space_type.standardsBuildingType.get
      standards_space_type = space_type.standardsSpaceType.get

      # lookup prototype space type
      row = prototype_space_type_lookup_hsh.select { |r| (r[:building_type] == standards_building_type) && (r[:space_type] == standards_space_type) }
      if row.empty?
        runner.registerError("Unable to find prototype space type for original standards type '#{standards_building_type} - #{standards_space_type}'")
        break
      end
      prototype_space_type = row[0][:prototype_space_type]

      # set prototype space type to additional properties
      space_type.additionalProperties.setFeature('prototype_space_type', prototype_space_type)
      runner.registerInfo("Set space type '#{space_type.name}' with original standards type '#{standards_building_type} - #{standards_space_type}' to prototype space type '#{prototype_space_type}'.")

      # set prototype space type properties to additional properties
      row = prototype_space_type_properties_lookup_hsh.select { |r| (r[:prototype_space_type] == prototype_space_type) }
      if row.empty?
        runner.registerError("Unable to find prototype space type properties for '#{prototype_space_type}'")
        break
      end
      prototype_space_type_properties = row[0]

      # set prototype space type properties
      prototype_lighting_space_type = prototype_space_type_properties[:prototype_lighting_space_type]
      space_type.additionalProperties.setFeature('prototype_lighting_space_type', prototype_lighting_space_type)
      runner.registerInfo("Set prototype lighting space type '#{prototype_lighting_space_type}' to prototype space type '#{prototype_space_type}'.")
    end

    return true
  end
end

# register the measure to be used by the application
PrototypeSpaceTypeAssignment.new.registerWithApplication
