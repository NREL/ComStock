

###### (Automatically generated documentation)

# env_window

## Description
Replaces windows with more efficient versions. The two versions are double pane and high performance. The double pane window assumes 3mm clear glass with a 6mm air gap; U-3.122, SHGC-0.762, TSOL-0.705, TVIS-0.812. The high performance window assumes triple pane, 3mm low-e (e5=0.1) clear glass, 6mm air gap; U-1.772, SHGC-0.579, TSOL-0.458, TVIS-0.698.

## Modeler Description
First gets all building detailed fenestration surfaces. Loops over all detailed fenestration surfaces and checks to see if the surface type is a window. If the surface type is a window then it gets the then get the construction name. With the construction name it determines the simple glazing system object name. With the simple glazing system object name it modifies the U-Value, SHGC, and VLT accordingly.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


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




