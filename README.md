# ComStock
ComStock is an NREL model of the U.S. commercial building stock. The model takes some building characteristics from the
U.S. Department of Energy's (DOE's) Commercial Prototype Building Models and Commercial Reference Building. However,
unlike many other building stock models, ComStock also combines these with a variety of additional public- and
private-sector data sets. Collectively, this information provides high-fidelity building stock representation with a
realistic diversity of building characteristics.

This repository contains the source code used to build and execute ComStock models, including upgrade scenarios. In
addition, the sampling of buildings characteristics used for the initial ComStock (V1.0) release is provided.  The ComStock model is under active calibration and development, which is publicly visible on this repository.

Execution of the ComStock workflow is managed through the [buildstockbatch repository](https://github.com/NREL/buildstockbatch), a shared asset of ResStock and ComStock,
specifically developed to scale to execution of tens of millions of simulations through multiple infrastructure
providers.

The dataset output from the initial ComStock (V1.0) release can be found at the accompanying
[ComStock data viewer website](https://comstock.nrel.gov) and additional information about ComStock found on the
[NREL Buildings Website](https://www.nrel.gov/buildings/comstock.html). For more details about ongoing model development
please consult the [End Use Load Profiles](https://www.nrel.gov/buildings/end-use-load-profiles.html) website.

ComStock is a direct result of the NREL residential stock modeling tool
[ResStock](https://www.nrel.gov/buildings/resstock.html) (recipient of a
[R&D100 award](https://www.rdworldonline.com/rd100/resstock-a-21st-century-tool-for-energy-efficiency-modeling-with-unparalleled-granularity/))
and was inspired by the high-fidelity solar & storage adoption model [dGen](https://www.nrel.gov/analysis/dgen/).
Additionally, this tool would not be possible without the decades of work undertaken by the
[OpenStudio](https://www.openstudio.net/) and [EnergyPlus](https://energyplus.net/) visionaries and contributors,
significant funding, feedback and support from the [Los Angeles Department of Water and Power](https://www.ladwp.com/),
and the [Department of Energy's Building Technology Office](https://www.energy.gov/eere/buildings/building-technologies-office)
ongoing support of and investment in building energy modeling software.

## Directories
- [**`/build`**](https://github.com/NREL/ComStock/tree/develop/build) contains instructions for building Singularity images for running ComStock on HPC systems.
- [**`/documentation`**](https://github.com/NREL/ComStock/tree/develop/documentation) contains LaTeX documentation and instructions for building the documentation.
- [**`/measures`**](https://github.com/NREL/ComStock/tree/develop/measures) contains the high-level "meta" measures used to call other measures, and the reporting measures used to summarize outputs.
- [**`/national`**](https://github.com/NREL/ComStock/tree/develop/national) contains seed directories necessary for a ComStock run using buildstockbatch.
- [**`/postprocessing`**](https://github.com/NREL/ComStock/tree/develop/postprocessing) contains postprocessing scripts to create graphics for viewing results and comparing to other data sources.
- [**`/resources`**](https://github.com/NREL/ComStock/tree/develop/resources) contains workflow and upgrade measures
- [**`/samples`**](https://github.com/NREL/ComStock/tree/develop/samples) contains sample buildstock.csv files, which describe the set of models included in a run.
- [**`/sampling`**](https://github.com/NREL/ComStock/tree/develop/sampling) contains instructions and code to generate buildstock.csv files.
- [**`/ymls`**](https://github.com/NREL/ComStock/tree/develop/ymls) contains sample .yml files, which are the configuration files used to execture a ComStock run with buildstockbatch.

## Usage
ComStock is under an open source license. See [LICENSE.txt](https://github.com/NREL/ComStock/blob/develop/LICENSE.txt) in this directory.
You are welcome to use this repository for your own use. However, we do not provide technical support. Please refer to our [technical assistance documentation](https://nrel.github.io/ComStock.github.io/docs/resources/resources.html) instead. We strongly suggest and support using the public datasets instead of attempting to run millions of building energy models yourself.
