# ComStock Sampling
This documentation outlines how to generate a sample to be run in ComStock.
Before running these scripts, please set up credentials for accessing the S3 RESBLDG account and create a new conda environment.

## Installation
Navigate to the `/sampling` directory of this repo:
```
$ cd /path/to/comstock/sampling
```

Create a new environment from the environment.yml file containing the packages needed for this repository:
```
$ conda env create -f environment.yml
```

This only needs to be done once because it will create a new environment called `comstock-sampling`. Before you begin running the sampling scripts, activate the environment:
```
$ conda activate comstock-sampling
```

Install buildstockbatch in comstock-sampling environment: navigate to location of buildstock batch, e.g.:
```
$ cd /path/to/buildstockbatch
$ python -m pip install -e .
```

## AWS Access

### Non-NREL Staff

To download your BuildStockBatch simulation results from S3 for postprocessing, you’ll need to configure your user account with your AWS credentials. This setup only needs to be done once.

1. [Install the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html) version 2
2. [Configure the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html#cli-quick-configuration). (Don’t type the `$` in the example.)
3. You may need to [change the Athena Engine version](https://docs.aws.amazon.com/athena/latest/ug/engine-versions-changing.html) for your query workgroup to v2 or v3.

### NREL Staff

NREL now uses a refreshable Single Sign On (SSO) approach for authentication of accounts.

### If you have already configured the SSO for the resbldg AWS account:

1. Set the `AWS_DEFAULT_PROFILE` environment variable to the alias for your AWS resbldg SSO account.
    - On Windows, the command is `set AWS_DEFAULT_PROFILE=my_resbldg_account_alias`
    - On OSX, the command is `export AWS_DEFAULT_PROFILE=my_resbldg_account_alias`
2. Run the following command to activate the SSO: `aws sso login` - follow the prompts in the webpage

You're now ready to execute the commands below! In case of an AWS access error please begin by running the login command again. The SSO does time out eventually.

### To configure SSO for the resbldg account

Note: Access to the SSO requires an NREL network account. We do not currently support use of the sampler for users without an NREL account.

1. Go to the [NREL AWS SSO page](https://nrel-ace.awsapps.com/start#/) and click on the AWS Account button.
2. Click on the NREL AWS RESBLDG dropdown. If you do not see the dropdown email the [CSC team](mailto:StratusCloudHelp@nrel.gov) and ask for accesss to the resbldg account.
3. Click on an available role (typically `developer`) and then click the `Command line or programatic access` link.
4. Follow the steps listed in the `AWS IAM Identity Center credentials (Recommended)` section.
5. Remember the name you give the profile during the configuration. This is the value you will set the `AWS_DEFAULT_PROFILE` enviornment variable to.
6. Open the `credentials` file inside your home directory:
    - On Windows, this is: `C:\Users\myusername\.aws\credentials`
    - On Mac, this is: `/Users/myusername/.aws/credentials`
7. If there are any values set under the `default` profile either rename the profile (replace the word `default` with something else) or delete the section. For reference a default profile in the `credentials` file looks like the following:
    ```
    [default]
    aws_access_key_id = AKIAIOSFODNN7EXAMPLE
    aws_secret_access_key = wJalrX+UtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
    ```
8. Follow the steps above to set the `AWS_DEFAULT_PROFILE` and login to the resbldg account.


## Generating a Sample
There are two steps to generating a sample to be run using ComStock:
1. Generate a `buildstock.csv` file with the main building characteristics.
2. Join geospatial columns to the `buildstock.csv`.

### Generating a `buildstock.csv`
There are two types of samples you can generate:
1. National sample using `tsv_resampling.py`
    - From this directory, run the following command:

    ```
    $ python tsv_resampling.py tsv_version sim_year n_samples n_buckets hvac_sizing
    ```

    - Where: 
        - `tsv_version` is the version of tsv files to sample from (e.g., v99 TODO: Ry to change)
        - `sim_year` is the simulation year (2015-2019)
        - `n_samples` is the number of samples you wish to generate. A typical full national sample is 350,000 samples.
        - 'n_buckets` is 1 (TODO: Ry to explain this)
        - `hvac_sizing` dictates whether the HVAC systems in the models are autosized or hardsized (use "autosize" or "hardsize" for this argument).
    - This will generate a buildstock.csv file and save it to `.\output-buildstocks\intermediate`.
    - The name of the file will include the date, tsv version, simulation year, your username, and number of samples. For example: `buildstock_20221020_v17_2018_alebar_500.csv`.

2. County-level sample using `tsv_resampling_wrapper.py`

    You also have the ability to sample individual counties for either more geographically granular sampling (i.e., for specific city-level or county-level projects), or upsampling counties that are under represented in the national sampling.
    - From this directory, run the following command:

    ```
    $ python tsv_resampling_wrapper.py tsv_version sim_year county_spec_path buildstock_output_dir hvac_sizing
    ```

    - Where `tsv_version` is the version of the tsv files to sample from (e.g., v16), `sim_year` is the simulation year (2015-2019),`county_spec_path` is the path to the .csv file with the FIPS codes from the counties you wish to sample and the number of samples for each (see example file in `.\resources`), `buildstock_output_dir` is the directory where you want to save the buildstock.csv file(s) (must be an empty directory), and `hvac_sizing` dictates whether the HVAC systems in the models are autosized or hardsized (use "autosize" or "hardsize" for this argument).
    - This will generate individual buildstock.csv files for each county included in `county_spec_path`. These can be run in ComStock separately, or concatenated before being run together.

### Join geospatial columns
For both types of sampling, you will need to join geospatial columns to the `buildstock.csv` file using `join_geospatial.py`.
- From this directory, run the following command:

    ```
    $ python join_geospatial.py name_of_buildstock.csv
    ```

- Where `name_of_buildstock.csv` is the file generated in the first step. Be sure to include the ".csv" file extension in the command.
- The script will read the file from the `output-buildstocks\intermediate` directory.
- This script will save a file to `output-buildstocks\final` with the same name as the original `buildstock.csv`.
