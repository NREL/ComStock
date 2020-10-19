# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2020, Alliance for Sustainable Energy, LLC.
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

class OpenStudio::Model::Model
  # Adds the HVAC system as derived from the combinations of CBECS 2012 MAINHT and MAINCL fields.
  # Mapping between combinations and HVAC systems per http://www.nrel.gov/docs/fy08osti/41956.pdf
  # Table C-31
  def add_cbecs_hvac_system(standard, system_type, zones)
    # the 'zones' argument includes zones that have heating, cooling, or both
    # if the HVAC system type serves a single zone, handle zones with only heating separately by adding unit heaters
    # applies to system types PTAC, PTHP, PSZ-AC, and Window AC
    heated_and_cooled_zones = zones.select { |zone| standard.thermal_zone_heated?(zone) && standard.thermal_zone_cooled?(zone) }
    heated_zones = zones.select { |zone| standard.thermal_zone_heated?(zone) }
    cooled_zones = zones.select { |zone| standard.thermal_zone_cooled?(zone) }
    cooled_only_zones = zones.select { |zone| !standard.thermal_zone_heated?(zone) && standard.thermal_zone_cooled?(zone) }
    heated_only_zones = zones.select { |zone| standard.thermal_zone_heated?(zone) && !standard.thermal_zone_cooled?(zone) }
    system_zones = heated_and_cooled_zones + cooled_only_zones

    # system type naming convention:
    # [ventilation strategy] [ cooling system and plant] [heating system and plant]

    case system_type

    when 'Baseboard electric'
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'Baseboard gas boiler'
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'Baseboard central air source heat pump'
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_only_zones)

    when 'Baseboard district hot water'
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)

    when 'Direct evap coolers with baseboard electric'
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)
      standard.model_add_hvac_system(self, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

    when 'Direct evap coolers with baseboard gas boiler'
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)
      standard.model_add_hvac_system(self, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

    when 'Direct evap coolers with baseboard central air source heat pump'
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_zones)
      standard.model_add_hvac_system(self, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

    when 'Direct evap coolers with baseboard district hot water'
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)
      standard.model_add_hvac_system(self, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

    when 'Direct evap coolers with forced air furnace'
      # Using unit heater to represent forced air furnace to limit to one airloop per thermal zone.
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)
      standard.model_add_hvac_system(self, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

    when 'Direct evap coolers with gas unit heaters'
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)
      standard.model_add_hvac_system(self, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

    when 'Direct evap coolers with no heat'
      standard.model_add_hvac_system(self, 'Evaporative Cooler', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

    when 'DOAS with fan coil chiller with boiler'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                     zone_equipment_ventilation: false)

    when 'DOAS with fan coil chiller with central air source heat pump'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones,
                                     zone_equipment_ventilation: false)

    when 'DOAS with fan coil chiller with district hot water'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones,
                                     zone_equipment_ventilation: false)

    when 'DOAS with fan coil chiller with baseboard electric'
      standard.model_add_hvac_system(self, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     zone_equipment_ventilation: false)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'DOAS with fan coil chiller with gas unit heaters'
      standard.model_add_hvac_system(self, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     zone_equipment_ventilation: false)
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'DOAS with fan coil chiller with no heat'
      standard.model_add_hvac_system(self, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     zone_equipment_ventilation: false)

    when 'DOAS with fan coil air-cooled chiller with boiler'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled',
                                     zone_equipment_ventilation: false)

    when 'DOAS with fan coil air-cooled chiller with central air source heat pump'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled',
                                     zone_equipment_ventilation: false)

    when 'DOAS with fan coil air-cooled chiller with district hot water'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled',
                                     zone_equipment_ventilation: false)

    when 'DOAS with fan coil air-cooled chiller with baseboard electric'
      standard.model_add_hvac_system(self, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled',
                                     zone_equipment_ventilation: false)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'DOAS with fan coil air-cooled chiller with gas unit heaters'
      standard.model_add_hvac_system(self, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled',
                                     zone_equipment_ventilation: false)
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'DOAS with fan coil air-cooled chiller with no heat'
      standard.model_add_hvac_system(self, 'DOAS', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled',
                                     zone_equipment_ventilation: false)

    when 'DOAS with fan coil district chilled water with boiler'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones,
                                     zone_equipment_ventilation: false)

    when 'DOAS with fan coil district chilled water with central air source heat pump'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'AirSourceHeatPump', znht = nil, cl = 'DistrictCooling', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'DistrictCooling', zones,
                                     zone_equipment_ventilation: false)

    when 'DOAS with fan coil district chilled water with district hot water'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones,
                                     zone_equipment_ventilation: false)

    when 'DOAS with fan coil district chilled water with baseboard electric'
      standard.model_add_hvac_system(self, 'DOAS', ht = nil, znht = nil, cl = 'DistrictCooling', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones,
                                     zone_equipment_ventilation: false)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'DOAS with fan coil district chilled water with gas unit heaters'
      standard.model_add_hvac_system(self, 'DOAS', ht = nil, znht = nil, cl = 'DistrictCooling', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones,
                                     zone_equipment_ventilation: false)
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'DOAS with fan coil district chilled water with no heat '
      standard.model_add_hvac_system(self, 'DOAS', ht = nil, znht = nil, cl = 'DistrictCooling', zones)
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones,
                                     zone_equipment_ventilation: false)

    when 'DOAS with VRF'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'Electricity', znht = nil, cl = 'Electricity', zones,
                                     air_loop_heating_type: 'DX',
                                     air_loop_cooling_type: 'DX')
      standard.model_add_hvac_system(self, 'VRF', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

    when 'DOAS with water source heat pumps fluid cooler with boiler'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Water Source Heat Pumps', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                     heat_pump_loop_cooling_type: 'FluidCooler',
                                     zone_equipment_ventilation: false)

    when 'DOAS with water source heat pumps cooling tower with boiler'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Water Source Heat Pumps', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                     heat_pump_loop_cooling_type: 'CoolingTower',
                                     zone_equipment_ventilation: false)

    when 'DOAS with water source heat pumps with ground source heat pump'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'Electricity', znht = nil, cl = 'Electricity', zones,
                                     air_loop_heating_type: 'DX',
                                     air_loop_cooling_type: 'DX')
      standard.model_add_hvac_system(self, 'Ground Source Heat Pumps', ht = 'Electricity', znht = nil, cl = 'Electricity', zones,
                                     zone_equipment_ventilation: false)

    when 'DOAS with water source heat pumps district chilled water with district hot water'
      standard.model_add_hvac_system(self, 'DOAS', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones)
      standard.model_add_hvac_system(self, 'Water Source Heat Pumps', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones,
                                     zone_equipment_ventilation: false)

    # ventilation provided by zone fan coil unit in fan coil systems
    when 'Fan coil chiller with boiler'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)

    when 'Fan coil chiller with central air source heat pump'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones)

    when 'Fan coil chiller with district hot water'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones)

    when 'Fan coil chiller with baseboard electric'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'Fan coil chiller with gas unit heaters'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'Fan coil chiller with no heat'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones)

    when 'Fan coil air-cooled chiller with boiler'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')

    when 'Fan coil air-cooled chiller with central air source heat pump'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')

    when 'Fan coil air-cooled chiller with district hot water'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')

    when 'Fan coil air-cooled chiller with baseboard electric'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'Fan coil air-cooled chiller with gas unit heaters'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'Fan coil air-cooled chiller with no heat'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')

    when 'Fan coil district chilled water with boiler'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones)

    when 'Fan coil district chilled water with central air source heat pump'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'AirSourceHeatPump', znht = nil, cl = 'DistrictCooling', zones)

    when 'Fan coil district chilled water with district hot water'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones)

    when 'Fan coil district chilled water with baseboard electric'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'Fan coil district chilled water with gas unit heaters'
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones)
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'Fan coil district chilled water with no heat '
      standard.model_add_hvac_system(self, 'Fan Coil', ht = nil, znht = nil, cl = 'DistrictCooling', zones)

    when 'Forced air furnace'
      # includes ventilation, whereas residential forced air furnace does not.
      standard.model_add_hvac_system(self, 'Forced Air Furnace', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'Gas unit heaters'
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'PTAC with baseboard electric'
      standard.model_add_hvac_system(self, 'PTAC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'PTAC with baseboard gas boiler'
      standard.model_add_hvac_system(self, 'PTAC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'PTAC with baseboard district hot water'
      standard.model_add_hvac_system(self, 'PTAC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)

    when 'PTAC with gas unit heaters'
      standard.model_add_hvac_system(self, 'PTAC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'PTAC with electric coil'
      standard.model_add_hvac_system(self, 'PTAC', ht = nil, znht = 'Electricity', cl = 'Electricity', system_zones)
      # use 'Baseboard electric' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

    when 'PTAC with gas coil'
      standard.model_add_hvac_system(self, 'PTAC', ht = nil, znht = 'NaturalGas', cl = 'Electricity', system_zones)
      # use 'Baseboard electric' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

    when 'PTAC with gas boiler'
      standard.model_add_hvac_system(self, 'PTAC', ht = 'NaturalGas', znht = nil, cl = 'Electricity', system_zones)
      # use 'Baseboard gas boiler' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_only_zones)

    when 'PTAC with central air source heat pump'
      standard.model_add_hvac_system(self, 'PTAC', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', system_zones)
      # use 'Baseboard central air source heat pump' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_only_zones)

    when 'PTAC with district hot water'
      standard.model_add_hvac_system(self, 'PTAC', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', system_zones)
      # use 'Baseboard district hot water heat' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_only_zones)

    when 'PTAC with no heat'
      standard.model_add_hvac_system(self, 'PTAC', ht = nil, znht = nil, cl = 'Electricity', system_zones)

    when 'PTHP'
      standard.model_add_hvac_system(self, 'PTHP', ht = 'Electricity', znht = nil, cl = 'Electricity', system_zones)
      # use 'Baseboard electric' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

    when 'PSZ-AC with baseboard electric'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'PSZ-AC with baseboard gas boiler'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'PSZ-AC with baseboard district hot water'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)

    when 'PSZ-AC with gas unit heaters'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = nil, cl = 'Electricity', system_zones)
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'PSZ-AC with electric coil'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = 'Electricity', cl = 'Electricity', system_zones)
      # use 'Baseboard electric' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

    when 'PSZ-AC with gas coil'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = 'NaturalGas', cl = 'Electricity', system_zones)
      # use 'Baseboard electric' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

    when 'PSZ-AC with gas boiler'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = 'NaturalGas', znht = nil, cl = 'Electricity', system_zones)
      # use 'Baseboard gas boiler' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_only_zones)

    when 'PSZ-AC with central air source heat pump'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = 'AirSourceHeatPump', znht = nil, cl = 'Electricity', system_zones)
      # use 'Baseboard central air source heat pump' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_only_zones)

    when 'PSZ-AC with district hot water'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = 'DistrictHeating', znht = nil, cl = 'Electricity', system_zones)
      # use 'Baseboard district hot water' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_only_zones)

    when 'PSZ-AC with no heat'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

    when 'PSZ-AC district chilled water with baseboard electric'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = nil, cl = 'DistrictCooling', system_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'PSZ-AC district chilled water with baseboard gas boiler'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = nil, cl = 'DistrictCooling', system_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'PSZ-AC district chilled water with gas unit heaters'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = nil, cl = 'DistrictCooling', system_zones)
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'PSZ-AC district chilled water with electric coil'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = 'Electricity', cl = 'DistrictCooling', system_zones)
      # use 'Baseboard electric' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

    when 'PSZ-AC district chilled water with gas coil'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = 'NaturalGas', cl = 'DistrictCooling', system_zones)
      # use 'Baseboard electric' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

    when 'PSZ-AC district chilled water with gas boiler'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', system_zones)
      # use 'Baseboard gas boiler' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_only_zones)

    when 'PSZ-AC district chilled water with central air source heat pump'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = 'AirSourceHeatPump', znht = nil, cl = 'DistrictCooling', system_zones)
      # use 'Baseboard central air source heat pump' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_only_zones)

    when 'PSZ-AC district chilled water with district hot water'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', system_zones)
      # use 'Baseboard district hot water' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_only_zones)

    when 'PSZ-AC district chilled water with no heat'
      standard.model_add_hvac_system(self, 'PSZ-AC', ht = nil, znht = nil, cl = 'DistrictCooling', cooled_zones)

    when 'PSZ-HP'
      standard.model_add_hvac_system(self, 'PSZ-HP', ht = 'Electricity', znht = nil, cl = 'Electricity', system_zones)
      # use 'Baseboard electric' for heated only zones
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_only_zones)

    # PVAV systems by default use a DX coil for cooling
    when 'PVAV with gas boiler reheat', 'Packaged VAV Air Loop with Boiler' # second enumeration for backwards compatibility with Tenant Star project
      standard.model_add_hvac_system(self, 'PVAV Reheat', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'Electricity', zones)

    when 'PVAV with central air source heat pump reheat'
      standard.model_add_hvac_system(self, 'PVAV Reheat', ht = 'AirSourceHeatPump', znht = 'AirSourceHeatPump', cl = 'Electricity', zones)

    when 'PVAV with district hot water reheat'
      standard.model_add_hvac_system(self, 'PVAV Reheat', ht = 'DistrictHeating', znht = 'DistrictHeating', cl = 'Electricity', zones)

    when 'PVAV with PFP boxes'
      standard.model_add_hvac_system(self, 'PVAV PFP Boxes', ht = 'Electricity', znht = 'Electricity', cl = 'Electricity', zones)

    when 'PVAV with gas heat with electric reheat'
      standard.model_add_hvac_system(self, 'PVAV Reheat', ht = 'Gas', znht = 'Electricity', cl = 'Electricity', zones)

    # all residential systems do not have ventilation
    when 'Residential AC with baseboard electric'
      standard.model_add_hvac_system(self, 'Residential AC', ht = nil, znht = nil, cl = nil, cooled_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'Residential AC with baseboard gas boiler'
      standard.model_add_hvac_system(self, 'Residential AC', ht = nil, znht = nil, cl = nil, cooled_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'Residential AC with baseboard central air source heat pump'
      standard.model_add_hvac_system(self, 'Residential AC', ht = nil, znht = nil, cl = nil, cooled_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_zones)

    when 'Residential AC with baseboard district hot water'
      standard.model_add_hvac_system(self, 'Residential AC', ht = nil, znht = nil, cl = nil, cooled_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)

    when 'Residential AC with residential forced air furnace'
      standard.model_add_hvac_system(self, 'Residential Forced Air Furnace with AC', ht = nil, znht = nil, cl = nil, zones)

    when 'Residential AC with no heat'
      standard.model_add_hvac_system(self, 'Residential AC', ht = nil, znht = nil, cl = nil, cooled_zones)

    when 'Residential heat pump'
      standard.model_add_hvac_system(self, 'Residential Air Source Heat Pump', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

    when 'Residential heat pump with no cooling'
      standard.model_add_hvac_system(self, 'Residential Air Source Heat Pump', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'Residential forced air furnace'
      standard.model_add_hvac_system(self, 'Residential Forced Air Furnace', ht = 'NaturalGas', znht = nil, cl = nil, zones)

    when 'VAV chiller with gas boiler reheat'
      standard.model_add_hvac_system(self, 'VAV Reheat', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'Electricity', zones)

    when 'VAV chiller with central air source heat pump reheat '
      standard.model_add_hvac_system(self, 'VAV Reheat', ht = 'AirSourceHeatPump', znht = 'AirSourceHeatPump', cl = 'Electricity', zones)

    when 'VAV chiller with district hot water reheat'
      standard.model_add_hvac_system(self, 'VAV Reheat', ht = 'DistrictHeating', znht = 'DistrictHeating', cl = 'Electricity', zones)

    when 'VAV chiller with PFP boxes'
      standard.model_add_hvac_system(self, 'VAV PFP Boxes', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'Electricity', zones)

    when 'VAV chiller with gas coil reheat'
      standard.model_add_hvac_system(self, 'VAV Gas Reheat', ht = 'NaturalGas', ht = 'NaturalGas', cl = 'Electricity', zones)

    when 'VAV chiller with no reheat with baseboard electric'
      standard.model_add_hvac_system(self, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'VAV chiller with no reheat with gas unit heaters'
      standard.model_add_hvac_system(self, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'VAV chiller with no reheat with zone heat pump'
      standard.model_add_hvac_system(self, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones)
      # Using PTHP to represent zone heat pump to limit to one airloop per thermal zone.
      standard.model_add_hvac_system(self, 'PTHP', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

    when 'VAV air-cooled chiller with gas boiler reheat'
      standard.model_add_hvac_system(self, 'VAV Reheat', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')

    when 'VAV air-cooled chiller with central air source heat pump reheat '
      standard.model_add_hvac_system(self, 'VAV Reheat', ht = 'AirSourceHeatPump', znht = 'AirSourceHeatPump', cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')

    when 'VAV air-cooled chiller with district hot water reheat'
      standard.model_add_hvac_system(self, 'VAV Reheat', ht = 'DistrictHeating', znht = 'DistrictHeating', cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')

    when 'VAV air-cooled chiller with PFP boxes'
      standard.model_add_hvac_system(self, 'VAV PFP Boxes', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')

    when 'VAV air-cooled chiller with gas coil reheat'
      standard.model_add_hvac_system(self, 'VAV Gas Reheat', ht = 'NaturalGas', ht = 'NaturalGas', cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')

    when 'VAV air-cooled chiller with no reheat with baseboard electric'
      standard.model_add_hvac_system(self, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'VAV air-cooled chiller with no reheat with gas unit heaters'
      standard.model_add_hvac_system(self, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'VAV air-cooled chiller with no reheat with zone heat pump'
      standard.model_add_hvac_system(self, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                     chilled_water_loop_cooling_type: 'AirCooled')
      # Using PTHP to represent zone heat pump to limit to one airloop per thermal zone.
      standard.model_add_hvac_system(self, 'PTHP', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

    when 'VAV district chilled water with gas boiler reheat'
      standard.model_add_hvac_system(self, 'VAV Reheat', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'DistrictCooling', zones)

    when 'VAV district chilled water with central air source heat pump reheat'
      standard.model_add_hvac_system(self, 'VAV Reheat', ht = 'AirSourceHeatPump', znht = 'AirSourceHeatPump', cl = 'DistrictCooling', zones)

    when 'VAV district chilled water with district hot water reheat'
      standard.model_add_hvac_system(self, 'VAV Reheat', ht = 'DistrictHeating', znht = 'DistrictHeating', cl = 'DistrictCooling', zones)

    when 'VAV district chilled water with PFP boxes'
      standard.model_add_hvac_system(self, 'VAV PFP Boxes', ht = 'NaturalGas', znht = 'NaturalGas', cl = 'DistrictCooling', zones)

    when 'VAV district chilled water with gas coil reheat'
      standard.model_add_hvac_system(self, 'VAV Gas Reheat', ht = 'NaturalGas', ht = 'NaturalGas', cl = 'DistrictCooling', zones)

    when 'VAV district chilled water with no reheat with baseboard electric'
      standard.model_add_hvac_system(self, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'VAV district chilled water with no reheat with gas unit heaters'
      standard.model_add_hvac_system(self, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones)
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'VAV district chilled water with no reheat with zone heat pump'
      standard.model_add_hvac_system(self, 'VAV No Reheat', ht = 'NaturalGas', znht = nil, cl = 'DistrictCooling', zones)
      # Using PTHP to represent zone heat pump to limit to one airloop per thermal zone.
      standard.model_add_hvac_system(self, 'PTHP', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

    when 'VRF'
      standard.model_add_hvac_system(self, 'VRF', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

    when 'Water source heat pumps fluid cooler with boiler'
      standard.model_add_hvac_system(self, 'Water Source Heat Pumps', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                     heat_pump_loop_cooling_type: 'FluidCooler')

    when 'Water source heat pumps cooling tower with boiler'
      standard.model_add_hvac_system(self, 'Water Source Heat Pumps', ht = 'NaturalGas', znht = nil, cl = 'Electricity', zones,
                                     heat_pump_loop_cooling_type: 'CoolingTower')

    when 'Water source heat pumps with ground source heat pump'
      standard.model_add_hvac_system(self, 'Ground Source Heat Pumps', ht = 'Electricity', znht = nil, cl = 'Electricity', zones)

    when 'Water source heat pumps district chilled water with district hot water'
      standard.model_add_hvac_system(self, 'Water Source Heat Pumps', ht = 'DistrictHeating', znht = nil, cl = 'DistrictCooling', zones)

    when 'Window AC with baseboard electric'
      standard.model_add_hvac_system(self, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'Electricity', znht = nil, cl = nil, heated_zones)

    when 'Window AC with baseboard gas boiler'
      standard.model_add_hvac_system(self, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'Window AC with baseboard central air source heat pump'
      standard.model_add_hvac_system(self, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'AirSourceHeatPump', znht = nil, cl = nil, heated_zones)

    when 'Window AC with baseboard district hot water'
      standard.model_add_hvac_system(self, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
      standard.model_add_hvac_system(self, 'Baseboards', ht = 'DistrictHeating', znht = nil, cl = nil, heated_zones)

    when 'Window AC with forced air furnace'
      standard.model_add_hvac_system(self, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
      standard.model_add_hvac_system(self, 'Forced Air Furnace', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'Window AC with unit heaters'
      standard.model_add_hvac_system(self, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)
      standard.model_add_hvac_system(self, 'Unit Heaters', ht = 'NaturalGas', znht = nil, cl = nil, heated_zones)

    when 'Window AC with no heat'
      standard.model_add_hvac_system(self, 'Window AC', ht = nil, znht = nil, cl = 'Electricity', cooled_zones)

    else
      puts "HVAC system type '#{system_type}' not recognized"
      return false
    end
    return true
  end
end
