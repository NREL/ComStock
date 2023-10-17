

###### (Automatically generated documentation)

# set_heating_fuel

## Description
Changes natural-gas-fired heating coils to either fuel oil or propane.  Not applicable when the input heating_fuel is NaturalGas, Electricity, DistrictHeating, or NoHeating, as the fuels for those systems are predetermined based on the HVAC system selection.

## Modeler Description
Should eventually be replaced by allowing specification of all fuels in create_typical_building_from_model

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Heating Fuel
The primary fuel used for space heating in the model.
**Name:** heating_fuel,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false




