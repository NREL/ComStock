

###### (Automatically generated documentation)

# env_window_film

## Description
Adds window film to existing windows. Assumes window film reduces SHGC by 53.5% and VLT by 53%. These numbers are average values from Table 4 in Bahadori-Jahromi, Rotimi, Mylona, Godfrey, and Cook (2017). Sustainability, 9(5), 731; https://doi.org/10.3390/su9050731. The SHGC reduction is averaged from the second to last column (Heat Gain Reduction [%]) and the VLT reduction is averaged from the last column (Glare Reduction [%]).

## Modeler Description
First gets all building detailed fenestration surfaces. Loops over all detailed fenestration surfaces and checks to see if the surface type is a window. If the surface type is a window then it gets the then get the construction name. With the construction name it determines the simple glazing system object name. With the simple glazing system object name it decreases the SHGC by 53.5% and the VLT by 53%.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Percent SHGC Reduction

**Name:** pct_shgc_reduct,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Percent VLT Reduction

**Name:** pct_vlt_reduct,
**Type:** Double,
**Units:** ,
**Required:** true,
**Model Dependent:** false




