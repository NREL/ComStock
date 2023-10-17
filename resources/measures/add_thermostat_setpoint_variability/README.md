

###### (Automatically generated documentation)

# add_thermostat_setpoint_variability

## Description
Measure will alter the models current thermostat setpoint and setback behavior. If user selects no_setback, the measure will remove heating and cooling thermostat setbacks if they exist. If the user selects setback, the model will add setbacks if none exist. The measure will also alter a models setpoint and setback delta based on user-input values. MEASURE SHOULD BE USED WITH SQUARE-WAVE SCHEDULES ONLY.

## Modeler Description
Measure will alter the models current thermostat setpoint and setback behavior. If user selects no_setback, the measure will remove heating and cooling thermostat setbacks if they exist. If the user selects setback, the model will add setbacks if none exist. The measure will also alter a models setpoint and setback delta based on user-input values. MEASURE SHOULD BE USED WITH SQUARE-WAVE SCHEDULES ONLY. 

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Cooling Thermostat Occupied Setpoint
Enter 999 for no change to setpoint.
**Name:** clg_sp_f,
**Type:** Double,
**Units:** F,
**Required:** true,
**Model Dependent:** false

### Cooling Thermostat Delta Setback
Enter 999 for no change to setback.
**Name:** clg_delta_f,
**Type:** Double,
**Units:** F,
**Required:** true,
**Model Dependent:** false

### Heating Thermostat Occupied Setpoint
Enter 999 for no change to setpoint.
**Name:** htg_sp_f,
**Type:** Double,
**Units:** F,
**Required:** true,
**Model Dependent:** false

### Heating Thermostat Delta Setback
Enter 999 for no change to setback.
**Name:** htg_delta_f,
**Type:** Double,
**Units:** F,
**Required:** true,
**Model Dependent:** false




