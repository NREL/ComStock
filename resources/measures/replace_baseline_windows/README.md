

###### (Automatically generated documentation)

# replace_baseline_windows

## Description
Replaces the windows in the baseline based on window type TSV, which details distributions of pane types and corresponding U-value, SHGC, and VLT.

## Modeler Description
First gets all building detailed fenestration surfaces. Loops over all detailed fenestration surfaces and checks to see if the surface type is a window. If the surface type is a window then it gets the then get the construction name. With the construction name it determines the simple glazing system object name. With the simple glazing system object name it modifies the U-Value, SHGC, and VLT accordingly.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Window Pane Type
Identify window pane type to be applied to entire building
**Name:** window_pane_type,
**Type:** Choice,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Window U-value

**Name:** u_value_ip,
**Type:** Double,
**Units:** Btu/ft^2*h*R,
**Required:** true,
**Model Dependent:** false

### Window SHGC

**Name:** shgc,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Window VLT

**Name:** vlt,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false




