

###### (Automatically generated documentation)

# hvac_furnace

## Description
This measure gets an AFUE from the user, it compares it with current furnaces in the model and increases the furnace AFUE in case it is lower than the chosen one.

## Modeler Description
This measure gets a value from the user for the desired AFUE, it loops through each furnace, and it gets the thermal efficiency of each gas coil.
            It is assumed AFUE = ThermalEfficiency, as indicated in the OpenStudio Standards.
            For each furnace, if the chosen AFUE is higher than the current furnace thermal efficiency, the latter is upgraded with the chosen AFUE.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Annual Fuel Use Efficiency

**Name:** afue,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false




