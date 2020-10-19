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

# dependencies
require 'openstudio-standards'

# start the measure
class HVACPTACControls < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'HVAC PTAC controls'
  end

  # human readable description
  def description
    return 'Adjusts the PTAC availability schedule to follow the zone occupancy schedule.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Adjusts the PTAC availability schedule to follow the zone occupancy schedule.'
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  def ptac_cooling_capacity(runner, ptac)
    cooling_coil = ptac.coolingCoil
    cooling_capacity_w = 0
    # CoilCoolingDXSingleSpeed
    if cooling_coil.to_CoilCoolingDXSingleSpeed.is_initialized
      coil = cooling_coil.to_CoilCoolingDXSingleSpeed.get
      if coil.ratedTotalCoolingCapacity.is_initialized
        cooling_capacity_w = coil.ratedTotalCoolingCapacity.get
      elsif coil.autosizedRatedTotalCoolingCapacity.is_initialized
        cooling_capacity_w = coil.autosizedRatedTotalCoolingCapacity.get
      end
    # CoilCoolingDXTwoSpeed
    elsif cooling_coil.to_CoilCoolingDXTwoSpeed.is_initialized
      coil = cooling_coil.to_CoilCoolingDXTwoSpeed.get
      if coil.ratedHighSpeedTotalCoolingCapacity.is_initialized
        cooling_capacity_w = coil.ratedHighSpeedTotalCoolingCapacity.get
      elsif coil.autosizedRatedHighSpeedTotalCoolingCapacity.is_initialized
        cooling_capacity_w = coil.autosizedRatedHighSpeedTotalCoolingCapacity.get
      end
    # CoilCoolingWater
    elsif cooling_coil.to_CoilCoolingWater.is_initialized
      coil = cooling_coil.to_CoilCoolingWater.get
      if coil.autosizedDesignCoilLoad.is_initialized
        cooling_capacity_w = coil.autosizedDesignCoilLoad.get
      end
    # CoilCoolingWaterToAirHeatPumpEquationFit
    elsif cooling_coil.to_CoilCoolingWaterToAirHeatPumpEquationFit.is_initialized
      coil = cooling_coil.to_CoilCoolingWaterToAirHeatPumpEquationFit.get
      if coil.ratedTotalCoolingCapacity.is_initialized
        cooling_capacity_w = coil.ratedTotalCoolingCapacity.get
      elsif coil.autosizedRatedTotalCoolingCapacity.is_initialized
        cooling_capacity_w = coil.autosizedRatedTotalCoolingCapacity.get
      end
    else
      runner.registerError("PTAC unit #{ptac.name} does not have a recognized cooling coil type. Cannot get cooling capacity.")
      return false
    end
    return cooling_capacity_w
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # check zones to see if there are PTAC or PTHP units
    ptacs = []
    pthps = []
    model.getThermalZones.each do |thermal_zone|
      thermal_zone.equipment.each do |equip|
        if equip.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
          ptacs << equip.to_ZoneHVACPackagedTerminalAirConditioner.get
        elsif equip.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
          pthps << equip.to_ZoneHVACPackagedTerminalHeatPump.get
        end
      end
    end

    # register as not applicable if not
    if ptacs.empty? && pthps.empty?
      runner.registerAsNotApplicable('Model does not contain PTAC or PTHP units')
      return false
    end

    runner.registerInitialCondition("The model contains #{ptacs.size} PTAC units and #{pthps} PTHP units.")

    # build standard to access methods
    template = 'ComStock 90.1-2013'
    std = Standard.build(template)

    run_sizing = false
    ptacs.each do |ptac|
      thermal_zone = ptac.thermalZone.get

      # for each thermal zone get occupancy schedule
      occ_sch = std.thermal_zone_get_occupancy_schedule(thermal_zone, sch_name: "#{thermal_zone.name} PTAC Occ Sch", occupied_percentage_threshold: 0.05)

      # set PTAC units with new availability schedule
      ptac.setAvailabilitySchedule(occ_sch)

      # get sizing
      next if run_sizing
      cooling_capacity_w = ptac_cooling_capacity(runner, ptac)
      run_sizing = true if cooling_capacity_w.zero?
    end

    pthps.each do |pthp|
      thermal_zone = pthp.thermalZone.get

      # for each thermal zone get occupancy schedule
      occ_sch = std.thermal_zone_get_occupancy_schedule(thermal_zone, sch_name: "#{thermal_zone.name} PTHP Occ Sch", occupied_percentage_threshold: 0.05)

      # set PTAC units with new availability schedule
      pthp.setAvailabilitySchedule(occ_sch)

      # get sizing, uses the same methods as ptac
      next if run_sizing
      cooling_capacity_w = ptac_cooling_capacity(runner, pthp)
      run_sizing = true if cooling_capacity_w.zero?
    end

    if run_sizing
      runner.registerInfo('PTAC cooling capacity not sized in at least one PTAC or PTHP unit. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/SizingRun") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    total_cooling_capacity_w = 0
    ptacs.each do |ptac|
      total_cooling_capacity_w += ptac_cooling_capacity(runner, ptac)
    end

    pthps.each do |pthp|
      total_cooling_capacity_w += ptac_cooling_capacity(runner, pthp)
    end

    if total_cooling_capacity_w.zero?
      runner.registerError('PTAC and PTHP cooling capacity is zero but is necessary for costing.')
      return false
    end

    total_cooling_capacity_btuh = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/hr').get
    total_cooling_capacity_tons = total_cooling_capacity_btuh / 12_000
    # report final condition of model
    runner.registerValue('hvac_ptac_controls_cooling_load_in_tons', total_cooling_capacity_tons)
    runner.registerFinalCondition("Adjusted availability schedules based on zone occupancy for #{ptacs.size} PTAC units and #{pthps.size} PTHP units with #{total_cooling_capacity_tons.round(1)} tons of total cooling capacity.")
    return true
  end
end

# register the measure to be used by the application
HVACPTACControls.new.registerWithApplication
