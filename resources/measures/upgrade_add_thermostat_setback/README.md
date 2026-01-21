

###### (Automatically generated documentation)

# Upgrade_Add_Thermostat_Setback

## Description
This measure implements thermostat setbacks during unoccupied periods.

## Modeler Description
This measure implements thermostat setbacks during unoccupied periods.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Cooling setback magnitude
Setback magnitude in cooling.
**Name:** clg_setback,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Heating setback magnitude
Setback magnitude in heating.
**Name:** htg_setback,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Model an optimum start different from what currently exists?
True if yes; false if no. If false, any existing optimum starts will be preserved.
**Name:** opt_start,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Length of optimum start.
Length of period (in hours) over which optimum start takes place before occupancy. If previous argument is false, this option is disregarded.
**Name:** opt_start_len,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Minimum heating setpoint
Minimum heating setpoint
**Name:** htg_min,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Maximum cooling setpoint
Maximum cooling setpoint
**Name:** clg_max,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false






