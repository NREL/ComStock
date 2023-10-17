

###### (Automatically generated documentation)

# env_window_film

## Description
Adds window film to ComStock's existing baseline windows.

## Modeler Description
First gets all building detailed fenestration surfaces. Loops over all detailed fenestration surfaces and checks to see if the surface type is a window. If the surface type is a window then it gets the corresponding construction objects. A hard-coded map is used to update the window performances (U-factor, SHGC, VLT) in relevant construction objects by leveraging ComStock's glazing system name and climate zone number as keys.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments




This measure does not have any user arguments


