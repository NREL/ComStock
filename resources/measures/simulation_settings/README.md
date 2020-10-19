

###### (Automatically generated documentation)

# Simulation Settings

## Description
Sets timestep, daylight savings, calendar year, and run period.

## Modeler Description
Sets timestep, daylight savings, calendar year, and run period.

## Measure Type
ModelMeasure

## Taxonomy


## Arguments


### Simulation Timestep
Simulation timesteps per hr
**Name:** timesteps_per_hr,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Enable Daylight Savings
Set to true to make model schedules observe daylight savings. Set to false if in a location where DST is not observed.
**Name:** enable_dst,
**Type:** Boolean,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Daylight Savings Starts
Only used if Enable Daylight Savings is true
**Name:** dst_start,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Daylight Savings Starts
Only used if Enable Daylight Savings is true
**Name:** dst_end,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Calendar Year
This will impact the day of the week the simulation starts on. An input value of 0 will leave the year un-altered
**Name:** calendar_year,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Day of Week that Jan 1st falls on
Only used if Calendar Year = 0.  If Calendar Year specified, use correct start day for that year.
**Name:** jan_first_day_of_wk,
**Type:** String,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Begin Month
First month of simulation
**Name:** begin_month,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### Begin Day
First day of simulation
**Name:** begin_day,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### End Month
Last month of simulation
**Name:** end_month,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false

### End Day
Last day of simulation
**Name:** end_day,
**Type:** Integer,
**Units:** ,
**Required:** true,
**Model Dependent:** false




