

###### (Automatically generated documentation)

# Unoccupied OA Controls

## Description
This measure sets minimum outdoor airflow to zero during extended periods of no occupancy (nighttime and weekends). Fans cycle during these unoccupied periods to meet the thermostat setpoints.

## Modeler Description
This measure ensures that the minimum outdoor air schedule aligns with the occupancy schedule of the building, so that fans cycling during unoccupied hours do not bring in outdoor air for ventilation. If the mininum OA schedule has been changed to a constant schedule through the nighttime operation variability measure, this measure reverts that. This measure continues to allow for air-side economizing during unoccupied hours, since it is only the minimum outdoor air level being modified.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments




This measure does not have any user arguments



