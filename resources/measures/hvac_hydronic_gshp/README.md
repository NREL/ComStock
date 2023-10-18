

###### (Automatically generated documentation)

# Replace Boiler With GTHP

## Description
This measure replaces an exising natural gas boiler with a water source heat pump. An electric resister element or the existing boiler could be used as a back up heater.The heat pump could be sized to handle the entire heating load or a percentage of the heating load with a back up system handling the rest. 

## Modeler Description
This measure replaces an exising natural gas boiler with a water source heat pump. An electric resister element or the existing boiler could be used as a back up heater.The heat pump could be sized to handle the entire heating load or a percentage of the heating load with a back up system handling the rest.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Keep existing hot water loop setpoint_rev2?

**Name:** keep_setpoint,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Hot water setpoint
Applicable only if user chooses to change the existing hot water setpoint
**Name:** hw_setpoint_F,
**Type:** Double,
**Units:** F,
**Required:** true,
**Model Dependent:** false

### Autosize heating coils?
Applicable only if user chooses to change the hot water setpoint
**Name:** autosize_hc,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Rated capacity per heating heat pump
Rated capacity per heat pump used for heating
**Name:** hp_des_cap_htg,
**Type:** Double,
**Units:** kW,
**Required:** true,
**Model Dependent:** false

### Rated capacity per cooling heat pump
Rated capacity per heat pump used for cooling
**Name:** hp_des_cap_clg,
**Type:** Double,
**Units:** kW,
**Required:** true,
**Model Dependent:** false

### Set heat pump rated COP (heating)
Applicable if Custom Performance Data is selected
**Name:** cop,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false




