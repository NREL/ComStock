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
class EnvRoofInsul < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # measure name should be the title case of the class name.
    return 'env_roof_insul'
  end

  # human readable description
  def description
    return 'Increases insulation R-value of roofs to R-XX (code) and R-XX (efficient)'
  end

  # human readable description of modeling approach
  def modeler_description
    return
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new
    # make an argument for insulation R-value
    r_val = OpenStudio::Measure::OSArgument.makeDoubleArgument('r_val', true)
    r_val.setDisplayName('Roof Insulation R-value')
    r_val.setUnits('ft^2*h*R/Btu')
    r_val.setDefaultValue(30.0)
    args << r_val
    # make bool argument to allow for change in R-value
    allow_reduct = OpenStudio::Measure::OSArgument.makeBoolArgument('allow_reduct', true)
    allow_reduct.setDisplayName('Allow both increase and decrease in R-value to reach requested target')
    allow_reduct.setDefaultValue(false)
    args << allow_reduct
    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    r_val = runner.getDoubleArgumentValue('r_val', user_arguments)
    allow_reduct = runner.getBoolArgumentValue('allow_reduct', user_arguments)

    # set limit for minimum insulation in IP units -- this is used to limit input and for inferring insulation layer in construction
    min_exp_r_val_ip = 1.0

    # check the R-value for reasonableness
    if (r_val < 0) || (r_val > 500)
      runner.registerError("The requested roof insulation R-value of #{r_val.round(2)} ft2-h-R/Btu was outside the measurable limit")
      return false
    elsif r_val > 100
      runner.registerWarning("The requested roof insulation R-value of #{r_val.round(2)} ft2-h-R/Btu is abnormally high")
    elsif r_val < min_exp_r_val_ip
      runner.registerWarning("The requested roof insulation R-value of #{r_val.round(2)} ft2-h-R/Btu is abnormally low")
    end

    # convert R-value to SI for future use
    r_val_si = OpenStudio.convert(r_val, 'ft^2*h*R/Btu', 'm^2*K/W').get

    # create an array of roofs and find range of starting construction R-value (not just insulation layer)
    ext_surfs = []
    ext_surf_consts = []
    ext_surf_const_names = []
    roof_resist = []
    model.getSurfaces.each do |surface|
      next unless (surface.outsideBoundaryCondition == 'Outdoors') && (surface.surfaceType == 'RoofCeiling')
      ext_surfs << surface
      roof_const = surface.construction.get
      # only add construction if it hasn't been added yet
      ext_surf_consts << roof_const.to_Construction.get unless ext_surf_const_names.include?(roof_const.name.to_s)
      ext_surf_const_names << roof_const.name.to_s
      roof_resist << 1 / roof_const.thermalConductance.to_f
    end

    # nothing will be done if there are no exterior surfaces
    if ext_surfs.empty?
      runner.registerAsNotApplicable('The building has no roofs.')
      return false
    end

    # report strings for initial condition
    init_str = []
    ext_surf_consts.uniq.each do |ext_surf_const|
      # unit conversion of roof insulation from SI units (m2-K/W) to IP units (ft2-h-R/Btu)
      init_r_val_ip = OpenStudio.convert(1 / ext_surf_const.thermalConductance.to_f, 'm^2*K/W', 'ft^2*h*R/Btu').get
      init_str << "#{ext_surf_const.name} (R-#{(format '%.1f', init_r_val_ip)})"
    end

    # register initial condition
    runner.registerInitialCondition("The building had #{init_str.size} roof constructions: #{init_str.sort.join(', ')}")

    # hashes to track constructions and materials made by the measure, to avoid duplicates
    consts_old_new = {}

    # used to get net area of new construction
    consts_new_old = {}
    matls_hash = {}

    # array and counter for new constructions that are made, used for reporting final condition
    final_consts = []

    # loop through all constructions and materials used on roofs, edit and clone
    ext_surf_consts.each do |ext_surf_const|
      matls_in_const = ext_surf_const.layers.map.with_index { |l, i| { 'name' => l.name.to_s, 'index' => i, 'nomass' => !l.to_MasslessOpaqueMaterial.empty?, 'r_val' => l.to_OpaqueMaterial.get.thermalResistance, 'matl' => l } }
      no_mass_matls = matls_in_const.select { |m| m['nomass'] == true }

      # measure will select the no-mass material with the highest R-value as the insulation layer -- if no no-mass materials are present, the measure will select the material with the highest R-value per inch
      if !no_mass_matls.empty?
        r_vals = no_mass_matls.map { |m| m['r_val'] }
        max_matl_hash = no_mass_matls.select { |m| m['r_val'] >= r_vals.max }
      else
        r_val_per_thick_vals = matls_in_const.map { |m| m['r_val'] / m['mat'].thickness }
        max_matl_hash = matls_in_const.select { |m| m['index'] == r_val_per_thick_vals.index(r_val_per_thick_vals.max) }
        r_vals = matls_in_const.map { |m| m['r_val'] }
      end
      max_r_val_matl = max_matl_hash[0]['matl']
      max_r_val_matl_idx = max_matl_hash[0]['index']
      if max_r_val_matl.to_OpaqueMaterial.get.thermalResistance <= OpenStudio.convert(min_exp_r_val_ip, 'ft^2*h*R/Btu', 'm^2*K/W').get
        runner.registerWarning("Construction '#{ext_surf_const.name}' does not appear to have an insulation layer and was not altered")
      elsif (max_r_val_matl.to_OpaqueMaterial.get.thermalResistance >= r_val_si) && !allow_reduct
        runner.registerInfo("The insulation layer of construction #{ext_surf_const.name} exceeds the requested R-value and was not altered")
      else

        # clone the construction
        final_const = ext_surf_const.clone(model).to_Construction.get
        final_const.setName("#{ext_surf_const.name} Added Roof Insul")
        final_consts << final_const

        # push to hashes
        consts_old_new[ext_surf_const.name.to_s] = final_const
        # push the object to hash key v. name
        consts_new_old[final_const] = ext_surf_const

        # find already cloned insulation material and link to construction
        found_matl = false
        matls_hash.each do |orig, new|
          if max_r_val_matl.name.to_s == orig
            new_matl = new
            matls_hash[max_r_val_matl.name.to_s] = new_matl
            final_const.eraseLayer(max_r_val_matl_idx)
            final_const.insertLayer(max_r_val_matl_idx, new_matl)
            found_matl = true
          end
        end

        # clone and edit insulation material and link to construction
        if found_matl == false
          new_matl = max_r_val_matl.clone(model).to_OpaqueMaterial.get
          new_matl.setName("#{max_r_val_matl.name}_R-value #{r_val} (ft^2*h*R/Btu)")
          matls_hash[max_r_val_matl.name.to_s] = new_matl
          final_const.eraseLayer(max_r_val_matl_idx)
          final_const.insertLayer(max_r_val_matl_idx, new_matl)

          # edit insulation material
          new_matl_reg = new_matl.to_Material
          new_matl_reg.get.setThickness(new_matl_reg.get.thickness * r_val_si / r_vals.max) unless new_matl_reg.empty?
          new_nomass_matl = new_matl.to_MasslessOpaqueMaterial
          final_r_val = new_nomass_matl.get.setThermalResistance(r_val_si) unless new_nomass_matl.empty?
          new_airgap_matl = new_matl.to_AirGap
          final_r_val = new_airgap_matl.get.setThermalResistance(r_val_si) unless new_airgap_matl.empty?
        end
      end
    end

    # loop through construction sets used in the model
    default_const_sets = model.getDefaultConstructionSets
    default_const_sets.each do |default_const_set|
      if default_const_set.directUseCount > 0
        default_surf_const_set = default_const_set.defaultExteriorSurfaceConstructions
        if !default_surf_const_set.empty?
          start_const = default_surf_const_set.get.roofCeilingConstruction

          # creating new default construction set
          new_default_const_set = default_const_set.clone(model)
          new_default_const_set = new_default_const_set.to_DefaultConstructionSet.get
          new_default_const_set.setName("#{default_const_set.name} Added Roof Insul")

          # create new surface set and link to construction set
          new_default_surf_const_set = default_surf_const_set.get.clone(model)
          new_default_surf_const_set = new_default_surf_const_set.to_DefaultSurfaceConstructions.get
          new_default_surf_const_set.setName("#{default_surf_const_set.get.name} Added Roof Insul")
          new_default_const_set.setDefaultExteriorSurfaceConstructions(new_default_surf_const_set)

          # use the hash to find the proper construction and link to the new default surface construction set
          target_const = new_default_surf_const_set.roofCeilingConstruction
          if !target_const.empty?
            target_const = target_const.get.name.to_s
            found_const_flag = false
            consts_old_new.each do |orig, new|
              if target_const == orig
                final_const = new
                new_default_surf_const_set.setRoofCeilingConstruction(final_const)
                found_const_flag = true
              end
            end
            # this should never happen but is just an extra test in case something goes wrong with the measure code
            runner.registerWarning("Measure couldn't find the roof construction named '#{target_const}' assigned to any exterior surfaces") if found_const_flag == false
          end

          # swap all uses of the old construction set for the new
          const_set_srcs = default_const_set.sources
          const_set_srcs.each do |const_set_src|
            bldg_src = const_set_src.to_Building

            # if statement for each type of object that can use a DefaultConstructionSet
            if !bldg_src.empty?
              bldg_src = bldg_src.get
              bldg_src.setDefaultConstructionSet(new_default_const_set)
            end
            bldg_story_src = const_set_src.to_BuildingStory
            if !bldg_story_src.empty?
              bldg_story_src = bldg_story_src.get
              bldg_story_src.setDefaultConstructionSet(new_default_const_set)
            end
            space_type_src = const_set_src.to_SpaceType
            if !bldg_story_src.empty?
              bldg_story_src = bldg_story_src.get
              bldg_story_src.setDefaultConstructionSet(new_default_const_set)
            end
            space_src = const_set_src.to_Space
            if !space_src.empty?
              space_src = space_src.get
              space_src.setDefaultConstructionSet(new_default_const_set)
            end
          end
        end
      end
    end

    # link cloned and edited constructions for surfaces with hard assigned constructions
    ext_surfs.each do |ext_surf|
      if !ext_surf.isConstructionDefaulted && !ext_surf.construction.empty?
        # use the hash to find the proper construction and link to surface
        target_const = ext_surf.construction
        if !target_const.empty?
          target_const = target_const.get.name.to_s
          consts_old_new.each do |orig, new|
            if target_const == orig
              final_const = new
              ext_surf.setConstruction(final_const)
            end
          end
        end
      end
    end

    # report strings for final condition, not all roof constructions, but only new ones made -- if roof didn't have insulation and was not altered we don't want to show it
    final_str = []
    area_changed_si = 0
    final_consts.uniq.each do |final_const|
      # unit conversion of roof insulation from SI units (M^2*K/W) to IP units (ft^2*h*R/Btu)
      final_r_val_ip = OpenStudio.convert(1.0 / final_const.thermalConductance.to_f, 'm^2*K/W', 'ft^2*h*R/Btu').get
      final_str << "#{final_const.name} (R-#{(format '%.1f', final_r_val_ip)})"
      area_changed_si += final_const.getNetArea
    end

    # add not applicable test if there were roof constructions but non of them were altered (already enough insulation or doesn't look like insulated roof)
    if area_changed_si == 0
      runner.registerAsNotApplicable('No roofs were altered')
      return false
    else
      # IP construction area for reporting
      area_changed_ip = OpenStudio.convert(area_changed_si, 'm^2', 'ft^2').get
    end

    # summary
    runner.registerFinalCondition("The insulation for roofs was set to R-#{r_val} -- this was applied to #{area_changed_ip.round(2)} ft2 across #{final_str.size} roof constructions: #{final_str.sort.join(', ')}")
    runner.registerValue('env_roof_insul_roof_area_ft2', area_changed_ip.round(2), 'ft2')
    return true
  end
end

# register the measure to be used by the application
EnvRoofInsul.new.registerWithApplication
