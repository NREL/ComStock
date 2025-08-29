

###### (Automatically generated documentation)

# Heat Recovery Chiller

## Description
This measure adds a heat recovery chiller and heat recovery loop to the model. The heat recovery chiller may be an existing chiller or new stand-alone heat recovery chiller. Converting an existing chiller will allow the chiller to rejected heat to the heat recovery loop in addition to the condenser loop. A new chiller will reject heat only to the heat recovery loop. The user may specify how to connect the heat recovery loop to the hot water loop, whether the heat recovery is in series or parallel with existing heating source objects, and optionally decide whether to adjust hot water loop temperatures and add output variables. The measure DOES NOT size the heat recovery chiller or heat recovery storage objects.

## Modeler Description
This creates a new heat recovery loop that is attached to a tertiary node to an existing chiller or a new chiller. The heat recovery loop consists of the chiller and a water heater mixed object that is also connected to a hot water loop. The heat recovery loop and hot water loop are sized to the same user defined temperature setpoint as well as all hot water coils in the model.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Cooling Loop
Choose the source loop for the heat recovery chiller. Infer From Model will use the chilled water loop by floor area served.
**Name:** cooling_loop_name,
**Type:** Choice,
**Units:** ,
**Required:** false,
**Model Dependent:** true


### Heating Loop
Choose the receipient loop for the heat recovery chiller. Infer From Model will use the largest hot water loop by floor area served.
**Name:** heating_loop_name,
**Type:** Choice,
**Units:** ,
**Required:** false,
**Model Dependent:** true


### Add new heat recovery chiller or use existing chiller?
The default is to add a new heat recovery chiller, otherwise the user will need to select an existing chiller.
**Name:** chiller_choice,
**Type:** Choice,
**Units:** ,
**Required:** false,
**Model Dependent:** true


### New heat recovery chiller size in tons cooling
Only applicable if add_new_chiller is set to true.
**Name:** new_chiller_size_tons,
**Type:** Double,
**Units:** ,
**Required:** false,
**Model Dependent:** false


### Existing Chiller to Convert
Only applicable if converting an existing chiller. Choose a chiller to convert to a heat recovery chiller. Infer from model will default to the first chiller on the selected chilled water loop.
**Name:** existing_chiller_name,
**Type:** Choice,
**Units:** ,
**Required:** false,
**Model Dependent:** true


### Heat recovery loop to hot water loop connection
Choose whether to connect the heat recovery loop to the hot water loop directly, or including a storage tank.
**Name:** link_option,
**Type:** Choice,
**Units:** ,
**Required:** false,
**Model Dependent:** true


### Heat recovery storage tank size in gallons
Only applicable if using a storage tank.
**Name:** storage_tank_size_gal,
**Type:** Double,
**Units:** ,
**Required:** false,
**Model Dependent:** false


### Hot water loop heat recovery ordering
Choose whether the heat recovery connection is in parallel or series with the existing hot water source object (boiler, heat pump, district heat, etc.).
**Name:** heating_order,
**Type:** Choice,
**Units:** ,
**Required:** false,
**Model Dependent:** true


### The heat recovery loop temperature in degrees F

**Name:** heat_recovery_loop_temperature_f,
**Type:** Double,
**Units:** ,
**Required:** false,
**Model Dependent:** false


### Reset hot water loop temperature?
If true, the measure will reset the hot water loop temperature to match the heat recovery loop temperature. It WILL NOT reset demand side coil objects, which could cause simulation errors or unmet hours. If the hot water loop is connected to the heat recovery loop by a heat exchanger instead of a storage tank, the hot water loop temperature will instead be reset to the heat recovery loop temperature minus 5F.
**Name:** reset_hot_water_loop_temperature,
**Type:** Boolean,
**Units:** ,
**Required:** false,
**Model Dependent:** false


### Reset heating coil design temperatures?
If true, the measure will reset the heating coil design temperatures to match the heat recovery loop temperature.
**Name:** reset_heating_coil_design_temp,
**Type:** Boolean,
**Units:** ,
**Required:** false,
**Model Dependent:** false


### Enable output variables?

**Name:** enable_output_variables,
**Type:** Boolean,
**Units:** ,
**Required:** false,
**Model Dependent:** false






