

###### (Automatically generated documentation)

# hvac_boiler

## Description
This measure gets an AFUE from the user, it compares it with current boilers in the model and increases the boilers AFUE in case it is lower than the chosen one.

## Modeler Description
This measure gets a value from the use, it loops through each boiler, it gets the thermal efficiency of each boiler.
            It is assumed AFUE = ThermalEfficiency, as indicated in the OpenStudio Standards.
            For each boiler, If the chosen AFUE is higher than the current boiler thermal efficiency, the latter is upgraded with the chosen AFUE.

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




