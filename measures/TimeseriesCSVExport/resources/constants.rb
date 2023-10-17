# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

class Constants

  # Numbers --------------------
  
  def self.AssumedInsideTemp
    return 73.5 # deg-F
  end
  def self.DefaultCoolingSetpoint
    return 76.0
  end
  def self.DefaultFramingFactorCeiling
    return 0.11
  end
  def self.DefaultFramingFactorFloor
    return 0.13
  end
  def self.DefaultFramingFactorInterior
    return 0.16
  end
  def self.DefaultHeatingSetpoint
    return 71.0
  end
  def self.DefaultHumiditySetpoint
    return 0.60
  end
  def self.DefaultSolarAbsCeiling
    return 0.3
  end
  def self.DefaultSolarAbsFloor
    return 0.6
  end
  def self.DefaultSolarAbsWall
    return 0.5
  end
  def self.g
    return 32.174    # gravity (ft/s2)
  end
  def self.MixedUseT
    return 110 # F
  end
  def self.MinimumBasementHeight
    return 7 # ft
  end
  def self.MonthNumDays
    return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  end
  def self.NoCoolingSetpoint
    return 10000
  end
  def self.NoHeatingSetpoint
    return -10000
  end
  def self.Patm
    return 14.696 # standard atmospheric pressure (psia)
  end
  def self.small 
    return 1e-9
  end

  # Strings --------------------
  
  def self.AtticSpace
    return 'attic space'
  end
  def self.AtticZone
    return 'attic zone'
  end
  def self.Auto
    return 'auto'
  end
  def self.ColorWhite
    return 'white'
  end
  def self.ColorLight
    return 'light'
  end
  def self.ColorMedium
    return 'medium'
  end
  def self.ColorDark
    return 'dark'
  end
  def self.CoordRelative
    return 'relative'
  end
  def self.CoordAbsolute
    return 'absolute'
  end
  def self.BasementSpace
    return 'basement space'
  end
  def self.BasementZone
    return 'basement zone'
  end
  def self.BAZoneCold
    return 'Cold'
  end
  def self.BAZoneHotDry
    return 'Hot-Dry'
  end
  def self.BAZoneSubarctic
    return 'Subarctic'
  end
  def self.BAZoneHotHumid
    return 'Hot-Humid'
  end
  def self.BAZoneMixedHumid
    return 'Mixed-Humid'
  end
  def self.BAZoneMixedDry
    return 'Mixed-Dry'
  end
  def self.BAZoneMarine
    return 'Marine'
  end
  def self.BAZoneVeryCold
    return 'Very Cold'
  end
  def self.BoilerTypeCondensing
    return 'hot water, condensing'
  end
  def self.BoilerTypeNaturalDraft
    return 'hot water, natural draft'
  end
  def self.BoilerTypeForcedDraft
    return 'hot water, forced draft'
  end
  def self.BoilerTypeSteam
    return 'steam'
  end
  def self.BoreConfigSingle
    return 'single'
  end
  def self.BoreConfigLine
    return 'line'
  end
  def self.BoreConfigOpenRectangle
    return 'open-rectangle'
  end  
  def self.BoreConfigRectangle
    return 'rectangle'
  end
  def self.BoreConfigLconfig
    return 'l-config'
  end
  def self.BoreConfigL2config
    return 'l2-config'
  end  
  def self.BoreConfigUconfig
    return 'u-config'
  end 
  def self.BuildingAmericaClimateZone
    return 'Building America'
  end
  def self.BuildingTypeMultifamily
    return 'multifamily'
  end
  def self.BuildingTypeSingleFamilyAttached
    return 'singlefamilyttached'
  end
  def self.BuildingTypeSingleFamilyDetached
    return 'singlefamilydetached'
  end
  def self.BuildingUnitFeatureDHWSchedIndex
    return 'DHWSchedIndex'
  end
  def self.BuildingUnitFeatureUnitNumber
    return 'UnitNumber'
  end
  def self.BuildingUnitFeatureNumBathrooms
    return 'NumberOfBathrooms'
  end
  def self.BuildingUnitFeatureNumBedrooms
    return 'NumberOfBedrooms'
  end
  def self.BuildingUnitTypeResidential
    return 'Residential'
  end
  def self.CalcTypeERIRatedHome
    return 'HERS Rated Home'
  end
  def self.CalcTypeERIReferenceHome
    return 'HERS Reference Home'
  end
  def self.CalcTypeERIIndexAdjustmentDesign
    return 'HERS Index Adjustment Design'
  end
  def self.CalcTypeStandard
    return 'Standard'
  end
  def self.CeilingFanControlTypical
    return 'typical'
  end
  def self.CeilingFanControlSmart
    return 'smart'
  end
  def self.ClothesWasherDrumVolume(clothes_washer)
    return "#{__method__.to_s}|#{clothes_washer.handle.to_s}"
  end
  def self.ClothesWasherIMEF(clothes_washer)
    return "#{__method__.to_s}|#{clothes_washer.handle.to_s}"
  end
  def self.ClothesWasherRatedAnnualEnergy(clothes_washer)
    return "#{__method__.to_s}|#{clothes_washer.handle.to_s}"
  end
  def self.CondenserTypeWater
    return 'watercooled'
  end
  def self.CorridorSpace(story=1)
    s_story = ""
    if story > 1 or story == 0
      s_story = "|story #{story}"
    end
    return "corridor space#{s_story}"
  end
  def self.CorridorZone
    return 'corridor zone'
  end
  def self.CrawlFoundationType
    return 'crawlspace'
  end
  def self.CrawlSpace(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "crawl space#{s_unit}"
  end
  def self.CrawlZone(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "crawl zone#{s_unit}"
  end
  def self.Ducted
    return 'ducted'
  end
  def self.EndUseHVACFan
    return 'residential hvac fan'
  end
  def self.EndUseMechVentFan
    return 'residential mech vent fan'
  end
  def self.FacadeFront
    return 'front'
  end
  def self.FacadeBack
    return 'back'
  end
  def self.FacadeLeft
    return 'left'
  end
  def self.FacadeRight
    return 'right'
  end
  def self.FinishedAtticSpace(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "finished attic space#{s_unit}"
  end
  def self.FinishedAtticType
    return 'finished attic'
  end
  def self.FinishedAtticZone(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "finished attic zone#{s_unit}"
  end
  def self.FinishedBasementFoundationType
    return 'finished basement'
  end
  def self.FinishedBasementSpace(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "finished basement space#{s_unit}"
  end
  def self.FinishedBasementZone(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "finished basement zone#{s_unit}"
  end
  def self.FluidWater
    return 'water'
  end
  def self.FluidPropyleneGlycol
    return 'propylene-glycol'
  end
  def self.FluidEthyleneGlycol
    return 'ethylene-glycol'
  end
  def self.FuelTypeElectric
    return 'electric'
  end
  def self.FuelTypeGas
    return 'gas'
  end
  def self.FuelTypePropane
    return 'propane'
  end
  def self.FuelTypeOil
    return 'oil'
  end
  def self.GarageSpace(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "garage space#{s_unit}"
  end
  def self.GarageAtticSpace(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "garage attic space#{s_unit}"
  end
  def self.GarageFinishedAtticSpace(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "garage finished attic space#{s_unit}"
  end
  def self.GarageZone(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "garage zone#{s_unit}"
  end
  def self.LivingSpace(story=1, unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    s_story = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    if story > 1
      s_story = "|story #{story}"
    end
    return "living space#{s_unit}#{s_story}"
  end
  def self.LivingZone(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "living zone#{s_unit}"
  end
  def self.LocationInterior
    return 'interior'
  end
  def self.LocationExterior
    return 'exterior'
  end
  def self.MaterialCopper
    return 'copper'
  end
  def self.MaterialGypcrete
    return 'crete'
  end
  def self.MaterialGypsum
    return 'gyp'
  end
  def self.MaterialOSB
    return 'osb'
  end
  def self.MaterialPEX
    return 'pex'
  end
  def self.MaterialCeilingMass
    return 'ResCeilingMass1'
  end
  def self.MaterialCeilingMass2
    return 'ResCeilingMass2'
  end
  def self.MaterialFloorMass
    return 'ResFloorMass'
  end
  def self.MaterialFloorCovering
    return 'ResFloorCovering'
  end
  def self.MaterialFloorRigidIns
    return 'ResFloorRigidIns'
  end
  def self.MaterialFloorSheathing
    return 'ResFloorSheathing'
  end
  def self.MaterialRadiantBarrier
    return 'ResRadiantBarrier'
  end
  def self.MaterialRoofMaterial
    return 'ResRoofMaterial'
  end
  def self.MaterialRoofRigidIns
    return 'ResRoofRigidIns'
  end
  def self.MaterialRoofSheathing
    return 'ResRoofSheathing'
  end
  def self.MaterialWallExtFinish
    return 'ResExtFinish'
  end
  def self.MaterialWallMass
    return 'ResExtWallMass1'
  end
  def self.MaterialWallMass2
    return 'ResExtWallMass2'
  end
  def self.MaterialWallMassOtherSide
    return 'ResExtWallMassOtherSide1'
  end
  def self.MaterialWallMassOtherSide2
    return 'ResExtWallMassOtherSide2'
  end
  def self.MaterialWallRigidIns
    return 'ResExtWallRigidIns'
  end
  def self.MaterialWallSheathing
    return 'ResExtWallSheathing'
  end
  def self.PVModuleTypeStandard
    return 'standard'
  end
  def self.PVModuleTypePremium
    return 'premium'
  end
  def self.PVModuleTypeThinFilm
    return 'thin film'
  end
  def self.MonthNames
    return ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
  end
  def self.ObjectNameAirflow(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "res af#{s_unit}"
  end
  def self.ObjectNameAirSourceHeatPump(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential ashp#{s_unit}"
  end
  def self.ObjectNameBath(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential bath#{s_unit}"
  end
  def self.ObjectNameBathDist(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential bath dist#{s_unit}"
  end
  def self.ObjectNameBoiler(fueltype="", unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential boiler #{fueltype}#{s_unit}"
  end  
  def self.ObjectNameBuildingUnit(unit_num=1)
    return "unit #{unit_num}"
  end
  def self.ObjectNameCeilingFan(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential ceiling fan#{s_unit}"
  end
  def self.ObjectNameCentralAirConditioner(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential central ac#{s_unit}"
  end  
  def self.ObjectNameClothesWasher(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential clothes washer#{s_unit}"
  end
  def self.ObjectNameClothesDryer(fueltype, unit_name=self.ObjectNameBuildingUnit)
    s_fuel = ""
    if not fueltype.nil?
      s_fuel = " #{fueltype}"
    end
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential clothes dryer#{s_fuel}#{s_unit}"
  end
  def self.ObjectNameCookingRange(fueltype, ignition=false, unit_name=self.ObjectNameBuildingUnit)
    s_fuel = ""
    if not fueltype.nil?
      s_fuel = " #{fueltype}"
    end
    s_ignition = ""
    if ignition
      s_ignition = " ignition"
    end
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential range#{s_fuel}#{s_ignition}#{s_unit}"
  end
  def self.ObjectNameCoolingSeason
    return 'residential cooling season'
  end
  def self.ObjectNameCoolingSetpoint
    return 'residential cooling setpoint'
  end
  def self.ObjectNameDehumidifier(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential dehumidifier#{s_unit}"
  end
  def self.ObjectNameDishwasher(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential dishwasher#{s_unit}"
  end
  def self.ObjectNameDucts(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "res ds#{s_unit}"
  end  
  def self.ObjectNameEaves(facade="")
    if facade.nil?
      facade = ""
    end
    if facade != ""
      facade = " #{facade}"
    end
    return "residential eaves#{facade}"
  end
  def self.ObjectNameElectricBaseboard(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential baseboard#{s_unit}"
  end    
  def self.ObjectNameExtraRefrigerator(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential extra refrigerator#{s_unit}"
  end
  def self.ObjectNameFreezer(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential freezer#{s_unit}"
  end
  def self.ObjectNameFurnace(fueltype="", unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential furnace #{fueltype}#{s_unit}"
  end
  def self.ObjectNameFurnaceAndCentralAirConditioner(fueltype, unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential furnace #{fueltype} and central ac#{s_unit}"
  end  
  def self.ObjectNameFurniture
    return 'residential furniture'
  end
  def self.ObjectNameGasFireplace(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential gas fireplace#{s_unit}"
  end
  def self.ObjectNameGasGrill(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential gas grill#{s_unit}"
  end
  def self.ObjectNameGasLighting(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential gas lighting#{s_unit}"
  end
  def self.ObjectNameGroundSourceHeatPumpVerticalBore(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential gshp vert bore#{s_unit}"
  end
  def self.ObjectNameHeatingSeason
    return 'residential heating season'
  end
  def self.ObjectNameHeatingSetpoint
    return 'residential heating setpoint'
  end
  def self.ObjectNameHotTubHeater(fueltype, unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential hot tub heater #{fueltype}#{s_unit}"
  end
  def self.ObjectNameHotTubPump(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential hot tub pump#{s_unit}"
  end
  def self.ObjectNameHotWaterRecircPump(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential hot water recirc pump#{s_unit}"
  end
  def self.ObjectNameHotWaterDistribution(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential hot water distribution#{s_unit}"
  end
  def self.ObjectNameInfiltration(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "res infil#{s_unit}"
  end
  def self.ObjectNameLighting(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential lighting#{s_unit}"
  end
  def self.ObjectNameMechanicalVentilation(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "res mv#{s_unit}"
  end
  def self.ObjectNameMiniSplitHeatPump(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential mshp#{s_unit}"
  end
  def self.ObjectNameMiscPlugLoads(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential misc plug loads#{s_unit}"
  end
  def self.ObjectNameNaturalVentilation(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "res nv#{s_unit}"
  end
  def self.ObjectNameNeighbors(facade="")
    if facade.nil?
      facade = ""
    end
    if facade != ""
      facade = " #{facade}"
    end
    return "residential neighbors#{facade}"
  end  
  def self.ObjectNameOccupants(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential occupants#{s_unit}"
  end
  def self.ObjectNamePhotovoltaics(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential photovoltaics#{s_unit}"
  end
  def self.ObjectNamePoolHeater(fueltype, unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential pool heater #{fueltype}#{s_unit}"
  end
  def self.ObjectNamePoolPump(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential pool pump#{s_unit}"
  end
  def self.ObjectNameRefrigerator(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential refrigerator#{s_unit}"
  end
  def self.ObjectNameRelativeHumiditySetpoint
    return 'residential relative humidity setpoint'
  end
  def self.ObjectNameRoomAirConditioner(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential room ac#{s_unit}"
  end  
  def self.ObjectNameShower(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential shower#{s_unit}"
  end
  def self.ObjectNameShowerDist(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential shower dist#{s_unit}"
  end
  def self.ObjectNameSink(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential sink#{s_unit}"
  end
  def self.ObjectNameSinkDist(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential sink dist#{s_unit}"
  end
  def self.ObjectNameSolarHotWater(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "res solar hot water#{s_unit}"
  end
  def self.ObjectNameWaterHeater(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "res wh#{s_unit}"
  end
  def self.ObjectNameWellPump(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "residential well pump#{s_unit}"
  end
  def self.ObjectNameWindowShading
    return 'residential window shading'
  end
  def self.OptionTypeLightingFractions
    return 'Lamp Fractions'
  end
  def self.OptionTypeLightingEnergyUses
    return 'Annual Energy Uses'
  end
  def self.OptionTypePlugLoadsMultiplier
    return 'Multiplier'
  end
  def self.OptionTypePlugLoadsEnergyUse
    return 'Annual Energy Use'
  end
  def self.PierBeamFoundationType
    return "pier and beam"
  end
  def self.PierBeamSpace(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "pier and beam space#{s_unit}"
  end
  def self.PierBeamZone(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "pier and beam zone#{s_unit}"
  end
  def self.PipeTypeTrunkBranch
    return 'trunk and branch'
  end
  def self.PipeTypeHomeRun
    return 'home run'
  end
  def self.PlantLoopDomesticWater(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "Domestic Hot Water Loop#{s_unit}"
  end
  def self.PlantLoopSolarHotWater(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "Solar Hot Water Loop#{s_unit}"
  end  
  def self.RADuctZone
    return 'RA Duct Zone'
  end
  def self.RecircTypeTimer
    return 'timer'
  end
  def self.RecircTypeDemand
    return 'demand' 
  end
  def self.RecircTypeNone
    return 'none'
  end
  def self.RoofMaterialAsphaltShingles
    return 'asphalt shingles'
  end
  def self.RoofMaterialMembrane
    return 'membrane'
  end
  def self.RoofMaterialMetal
    return 'metal'
  end
  def self.RoofMaterialTarGravel
    return 'tar gravel'
  end
  def self.RoofMaterialTile
    return 'tile'
  end
  def self.RoofMaterialWoodShakes
    return 'wood shakes'
  end
  def self.RoofStructureRafter
    return 'rafter'
  end
  def self.RoofStructureTrussCantilever
    return 'truss, cantilever'
  end
  def self.RoofTypeFlat
    return 'flat'
  end
  def self.RoofTypeGable
    return 'gable'
  end
  def self.RoofTypeHip
    return 'hip'
  end
  def self.SeasonHeating
    return 'Heating'
  end
  def self.SeasonCooling
    return 'Cooling'
  end
  def self.SeasonOverlap
    return 'Overlap'
  end
  def self.SeasonNone
    return 'None'
  end
  def self.SizingAuto
    return 'autosize'
  end
  def self.SizingAutoMaxLoad
    return 'autosize for max load'
  end
  def self.SizingInfo(property, obj=nil)
    s_obj = ''
    if not obj.nil?
        s_obj = "|#{obj.handle.to_s}"
    end
    return "#{property}#{s_obj}"
  end
  def self.SizingInfoBasementWallInsulationHeight(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoBasementWallRvalue(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoCMUWallFurringInsRvalue(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoDuctsLocationFrac
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoDuctsLocationZone
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoDuctsReturnLoss
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoDuctsReturnRvalue
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoDuctsReturnSurfaceArea
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoDuctsSupplyLoss
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoDuctsSupplyRvalue
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoDuctsSupplySurfaceArea
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoGarageFracUnderFinishedSpace
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoGSHPBoreConfig
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoGSHPBoreDepth
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoGSHPBoreHoles
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoGSHPBoreSpacing
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoGSHPCoil_BF_FT_SPEC
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoGSHPCoilBF
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoGSHPUTubeSpacingType
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoHPSizedForMaxLoad
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoHVACCapacityDerateFactorCOP
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoHVACCapacityDerateFactorEER
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoHVACCapacityRatioCooling
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoHVACCapacityRatioHeating
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoHVACCoolingCFMs
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoHVACHeatingCapacityOffset
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoHVACHeatingCFMs
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoHVACRatedCFMperTonHeating
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoHVACRatedCFMperTonCooling
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoHVACSHR
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoMechVentType
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoMechVentApparentSensibleEffectiveness
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoMechVentLatentEffectiveness
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoMechVentTotalEfficiency
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoMechVentWholeHouseRate
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoMSHPIndices
    return self.SizingInfo(__method__.to_s)
  end
  def self.SizingInfoRoofCavityRvalue(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoRoofColor(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoRoofHasRadiantBarrier(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoRoofMaterial(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoRoofRigidInsRvalue(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoSIPWallInsThickness(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoSlabRvalue(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoSpaceCeilingInsulated(space)
    return self.SizingInfo(__method__.to_s, space)
  end
  def self.SizingInfoSpaceWallsInsulated(space)
    return self.SizingInfo(__method__.to_s, space)
  end
  def self.SizingInfoStudWallCavityRvalue(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoWallType(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoWallRigidInsRvalue(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoWallRigidInsThickness(surface)
    return self.SizingInfo(__method__.to_s, surface)
  end
  def self.SizingInfoZoneInfiltrationCFM(zone)
    return self.SizingInfo(__method__.to_s, zone)
  end
  def self.SizingInfoZoneInfiltrationELA(zone)
    return self.SizingInfo(__method__.to_s, zone)
  end
  def self.SlabFoundationType
    return 'slab'
  end
  def self.Standalone
    return 'standalone'
  end
  def self.TerrainOcean
    return 'ocean'
  end
  def self.TerrainPlains
    return 'plains'
  end
  def self.TerrainRural
    return 'rural'
  end
  def self.TerrainSuburban
    return 'suburban'
  end
  def self.TerrainCity
    return 'city'
  end
  def self.TiltPitch
    return 'pitch'
  end
  def self.TiltLatitude
    return 'latitude'
  end
  def self.UnfinishedAtticSpace(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "unfinished attic space#{s_unit}"
  end
  def self.UnfinishedAtticType
    return 'unfinished attic'
  end
  def self.UnfinishedAtticZone(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "unfinished attic zone#{s_unit}"
  end
  def self.UnfinishedBasementFoundationType
    return 'unfinished basement'
  end
  def self.UnfinishedBasementSpace(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "unfinished basement space#{s_unit}"
  end
  def self.UnfinishedBasementZone(unit_name=self.ObjectNameBuildingUnit)
    s_unit = ""
    if unit_name != self.ObjectNameBuildingUnit
      s_unit = "|#{unit_name}"
    end
    return "unfinished basement zone#{s_unit}"
  end
  def self.URBANoptFinishedZoneIdentifier
    return 'Story'
  end
  def self.VentTypeExhaust
    return 'exhaust'
  end
  def self.VentTypeNone
    return 'none'
  end
  def self.VentTypeSupply
    return 'supply'
  end
  def self.VentTypeBalanced
    return 'balanced'
  end
  def self.WaterHeaterTypeTankless
    return 'tankless'
  end
  def self.WaterHeaterTypeTank
    return 'tank'
  end
  def self.WaterHeaterTypeHeatPump
    return 'heatpump'
  end
  def self.WorkflowDescription
    return ' See https://github.com/NREL/OpenStudio-BEopt#workflows for supported workflows using this measure.'
  end
    
end
