# Economizer incorrect changeover temperature

## Description

Changeover temperature for fixed dry-bulb control incorrectly configured. Fault intensity: changeover temperature = 10.88C (51.6F). Fault prevalence: 30% of buildings with economizers. Fault incidence: fault present whenever economizing. Fault evolution: not relevant so not implemented.
  
## Modeler Description

To use this fault measure, user can either select all economizers or one economizer in the model to impose fault. Incorrect changeover temperature can also be changed from default value of 10.88C.
  
## Measure Type

OpenStudio Measure 
	
## Taxonomy

HVAC.Energy Recovery

## Arguments 
  
econ_choice: economizer to impose fault
changeovertemp: changeover (highlimit) temperature for the fixed dry-bulb economizer 
apply_measure: measure activation switch for debugging
  

