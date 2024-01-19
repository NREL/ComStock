# ComStock Meta and Reporting Measures

There are **TWO** measure directories on this GitHub repository.
This measure directory contains meta and reporting measures that do not require input arguments.

Workflow and upgrade measures are located under [resources/measures](https://github.com/NREL/ComStock/tree/main/resources/measures).

# Meta Measures

### BuildExistingModel
The output of this measure is a baseline building energy model. It takes the options (columnar inputs) for a single model (row) in the `buildstock.csv` file and converts them into a series of OpenStudio measures and measure arguments using the `options_lookup.tsv` file. The order of the options in the `options_lookup.tsv` file controls the order that the measures are executed. This measure executes a series of other measures, which is not the typical workflow that OpenStudio users may be familiar with.

### ApplyUpgrade
This measure applies upgrades to the baseline building energy model. It takes the options for each `upgrade` listed in the `YML` file and converts them into a series of OpenStudio measures and measure arguments using the `options_lookup.tsv` file. The order of the options in the `options_lookup.tsv` file controls the order that the measures are executed. This measure executes a series of other measures.

# Reporting Measures

### comstock_sensitivity_reports
This measure logs model properties such as envelope area and hvac system counts and weighted efficiencies. The variables help determine model output sensitivity to model inputs.

### emissions_reporting
This measure calculates greenhouse gas and criteria pollutant emissions using a range of emission factors, including [NREL Cambium](https://www.nrel.gov/analysis/cambium.html) emissions.

### la_100_qaqc
This measure runs several QAQC checks on the model.

### qoi_report
This measure reports Quantities of Interest (QOIs) which include peak demand, such as the average daily summer peak demand.

### run_directory_cleanup
This measure deletes most of the model run files after the simulation is complete to save drive space on large runs.

### scout_loads_summary
This measure attributes HVAC loads to their originating source, such as window solar gain, wall conduction, or delayed radiant gains from internal equipent.

### simulation_settings_check
This measure checks the year, start day of week, daylight savings, leap year, and timestep inputs and outputs.

### SimulationOutputReport
This measure reports out energy use and other outputs as register values.

### TimeseriesCSVExport
This measure exports all available hourly timeseries enduses to csv.