

###### (Automatically generated documentation)

# hvac_chiller

## Description
This measure gets an AFUE from the user, it compares it with current chillers in the model and increases the chillers AFUE in case it is lower than the chosen one.

## Modeler Description
This measure gets a value from the use, it loops through each chiller, it gets the thermal efficiency of each chiller.
            It is assumed AFUE = ThermalEfficiency, as indicated in the OpenStudio Standards.
            For each chiller, If the chosen AFUE is higher than the current chiller thermal efficiency, the latter is upgraded with the chosen AFUE.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Chiller Efficiency Level

**Name:** efficiency_level,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false




