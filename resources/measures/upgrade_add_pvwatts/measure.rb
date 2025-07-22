# ComStock™, Copyright (c) 2025 Alliance for Sustainable Energy, LLC. All rights reserved.
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

require 'openstudio-standards'

# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# start the measure
class UpgradeAddPvwatts < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    'upgrade_add_pvwatts'
  end

  # human readable description
  def description
    'Adds rooftop fixed solar photovolatic panels based on user-specified fraction of roof area covered.'
  end

  # human readable description of modeling approach
  def modeler_description
    'Uses PV Watts solar objects'
  end

  # returns the 'optimal' fixed PV array tilt based on latitude
  # from: https://doi.org/10.1016/j.solener.2018.04.030, Figure 1.
  #
  # @param latitude [Double] building site latitude (degrees)
  # @return [Array] array of [tilt, azimuth]
  def model_pv_optimal_fixed_position(latitude)
    # ensure float
    latitude = latitude.to_f
    if latitude > 0
      # northern hemisphere
      tilt = 1.3793 + latitude * (1.2011 + latitude * (-0.014404 + latitude * 0.000080509))
      # from EnergyPlus I/O: An azimuth angle of 180◦ is for a south-facing array, and an azimuth angle of 0◦ is for anorth-facing array.
      azimuth = 180.0
    else
      # southern hemisphere - calculates negative tilt from negative latitude
      tilt = -0.41657 + latitude * (1.4216 + latitude * (0.024051 + latitude * 0.00021828))
      tilt = abs(tilt)
      azimuth = 0.0
    end
    # To allow for rain to naturally clean panels, optimal tilt angles between −10 and +10° latitude
    # are usually limited to either −10° (for negative values) or +10° (for positive values)
    tilt = 10.0 if tilt.abs < 10.0
    [tilt, azimuth]
  end

  # creates a Generator:PVWatts
  # TODO modify for tracking systems
  def model_add_pvwatts_system(model,
                               name: 'PV System',
                               module_type: 'Premium',
                               array_type: 'FixedRoofMounted',
                               system_capacity_kw: nil,
                               system_losses: 0.14,
                               azimuth_angle: nil,
                               tilt_angle: nil)
    system_capacity_w = system_capacity_kw * 1000
    pvw_generator = OpenStudio::Model::GeneratorPVWatts.new(model, system_capacity_w)
    pvw_generator.setName(name)
    if %w[Standard Premium ThinFilm].include? module_type
      pvw_generator.setModuleType(module_type)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model',
                         'Wrong module type entered for OpenStudio::Generator::PVWatts. Review Input.')
      return false
    end

    if %w[FixedOpenRack FixedRoofMounted OneAxis OneAxisBacktracking TwoAxis].include? array_type
      pvw_generator.setArrayType(array_type)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model',
                         'Wrong array type entered for OpenStudio::Generator::PVWatts. Review Input.')
      return false
    end
    pvw_generator.setSystemLosses(system_losses)

    if tilt_angle.nil? && azimuth_angle.nil?
      # check if site is poulated
      latitude_defaulted = model.getSite.isLatitudeDefaulted
      if !latitude_defaulted
        latitude = model.getSite.latitude
        # calcaulate optimal fixed tilt
        tilt, azimuth = model_pv_optimal_fixed_position(latitude)
      else
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model',
                           'No Site location found: Generator:PVWatts will be created with tilt of 25 degree tilt and 180 degree azimuth.')
        tilt = 25.0
        azimuth = 180.0
      end
    end

    pvw_generator.setAzimuthAngle(azimuth)
    pvw_generator.setTiltAngle(tilt)

    pvw_generator
  end

  # creates an ElectricLoadCenter:Inverter:PVWatts
  def model_add_pvwatts_inverter(model,
                                 name: 'Default PV System Inverter',
                                 dc_to_ac_size_ratio: 1.10,
                                 inverter_efficiency: 0.96)
    pvw_inverter = OpenStudio::Model::ElectricLoadCenterInverterPVWatts.new(model)
    pvw_inverter.setName(name)
    pvw_inverter.setDCToACSizeRatio(dc_to_ac_size_ratio)
    pvw_inverter.setInverterEfficiency(inverter_efficiency)

    pvw_inverter
  end

  # define the arguments that the user will input
  def arguments(_model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # the name of the space to add to the model
    pv_area_fraction = OpenStudio::Measure::OSArgument.makeDoubleArgument('pv_area_fraction', true)
    pv_area_fraction.setDisplayName('Fraction of roof area for PV')
    pv_area_fraction.setDescription('The fraction of roof area for PV installation.')
    pv_area_fraction.setDefaultValue(0.4)
    args << pv_area_fraction

    args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments) # Do **NOT** remove this line

    # use the built-in error checking
    return false unless runner.validateUserArguments(arguments(model), user_arguments)

    # assign the user inputs to variables
    pv_area_fraction = runner.getDoubleArgumentValue('pv_area_fraction', user_arguments)

    # build standard to use OS standards methods
    template = 'ComStock 90.1-2019'
    Standard.build(template)

    # get exterior roof area
    ext_roof_area_m2 = model.getBuilding.exteriorSurfaceArea - model.getBuilding.exteriorWallArea
    ext_roof_area_ft2 = OpenStudio.convert(ext_roof_area_m2, 'm^2', 'ft^2').get

    # calculate area of rooftop PV
    pv_area = ext_roof_area_m2 * pv_area_fraction
    pv_area_ft2 = OpenStudio.convert(pv_area, 'm^2', 'ft^2').get

    # report initial condition of model
    runner.registerInitialCondition("The building started with #{ext_roof_area_ft2.round(0)} ft^2 of roof area. The user specified #{(pv_area_fraction * 100).round(0)}% of the roof area to be covered with PV panels, which totals #{pv_area_ft2.round(0)} ft^2 of PV to be added.")

    # Get total system capacity
    panel_efficiency = 0.21 # associated with premium PV Watts panels
    total_system_capacity_kw = panel_efficiency * 1 * pv_area

    # create pv watts generator
    pv_generator = model_add_pvwatts_system(model,
                                            name: 'PV System',
                                            module_type: 'Premium',
                                            array_type: 'FixedRoofMounted',
                                            system_capacity_kw: total_system_capacity_kw,
                                            system_losses: 0.14,
                                            azimuth_angle: nil,
                                            tilt_angle: nil)

    # add pv watts inverter
    pv_inverter = model_add_pvwatts_inverter(model,
                                             name: 'Default PV System Inverter',
                                             dc_to_ac_size_ratio: 1.10,
                                             inverter_efficiency: 0.96)

    # add electric load center distribution
    electric_load_center_distribution = OpenStudio::Model::ElectricLoadCenterDistribution.new(model)
    electric_load_center_distribution.setName('ELC1')
    electric_load_center_distribution.setInverter(pv_inverter)
    electric_load_center_distribution.setGeneratorOperationSchemeType('TrackElectrical')
    electric_load_center_distribution.setElectricalBussType('DirectCurrentWithInverter')
    electric_load_center_distribution.addGenerator(pv_generator)

    # get specs for output
    pv_system_capacity = pv_generator.dcSystemCapacity
    pv_module_type = pv_generator.moduleType
    pv_array_type = pv_generator.arrayType
    pv_system_losses = pv_generator.systemLosses
    pv_title_angle = pv_generator.tiltAngle
    pv_azimuth_angle = pv_generator.azimuthAngle

    # report final condition of model
    runner.registerFinalCondition("The building finished with #{(pv_system_capacity / 1000).round(0)} kW of PV covering #{pv_area_ft2.round(0)} ft^2 of roof area. The module type is #{pv_module_type}, the array type is #{pv_array_type}, the system losses are #{pv_system_losses}, the title angle is #{pv_title_angle.round(0)}°, and the azimuth angle is #{pv_azimuth_angle.round(0)}°. The inverter has a DC to AC size ratio of #{pv_inverter.dcToACSizeRatio} and an inverter efficiency of #{(pv_inverter.inverterEfficiency * 100).round(0)}%.")

    true
  end
end

# register the measure to be used by the application
UpgradeAddPvwatts.new.registerWithApplication
