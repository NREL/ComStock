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
# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

# Dependencies
require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'openstudio-standards'
require 'fileutils'

# Start the measure
class HVACVAVMinimumAirflow < OpenStudio::Measure::ModelMeasure
  # Human readable name
  def name
    return 'VAV Terminal Minimum Airflow'
  end

  # Human readable description
  def description
    return 'This energy efficiency measure (EEM) changes the VAV box minimum flow setting to 0.4 cfm/sf for all AirLoops in the model.'
  end

  # Human readable description of modeling approach
  def modeler_description
    return 'This measure loops through the thermal zones in all air loops. It then selects the thermal zone area and then calculates the minimum flow rate of 0.4 cfm/sf. If the zone has an AirTerminalSingleDuct VAVReheat & AirTerminalSingleDuctVAVNoReheat terminal unit the measure changes the zone minimum air flow method to fixed flow rate and applies the calculated minimum flow rate.'
  end

  # Define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new
    return args
  end

  def neat_numbers(number, roundto = 2)
    # round to 0 or 2
    if roundto == 2
      number = format '%.2f', number
    else
      number = number.round
    end
      # Regex to add commas
      number.to_s.reverse.gsub(%r{([0-9]{3}(?=([0-9])))}, '\\1,').reverse
  end

  # Define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Initialize counter variables
    numb_airsingle_terminal_vavreheat = 0
    numb_airsingle_terminal_vavnoreheat = 0
    total_airflow_m3_s = 0

    # Get all airloops from the model
    all_airloops = model.getAirLoopHVACs

    if all_airloops.empty?
      runner.registerAsNotApplicable('This model has no airloops. The measure is not applicable.')
      return true
    end

    # Loop through each airloop object
    all_airloops.each do |loop|
      # Retrieve the thermal zone objects associated with each airloop
      thermal_zones = loop.thermalZones

      # Loop through the thermal zone objects attached to each airloop
      thermal_zones.each do |thermal_zone|
      # Retrieve the area of the thermal zone
      m2_thermal_zone_area = thermal_zone.floorArea
      # Convert metric floor area into floor area using IP units and round
      sqft_thermal_zone_area = OpenStudio.convert(m2_thermal_zone_area, 'm^2', 'ft^2')
      ft2_thermal_zone_area = neat_numbers(sqft_thermal_zone_area, 2)
      # Calculate the minimum airflow rate needed for the zone
      thermal_zone_min_flow = (sqft_thermal_zone_area.to_f * 0.4)

      # Retrieve all ZoneEquipment objects attached to the thermal zone
      zone_equip = thermal_zone.equipment

      # Loop through each ZoneEquipment objects
      zone_equip.each do |vav_box|
        # Attempt to map the ZoneEquipment object to a Single Duct VAV box (No Reheat or Reheat) object type
        airterminal_singleduct_vavreheat = vav_box.to_AirTerminalSingleDuctVAVReheat
        airterminal_singleduct_vavnoreheat = vav_box.to_AirTerminalSingleDuctVAVNoReheat # alter equipment of the correct type

        # If ZoneEquipment object = type single duct VAV with reheat then execute this logic
        if !airterminal_singleduct_vavreheat.empty?
          airterminal_singleduct_vavreheat = airterminal_singleduct_vavreheat.get
          # Retrieve and store existing method for ZoneMinimumAirflowRate from the SingeDuctVAVReheat box object
          existing_method = airterminal_singleduct_vavreheat.zoneMinimumAirFlowMethod
          if existing_method == 'FixedFlowRate'
            existing_cubic_mps = airterminal_singleduct_vavreheat.fixedMinimumAirFlowRate
            existing_cfm = OpenStudio.convert(existing_cubic_mps, 'm^3/s', 'cfm')
            existing_cfm = neat_numbers(existing_cfm, 2)
          end
          if existing_method == 'Constant'
            existing_cons_air_frac = airterminal_singleduct_vavreheat.constantMinimumAirFlowFraction
            existing_cons_air_frac = neat_numbers(existing_cons_air_frac, 2)
          end

          # Change the zoneMinimumAirFlowMethod
            airterminal_singleduct_vavreheat.setZoneMinimumAirFlowMethod('FixedFlowRate')
            airterminal_singleduct_vavreheat.setFixedMinimumAirFlowRate(thermal_zone_min_flow)
            cubic_mps = airterminal_singleduct_vavreheat.fixedMinimumAirFlowRate
            cubic_mps = neat_numbers(cubic_mps, 2)
            # Short def to make numbers pretty (converts 4125001.25641 to 4,125,001.26 or 4,125,001). The definition be called through this measure
            atsdvr = airterminal_singleduct_vavreheat.name.get
            runner.registerInfo("Minimum Airflow rate for Single duct VAV with reheat named '#{atsdvr}' with area #{ft2_thermal_zone_area} sqft, & zone minimum air flow input method as '#{existing_method}' = #{existing_cfm} #{existing_cons_air_frac} has been changed to a minimum fixed flow rate of #{cubic_mps} cfm.")
            # Increment counter of above object by one
            numb_airsingle_terminal_vavreheat += 1
          end

          # If ZoneEquipment object = type single duct VAV without reheat then execute this logic
          if !airterminal_singleduct_vavnoreheat.empty?
            airterminal_singleduct_vavnoreheat = airterminal_singleduct_vavnoreheat.get
            existing_method_2 = airterminal_singleduct_vavnoreheat.zoneMinimumAirFlowInputMethod
            if existing_method_2.to_s == 'FixedFlowRate'
              existing_cubic_mps_2 = airterminal_singleduct_vavnoreheat.fixedMinimumAirFlowRate

              if !existing_cubic_mps_2.empty?
                existing_cfm_2 = OpenStudio.convert(existing_cubic_mps_2.get, 'm^3/s', 'cfm')
                existing_cfm_2 = neat_numbers(existing_cfm_2, 2)
              end
            end
            if existing_method_2.to_s == 'Constant'
              existing_cons_air_frac_2 = airterminal_singleduct_vavnoreheat.constantMinimumAirFlowFraction
              existing_cons_air_frac_2 = neat_numbers(existing_cons_air_frac_2, 2)
            end

            # Change the zoneMinimumAirFlowMethod
            airterminal_singleduct_vavnoreheat.setZoneMinimumAirFlowInputMethod('FixedFlowRate')
            airterminal_singleduct_vavnoreheat.setFixedMinimumAirFlowRate(thermal_zone_min_flow)
            cubic_mps_2 = airterminal_singleduct_vavnoreheat.fixedMinimumAirFlowRate
            cubic_mps_2 = neat_numbers(cubic_mps_2, 2)

            # Short def to make numbers pretty (converts 4125001.25641 to 4,125,001.26 or 4,125,001). The definition be called through this measure
            atsdvnr = airterminal_singleduct_vavnoreheat.name.get
            runner.registerInfo("Minimum Airflow rate for Single duct VAV with no reheat named '#{atsdvnr}' with area #{ft2_thermal_zone_area} sqft, & zone minimum air flow input method as '#{existing_method_2}' = #{existing_cfm_2} #{existing_cons_air_frac_2} has been changed to a minimum fixed flow rate of #{cubic_mps_2} cfm.")
          # Increment counter of above object by one
            numb_airsingle_terminal_vavnoreheat += 1
          end

          airterminal_singleduct_vavreheat = vav_box.to_AirTerminalSingleDuctVAVReheat
          airterminal_singleduct_vavnoreheat = vav_box.to_AirTerminalSingleDuctVAVNoReheat
          # Add flow through this loop to total flow rate
          if !airterminal_singleduct_vavreheat.empty?
            if loop.designSupplyAirFlowRate.is_initialized
              total_airflow_m3_s += loop.designSupplyAirFlowRate.get
            elsif loop.autosizedDesignSupplyAirFlowRate.is_initialized
              total_airflow_m3_s += loop.autosizedDesignSupplyAirFlowRate.get
            end
          end

          if !airterminal_singleduct_vavnoreheat.empty?
            if loop.designSupplyAirFlowRate.is_initialized
              total_airflow_m3_s += loop.designSupplyAirFlowRate.get
            elsif loop.autosizedDesignSupplyAirFlowRate.is_initialized
              total_airflow_m3_s += loop.autosizedDesignSupplyAirFlowRate.get
            end
          end
        end
      end
    end

    total_modified_objects = numb_airsingle_terminal_vavreheat + numb_airsingle_terminal_vavnoreheat
    total_airflow_cfm = OpenStudio.convert(total_airflow_m3_s, 'm^3/s', 'ft^3/min').get

    # Report 'AsNotApplicable' condition of model
    if total_modified_objects == 0
      runner.registerAsNotApplicable('The building contains no qualified single duct VAV objects. Measure is not applicable.')
      return false
    end

    # Report initial condition of model
    runner.registerInitialCondition("The model begins with #{numb_airsingle_terminal_vavreheat} Single duct VAV with reheat objects & #{numb_airsingle_terminal_vavnoreheat} Single duct VAV with no reheat objects.") # report initial condition of model

    # Report final condition of model
    runner.registerFinalCondition("The model finished with #{total_modified_objects} objects having the 'zone minimum air flow method' set to 'fixed flow rate' and a minimum airflow rate of 0.4 cfm/sf.")
    runner.registerValue('hvac_vav_min_airflow_cfm', total_airflow_cfm)
    return true
  end
end

# Register the measure to be used by the application
HVACVAVMinimumAirflow.new.registerWithApplication
