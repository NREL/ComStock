

###### (Automatically generated documentation)

# Add Rooftop PV

## Description
This measure will create new shading surface geometry above the roof for each thermal zone inyour model where the surface azmith falls within the user specified range. Arguments are exposed for panel efficiency, inverter efficiency, and the fraction of each roof surface that has PV.

## Modeler Description
The fraction of surface containing PV will not only set the PV properties, but will also change the transmittance value for the shading surface. This allows the measure to avoid attempting to layout the panels. Simple PV will be used to model the PV.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Fraction of Surface Area with Active Solar Cells

**Name:** fraction_of_surface,
**Type:** Double,
**Units:** fraction,
**Required:** true,
**Model Dependent:** false

### Cell Efficiency

**Name:** cell_efficiency,
**Type:** Double,
**Units:** fraction,
**Required:** true,
**Model Dependent:** false

### Inverter Efficiency

**Name:** inverter_efficiency,
**Type:** Double,
**Units:** fraction,
**Required:** true,
**Model Dependent:** false




