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
class EnvWindowFilm < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # measure name should be the title case of the class name.
    return 'env_window_film'
  end

  # human readable description
  def description
    return 'Adds window film to existing windows. Assumes window film reduces SHGC by 53.5% and VLT by 53%. These numbers are average values from Table 4 in Bahadori-Jahromi, Rotimi, Mylona, Godfrey, and Cook (2017). Sustainability, 9(5), 731; https://doi.org/10.3390/su9050731. The SHGC reduction is averaged from the second to last column (Heat Gain Reduction [%]) and the VLT reduction is averaged from the last column (Glare Reduction [%]).'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'First gets all building detailed fenestration surfaces. Loops over all detailed fenestration surfaces and checks to see if the surface type is a window. If the surface type is a window then it gets the then get the construction name. With the construction name it determines the simple glazing system object name. With the simple glazing system object name it decreases the SHGC by 53.5% and the VLT by 53%.'
  end

  # define the arguments that the user will input
  def arguments(model)
    # make an argument vector
    args = OpenStudio::Measure::OSArgumentVector.new

    # make an argument for percent window SHGC reduction
    pct_shgc_reduct = OpenStudio::Measure::OSArgument.makeDoubleArgument('pct_shgc_reduct', true)
    pct_shgc_reduct.setDisplayName('Percent SHGC Reduction')
    pct_shgc_reduct.setDefaultValue(0.535)
    args << pct_shgc_reduct

    # make an argument for percent window VLT reduction
    pct_vlt_reduct = OpenStudio::Measure::OSArgument.makeDoubleArgument('pct_vlt_reduct', true)
    pct_vlt_reduct.setDisplayName('Percent VLT Reduction')
    pct_vlt_reduct.setDefaultValue(0.53)
    args << pct_vlt_reduct

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
    # key = old const, value = new const
    new_construction_hash = {}

    # assign the user inputs to variables
    pct_shgc_reduct = runner.getDoubleArgumentValue('pct_shgc_reduct', user_arguments)
    pct_vlt_reduct = runner.getDoubleArgumentValue('pct_vlt_reduct', user_arguments)

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

    # apply shgc and vlt reductions to objects
    area_changed_m2 = 0
    constructions.each do |construction|
      simple_glazings.each do |simple_glazing|
        # check if construction layer name matches simple glazing name
        next unless construction.to_Construction.get.layers[0].name.get == simple_glazing.name.get

        # get old values
        old_simple_glazing_u = simple_glazing.uFactor
        old_simple_glazing_shgc = simple_glazing.solarHeatGainCoefficient
        old_simple_glazing_vlt = simple_glazing.visibleTransmittance.get

        # register initial condition
        runner.registerInfo("Existing window #{simple_glazing.name.get} has #{old_simple_glazing_u.round(2)} W/m2-K U-value , #{old_simple_glazing_shgc} SHGC, and #{old_simple_glazing_vlt} VLT.")

        # calculate new values
        new_simple_glazing_u = old_simple_glazing_u
        new_simple_glazing_shgc = old_simple_glazing_shgc * (1 - pct_shgc_reduct)
        new_simple_glazing_vlt = old_simple_glazing_vlt * (1 - pct_vlt_reduct)

        # check to make sure the new properties are better than the old before replacing
        if old_simple_glazing_shgc <= new_simple_glazing_shgc
          runner.registerWarning('Old simple glazing SHGC is lower than the new simple glazing SHGC. Consider revising measure arguments.')
        end

        # check if construction has been made
        if new_construction_hash.key?(construction)
          new_construction = new_construction_hash[construction]
        else
          # make new simple glazing with SHGC and VLT reductions
          new_simple_glazing = OpenStudio::Model::SimpleGlazing.new(model)
          new_simple_glazing.setName("#{simple_glazing.name.get} with film")

          # set and register final conditions
          new_simple_glazing.setUFactor(new_simple_glazing_u)
          new_simple_glazing.setSolarHeatGainCoefficient(new_simple_glazing_shgc)
          new_simple_glazing.setVisibleTransmittance(new_simple_glazing_vlt)

          # register final condition
          runner.registerInfo("New window #{new_simple_glazing.name.get} has #{new_simple_glazing_u.round(2)} W/m2-K U-value , #{new_simple_glazing_shgc} SHGC, and #{new_simple_glazing_vlt} VLT.")

          # create new construction with this new simple glazing layer
          new_construction = OpenStudio::Model::Construction.new(model)
          new_construction.setName("#{construction.name.get} with film")
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
    end

    # summary
    area_changed_ft2 = OpenStudio.convert(area_changed_m2, 'm^2', 'ft^2').get
    runner.registerFinalCondition("Added window film to #{area_changed_ft2.round(2)} ft2 of window that reduced SHGC by #{pct_shgc_reduct * 100}% and VLT by #{pct_vlt_reduct * 100}%.")
    runner.registerValue('env_window_film_fen_area_ft2', area_changed_ft2.round(2), 'ft2')
    return true
  end
end

# register the measure to be used by the application
EnvWindowFilm.new.registerWithApplication
