

###### (Automatically generated documentation)

# upgrade_hvac_chiller

## Description
The UpgradeHvacChiller measure is designed to improve the energy efficiency and performance of HVAC systems by upgrading chillers, pumps, and control strategies in a building model. This measure reflects the latest performance of chillers in the current market (as of 2025 May) and provides options for upgrading air-cooled and water-cooled chillers, optimizing pump performance, and implementing advanced control strategies.

## Modeler Description
Chiller Upgrades: Replaces existing chillers with high-efficiency models. Supports both air-cooled and water-cooled chillers. Updates performance curves and adjusts reference COPs to reflect improved efficiency. Pump Upgrades: Updates pump motor efficiencies to meet ASHRAE 90.1-2019 standards. Optimizes part-load performance for variable-speed pumps. Control Strategy Enhancements: Adds outdoor air temperature reset for chilled water supply temperature. Implements condenser water temperature reset based on Appendix G of ASHRAE 90.1-2019. Detailed Reporting: Provides pre- and post-upgrade specifications for chillers, pumps, and control systems. Includes debugging options for detailed logs during measure execution.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Update pump specifications based on the latest 90.1 standards?

**Name:** upgrade_pump,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Add outdoor air temperature reset for chilled water supply temperature?

**Name:** chw_oat_reset,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Add outdoor air temperature reset for condenser water temperature?

**Name:** cw_oat_reset,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Print out detailed debugging logs if this parameter is true

**Name:** debug_verbose,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false






