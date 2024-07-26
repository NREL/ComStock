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

require_relative './os_lib_scout_meters'
require_relative './os_lib_scout_hvac'

module OsLib
  module Scout
    module BuildingMeters
      # A MeterSet with the added ability to
      # populate itself with the reporting information
      # and values from the sql file representing the supply
      # and demand side at the sub end use level for a building
      class BuildingMeterSet < OsLib::Scout::Meters::MeterSet
        # @param num_ts Number of timesteps
        def initialize(num_ts)
          super(num_ts)
        end

        # Get details for all of the custom meters and custom decrement meters
        # which together make up the full set of
        # fuel type > end use > supply > sub end uses
        # that will be reported to Scout to populate the mseg file
        def populate_supply_meter_details(model)
          eu = 'heating'
          OsLib_ScoutHVAC.model_all_heating_equipment(model).each do |component, ft|
            seu = scout_hvac_equipment_type(component)
            energy_consumption_output_variables(component).each do |var|
              self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{component.name}", var]
            end
          end

          eu = 'cooling'
          OsLib_ScoutHVAC.model_all_cooling_equipment(model).each do |component, ft|
            seu = scout_hvac_equipment_type(component)
            energy_consumption_output_variables(component).each do |var|
              self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{component.name}", var]
            end
          end

          eu = 'pumps'
          model_all_pumps(model).each do |component|
            ft = 'electricity'
            seu = scout_pump_type(component)
            energy_consumption_output_variables(component).each do |var|
              self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{component.name}", var]
            end
          end

          eu = 'fans'
          model_all_fans(model).each do |component|
            ft = 'electricity'
            seu = scout_fan_type(component)
            energy_consumption_output_variables(component).each do |var|
              self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{component.name}", var]
            end
          end

          eu = 'water_systems'
          model_all_water_heaters(model).each do |component|
            # TODO factor water heater fuel type out of plant loop heating fuels and reuse here
            # Get the object type
            obj_type = component.iddObjectType.valueName.to_s
            case obj_type
            when 'OS_WaterHeater_HeatPump', 'OS_WaterHeater_WrappedCondenser'
              ft = 'electricity'
            when 'OS_WaterHeater_Mixed', 'OS_WaterHeater_Stratified'
              # Check if the heater actually has a capacity (otherwise it's simply a Storage Tank)
              if component.heaterMaximumCapacity.empty? || component.heaterMaximumCapacity.get != 0
                ft = scout_fuel_type_from_energyplus_fuel_type(component.heaterFuelType)
              else
                next
              end
            end
            seu = scout_water_heater_type(component)
            energy_consumption_output_variables(component).each do |var|
              self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{component.name}", var]
            end
          end

          eu = 'interior_lighting'
          model.getThermalZones.each do |zone|
            zone.spaces.each do |space|
              # Lights assigned to space directly
              space.lights.each do |component|
                ft = 'electricity'
                seu = scout_lighting_type(component)
                energy_consumption_output_variables(component).each do |var|
                  self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{component.name}", var]
                end
              end

              # Lights assigned to space type are metered at the space
              next if space.spaceType.empty?
              space.spaceType.get.lights.each do |component|
                ft = 'electricity'
                seu = scout_lighting_type(component)
                energy_consumption_output_variables(component).each do |var|
                  self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{space.name} #{component.name}", var]
                end
              end
            end
          end

          eu = 'exterior_lighting'
          model_all_exterior_lights(model).each do |component|
            ft = 'electricity'
            seu = scout_lighting_type(component)
            energy_consumption_output_variables(component).each do |var|
              self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{component.name}", var]
            end
          end

          eu = 'interior_equipment'
          model.getThermalZones.each do |zone|
            zone.spaces.each do |space|
              # Electric equipment assigned to space directly
              space.electricEquipment.each do |component|
                ft = 'electricity'
                seu = scout_electric_equipment_type(component)
                energy_consumption_output_variables(component).each do |var|
                  self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{component.name}", var]
                end
              end

              # Gas equipment assigned to space directly
              space.gasEquipment.each do |component|
                ft = 'natural_gas'
                seu = scout_gas_equipment_type(component)
                energy_consumption_output_variables(component).each do |var|
                  self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{component.name}", var]
                end
              end

              # Electric equipment assigned to space type are metered at the space
              next if space.spaceType.empty?
              space.spaceType.get.electricEquipment.each do |component|
                ft = 'electricity'
                seu = scout_electric_equipment_type(component)
                energy_consumption_output_variables(component).each do |var|
                  self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{space.name} #{component.name}", var]
                end
              end

              # Gas equipment assigned to space type are metered at the space
              space.spaceType.get.gasEquipment.each do |component|
                ft = 'natural_gas'
                seu = scout_gas_equipment_type(component)
                energy_consumption_output_variables(component).each do |var|
                  self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{space.name} #{component.name}", var]
                end
              end
            end
          end

          eu = 'refrigeration'
          model_all_refrigeration(model).each do |component|
            ft = 'electricity'
            seu = scout_refrigeration_type(component)
            energy_consumption_output_variables(component).each do |var|
              self.end_use.supply(eu).sub_end_use(seu, ft).eplus_key_var_pairs << ["#{component.name}", var]
            end
          end

          # Meter the remainder between the sum of sub-end-uses and the total for that end-use
          remainder_seu = 'other'
          self.end_use.supply.each do |supply_end_use|
            supply_end_use.sub_end_use.each do |sub_end_use_meter|
              next if sub_end_use_meter.eplus_key_var_pairs.size.zero?
              # Get the remainder 'other' meter
              remainder_meter = self.end_use.supply(sub_end_use_meter.end_use).sub_end_use(remainder_seu, sub_end_use_meter.fuel_type)
              remainder_meter.meter_type = 'decrement'
              remainder_meter.source_meter_name = "#{sub_end_use_meter.end_use}:#{sub_end_use_meter.fuel_type}"
              remainder_meter.eplus_key_var_pairs << ['', sub_end_use_meter.meter_name]
            end
          end

          return true
        end

        private

        # Get all of the pumps in the model
        def model_all_pumps(model)
          all_pumps = []
          all_pumps += model.getPumpConstantSpeeds
          all_pumps += model.getPumpVariableSpeeds
          all_pumps += model.getHeaderedPumpsConstantSpeeds
          all_pumps += model.getHeaderedPumpsVariableSpeeds

          return all_pumps
        end

        # Get all of the fans in the model
        def model_all_fans(model)
          all_fans = []
          all_fans += model.getFanConstantVolumes
          all_fans += model.getFanOnOffs
          all_fans += model.getFanVariableVolumes

          return all_fans
        end

        # Get all of the water heaters in the model
        def model_all_water_heaters(model)
          all_whs = []
          all_whs += model.getWaterHeaterMixeds
          all_whs += model.getWaterHeaterHeatPumps
          all_whs += model.getWaterHeaterHeatPumpWrappedCondensers
          all_whs += model.getWaterHeaterStratifieds

          return all_whs
        end

        # Get all of the exterior lights in the model
        def model_all_exterior_lights(model)
          all_lts = []
          all_lts += model.getExteriorLightss

          return all_lts
        end

        # Get all of the refrigeration in the model
        def model_all_refrigeration(model)
          all_ref = []
          all_ref += model.getRefrigerationCompressors
          all_ref += model.getRefrigerationCases
          all_ref += model.getRefrigerationWalkIns
          all_ref += model.getRefrigerationCondenserAirCooleds

          return all_ref
        end

        # Assign Scout pump enumeration based on OpenStudio component type
        # Choices are:
        # chilled_water_pump,
        # hot_water_pump,
        # condenser_water_pump,
        # service_water_pump
        def scout_pump_type(component)
          # Get the object type
          obj_type = component.iddObjectType.valueName.to_s
          case obj_type
          when 'OS_Pump_ConstantSpeed', 'OS_Pump_VariableSpeed', 'OS_HeaderedPumps_ConstantSpeed', 'OS_HeaderedPumps_VariableSpeed'
            plant_loop = component.plantLoop
            if plant_loop.empty?
              st = "scout_pump_type_not_defined"
            else
              plant_loop_name = plant_loop.get.name.get.to_s
              if plant_loop_name.include?('Hot Water')
                st = 'hot_water_pump'
              elsif plant_loop_name.include?('Chilled Water')
                st = 'chilled_water_pump'
              elsif plant_loop_name.include?('Condenser Water') || plant_loop_name.include?('Heat Pump')
                st = 'condenser_water_pump'
              elsif plant_loop_name.include?('Service Water')
                st = 'service_water_pump'
              else
                st = "scout_pump_type_not_defined"
              end
            end
          else
            st = "scout_pump_type_not_defined"
          end

          return st
        end

        # Assign Scout fan enumeration based on OpenStudio component type
        # Choices are:
        # supply_fan
        def scout_fan_type(component)
          st = "supply_fan"

          return st
        end

        # Assign Scout water heater enumeration based on OpenStudio component type
        # Choices are:
        # gas_storage_water_heater,
        # gas_booster_water_heater,
        # electric_resistance_storage_water_heater,
        # electric_resistance_booster_water_heater,
        # heat_pump_storage_water_heater
        def scout_water_heater_type(component)
          # Get the object type
          obj_type = component.iddObjectType.valueName.to_s
          case obj_type
          when 'OS_WaterHeater_HeatPump', 'OS_WaterHeater_WrappedCondenser'
            st = 'heat_pump_storage_water_heater'
          when 'OS_WaterHeater_Mixed', 'OS_WaterHeater_Stratified'
            if component.heaterFuelType == 'NaturalGas'
              if component.name.get.to_s.downcase.include?('booster')
                st = 'gas_booster_water_heater'
              else
                st = 'gas_storage_water_heater'
              end
            else
              if component.name.get.to_s.downcase.include?('HeatPump')
                # To capture the approximation ComStock uses for heat pump water heaters,
                # which uses the standard EnergyPlus WaterHeater:Mixed with EMS to set eff > 100%
                st = 'heat_pump_storage_water_heater'
              elsif component.name.get.to_s.downcase.include?('booster')
                st = 'electric_resistance_booster_water_heater'
              else
                st = 'electric_resistance_storage_water_heater'
              end
            end
          else
            st = "scout_water_heater_type_not_defined"
          end

          return st
        end

        # Assign Scout lighting enumeration based on OpenStudio component type
        # Choices are:
        # general,
        # parking_areas_and_drives,
        # building_facades,
        # main_entries,
        # other_doors,
        # entry_canopies,
        # emergency_canopies,
        # drive_through_windows,
        # base_site_allowance
        def scout_lighting_type(component)
          # Get the object type
          obj_type = component.iddObjectType.valueName.to_s
          case obj_type
          when 'OS_Lights'
            st = 'general'
          when 'OS_Exterior_Lights'
            # Get the end use subcategory
            subcat = component.endUseSubcategory
            if subcat == 'General' || subcat == ''
              st = 'general'
            else
              st = "#{subcat.downcase.gsub(' ', '_')}"
            end
          else
            st = "scout_lighting_type_not_defined"
          end

          return st
        end

        # Assign Scout electric equipment enumeration based on OpenStudio component type
        # Choices are:
        # general,
        # elevators
        def scout_electric_equipment_type(component)
          # Get the object type
          obj_type = component.iddObjectType.valueName.to_s
          case obj_type
          when 'OS_ElectricEquipment'
            # Get the end use subcategory
            subcat = component.endUseSubcategory
            case subcat
            when 'General', '', 'ResPublicArea', 'ElectricEquipment'
              st = 'general'
            else
              st = subcat.downcase.gsub(' ', '_')
            end
          else
            st = "scout_electric_equipment_type_not_defined"
          end

          return st
        end

        # Assign Scout natural gas equipment enumeration based on OpenStudio component type
        def scout_gas_equipment_type(component)
          return 'general'
        end

        # Assign Scout refrigeration enumeration based on OpenStudio component type
        # Choices are:
        # compressor,
        # refrigerated_case,
        # walkin,
        # condenser
        def scout_refrigeration_type(component)
          # Get the object type
          obj_type = component.iddObjectType.valueName.to_s
          case obj_type
          when 'OS_Refrigeration_Compressor'
            st = 'compressor'
          when 'OS_Refrigeration_Case'
            st = 'refrigerated_case'
          when 'OS_Refrigeration_WalkIn'
            st = 'walkin'
          when 'OS_Refrigeration_Condenser_AirCooled'
            st = 'condenser'
          else
            st = "scout_refrigeration_type_not_defined"
          end

          return st
        end

        # Assign Scout HVAC equipment enumeration based on OpenStudio component type
        # Choices are:
        # gas_boiler
        # scroll_chiller, reciprocating_chiller, centrifugal_chiller, screw_chiller
        # gas_furnace
        # comm_GSHP-cool, comm_GSHP-heat
        # wall-window_room_ASHP-heat, wall-window_room_ASHP-cool
        # rooftop_ASHP-heat, rooftop_ASHP-cool, rooftop_AC
        # central_ASHP-heat, central_ASHP-cool, central_AC
        def scout_hvac_equipment_type(component)
          # Get the object type
          obj_type = component.iddObjectType.valueName.to_s
          case obj_type
          when 'OS_Boiler_HotWater', 'OS_Boiler_Steam'
            if component.fuelType == 'NaturalGas'
              st = 'gas_boiler'
            else
              st = 'electric_boiler'
            end
          when 'OS_DistrictHeating' # Assume district heating is provided by a gas boiler
            st = 'gas_boiler'
          when 'OS_Chiller_Electric_EIR'
            # Determine if WaterCooled or AirCooled by
            # checking if the chiller is connected to a condenser
            # water loop or not.  Use name as fallback for exporting HVAC library.
            cooling_type = 'AirCooled'
            if component.secondaryPlantLoop.is_initialized || component.name.get.to_s.include?('WaterCooled')
              cooling_type = 'WaterCooled'
            end

            # TODO: Standards replace this with a mechanism to store this
            # data in the chiller object itself.
            # For now, retrieve the condenser type from the name
            name = component.name.get
            if cooling_type == 'AirCooled'
              # Assume all AirCooled chillers are small scroll chillers
              st = 'scroll_chiller'
            elsif cooling_type == 'WaterCooled'
              if name.include?('Reciprocating')
                st = 'reciprocating_chiller'
              elsif name.include?('Rotary Screw')
                st = 'screw_chiller'
              elsif name.include?('Scroll')
                st = 'scroll_chiller'
              elsif name.include?('Centrifugal')
                st = 'centrifugal_chiller'
              else
                st = 'scroll_chiller' # default assumption
              end
            end
          when 'OS_Coil_Heating_DX_MultiSpeed', 'OS_Coil_Heating_DX_SingleSpeed', 'OS_Coil_Heating_DX_VariableRefrigerantFlow', 'OS_Coil_Heating_DX_VariableSpeed'
            if is_inside_zone_hvac(component) && component.containingZoneHVACComponent.get.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
              st = 'wall-window_room_ASHP-heat'
            elsif is_inside_unitary(component) && component.containingHVACComponent.get.to_AirLoopHVACUnitaryHeatPumpAirToAir.is_initialized
              st = 'rooftop_ASHP-heat'
            elsif is_inside_unitary(component) && component.containingHVACComponent.get.to_AirLoopHVACUnitarySystem.is_initialized
              st = 'central_ASHP-heat'
            elsif component.airLoopHVAC.is_initialized
              air_loop_name = component.airLoopHVAC.get.name.get.to_s
              if air_loop_name.include?('PSZ-HP')
                st = 'rooftop_ASHP-heat'
              else
                st = 'central_ASHP-heat'
              end
            else
              st = 'central_ASHP-heat'
            end
          when 'OS_Coil_Heating_WaterToAirHeatPump_EquationFit', 'OS_Coil_Heating_WaterToAirHeatPump_VariableSpeed_EquationFit'
            st = 'comm_GSHP-heat'
          when 'OS_Coil_Cooling_WaterToAirHeatPump_EquationFit', 'OS_Coil_Cooling_WaterToAirHeatPump_VariableSpeed_EquationFit'
            st = 'comm_GSHP-cool'
          when 'OS_Coil_Heating_Electric'
            if is_inside_zone_hvac(component) && component.containingZoneHVACComponent.get.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
              st = 'wall-window_room_ASHP-heat'
            elsif is_inside_unitary(component) && component.containingHVACComponent.get.to_AirLoopHVACUnitaryHeatPumpAirToAir.is_initialized
              st = 'rooftop_ASHP-heat'
            elsif component.airLoopHVAC.is_initialized
              air_loop_name = component.airLoopHVAC.get.name.get.to_s
              if air_loop_name.include?('PSZ-HP')
                st = 'rooftop_ASHP-heat'
              else
                st = 'central_ASHP-heat'
              end
            else
              st = 'central_ASHP-heat'
            end
          when 'OS_Coil_Cooling_DX_SingleSpeed', 'OS_Coil_Cooling_DX_TwoSpeed'
            if is_inside_zone_hvac(component) && component.containingZoneHVACComponent.get.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized
              st = 'wall-window_room_AC'
            elsif is_inside_zone_hvac(component) && component.containingZoneHVACComponent.get.to_ZoneHVACFourPipeFanCoil.is_initialized
              st = 'wall-window_room_AC'
            elsif is_inside_zone_hvac(component) && component.containingZoneHVACComponent.get.to_ZoneHVACPackagedTerminalHeatPump.is_initialized
              st = 'wall-window_room_ASHP-cool'
            elsif is_inside_unitary(component) && component.containingHVACComponent.get.to_AirLoopHVACUnitaryHeatPumpAirToAir.is_initialized
              st = 'rooftop_ASHP-cool'
            elsif component.airLoopHVAC.is_initialized
              air_loop_name = component.airLoopHVAC.get.name.get.to_s
              if air_loop_name.include?('PSZ-HP')
                st = 'rooftop_ASHP-cool'
              else
                st = 'central_AC'
              end
            else
              st = 'central_AC'
            end
          when 'OS_Coil_Heating_Gas'
            st = 'gas_furnace'
          when 'OS_DistrictCooling'
            st = 'centrifugal_chiller'
          when 'OS_EvaporativeCooler_Direct_ResearchSpecial'
            st = 'evap_cooler'
          when 'OS_ZoneHVAC_Baseboard_Convective_Electric'
            st = 'electric_baseboard'
          else
            st = "scout_hvac_type_not_defined"
          end

          # Append any end use subcategory defined at the component level in the model
          if component.respond_to?(:endUseSubcategory)
            end_use = component.endUseSubcategory
            unless end_use == 'General' || end_use == ''
              st += ":#{end_use}"
            end
          end

          return st
        end

        # Determine if an HVAC component is inside of a unitary equipment
        def is_inside_unitary(component)
          if component.containingHVACComponent.is_initialized
            return true
          else
            return false
          end
        end

        # Determine if an HVAC component is inside of a zone HVAC component
        def is_inside_zone_hvac(component)
          if component.containingZoneHVACComponent.is_initialized
            return true
          else
            return false
          end
        end

        # Get the output variables comprising the energy consumption
        # recorded for each type of object
        def energy_consumption_output_variables(component)

          # Handle fuel output variables that changed in EnergyPlus version 9.4 (Openstudio version >= 3.1)
          elec = 'Electric'
          gas = 'Gas'
          fuel_oil = 'FuelOil#2'
          if component.model.version > OpenStudio::VersionString.new('3.0.1')
            elec = 'Electricity'
            gas = 'NaturalGas'
            fuel_oil = 'FuelOilNo2'
          end

           # Get the object type
          obj_type = component.iddObjectType.valueName.to_s
          vars = []
          case obj_type
          # HVAC equipment
          when 'OS_Boiler_HotWater', 'OS_Boiler_Steam'
            if component.fuelType == 'NaturalGas'
              vars << "Boiler #{gas} Energy"
            else
              vars << "Boiler #{elec} Energy"
            end
          when 'OS_WaterHeater_Mixed', 'OS_WaterHeater_Stratified'
            if component.heaterFuelType == 'NaturalGas'
              vars << "Water Heater #{gas} Energy"
            else
              vars << "Water Heater #{elec} Energy"
            end
          when 'OS_WaterHeater_HeatPump', 'OS_WaterHeater_WrappedCondenser'
            # TODO: confirm what object (coil or tank) is returned by OpenStudio
            # vars << 'Water Heater Electric Energy'
            # vars << 'Water Heater On Cycle Ancillary Electric Energy'
            # vars << 'Water Heater Off Cycle Ancillary Electric Energy'
          when 'OS_ZoneHVAC_Baseboard_Convective_Electric', 'OS_ZoneHVAC_Baseboard_RadiantConvective_Electric'
            vars << 'Baseboard Electric Energy'
          when 'OS_ZoneHVAC_HighTemperatureRadiant'
            if component.fuelType == 'NaturalGas'
              vars << "Zone Radiant HVAC #{gas} Energy"
            else
              vars << "Zone Radiant HVAC #{electric} Energy"
            end
          when 'OS_ZoneHVAC_LowTemperatureRadiant_Electric'
            vars << "Zone Radiant HVAC #{elec} Energy"
          when 'OS_DistrictHeating' # Assume district heating is provided by a gas boiler
            vars << 'District Heating Hot Water Energy'
          when 'OS_DistrictCooling' # Assume district cooling energy is provided by an electric chiller
            vars << 'District Cooling Chilled Water Energy'
          when 'OS_Chiller_Electric_EIR', 'OS_Chiller_Absorption', 'OS_Chiller_Absorption_Indirect'
            vars << "Chiller #{elec} Energy"
          when 'OS_Coil_Heating_Gas', 'OS_Coil_Heating_Gas_MultiStage'
            vars << "Heating Coil #{gas} Energy"
          when 'OS_Coil_Heating_DX_VariableRefrigerantFlow'
            puts "ERROR - No variable listed in I/O ref for #{obj_type}"
            vars << 'no_eplus_var_defined'
          when 'OS_Coil_WaterHeating_AirToWaterHeatPump', 'OS_Coil_WaterHeating_Desuperheater'
            vars << "Cooling Coil Water Heating #{elec} Energy"
          when 'OS_Refrigeration_AirChiller'
            vars << "Refrigeration Zone Air Chiller Total #{elec} Energy"
          when 'OS_Coil_Heating_WaterToAirHeatPump_EquationFit',
              'OS_Coil_Heating_WaterToAirHeatPump_VariableSpeed_EquationFit',
              'OS_Coil_Heating_Desuperheater',
              'OS_Coil_Heating_Electric'
            vars << "Heating Coil #{elec} Energy"
          when 'OS_Coil_Heating_DX_MultiSpeed',
              'OS_Coil_Heating_DX_SingleSpeed',
              'OS_Coil_Heating_DX_VariableSpeed'
            vars << "Heating Coil #{elec} Energy"
            vars << "Heating Coil Defrost #{elec} Energy"
            vars << "Heating Coil Crankcase Heater #{elec} Energy"
          when 'OS_Coil_Cooling_DX_MultiSpeed',
              'OS_Coil_Cooling_DX_SingleSpeed',
              'OS_Coil_Cooling_DX_TwoSpeed',
              'OS_Coil_Cooling_DX_TwoStageWithHumidityControlMode',
              'OS_Coil_Cooling_DX_VariableRefrigerantFlow',
              'OS_Coil_Cooling_DX_VariableSpeed',
              'OS_Coil_Cooling_WaterToAirHeatPump_EquationFit',
              'OS_Coil_Cooling_WaterToAirHeatPump_VariableSpeed_EquationFit'
            vars << "Cooling Coil #{elec} Energy"
          when 'OS_CoolingTower_SingleSpeed',
              'OS_CoolingTower_TwoSpeed',
              'OS_CoolingTower_VariableSpeed',
              'OS_EvaporativeFluidCooler_SingleSpeed',
              'OS_EvaporativeFluidCooler_TwoSpeed',
              'OS_FluidCooler_SingleSpeed',
              'OS_FluidCooler_TwoSpeed'
            vars << "Cooling Tower Fan #{elec} Energy"
          when 'OS_EvaporativeCooler_Direct_ResearchSpecial', 'OS_EvaporativeCooler_Indirect_ResearchSpecial'
            vars << "Evaporative Cooler #{elec} Energy"
          when 'OS_HeatPump_WaterToWater_EquationFit_Cooling'
            vars << "Water to Water Heat Pump #{elec} Energy"
          # Pumps
          when 'OS_Pump_ConstantSpeed',
              'OS_Pump_VariableSpeed',
              'OS_HeaderedPumps_ConstantSpeed',
              'OS_HeaderedPumps_VariableSpeed'
            vars << "Pump #{elec} Energy"
          # Fans
          when 'OS_Fan_ConstantVolume',
              'OS_Fan_OnOff',
              'OS_Fan_VariableVolume'
            vars << "Fan #{elec} Energy"
          # Interior lights
          when 'OS_Lights'
            vars << "Lights #{elec} Energy"
          # Exterior lights
          when 'OS_Exterior_Lights'
            vars << "Exterior Lights #{elec} Energy"
          # Interior equipment
          when 'OS_ElectricEquipment'
            vars << "Electric Equipment #{elec} Energy"
          # Gas Equipment
          when 'OS_GasEquipment'
            vars << "Gas Equipment #{gas} Energy"
          # Refrigeration
          when 'OS_Refrigeration_Compressor'
            vars << "Refrigeration Compressor #{elec} Energy"
          when 'OS_Refrigeration_Condenser_AirCooled'
            vars << "Refrigeration System Condenser Fan #{elec} Energy"
          when 'OS_Refrigeration_Case'
            vars << "Refrigeration Case Evaporator Fan #{elec} Energy"
            vars << "Refrigeration Case Lighting #{elec} Energy"
            unless component.antiSweatHeaterControlType == 'None'
              vars << "Refrigeration Case Anti Sweat #{elec} Energy"
            end
            if ['Electric', 'ElectricWithTemperatureTermination'].include?(component.caseDefrostType)
              vars << "Refrigeration Case Defrost #{elec} Energy"
            end
          when 'OS_Refrigeration_WalkIn'
            vars << "Refrigeration Walk In Fan #{elec} Energy"
            vars << "Refrigeration Walk In Lighting #{elec} Energy"
            vars << "Refrigeration Walk In Heater #{elec} Energy"
            if component.defrostType == 'Electric'
              vars << "Refrigeration Walk In Defrost #{elec} Energy"
            end
          else
            vars << "energy_output_variable_not_defined_for_#{obj_type}"
          end

          return vars
        end

        # Convert the EnergyPlus HVAC object fuel type enumerations
        # into the Scout fuel types
        def scout_fuel_type_from_energyplus_fuel_type(energyplus_fuel_type)
          case energyplus_fuel_type
          when 'NaturalGas', 'Gas'
            'natural_gas'
          when 'Electricity', 'Electric'
            'electricity'
          when 'DistrictCooling'
            'district_cooling'
          when 'DistrictHeating', 'DistrictHeatingWater', 'DistrictHeatingSteam'
            'district_heating'
          when 'SolarEnergy'
            'solar_energy'
          when 'PropaneGas'
            'propane_gas'
          when 'FuelOil#1'
            'fuel_oil_1'
          when 'FuelOil#2'
            'fuel_oil_2'
          when 'Coal'
            'coal'
          when 'Diesel'
            'diesel'
          when 'Gasoline'
            'gasoline'
          when 'OtherFuel1'
            'other_fuel_1'
          when 'OtherFuel2'
            'other_fuel_2'
          end
        end
      end
    end
  end
end

