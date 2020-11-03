# ComStock
ComStock is a U.S. Department of Energy (DOE) model of the U.S. commercial building stock, developed and maintained by
NREL. The model takes some building characteristics from the DOE Commercial Prototype Building Models and Commercial
Reference Building. However, unlike many other building stock models, ComStock also combines these with a variety of
additional public and private-sector data sets. Collectively, this information provides high-fidelity building stock
representation with a realistic diversity of building characteristics.

This repository contains the source code used to build and execute ComStock models, including upgrade scenarios. In
addition, the sampling of buildings characteristics used for the initial ComStock (V1.0) release is provided.  At present
the ComStock model is under active calibration and development, and as such this repository is not yet supported.

Execution of this repo is managed through the buildstockbatch repository, a shared asset of ResStock and ComStock,
specifically developed to scale to execution of tens of millions of simulations through multiple infrastructure
providers.This software is a pre-release beta and under active development. APIs and input schemas are subject to change
without notice. While good faith efforts are made to document use of the software, technical support is unavailable at this
time.

The results of the initial ComStock (V1.0) release can be found at the accompanying
[VizStock website](https://comstock.nrel.gov) and additional information about ComStock found on the
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
