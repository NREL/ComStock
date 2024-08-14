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

module OsLib_ScoutHVAC
  # Cast a generic component to its concrete class
  # based on the IDD object type.
  def self.component_to_concrete(component)
    obj_type = component.iddObjectType.valueName.to_s.gsub('OS_', '').gsub('_', '')
    concrete_component = component.public_send("to_#{obj_type}")
    if concrete_component.is_initialized
      component = concrete_component.get
    else
      puts "Could not cast #{obj_type} to concrete object, will return base class instance."
    end

    return component
  end

  # Get the heating fuel type of a plant loop
  # @Todo: If no heating equipment is found, check if there's a heat exchanger,
  # or a WaterHeater:Mixed or stratified that is connected to a heating source on the demand side
  def self.plant_loop_heating_fuels(plant_loop)
    fuels = []
    # Get the heating fuels for all supply components
    # on this plant loop.
    plant_loop.supplyComponents.each do |component|
      # Convert objects from HVACComponent class to their concrete class
      component = component_to_concrete(component)
      # Get the object type
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_Boiler_HotWater',
          'OS_Boiler_Steam'
        fuels << [component, scout_fuel_type_from_energyplus_fuel_type(component.fuelType)]
      when 'OS_DistrictHeating'
        fuels << [component, 'district_heating'] # TODO decide how to account for district heating
      when 'OS_HeatPump_WaterToWater_EquationFit_Heating'
        fuels << [component, 'electricity']
      when 'OS_SolarCollector_FlatPlate_PhotovoltaicThermal',
          'OS_SolarCollector_FlatPlate_Water',
          'OS_SolarCollector_IntegralCollectorStorage'
        fuels << [component, 'solar_energy']
      when 'OS_WaterHeater_HeatPump'
        fuels << [component, 'electricity']
      when 'OS_WaterHeater_Mixed'
        # Check if the heater actually has a capacity (otherwise it's simply a Storage Tank)
        if component.heaterMaximumCapacity.empty? || component.heaterMaximumCapacity.get != 0
          # If it does, we add the heater Fuel Type
          fuels << [component, scout_fuel_type_from_energyplus_fuel_type(component.heaterFuelType)]
        end  # @Todo: not sure about whether it should be an elsif or not
        # Check the plant loop connection on the source side
        if component.secondaryPlantLoop.is_initialized
          fuels += self.plant_loop_heating_fuels(component.secondaryPlantLoop.get)
        end
      when 'OS_WaterHeater_Stratified'
        # Check if the heater actually has a capacity (otherwise it's simply a Storage Tank)
        if component.heaterMaximumCapacity.empty? || component.heaterMaximumCapacity.get != 0
          # If it does, we add the heater Fuel Type
          fuels << [component, scout_fuel_type_from_energyplus_fuel_type(component.heaterFuelType)]
        end # @Todo: not sure about whether it should be an elsif or not
        # Check the plant loop connection on the source side
        if component.secondaryPlantLoop.is_initialized
          fuels += self.plant_loop_heating_fuels(component.secondaryPlantLoop.get)
        end
      when 'OS_HeatExchanger_FluidToFluid'
        cooling_hx_control_types = ["CoolingSetpointModulated", "CoolingSetpointOnOff", "CoolingDifferentialOnOff", "CoolingSetpointOnOffWithComponentOverride"]
        cooling_hx_control_types.each {|x| x.downcase!}
        if !cooling_hx_control_types.include?(component.controlType.downcase) && component.secondaryPlantLoop.is_initialized
          fuels += self.plant_loop_heating_fuels(component.secondaryPlantLoop.get)
        end
      when 'OS_Node',
          'OS_Pump_ConstantSpeed',
          'OS_Pump_VariableSpeed',
          'OS_Connector_Splitter',
          'OS_Connector_Mixer',
          'OS_Pipe_Adiabatic',
          'OS_HeaderedPumps_ConstantSpeed',
          'OS_HeaderedPumps_VariableSpeed'
        # These components do not provide heating
      else
        # OpenStudio::logFree(OpenStudio::Debug, 'openstudio.sizing.Model', "No heating fuel types found for #{obj_type}")
      end
    end

    return fuels.uniq.sort
  end

  # Get the cooling fuel type of a plant loop
  # Do not search for the fuel used for heat rejection
  # on the condenser loop.
  def self.plant_loop_cooling_fuels(plant_loop)
    fuels = []
    # Get the cooling fuels for all supply components
    # on this plant loop.
    plant_loop.supplyComponents.each do |component|
      # Convert objects from HVACComponent class to their concrete class
      component = component_to_concrete(component)
       # Get the object type
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_Chiller_Absorption'
        fuels << [component, 'natural_gas']
        # OpenStudio::logFree(OpenStudio::Warn, 'openstudio.sizing.Model', "Assuming NaturalGas as fuel for absorption chiller.")
      when 'OS_Chiller_Absorption_Indirect'
        fuels << [component, 'natural_gas']
        # OpenStudio::logFree(OpenStudio::Warn, 'openstudio.sizing.Model', "Assuming NaturalGas as fuel for absorption chiller indirect.")
      when 'OS_Chiller_Electric_EIR',
          'OS_CoolingTower_SingleSpeed',
          'OS_CoolingTower_TwoSpeed',
          'OS_CoolingTower_VariableSpeed',
          'OS_EvaporativeFluidCooler_SingleSpeed',
          'OS_EvaporativeFluidCooler_TwoSpeed',
          'OS_FluidCooler_SingleSpeed',
          'OS_FluidCooler_TwoSpeed'
        fuels << [component, 'electricity']
      when 'OS_DistrictCooling'
        # fuels << [component, 'district_cooling'] # TODO decide how to account for district cooling
      when 'OS_Node',
          'OS_Pump_ConstantSpeed',
          'OS_Pump_VariableSpeed',
          'OS_Connector_Splitter',
          'OS_Connector_Mixer',
          'OS_Pipe_Adiabatic',
          'OS_HeaderedPumps_ConstantSpeed',
          'OS_HeaderedPumps_VariableSpeed'
        # These components do not provide heating
      else
        #OpenStudio::logFree(OpenStudio::Debug, 'openstudio.sizing.Model', "No cooling fuel types found for #{obj_type}")
      end
    end

    return fuels.uniq.sort
  end

  # Get the heating fuel type of a heating coil
  def self.coil_heating_fuels(component)
    fuels = []
    # Convert objects from HVACComponent class to their concrete class
    component = component_to_concrete(component)
    # Get the object type
    obj_type = component.iddObjectType.valueName.to_s
    case obj_type
    when 'OS_Coil_Heating_DX_MultiSpeed',
        'OS_Coil_Heating_DX_SingleSpeed',
        'OS_Coil_Heating_DX_VariableRefrigerantFlow',
        'OS_Coil_Heating_DX_VariableSpeed',
        'OS_Coil_Heating_Desuperheater',
        'OS_Coil_Heating_Electric',
        'OS_Coil_WaterHeating_AirToWaterHeatPump',
        'OS_Coil_WaterHeating_Desuperheater'
      fuels << [component, 'electricity']
    when 'OS_Coil_Heating_Gas', 'OS_Coil_Heating_Gas_MultiStage'
      fuels << [component, 'natural_gas']
    when 'OS_Coil_Heating_Water',
        'OS_Coil_Heating_LowTemperatureRadiant_ConstantFlow',
        'OS_Coil_Heating_LowTemperatureRadiant_VariableFlow'
      if component.plantLoop.is_initialized
        fuels += self.plant_loop_heating_fuels(component.plantLoop.get)
      end
    when 'OS_Coil_Heating_WaterToAirHeatPump_EquationFit',
        'OS_Coil_Heating_WaterToAirHeatPump_VariableSpeedEquationFit'
      fuels << [component, 'electricity']
      if component.plantLoop.is_initialized
        fuels += self.plant_loop_heating_fuels(component.plantLoop.get)
      end
    else
      # OpenStudio::logFree(OpenStudio::Debug, 'openstudio.sizing.Model', "No heating fuel types found for #{obj_type}")
    end

    return fuels.uniq.sort
  end

  # Get the cooling fuel type of a cooling coil
  def self.coil_cooling_fuels(component)
    fuels = []
    # Convert objects from HVACComponent class to their concrete class
    component = component_to_concrete(component)
    # Get the object type
    obj_type = component.iddObjectType.valueName.to_s
    case obj_type
    when 'OS_Coil_Cooling_DX_MultiSpeed'
    'electricity'
    when 'OS_Coil_Cooling_DX_SingleSpeed',
        'OS_Coil_Cooling_DX_TwoSpeed',
        'OS_Coil_Cooling_DX_TwoStageWithHumidityControlMode',
        'OS_Coil_Cooling_DX_VariableRefrigerantFlow',
        'OS_Coil_Cooling_DX_VariableSpeed',
        'OS_Coil_Cooling_WaterToAirHeatPump_EquationFit',
        'OS_Coil_Cooling_WaterToAirHeatPump_VariableSpeed_EquationFit',
        'OS_CoilSystem_Cooling_DX_HeatExchangerAssisted',
        'OS_CoilSystem_Cooling_Water_HeatExchangerAssisted',
        'OS_HeatPump_WaterToWater_EquationFit_Cooling',
        'OS_Refrigeration_AirChiller'
      fuels << [component, 'electricity']
    when 'OS_Coil_Cooling_CooledBeam',
        'OS_Coil_Cooling_LowTemperatureRadiant_ConstantFlow',
        'OS_Coil_Cooling_LowTemperatureRadiant_VariableFlow',
        'OS_Coil_Cooling_Water'
      if component.plantLoop.is_initialized
        fuels += self.plant_loop_cooling_fuels(component.plantLoop.get)
      end
    else
      # OpenStudio::logFree(OpenStudio::Debug, 'openstudio.sizing.Model', "No cooling fuel types found for #{obj_type}")
    end

    return fuels.uniq.sort
  end

  # Get the heating fuels for a zone
  def self.zone_equipment_heating_fuels(zone)
    fuels = []
    # Get the heating fuels for all zone HVAC equipment
    zone.equipment.each do |component|
      # Convert objects from HVACComponent class to their concrete class
      component = component_to_concrete(component)
      # Get the object type
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirTerminal_SingleDuct_ConstantVolume_FourPipeInduction',
          'OS_ZoneHVAC_Baseboard_Convective_Water',
          'OS_ZoneHVAC_Baseboard_RadiantConvective_Water',
          'OS_ZoneHVAC_FourPipeFanCoil',
          'OS_ZoneHVAC_LowTemperatureRadiant_ConstantFlow',
          'OS_ZoneHVAC_LowTemperatureRadiant_VariableFlow',
          'OS_ZoneHVAC_UnitHeater',
          'OS_ZoneHVAC_PackagedTerminalAirConditioner',
          'OS_ZoneHVAC_WaterToAirHeatPump'
        fuels += self.coil_heating_fuels(component.heatingCoil)
      when 'OS_AirTerminal_SingleDuct_ConstantVolume_Reheat',
          'OS_AirTerminal_SingleDuct_ParallelPIUReheat',
          'OS_AirTerminal_SingleDuct_SeriesPIUReheat',
          'OS_AirTerminal_SingleDuct_VAVHeatAndCool_Reheat',
          'OS_AirTerminal_SingleDuct_VAV_Reheat'
        fuels += self.coil_heating_fuels(component.reheatCoil)
      when 'OS_AirTerminal_SingleDuct_InletSideMixer'
        # This component does not provide heating
      when 'OS_ZoneHVAC_UnitVentilator'
        if component.heatingCoil.is_initialized
          fuels += self.coil_heating_fuels(component.heatingCoil.get)
        end
      when 'OS_ZoneHVAC_Baseboard_Convective_Electric',
          'OS_ZoneHVAC_Baseboard_RadiantConvective_Electric',
          'OS_ZoneHVAC_LowTemperatureRadiant_Electric'
        'OS_ZoneHVAC_TerminalUnit_VariableRefrigerantFlow'
        fuels << [component, 'electricity']
      when 'OS_ZoneHVAC_HighTemperatureRadiant'
        fuels << [component, scout_fuel_type_from_energyplus_fuel_type(component.fuelType)]
      when 'OS_ZoneHVAC_IdealLoadsAirSystem'
        fuels << [component, 'district_heating']
      when 'OS_ZoneHVAC_PackagedTerminalHeatPump'
        fuels += self.coil_heating_fuels(component.heatingCoil)
        fuels += self.coil_heating_fuels(component.supplementalHeatingCoil)
      else
        # OpenStudio::logFree(OpenStudio::Debug, 'openstudio.sizing.Model', "No heating fuel types found for #{obj_type}")
      end
    end

    return fuels.uniq.sort
  end

  # Get the cooling fuels for a zone
  def self.zone_equipment_cooling_fuels(zone)
    fuels = []
    # Get the cooling fuels for all zone HVAC equipment
    zone.equipment.each do |component|
      # Convert objects from HVACComponent class to their concrete class
      component = component_to_concrete(component)
      # Get the object type
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirTerminal_SingleDuct_ConstantVolume_CooledBeam'
        fuels += self.coil_cooling_fuels(component.coilCoolingCooledBeam)
      when 'OS_AirTerminal_SingleDuct_ConstantVolume_FourPipeInduction'
        if component.coolingCoil.is_initialized
          fuels += self.coil_cooling_fuels(component.coolingCoil.get)
        end
      when 'OS_ZoneHVAC_FourPipeFanCoil',
          'OS_ZoneHVAC_LowTemperatureRadiant_ConstantFlow',
          'OS_ZoneHVAC_LowTemperatureRadiant_VariableFlow',
          'OS_ZoneHVAC_PackagedTerminalAirConditioner',
          'OS_ZoneHVAC_PackagedTerminalHeatPump'
        fuels += self.coil_cooling_fuels(component.coolingCoil)
      when 'OS_Refrigeration_AirChiller'
        'OS_ZoneHVAC_TerminalUnit_VariableRefrigerantFlow'
        fuels << [component, 'electricity']
      when 'OS_ZoneHVAC_IdealLoadsAirSystem'
        fuels << [component, 'DistrictCooling']
      else
        # OpenStudio::logFree(OpenStudio::Debug, 'openstudio.sizing.Model', "No cooling fuel types found for #{obj_type}")
      end
    end

    return fuels.uniq.sort
  end

  # Get the heating fuels for a zones airloop
  def self.zone_airloop_heating_fuels(zone)
    fuels = []
    # Get the air loop that serves this zone
    air_loop = zone.airLoopHVAC
    if air_loop.empty?
      return fuels.uniq.sort
    end
    air_loop = air_loop.get

    # Find fuel types of all equipment
    # on the supply side of this airloop.
    air_loop.supplyComponents.each do |component|
      # Convert objects from HVACComponent class to their concrete class
      component = component_to_concrete(component)
      # Get the object type
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
        fuels += self.coil_heating_fuels(component.heatingCoil)
      when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir'
        fuels += self.coil_heating_fuels(component.heatingCoil)
      when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed'
        fuels += self.coil_heating_fuels(component.heatingCoil)
      when 'OS_AirLoopHVAC_UnitarySystem'
        if component.heatingCoil.is_initialized
          fuels += self.coil_heating_fuels(component.heatingCoil.get)
        end
      when 'OS_Coil_Heating_DX_MultiSpeed',
          'OS_Coil_Heating_DX_SingleSpeed',
          'OS_Coil_Heating_DX_VariableSpeed',
          'OS_Coil_Heating_Desuperheater',
          'OS_Coil_Heating_Electric',
          'OS_Coil_Heating_Gas',
          'OS_Coil_Heating_Gas_MultiStage',
          'OS_Coil_Heating_Water',
          'OS_Coil_Heating_WaterToAirHeatPump_EquationFit',
          'OS_Coil_Heating_WaterToAirHeatPump_VariableSpeed_EquationFit',
          'OS_Coil_WaterHeating_AirToWaterHeatPump',
          'OS_Coil_WaterHeating_Desuperheater'
        fuels += self.coil_heating_fuels(component)
      when 'OS_Node',
          'OS_Fan_ConstantVolume',
          'OS_Fan_VariableVolume',
          'OS_AirLoopHVAC_OutdoorAirSystem'
        # These components do not provide heating
      else
        # OpenStudio::logFree(OpenStudio::Debug, 'openstudio.sizing.Model', "No heating fuel types found for #{obj_type}")
      end
    end

    return fuels.uniq.sort
  end

  # Get the cooling fuels for a zones airloop
  def self.zone_airloop_cooling_fuels(zone)
    fuels = []
    # Get the air loop that serves this zone
    air_loop = zone.airLoopHVAC
    if air_loop.empty?
      return fuels.uniq.sort
    end
    air_loop = air_loop.get

    # Find fuel types of all equipment
    # on the supply side of this airloop.
    air_loop.supplyComponents.each do |component|
      # Convert objects from HVACComponent class to their concrete class
      component = component_to_concrete(component)
      # Get the object type
      obj_type = component.iddObjectType.valueName.to_s
      case obj_type
      when 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass',
          'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir',
          'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed'
        fuels += self.coil_cooling_fuels(component.coolingCoil)
      when 'OS_AirLoopHVAC_UnitarySystem'
        if component.coolingCoil.is_initialized
          fuels += self.coil_cooling_fuels(component.coolingCoil.get)
        end
      when 'OS_EvaporativeCooler_Direct_ResearchSpecial',
          'OS_EvaporativeCooler_Indirect_ResearchSpecial'
        fuels << [component, 'electricity']
      when 'OS_Coil_Cooling_DX_MultiSpeed',
          'OS_Coil_Cooling_DX_TwoSpeed',
          'OS_Coil_Cooling_DX_TwoStageWithHumidityControlMode',
          'OS_Coil_Cooling_DX_VariableRefrigerantFlow',
          'OS_Coil_Cooling_DX_VariableSpeed',
          'OS_Coil_Cooling_WaterToAirHeatPump_EquationFit',
          'OS_Coil_Cooling_WaterToAirHeatPump_VariableSpeed_EquationFit',
          'OS_CoilSystem_Cooling_DX_HeatExchangerAssisted',
          'OS_CoilSystem_Cooling_Water_HeatExchangerAssisted',
          'OS_Coil_Cooling_Water',
          'OS_HeatPump_WaterToWater_EquationFit_Cooling'
        fuels += self.coil_cooling_fuels(component)
      when 'OS_Coil_Cooling_DX_SingleSpeed'
        fuels += self.coil_cooling_fuels(component_to_concrete(component))
      when 'OS_Node',
          'OS_Fan_ConstantVolume',
          'OS_Fan_VariableVolume',
          'OS_AirLoopHVAC_OutdoorAirSystem'
        # These components do not provide cooling
      else
        # OpenStudio::logFree(OpenStudio::Debug, 'openstudio.sizing.Model', "No heating fuel types found for #{obj_type}")
      end
    end

    return fuels.uniq.sort
  end

  # Get all of the HVAC equipment providing heating to this zone
  def self.zone_all_heating_equipment(zone)
    return (zone_equipment_heating_fuels(zone) + zone_airloop_heating_fuels(zone)).uniq
  end

  # Get all of the HVAC equipment providing heating to this zone
  def self.model_all_heating_equipment(model)
    all_equip = []
    model.getThermalZones.each do |zone|
      all_equip += zone_all_heating_equipment(zone)
    end

    return all_equip.uniq
  end

  # Get all of the HVAC equipment providing cooling to this zone
  def self.zone_all_cooling_equipment(zone)
    return (zone_equipment_cooling_fuels(zone) + zone_airloop_cooling_fuels(zone)).uniq
  end

  # Get all of the HVAC equipment providing cooling to this zone
  def self.model_all_cooling_equipment(model)
    all_equip = []
    model.getThermalZones.each do |zone|
      all_equip += zone_all_cooling_equipment(zone)
    end

    return all_equip.uniq
  end

  # Convert the EnergyPlus HVAC object fuel type enumerations
  # into the Scout fuel types
  def self.scout_fuel_type_from_energyplus_fuel_type(energyplus_fuel_type)
    case energyplus_fuel_type
    when 'NaturalGas'
      'natural_gas'
    when 'Electricity'
      'electricity'
    when 'DistrictCooling'
      'district_cooling'
    when 'DistrictHeating'
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
