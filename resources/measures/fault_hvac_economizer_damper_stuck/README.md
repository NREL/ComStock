# Economizer Opening Stuck

## Description

Economizer outdoor air damper fully closed during faulted period. Fault intensity: damper fully closed. Fault prevalence: 35% of buildings with economizers. Fault incidence: once per year with the duration of one month. Fault evolution: not relevant so not implemented.
  
## Modeler Description

To use this fault measure, user can either select all economizers or one economizer in the model to impose fault. Incorrect changeover temperature can also be changed from default value of 10.88C.
  
## Measure Type

OpenStudio Measure 
	
## Taxonomy

HVAC.Energy Recovery

## Arguments 
  
econ_choice: economizer to impose fault
start_month: starting month of faulty operation
start_day: starting day of faulty operation
duration_days: duration of faulty operation in days
damper_pos: damper position
apply_measure: measure activation switch for debugging
 

