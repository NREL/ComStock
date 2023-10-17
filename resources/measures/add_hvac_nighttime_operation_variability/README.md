

###### (Automatically generated documentation)

# add_hvac_nighttime_operation_variability

## Description
Measure will set nighttime hvac operation behavior for fans and ventilation for PSZ and VAV systems. Fans can cycle  or run continuosly at night, and can do so with or without outdoor air ventilation.

## Modeler Description
Measure will modify the fan and outdoor air behavior of PSZ and VAV systems during their nighttime operations through schedule changes. Options are 1) RTUs runs continuosly through the night, both fans and ventialtion, 2) RTUs shut off at night but cycle fans when needed to maintain zone thermostat loads with ventilation or 3)  RTUs shut off at night but cycle fans when needed to maintain zone thermostat loads without ventilation. A fourth option is possible where RTUs run continuously at night but ventilation shuts off during unoccupied hours, but this is unlikely in building operation and not recommended. 

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### RTU Unoccupied Fan Behavior
This option will determine if the RTU fans run continuously through the night, or if they cycle at night only to meet thermostat requirements.
**Name:** rtu_night_mode,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false




