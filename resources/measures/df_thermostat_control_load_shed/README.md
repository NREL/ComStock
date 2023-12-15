

###### (Automatically generated documentation)

# df thermostat control load shed

## Description
tbd

## Modeler Description
tbd

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Path to weather file (epw)

**Name:** input_path,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Length of dispatch window (hour)

**Name:** peak_len,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Length of rebound period after dispatch window (hour)

**Name:** rebound_len,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Path to output data CSV. INCLUDE .CSV EXTENSION

**Name:** output_path,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false


### Number/Count of timesteps in an hour for sample simulations

**Name:** num_timesteps_in_hr,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false






