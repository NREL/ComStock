

###### (Automatically generated documentation)

# EIFS Wall Insulation

## Description
EIFS is a layer of insulation that is applied to the outside walls of a building.  It is typically a layer of foam insulation covered by a thin layer of fiber mesh embedded in polymer.

## Modeler Description
Determine the thickness of expanded polystyrene insulation required to meet the specified R-value.  Find all the constructions used by exterior walls in the model, clone them, add a layer of insulation to the cloned constructions, and then assign the construction back to the wall.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Run Measure
integer argument to run measure [1 is run, 0 is no run]
**Name:** run_measure,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Insulation R-value

**Name:** r_val_ip,
**Type:** Double,
**Units:** ft^2*h*R/Btu,
**Required:** true,
**Model Dependent:** false




