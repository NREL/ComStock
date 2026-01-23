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

require 'matrix'
require_relative './os_lib_sql_file'

module OsLib
  module Scout
    module Meters
      # Represents a fuel type > end use > sub-end-use > supply or demand timeseries
      # Timeseries values initialized to zero
      class SubEndUseMeter
        attr_accessor :fuel_type
        attr_accessor :end_use
        attr_accessor :sub_end_use
        attr_accessor :supply_or_demand
        attr_accessor :meter_type
        attr_accessor :source_meter_name
        attr_accessor :eplus_key_var_pairs
        attr_accessor :vals
        attr_accessor :units

        def initialize(num_ts, units = '')
          @fuel_type = nil
          @end_use = nil
          @sub_end_use = nil
          @supply_or_demand = nil
          @meter_type = 'normal'
          @source_meter_name = nil
          @eplus_key_var_pairs = []
          @vals = Array.new(num_ts, 0.0)
          @units = ''
        end

        # Returns the meter name as a String
        def meter_name
          return "#{fuel_type}:#{end_use}:#{sub_end_use}"
        end

        def sum_vals(desired_units = nil)
          total = @vals.inject(:+)
          return total if desired_units.nil?

          desired_unit_total = OpenStudio.convert(total, @units, desired_units)
          if desired_unit_total.empty?
            raise("Could not convert value from units of #{@units} to #{desired_units}")
          end

          return desired_unit_total.get
        end

        # Creates an IDF object (Meter:Custom or Meter:CustomDecrement)
        # and the required Output:Meter object for this meter
        def meter_idf_objects(model)
          reporting_frequency = 'timestep'
          idf_objects = []
          return idf_objects if eplus_key_var_pairs.empty?
          if meter_type == 'normal'
            # Meter:Custom
            fuel_type_in_eplus_meter_input = OsLib::Scout::Meters.energyplus_fuel_type_for_meter_input(fuel_type)
            idf_obj = "Meter:Custom,#{meter_name},#{fuel_type_in_eplus_meter_input}"
            eplus_key_var_pairs.each do |pair|
              key, var = pair
              idf_obj += ",#{key},#{var}"
            end
            idf_obj += ";"
            idf_objects << OpenStudio::IdfObject.load(idf_obj).get
          else
            # Meter:CustomDecrement
            fuel_type_in_eplus_meter_name = OsLib::Scout::Meters.energyplus_fuel_type_for_decrement_meter(fuel_type, model)
            fuel_type_in_eplus_meter_input = OsLib::Scout::Meters.energyplus_fuel_type_for_meter_input(fuel_type)
            eplus_end_use = OsLib::Scout::Meters.energyplus_end_use_type_for_meter_name_map(end_use)
            source_meter_name = "#{eplus_end_use}:#{fuel_type_in_eplus_meter_name}"
            idf_obj = "Meter:CustomDecrement,#{meter_name},#{fuel_type_in_eplus_meter_input},#{source_meter_name}"
            eplus_key_var_pairs.each do |pair|
              key, var = pair
              idf_obj += ",#{key},#{var}"
            end
            idf_obj += ";"
            idf_objects << OpenStudio::IdfObject.load(idf_obj).get
          end
          # Output:Meter to output into sql file
          idf_objects << OpenStudio::IdfObject.load("Output:Meter,#{meter_name},#{reporting_frequency};").get

          return idf_objects
        end

        # Convert the meter characteristics into an acceptable string for runner.registerValue
        # Anything besides letters and numbers is replaced with underscores by the C++ here:
        # https://github.com/NREL/OpenStudio/blob/master/src/measure/OSRunner.cpp#L948
        # so choice of separators is limited
        def register_value_name
          return "#{@fuel_type}999#{@end_use}999#{supply_or_demand}999#{sub_end_use}#[GJ]"#.gsub(/\W/, '_')
        end
      end

      # Base class for different sets of sub end uses
      class SubEndUseBase
        attr_reader :sub_end_use_enums
        attr_reader :fuel_type_enums
        attr_reader :end_use

        # @param num_ts Number of timesteps
        def initialize(num_ts, end_use, supply_or_demand, sub_end_use_enums)
          @end_use = end_use
          @sub_end_use_enums = sub_end_use_enums
          @_sub_end_uses = []
          @fuel_type_enums = [
            'electricity',
            'natural_gas',
            'district_heating',
            'district_cooling'
          ]

          # Create meters for all sub end use/fuel type combos, initialized to array of zeroes
          @sub_end_use_enums.each do |demand_sub_end_use_enum|
            @fuel_type_enums.each do |fuel_type|
              new_meter = SubEndUseMeter.new(num_ts)
              new_meter.fuel_type = fuel_type
              new_meter.end_use = end_use
              new_meter.sub_end_use = demand_sub_end_use_enum
              new_meter.supply_or_demand = supply_or_demand
              new_meter.units = 'J'
              @_sub_end_uses << new_meter
            end
          end
        end

        # @param sub_end_use when nil, returns Meters for all sub_end_uses,
        # but when a string is specified, returns Meter for that one sub_end_use.
        def sub_end_use(sub_end_use = nil, fuel_type = nil)
          if sub_end_use.nil? && fuel_type.nil?
            # puts "only seu"
            return @_sub_end_uses
          elsif !sub_end_use.nil? && fuel_type.nil?
            # puts "seu but not ft"
            unless @sub_end_use_enums.include?(sub_end_use)
              raise("#{sub_end_use} is not a valid sub end use.  Valid choices are #{@sub_end_use_enums.join(', ')}")
            end
            sub_end_use_meters = @_sub_end_uses.select { |meter| meter.sub_end_use == sub_end_use }
            return sub_end_use_meters
          else
            # puts "seu and ft"
            # both sub_end_use and fuel_type are provided
            unless @sub_end_use_enums.include?(sub_end_use)
              raise("#{sub_end_use} is not a valid sub end use.  Valid choices are #{@sub_end_use_enums.join(', ')}")
            end
            unless @fuel_type_enums.include?(fuel_type)
              raise("#{fuel_type} is not a valid fuel type.  Valid choices are #{@fuel_type_enums.join(', ')}")
            end
            sub_end_use_meters = @_sub_end_uses.select { |meter|  meter.sub_end_use == sub_end_use && meter.fuel_type == fuel_type }
            if sub_end_use_meters.size > 1
              raise("There should only be 1 meter with the sub_end_use #{sub_end_use} and fuel_type #{fuel_type}, but there are #{sub_end_use_meters.size}")
            end
            return sub_end_use_meters.first
          end
        end

        # Adds an array of values to the original array of values element by element
        def add_vals_to_sub_end_use(sub_end_use, fuel_type, vals_to_add)
          meter = sub_end_use(sub_end_use, fuel_type)
          orig_vals = meter.vals
          unless vals_to_add.size == orig_vals.size
            raise("Both meters must have the same length.  Original meter had #{orig_vals.size}, vals_to_add had #{vals_to_add.size}")
          end

          orig_vals_vect = Vector.elements(meter.vals)
          vals_to_add_vect = Vector.elements(vals_to_add)
          new_vals_vect = orig_vals_vect + vals_to_add_vect
          meter.vals = new_vals_vect.to_a

          return true
        end
      end

      # Demand-side (heating or cooling) sub end uses
      class HeatingOrCoolingDemandSubEndUse < SubEndUseBase
        def initialize(num_ts, end_use)
          sub_end_use_enums = [
            'people_gain',
            'lighting_gain',
            'equipment_gain',
            'wall',
            'foundation_wall',
            'roof',
            'floor',
            'ground',
            'windows_conduction',
            'doors_conduction',
            'windows_solar',
            'infiltration',
            'ventilation'
          ]

          super(num_ts, end_use, 'demand', sub_end_use_enums)
        end
      end

      # Supply-side heating sub end uses
      class HeatingSupplySubEndUse < SubEndUseBase
        def initialize(num_ts, end_use)
          sub_end_use_enums = [
            'gas_boiler',
            'electric_boiler',
            'gas_furnace',
            'wall-window_room_ASHP-heat',
            'rooftop_ASHP-heat',
            'central_ASHP-heat',
            'comm_GSHP-heat',
            'electric_baseboard',
            'other',
            'scout_heating_type_not_defined'
          ]

          super(num_ts, end_use, 'supply', sub_end_use_enums)
        end
      end

      # Supply-side cooling sub end uses
      class CoolingSupplySubEndUse < SubEndUseBase
        def initialize(num_ts, end_use)
          sub_end_use_enums = [
            'scroll_chiller',
            'reciprocating_chiller',
            'screw_chiller',
            'centrifugal_chiller',
            'wall-window_room_ASHP-cool',
            'central_AC',
            'comm_GSHP-cool',
            'wall-window_room_AC',
            'rooftop_ASHP-cool',
            'evap_cooler',
            'other',
            'scout_cooling_type_not_defined'
          ]

          super(num_ts, end_use, 'supply', sub_end_use_enums)
        end
      end

      # Supply-side pumps sub end uses
      class PumpsSupplySubEndUse < SubEndUseBase
        def initialize(num_ts, end_use)
          sub_end_use_enums = [
            'hot_water_pump',
            'chilled_water_pump',
            'condenser_water_pump',
            'service_water_pump',
            'other',
            'scout_pump_type_not_defined'
          ]

          super(num_ts, end_use, 'supply', sub_end_use_enums)
        end
      end

      # Supply-side fans sub end uses
      class FansSupplySubEndUse < SubEndUseBase
        def initialize(num_ts, end_use)
          sub_end_use_enums = [
            'supply_fan',
            'other',
            'scout_fans_type_not_defined'
          ]

          super(num_ts, end_use, 'supply', sub_end_use_enums)
        end
      end

      # Supply-side water heating sub end uses
      class WaterSystemsSupplySubEndUse < SubEndUseBase
        def initialize(num_ts, end_use)
          sub_end_use_enums = [
            'gas_storage_water_heater',
            'gas_booster_water_heater',
            'electric_resistance_storage_water_heater',
            'electric_resistance_booster_water_heater',
            'heat_pump_storage_water_heater',
            'other',
            'scout_water_heater_type_not_defined'
          ]

          super(num_ts, end_use, 'supply', sub_end_use_enums)
        end
      end

      # Supply-side interior lighting sub end uses
      class InteriorLightingSupplySubEndUse < SubEndUseBase
        def initialize(num_ts, end_use)
          sub_end_use_enums = [
            'general',
            'other',
            'scout_interior_lighting_type_not_defined'
          ]

          super(num_ts, end_use, 'supply', sub_end_use_enums)
        end
      end

      # Supply-side interior lighting sub end uses
      class ExteriorLightingSupplySubEndUse < SubEndUseBase
        def initialize(num_ts, end_use)
          sub_end_use_enums = [
            'general',
            'parking_areas_and_drives',
            'building_facades',
            'main_entries',
            'other_doors',
            'entry_canopies',
            'emergency_canopies',
            'drive_through_windows',
            'base_site_allowance',
            'other',
            'scout_exterior_lighting_type_not_defined'
          ]

          super(num_ts, end_use, 'supply', sub_end_use_enums)
        end
      end

      # Supply-side exterior lighting sub end uses
      class InteriorEquipmentSupplySubEndUse < SubEndUseBase
        def initialize(num_ts, end_use)
          sub_end_use_enums = [
            'general',
            'elevators',
            'other',
            'scout_interior_equipment_type_not_defined'
          ]

          super(num_ts, end_use, 'supply', sub_end_use_enums)
        end
      end

      # Supply-side exterior lighting sub end uses
      class RefrigerationSupplySubEndUse < SubEndUseBase
        def initialize(num_ts, end_use)
          sub_end_use_enums = [
            'compressor',
            'refrigerated_case',
            'walkin',
            'condenser',
            'other',
            'scout_refrigeration_equipment_type_not_defined'
          ]

          super(num_ts, end_use, 'supply', sub_end_use_enums)
        end
      end

      # Supply and demand-side end uses
      class EndUse
        attr_reader :demand_end_uses_enums
        attr_reader :supply_end_use_enums

        # @param num_ts Number of timesteps
        def initialize(num_ts)
          @_supply_sub_end_uses = []
          @_demand_sub_end_uses = []

          # These are aligned with the EnergyPlus end use categories
          @supply_end_use_enums = [
            'heating',
            'cooling',
            'pumps',
            'fans',
            'water_systems',
            'interior_lighting',
            'exterior_lighting',
            'interior_equipment',
            'refrigeration'
            # TODO: Break down other E+ end uses at some point
            # exterior_equipment (currently only used to model some elevators)
            # heat_rejection (cooling towers, common on large buildings but low energy use)
            # humidification (not using this at all in ComStock yet?)
            # heat_recovery (energy recovery, pretty common but low energy use)
            # generators (not using this in ComStock)
          ]

          @demand_end_use_enums = [
            'heating',
            'cooling',
            'floating'
          ]

          @supply_end_use_enums.each do |end_use|
            case end_use
            when 'heating'
              @_supply_sub_end_uses << HeatingSupplySubEndUse.new(num_ts, end_use)
            when 'cooling'
              @_supply_sub_end_uses << CoolingSupplySubEndUse.new(num_ts, end_use)
            when 'pumps'
              @_supply_sub_end_uses << PumpsSupplySubEndUse.new(num_ts, end_use)
            when 'fans'
              @_supply_sub_end_uses << FansSupplySubEndUse.new(num_ts, end_use)
            when 'water_systems'
              @_supply_sub_end_uses << WaterSystemsSupplySubEndUse.new(num_ts, end_use)
            when 'interior_lighting'
              @_supply_sub_end_uses << InteriorLightingSupplySubEndUse.new(num_ts, end_use)
            when 'exterior_lighting'
              @_supply_sub_end_uses << ExteriorLightingSupplySubEndUse.new(num_ts, end_use)
            when 'interior_equipment'
              @_supply_sub_end_uses << InteriorEquipmentSupplySubEndUse.new(num_ts, end_use)
            when 'refrigeration'
              @_supply_sub_end_uses << RefrigerationSupplySubEndUse.new(num_ts, end_use)
            else
              # TODO: Define sub end uses for other end uses
            end
          end

          @demand_end_use_enums.each do |end_use|
            @_demand_sub_end_uses << HeatingOrCoolingDemandSubEndUse.new(num_ts, end_use)
          end
        end

        # @param end_use when nil, returns r all sub_end_uses,
        # but when a string is specified, returns Meter for that one sub_end_use.
        def supply(end_use = nil)
          return @_supply_sub_end_uses if end_use.nil?

          unless @supply_end_use_enums.include?(end_use)
            raise("#{end_use} is not a valid supply end use.  Valid choices are #{@supply_end_use_enums.join(', ')}")
          end

          sub_end_uses = @_supply_sub_end_uses.select { |dseu| dseu.end_use == end_use }
          if sub_end_uses.size > 1
            raise("There should only be 1 supply sub end use with the end_use #{end_use}, but there are #{sub_end_uses.size}")
          end

          return sub_end_uses.first
        end

        # @param end_use when nil, returns r all sub_end_uses,
        # but when a string is specified, returns Meter for that one sub_end_use.
        def demand(end_use = nil)
          return @_demand_sub_end_uses if end_use.nil?

          unless @demand_end_use_enums.include?(end_use)
            raise("#{end_use} is not a valid demand end use.  Valid choices are #{@demand_end_use_enums.join(', ')}")
          end

          sub_end_uses = @_demand_sub_end_uses.select { |dseu| dseu.end_use == end_use }
          if sub_end_uses.size > 1
            raise("There should only be 1 demand sub end use with the end_use #{end_use}, but there are #{sub_end_uses.size}")
          end

          return sub_end_uses.first
        end
      end

      # A set of SubEndUseMeters for each
      # possible combination of:
      # fuel type > end use > supply/demand > sub end use
      class MeterSet
        attr_accessor :end_use

        # @param num_ts Number of timesteps
        def initialize(num_ts)
          @end_use = EndUse.new(num_ts)
        end

        # Creates IDF objects for every meter in the MeterSet
        def all_supply_meter_idf_objects(model)
          idf_objects = []
          end_use.supply.each do |supply_end_use|
            supply_end_use.sub_end_use.each do |sub_end_use_meter|
              idf_objects += sub_end_use_meter.meter_idf_objects(model)
            end
          end

          return idf_objects
        end

        # Query the sql file based on the meter details defined
        # Only make queries for meters with key/value pairs
        def populate_supply_meter_timeseries(runner, sql, env_period, timestep, num_timesteps, expected_units = nil)
          end_use.supply.each do |supply_end_use|
            supply_end_use.sub_end_use.each do |meter|
              next if meter.eplus_key_var_pairs.size.zero?
              # Note: Must UPCASE meter name for custom meters!
              vals = OsLib_SqlFile.get_timeseries_array(runner, sql, env_period, timestep, meter.meter_name.upcase, '', num_timesteps, expected_units)
              end_use.supply(meter.end_use).add_vals_to_sub_end_use(meter.sub_end_use, meter.fuel_type, vals)
            end
          end

          return true
        end
      end

      # Convert the Scout fuel type into
      # the fuel type EnergyPlus meters expect for "Fuel Type" field inputs
      def self.energyplus_fuel_type_for_meter_input(fuel_type)
        case fuel_type.downcase
        when 'natural_gas', 'naturalgas'
          'NaturalGas'
        when 'electricity'
          'Electricity'
        when 'district_cooling'
          'DistrictCooling'
        when 'district_heating'
          'DistrictHeatingWater'
        when 'solar_energy'
          'SolarEnergy'
        when 'propane_gas'
          'PropaneGas'
        when 'fuel_oil_1'
          'FuelOil#1'
        when 'fuel_oil_2'
          'FuelOil#2'
        when 'coal'
          'Coal'
        when 'diesel'
          'Diesel'
        when 'gasoline'
          'Gasoline'
        when 'other_fuel_1'
          'OtherFuel1'
        when 'other_fuel_2'
          'OtherFuel2'
        end
      end

      # Convert the Scout fuel type into
      # the fuel type used by the default EnergyPlus meters,
      # which don't match the enumerations EnergyPlus uses in
      # the fuel type inputs for HVAC objects
      def self.energyplus_fuel_type_for_decrement_meter(fuel_type, model)
        case fuel_type
        when 'natural_gas'
          if model.version > OpenStudio::VersionString.new('3.0.1')
            'NaturalGas'
          else
            'Gas'
          end
        when 'electricity'
          'Electricity'
        when 'district_cooling'
          'DistrictCooling'
        when 'district_heating'
          'DistrictHeatingWater'
        when 'solar_energy'
          'SolarEnergy'
        when 'propane_gas'
          'PropaneGas'
        when 'fuel_oil_1'
          if model.version > OpenStudio::VersionString.new('3.0.1')
            'FuelOilNo1'
          else
            'FuelOil#1'
          end
        when 'fuel_oil_2'
          if model.version > OpenStudio::VersionString.new('3.0.1')
            'FuelOilNo2'
          else
            'FuelOil#2'
          end
        when 'coal'
          'Coal'
        when 'diesel'
          'Diesel'
        when 'gasoline'
          'Gasoline'
        when 'other_fuel_1'
          'OtherFuel1'
        when 'other_fuel_2'
          'OtherFuel2'
        end
      end

      # Convert the Scout end use name into
      # the EnergyPlus end use name
      def self.energyplus_end_use_type_for_meter_name_map(end_use)
        case end_use
        when 'fans'
          'Fans'
        when 'water_systems'
          'WaterSystems'
        when 'interior_lighting'
          'InteriorLights'
        when 'exterior_lighting'
          'ExteriorLights'
        when 'interior_equipment'
          'InteriorEquipment'
        else
          end_use
        end
      end
    end
  end
end

