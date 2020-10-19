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
class HVACDCV < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'HVAC DCV'
  end

  # human readable description
  def description
    return 'Add demand control ventilation to an HVAC system.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Add demand control ventilation to variable volume HVAC systems.
Requires that the design specification outdoor air objects have some part of the ventilation be specified as per person.
Also requires that if zone hvac equipment is present, it takes load priority over the venilation system.'
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

    # build standard to access methods
    template = 'ComStock 90.1-2013'
    std = Standard.build(template)

    no_outdoor_air_loops = 0
    constant_volume_doas_loops = 0
    existing_dcv_loops = 0
    selected_air_loops = []
    model.getAirLoopHVACs.each do |air_loop_hvac|
      oa_system = air_loop_hvac.airLoopHVACOutdoorAirSystem
      if oa_system.is_initialized
        oa_system = oa_system.get
      else
        no_outdoor_air_loops += 1
        runner.registerInfo("Air loop #{air_loop_hvac.name} does not have outdoor air and cannot have demand control ventilation.")
        next
      end

      sizing_system = air_loop_hvac.sizingSystem
      type_of_load = sizing_system.typeofLoadtoSizeOn
      if type_of_load == 'VentilationRequirement'
        # check to see if terminal equipment has VAV option
        constant_volume_doas_loops += 1
        runner.registerInfo("Air loop #{air_loop_hvac.name} is a constant volume DOAS system and cannot have demand control ventilation.")
        next
      end

      controller_oa = oa_system.getControllerOutdoorAir
      controller_mv = controller_oa.controllerMechanicalVentilation
      if controller_mv.demandControlledVentilation == true
        existing_dcv_loops += 1
        runner.registerInfo("Air loop #{air_loop_hvac.name} already has demand control ventilation enabled.")
        next
      end

      runner.registerInfo("Air loop #{air_loop_hvac.name} does not have existing demand control ventilation.  This measure will enable it.")
      selected_air_loops << air_loop_hvac
    end

    # report initial condition of model
    runner.registerInitialCondition("Out of #{model.getAirLoopHVACs.size} air loops, #{no_outdoor_air_loops} do not have outdoor air, #{constant_volume_doas_loops} are constant volume DOAS systems, and #{existing_dcv_loops} already have demand control ventilation enabled, leaving #{selected_air_loops.size} eligible for demand control ventilation.")

    if selected_air_loops.size.zero?
      runner.registerAsNotApplicable('Model does not contain air loops eligible for enabling demand control ventilation.')
      return false
    end

    # for selected air loops determine if the zone design specification outdoor air objects need to be convert to per person
    per_person_values_present = false
    selected_air_loops.each do |air_loop_hvac|
      air_loop_hvac.thermalZones.sort.each do |zone|
        break if per_person_values_present
        zone.spaces.each do |space|
          dsn_oa = space.designSpecificationOutdoorAir
          next if dsn_oa.empty?
          dsn_oa = dsn_oa.get
          unless dsn_oa.outdoorAirFlowperPerson.zero?
            per_person_values_present = true
            break
          end
        end
      end
    end

    # assume models with no per person values specified are DEER models
    unless per_person_values_present
      runner.registerWarning('No per person values were present in the model.  Using a minimum of 15 cfm / person and assigning the remaining space outdoor air requirement to per area.')
      # convert per area values to a per person and per area
      selected_air_loops.each do |air_loop_hvac|
        air_loop_hvac.thermalZones.sort.each do |zone|
          break if per_person_values_present
          zone.spaces.each do |space|
            dsn_oa = space.designSpecificationOutdoorAir
            next if dsn_oa.empty?
            dsn_oa = dsn_oa.get

            # Get the space properties
            floor_area = space.floorArea
            number_of_people = space.numberOfPeople
            volume = space.volume

            # Sum up the total OA from all sources
            oa_for_people = number_of_people * dsn_oa.outdoorAirFlowperPerson
            oa_for_floor_area = floor_area * dsn_oa.outdoorAirFlowperFloorArea
            oa_rate = dsn_oa.outdoorAirFlowRate
            oa_for_volume = volume * dsn_oa.outdoorAirFlowAirChangesperHour / 3600
            tot_oa = oa_for_people + oa_for_floor_area + oa_rate + oa_for_volume
            tot_oa_cfm = OpenStudio.convert(tot_oa, 'm^3/s', 'ft^3/min').get

            # default ventilation is 15 cfm / person
            per_person_ventilation_rate = OpenStudio.convert(15.0, 'ft^3/min', 'm^3/s').get

            # assign remaining oa to per area
            new_oa_for_people = number_of_people * per_person_ventilation_rate
            new_oa_for_people_cfm = OpenStudio.convert(new_oa_for_people, 'm^3/s', 'ft^3/min').get
            remaining_oa = tot_oa - (number_of_people * per_person_ventilation_rate)
            if (remaining_oa + 0.0005) < 0
              runner.registerWarning("Space '#{space.name}' has #{number_of_people.round(1)} people which corresponds to a ventilation minimum requirement of #{new_oa_for_people_cfm.round(0)} cfm at 15 cfm / person, but total zone outdoor air is only #{tot_oa_cfm.round(0)} cfm. Setting all outdoor air as per person.")
              per_person_ventilation_rate = tot_oa / number_of_people
              dsn_oa.setOutdoorAirFlowperFloorArea(0.0)
            else
              oa_per_area = remaining_oa / floor_area
              dsn_oa.setOutdoorAirFlowperFloorArea(oa_per_area)
            end
            dsn_oa.setOutdoorAirFlowperPerson(per_person_ventilation_rate)

            # zero-out the ACH, and flow requirements
            dsn_oa.setOutdoorAirFlowAirChangesperHour(0.0)
            dsn_oa.setOutdoorAirFlowRate(0.0)
          end
        end
      end
    end

    # check to see if sizing run is needed
    run_sizing = false
    selected_air_loops.each do |air_loop_hvac|
      break if run_sizing
      airflow_rate = 0
      if air_loop_hvac.designSupplyAirFlowRate.is_initialized
        airflow_rate = air_loop_hvac.designSupplyAirFlowRate.get
      elsif air_loop_hvac.autosizedDesignSupplyAirFlowRate.is_initialized
        airflow_rate = air_loop_hvac.autosizedDesignSupplyAirFlowRate.get
      end
      run_sizing = true if airflow_rate.zero?
    end

    if run_sizing
      runner.registerInfo('At least one selected air loop is not sized. Running sizing run.')
      if std.model_run_sizing_run(model, "#{Dir.pwd}/SizingRun") == false
        runner.registerError('Sizing run failed. See errors in sizing run directory or this measure')
        return false
      end
    end

    # enable DCV on selected air loops
    enabled_dcv = 0
    total_cooling_capacity_w = 0
    total_airflow_m3_s = 0
    selected_air_loops.each do |air_loop_hvac|
      if air_loop_hvac.designSupplyAirFlowRate.is_initialized
        total_airflow_m3_s += air_loop_hvac.designSupplyAirFlowRate.get
      elsif air_loop_hvac.autosizedDesignSupplyAirFlowRate.is_initialized
        total_airflow_m3_s += air_loop_hvac.autosizedDesignSupplyAirFlowRate.get
      else
        runner.registerWarning("Air loop #{air_loop_hvac.name} air flow rate is unavailable.  This is needed for measure costing. Skipping this air loop.")
        next
      end

      # set design specification outdoor air objects to sum
      air_loop_hvac.thermalZones.sort.each do |zone|
        zone.spaces.each do |space|
          dsn_oa = space.designSpecificationOutdoorAir
          next if dsn_oa.empty?
          dsn_oa = dsn_oa.get
          dsn_oa.setOutdoorAirMethod('Sum')
        end
      end

      total_cooling_capacity_w += std.air_loop_hvac_total_cooling_capacity(air_loop_hvac)
      std.air_loop_hvac_enable_demand_control_ventilation(air_loop_hvac, '')
      enabled_dcv += 1
    end

    if total_cooling_capacity_w.zero?
      runner.registerWarning('Total cooling capacity of all air loops with newly enabled DCV is zero.  Model may not have cooling.')
    end

    if total_airflow_m3_s.zero?
      runner.registerAsNotApplicable('Total air flow rate of all air loops with newly enabled DCV is zero.  This is needed for measure costing.')
      return false
    end

    total_cooling_capacity_btuh = OpenStudio.convert(total_cooling_capacity_w, 'W', 'Btu/hr').get
    total_cooling_capacity_tons = total_cooling_capacity_btuh / 12_000
    total_airflow_cfm = OpenStudio.convert(total_airflow_m3_s, 'm^3/s', 'ft^3/min').get
    # report final condition of model
    runner.registerValue('hvac_dcv_cooling_load_in_tons', total_cooling_capacity_tons)
    runner.registerValue('hvac_dcv_cfm', total_airflow_cfm)
    runner.registerFinalCondition("Enabled DCV for #{enabled_dcv} air loops in the model with #{total_cooling_capacity_tons.round(1)} tons of total cooling capacity and #{total_airflow_cfm} cfm of design airflow.")

    return true
  end
end

# register the measure to be used by the application
HVACDCV.new.registerWithApplication
