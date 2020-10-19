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
class EIFSWallInsulation < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'EIFS Wall Insulation'
  end

  # human readable description
  def description
    return 'EIFS is a layer of insulation that is applied to the outside walls of a building.  It is typically a layer of foam insulation covered by a thin layer of fiber mesh embedded in polymer.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Determine the thickness of expanded polystyrene insulation required to meet the specified R-value.  Find all the constructions used by exterior walls in the model, clone them, add a layer of insulation to the cloned constructions, and then assign the construction back to the wall.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Make integer arg to run measure [1 is run, 0 is no run]
    run_measure = OpenStudio::Measure::OSArgument.makeIntegerArgument('run_measure', true)
    run_measure.setDisplayName('Run Measure')
    run_measure.setDescription('integer argument to run measure [1 is run, 0 is no run]')
    run_measure.setDefaultValue(1)
    args << run_measure

    # Make an argument for insulation R-value
    r_val_ip = OpenStudio::Measure::OSArgument.makeDoubleArgument('r_val_ip', true)
    r_val_ip.setDisplayName('Insulation R-value')
    r_val_ip.setUnits('ft^2*h*R/Btu')
    r_val_ip.setDefaultValue(30.0)
    args << r_val_ip

    return args
  end

  # define what happens when the measure is run
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

    r_val_ip = runner.getDoubleArgumentValue('r_val_ip', user_arguments)

    # Check the r_val_ip for reasonableness
    if r_val_ip <= 0
      runner.registerError("R-value must be greater than 0.  You entered #{r_val_ip}.")
      return false
    end

    # Convert r_val_ip to si
    r_val_si = OpenStudio.convert(r_val_ip, 'ft^2*h*R/Btu', 'm^2*K/W').get

    # Create a material for Expanded Polystyrene - Molded Beads
    # https://bcl.nrel.gov/node/34582
    # Expanded Polystyrene - Molded Beads - 1 in.,  ! Name
    # VeryRough,                ! Roughness
    # 0.0254,                   ! Thickness {m}
    # 0.0352,                   ! Conductivity {W/m-K}
    # 24,                       ! Density {kg/m3}
    # 1210,                     ! Specific Heat {J/kg-K}
    ins_layer = OpenStudio::Model::StandardOpaqueMaterial.new(model)
    ins_layer.setRoughness('VeryRough')
    ins_layer.setConductivity(0.0352)
    ins_layer.setDensity(24.0)
    ins_layer.setSpecificHeat(1210.0)

    # Calculate the thickness required to meet the desired R-Value
    reqd_thickness_si = r_val_si * ins_layer.thermalConductivity
    reqd_thickness_ip = OpenStudio.convert(reqd_thickness_si, 'm', 'in').get
    ins_layer.setThickness(reqd_thickness_si)
    ins_layer.setName("Expanded Polystyrene - Molded Beads - #{reqd_thickness_ip.round(1)} in.")
    runner.registerInfo("To achieve an R-Value of #{r_val_ip.round(2)} you need #{ins_layer.name} insulation.")

    # Find all exterior walls and get a list of their constructions
    wall_constructions = []
    model.getSurfaces.each do |surface|
      if surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'Wall'
        if surface.construction.is_initialized
          wall_constructions << surface.construction.get
        end
      end
    end

    # Make clones of all the wall constructions used and the add
    # insulation layer to these new constructions.
    old_to_new_construction_map = {}
    wall_constructions.uniq.each do |wall_construction|
      wall_construction_plus_ins = wall_construction.clone(model).to_Construction.get
      wall_construction_plus_ins.insertLayer(0, ins_layer)
      old_to_new_construction_map[wall_construction] = wall_construction_plus_ins
    end

    # Find all exterior walls and replace their old constructions with the
    # cloned constructions that include the insulation layer.
    area_of_insulation_added_si = 0
    model.getSurfaces.each do |surface|
      if surface.outsideBoundaryCondition == 'Outdoors' && surface.surfaceType == 'Wall'
        if surface.construction.is_initialized
          wall_construction = surface.construction.get
          wall_construction_plus_ins = old_to_new_construction_map[wall_construction]
          surface.setConstruction(wall_construction_plus_ins)
          area_of_insulation_added_si += surface.netArea
        end
      end
    end

    # This measure is not applicable if there are no exterior walls
    if area_of_insulation_added_si == 0
      runner.registerAsNotApplicable('Not Applicable - Model does not have any exterior walls to add EIFS insulation to.')
      return true
    end

    # Convert affected area to ft^2 for reporting
    area_of_insulation_added_ip = OpenStudio.convert(area_of_insulation_added_si, 'm^2', 'ft^2').get

    # Report the initial condition
    runner.registerInitialCondition("The building has #{area_of_insulation_added_ip.round(2)} ft2 of exterior walls.")

    # Report the final condition
    runner.registerFinalCondition("#{ins_layer.name} insulation has been applied to #{area_of_insulation_added_ip.round} ft2 of exterior walls.")
    runner.registerValue('env_wall_eifs_area_ft2', area_of_insulation_added_ip.round(2), 'ft2')
    return true
  end
end

# register the measure to be used by the application
EIFSWallInsulation.new.registerWithApplication
