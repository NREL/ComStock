

###### (Automatically generated documentation)

# upgrade_hvac_pump

## Description
This measure evaluates the replacement of pumps with variable speed high-efficiency pumps in existing water-based systems for space heating and cooling, excluding domestic water heating. High-efficiency pumps considered in the measure refer to top-tier products currently available in the U.S. market as of July 2025. The nominal efficiencies of pump motors range from 91% to 96%, depending on the motor’s horsepower, compared to ComStock pumps, which typically range from 70% to 96%.

## Modeler Description
Constant-speed pumps in existing buildings are replaced with variable-speed pumps featuring advanced part-load performance enabled by modern control strategies. Older variable-speed pumps are upgraded to newer models with advanced part-load efficiency through modern control technologies, such as dynamic static pressure reset. Applicable to pumps used for space heating and cooling: chiller system, boiler system, and district heating and cooling system.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Add outdoor air temperature reset"\
    " for chilled water supply temperature?

**Name:** chw_oat_reset,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Add outdoor air temperature reset"\
    " for condenser water temperature?

**Name:** cw_oat_reset,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Print out detailed debugging logs"\
    " if this parameter is true

**Name:** debug_verbose,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false






