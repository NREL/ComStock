

###### (Automatically generated documentation)

# Upgrade HVAC Enable Ideal Air Loads

## Description
Replaces all HVAC systems with conceptual ZoneHVACIdealLoadsAirSystems to model building thermal loads.

## Modeler Description
All HVAC systems are removed and replaced with ZoneHVACIdealLoadsAirSystems objects. Outdoor ventilation air follows occupancy schedule, which may not align with the original HVAC ventilation schedule found in the baseline model. All thermostat schedules are held constant with baseline model. Energy from ZoneHVACIdealLoadsAirSystems is reported under district end uses, not necesarily aligning with the HVAC fuel type of the baseline model.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments




This measure does not have any user arguments


