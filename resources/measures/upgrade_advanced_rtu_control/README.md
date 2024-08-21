

###### (Automatically generated documentation)

# Advanced RTU Control

## Description
This measure implements advanced RTU controls, including a variable-speed fan, with options for economizing and demand-controlled ventilation.

## Modeler Description
This measure iterates through airloops, and, where applicable, replaces constant speed fans with variable speed fans, and replaces the existing zone terminal.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Economizer to be added?
Add economizer (true) or not (false)
**Name:** add_econo,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### DCV to be added?
Add DCV (true) or not (false)
**Name:** add_dcv,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false






