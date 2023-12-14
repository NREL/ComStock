

###### (Automatically generated documentation)

# Dispatch Schedule Generation

## Description
This measure reads in epw weather file, create outdoor air bins, pick sample days in bins and run simulation for samples to create dispactch schedule based on daily peaks

## Modeler Description
Replace this text with an explanation for the energy modeler specifically.  It should explain how the measure is modeled, including any requirements about how the baseline model must be set up, major assumptions, citations of references to applicable modeling resources, etc.  The energy modeler should be able to read this description and understand what changes the measure is making to the model and why these changes are being made.  Because the Modeler Description is written for an expert audience, using common abbreviations for brevity is good practice.

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

**Name:** sample_num_timesteps_in_hr,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false






