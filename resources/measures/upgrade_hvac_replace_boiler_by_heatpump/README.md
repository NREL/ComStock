

###### (Automatically generated documentation)

# replace_boiler_by_heatpump

## Description
This measure replaces an exising natural gas boiler by an air source heat pump. An electric resister element or the existing boiler could be used as a back up heater.The heat pump could be sized to handle the entire heating load or a percentage of the heating load with a back up system handling the rest. 

## Modeler Description
This measure replaces an exising natural gas boiler by an air source heat pump. An electric resister element or the existing boiler could be used as a back up heater.The heat pump could be sized to handle the entire heating load or a percentage of the heating load with a back up system handling the rest.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Keep existing hot water loop setpoint?

**Name:** keep_setpoint,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Set hot water setpoint [F]
Applicable only if user chooses to change the existing hot water setpoint
**Name:** hw_setpoint_F,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Autosize heating coils?
Applicable only if user chooses to change the hot water setpoint
**Name:** autosize_hc,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Select heat pump water heater sizing method

**Name:** sizing_method,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### HP Sizing Temperature[F]
Applicable only if "Based on Outdoor Temperature" is selected for the sizing method
**Name:** hp_sizing_temp,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### HP Sizing Percentage[%]
Applicable only if "Percentage of Peak Load" is selected for the sizing method
**Name:** hp_sizing_per,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Rated ASHP heating capacity per unit [kW]

**Name:** hp_des_cap,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Select backup heater

**Name:** bu_type,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Set the heat pump cutoff temperature [F]

**Name:** hpwh_cutoff_T,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Set the heat pump design outdoor air temperature to base the performance data [F]

**Name:** hpwh_Design_OAT,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Set heat pump rated COP (heating)
Applicaeble if Custom Performance Data is selected
**Name:** cop,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false




