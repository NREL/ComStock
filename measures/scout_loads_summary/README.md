

###### (Automatically generated documentation)

# Scout Loads Summary

## Description
Breaks the demand (heat gains and losses) down by sub-end-use (walls, windows, roof, etc.) and supply (things in building consuming energy) down by sub-end-use (hot water pumps, chilled water pumps, etc.) for use in Scout.

## Modeler Description
Uses zone- and surface- level output variables to break heat gains/losses down by building component.  Uses a series of custom meters to disaggregate the EnergyPlus end uses into sub-end-uses.  Warning: resulting sql files will very large because of the number of output variables and meters.  Measure will output results on a timestep basis if requested.

## Measure Type
ReportingMeasure

## Taxonomy


## Arguments


### Report timeseries data to csv file

**Name:** report_timeseries_data,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Enable/disable supply side reporting

**Name:** enable_supply_side_reporting,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Enable extra variables for debugging zone loads

**Name:** debug_mode,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false




