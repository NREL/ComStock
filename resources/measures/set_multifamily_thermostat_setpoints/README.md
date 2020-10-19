

###### (Automatically generated documentation)

# Set Multifamily Thermostat Setpoints

## Description
Change the thermostat setpoints in multifamily (MFm) residential spaces to one of five typical thermostat setpoint patterns.

## Modeler Description
Creates new ruleset schedules following one of five typical thermostat setpoint patterns in the DEER MASControl database.  These are equal likelihood, and use an input of 1-5 to determine which schedule set to use. The same schedule applies to all residential space types in the building. 

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Template
Vintage year lookup for thermostat setpoint schedules.
**Name:** template,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Climate Zone

**Name:** climate_zone,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Thermostat Setpoint Schedule Index
Select one of five thermostat setpoint schedules to apply.
**Name:** tstat_index,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false




