# NREL Staff Instructions for Running ComStock on NREL's Supercomputer

## Permissions Dependencies
 - Request an [HPC account](https://www.nrel.gov/hpc/user-accounts.html)
   - When asked for allocation in the request portal, use 'cscore' for ComStock or 'eusscom' for EUSS
 - Get added to specific allocations.  Contact Ry Horsey for ComStock 'cscore' or Chris CaraDonna for EUSS 'eusscom' permissions.
   - Recommend requesting access to both folders, as well as buildstockbatch, because there could be dependencies some dependencies in the environments that will cause permissions issues.
 - If uploading results to S3, Athena, ask Noel for an S3 account
   - Setup MFA on your AWS account
   - Under the security tab, create API access keys.  You'll need one for Kestrel and one for your local machine if you plan to process results.
   - Add AWS credentials in Kestrel using ```aws configure```.  Add your access key and secret key.
   - Install the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html) on your machine and set credentials in command line with ```aws configure```.
   - You may need to create a folder called ```.aws``` on Kestrel in your /home/username/ folder. Inside ```.aws``` folder, you will then create a folder called ```credentials```. Inside the ```credentials``` folder, create a file called ```config``` and a file called ```credentials```.
     - Inside the ```config``` file,  type
       ```
       [default]
       region = us-west-2
     - Inside the ```credentials``` file, type
       ```
       [default]
       aws_access_key_id = insert_aws_access_key
       aws_secret_access_key = insert_aws_secret_key
   - If you dont have access to RES AWS RESBLDG in your account reach out to Andrew Parker or Ry Horsey
   - Further instructions for AWS SSO can be found at: https://github.com/NREL/cloud-tools

## Software Dependencies
 - [WinSCP](https://winscp.net/eng/index.php) to transfer files to/from HPC
 - A linux-based command line tool such as [Git Bash](https://gitforwindows.org/), or [Ubuntu for Windows](https://ubuntu.com/tutorials/tutorial-ubuntu-on-windows#1-overview).  You will likely need to have an NREL IT admin install this for you as these require elevated permissions.  Install using your NREL microsoft account. The most broadly used (and thus supported) approach is to install the [Windows subsystem for linux](https://docs.microsoft.com/en-us/windows/wsl/install-win10) and then [setup a connection from there to Docker for Windows](https://nickjanetakis.com/blog/setting-up-docker-for-windows-and-wsl-to-work-flawlessly). This isn't required, however not doing so will lead to you having to do some independent learning sooner or later on the quirks of Windows and Docker.

## Accessing HPC
To run commands, use Git Bash or Ubuntu terminal:
 - ```ssh username@hostname``` (e.g. ```ssh mprapros@kestrel.hpc.nrel.gov```)
 - Enter Kestrel password (this is the same as your old Eagle password, and must be updated every ~6 months)

To just access files, use WinSCP:
 - Host name: kestrel.hpc.nrel.gov
 - Username: NREL username (e.g. mprapros)
 - Password: Kestrel PW

## ComStock
 - Run documents for ComStock-funded projects located in ```/kfs2/projects/cscore/``` or ```/kfs2/projects/eusscom/```
   - If using ComStock for another project, you may need to use another folder depending on what allocation is being used
 - Exception: openstudio-standards apptainer containers located in ```/kfs2/shared-projects/buildstock/apptainer_images/```
 - The cscore and eusscom Kestrel folders contain:
   - ```envs```
     - buildstockbatch conda environment
     - [Developer installation instructions](http://buildstock-batch.s3-website-us-west-2.amazonaws.com/installation.html#developer-installation)
     - Build in development mode (add -d) – able to make changes
   - ```repos```
     - ```buildstockbatch```. Run and manage batch simulations for stock modeling; commercial equivalent of OpenStudio-BuildStock
     - ```comstock```. All measures and resources related to ComStock
     - ```vizstock-upload```. Process and upload ComStock results from Kestrel for use in VizStock
   - ```samples```. Contains all the *buildstock.csv* files
   - ```apptainer_images```. openstudio-standards apptainer containers
     - buildstockbatch conda environment
   - ```weather```. Zip folders of weather files
     - *!!!Must contain an empty.ddy, empty.epw, and empty.stat file!!!*
   - ```ymls```. yml files outlining conditions for simulation

## Folder Structure Guidelines:
- repos
  - Shared repos will be stored here (i.e. buildstockbatch, comstock, vizstock)
  - Clone the repo you are working in using this command: git clone [http://github.com/nrel/\*repo-name\*.git](http://github.com/nrel/*repo-name*.git)
  - If there are multiple ComStock runs going at once, especially from different branches, use caution and communicate with the team members because checking out another branch it will affect other runs
  - Instead, you can clone multiple versions of the same repo, therefore multiple people can run tests simultaneously off of separate branches (e.g. name the folder comstock_your_name, checkout your branch here, and use this for your personal testing)
- samples
  - Inside the samples folder, put your buildstock samples within the correct project folder, or create a new project folder. This will make it easier to find samples. Label the samples with the version of the TSVs that were used to generate the sample.
- runs
  - Inside the runs folder, output your runs into the correct project folder, or create a new project folder. This will limit the number of folders in the /cscore/runs or /eusscom/runs directory
  - Try to keep a standard naming convention for your runs
  - Recommend making sub-folders for different types of test runs so that you can easily find your output folder.
- ymls
  - Inside the ymls folder, put your yml file into the correct project folder, or create a new project folder. This will make it easier to find yml files.
  - Make sure everything if you are copying an old yml file that you update the folder locations as necessary.
- weather
  - Shared weather zip files will be stored here
- envs
  - Shared buildstockbatch environments will be stored here


### Example yml File Contents:
PLEASE READ: yml formatting has changed since switching to schema_version 0.3. Your simulation will fail if using old formatting!
```
schema_version: '0.3'
buildstock_directory: /kfs2/projects/cscore/repos/comstock
project_directory: national
output_directory: /kfs2/projects/cscore/runs/com-segmentation/com_segmentation_with_scout_full/
weather_files_path: /kfs2/projects/cscore/weather/BuildStock_2018_FIPS_HI.zip

sampler:
  type: precomputed
  args:
    sample_file: /kfs2/projects/cscore/samples/segmentation/buildstock_loads_measure.csv

kestrel:
  account: cscore
  n_jobs: 5
  minutes_per_sim: 120
  postprocessing:
    time: 600

postprocessing:
  keep_individual_timeseries: true
  aws:
    region_name: 'us-west-2'
    s3:
      bucket: eulp
      prefix: simulation_output/regional_runs/comstock/com_segmentation_full/
    athena:
      glue_service_role: service-role/AWSGlueServiceRole-default
      database_name: enduse
      max_crawling_time: 1200 # Time to wait for the crawler to complete before aborting it

baseline:
  n_buildings_represented: 2000
  custom_gems: True

os_version: eulp_com_v17
os_sha: 3472e8b799
max_minutes_per_sim: 240
workflow_generator:
  type: commercial_default
  args:
    reporting_measures:
    - measure_dir_name: SimulationOutputReport
    - measure_dir_name: comstock_sensitivity_reports
    - measure_dir_name: qoi_report
    - measure_dir_name: simulation_settings_check
      arguments:
        run_sim_settings_checks: true
    - measure_dir_name: run_directory_cleanup
    timeseries_csv_export:
       reporting_frequency: Timestep
       inc_output_variables: false

upgrades:
  - upgrade_name: Thermochromic BIPV
    options:
      - option: run_bipv_ep_measure|TRUE
```
Notes:
 - ```schema_version```: always "0.3"
 - ```buildstock_directory``` points to the ComStock repo you are using
 - ```project_directory```: always "national"
 - ```output_directory``` name (your choice) and location (/runs/*your_project_name*) of output directory
 - ```weather_files_path:``` points to the weather zip

 - ```sampler```:
   -   ```type```: always "precomputed"
   -   ```args```:
     - ```sample_file```: points to correct buildstock.csv in /samples/*project_name* folder

 - ```kestrel```:
   - ```account```: kestrel allocation for project (e.g. eusscom)
   - ```n_jobs```: estimate based on number of datapoints x number of upgrades (number of jobs necessary roughly equal to total number of simulations divided by 5000-6000)
   - ```minutes_per_sim```: 30-60 usually sufficient for most runs; use 120-200 for runs with scout component loads measure
   - ```postprocessing```:
     - ```time```: typically 200-400 is sufficient, but can bump up for larger runs

 - ```postprocessing```:
   - ```keep_individual_timeseries```: true or false depending on if you need timeseries results
   - ```aws```:
     - ```region_name```: always "us-west-2"
     - ```s3```:
       - ```bucket```: depends on what project it's for; ask Noel if you're not sure (e.g. "eulp")
       - ```prefix```: name in a way that you can easily find it on S3; try to keep consistent organization structure for all runs within a project (e.g. "simulation_output/regional_runs/comstock/com_segmentation_full/")
     - ```athena```:
       - ```glue_service_role```: always "service-role/AWSGlueServiceRole-default"
       - ```database_name```: depends on what project it's for (e.g. "enduse")
       - ```max_crawling_time```: time to wait for the crawler to complete before aborting it; default 1200

 - ```baseline```:
   - ```n_buildings_represented```: number of buildings in buildstock.csv
   - ```custom_gems```: always "True"

 - ```os_version```: name of apptainer image being used
 - ```os_sha```: OS version used to build singularity container
 - ```max_minutes_per_sim```: max time until the building simulation will be terminated (to prevent job timeouts); use 240 for most runs, 480 for runs of really large buildings
 - ```workflow_generator```: this section outlines which rpeorting measures are run with the simulation and it can for the most part stay the same. The only time you would need to modify this section is if you are adding a reporting measure (i.e. scout component loads measure). To add a measure, follow this format:
   - ```measure_dir_name```: *measure name*
     - ```arguments:```
       - ```*argument 1 name*```: *argument 1 input*
       - ```*argument 2 name*```: *argument 2 input* and so on

 - ```upgrades```: if you are running upgrade measures, add them here in this format:
   - ```upgrade_name```: your choice; description of upgrade
     - ```options:```
       - ```option```: *parameter name*|*option name* #(from options_lookup.tsv)

## Running a Simulation
### Setup
 1. Activate python environment:
    ```
    module load python
    source *path to buildstock environment you are using*/bin/activate
    ```
    example:
    ```
    module load python
    source /kfs2/shared-projects/buildstock/envs/bsb-2024.01.0-ry/bin/activate
    ```
 2. Check to make sure you are using the latest singularity image and that your yml points to this image:
    - Located in ```/kfs2/shared-projects/buildstock/apptainer_images```
 3. Make sure you commit all of your changes, push them to github, and pull changes onto Kestrel
    - navigate to ```/kfs2/projects/cscore/repos/comstock``` (or whatever repo you're running from)
    - if not already initialized use ```git init``` (reinitalizes the existing repo)
    - ```git status```
    - ```git fetch```
    - if not already on branch you want to use ```git checkout *branch name*```
    - ```git pull```
 4. If you added any upgrade measures to the ComStock repo (```/comstock/resources/measures/``` folder), make sure you also added them to yml file and the options_lookup.tsv
    - ```yml``` (see formatting above)
    - ```options_lookup```:
      - Parameter Name: your choice; must match yml
      - Option Name: your choice; must match yml
      - Measure Dir: name of measure folder
      - Measure Args: measure arguments and values from measure.rb
      - Example:
        ```
        | Parameter Name        | Option Name          | Measure Dir    | Measure Arg 1 | Measure Arg 2      |
        | env_wall_insul_r_val  | wall_insul_efficient | env_wall_insul | r_val=30.0    | allow_reduct=false |
        ```
  5. If you made any changes to the options_lookup, make sure it is copied into both locations in the comstock repo:
     - ```comstock/national/housing_characteristics/```
     - ```comstock/resources/```
  6. If you added any reporting measures (to the comstock/measures/ folder), make sure you also added them to the yml file
     - yml format for reporting measures (see formatting above)
  7. Double check that your yml is pointing to all the right locations for the sample, repo, weather, and output folder

### Running a job
  - In terminal, navigate to ```/kfs2/projects/cscore/ymls/*project name*```
  - Make sure your desired python environment is activated (see above)
  - ```buildstock_kestrel name_of_yml.yml```
  - If it is a small run and you want it to get done quickly, you can use high priority nodes:
    - ```buildstock_kestrel --hipri name_of_yml.yml```
    - Avoid using hipri for larger runs, as we only get a certain amount of hipri nodes per allocation
  - If you need to rerun the postprocessing for certain run (e.g. the results.csv files did not populate), you can rerun only the post processing:
    - ```buildstock_kestrel --postprocessonly name_of_yml.yml```
  - [Monitoring your runs]
    - Commands for check status of jobs, estimated start time, queue length, cancel jobs, etc. can be found at (https://www.nrel.gov/hpc/eagle-monitor-control-commands.html). Kestrel documentation is not out yet but the commands should be the same.
    - Navigate to your run output folder and open the job.out files
      - Shows number of simulations that have completed, elapsed time, etc.
  -  [Manually killing a job]
    - Sometimes (especially in really large runs), a few buildings can get stuck during the simulation (e.g. something is not converging or stuck in a loop).
    - If the job reaches its maximum time and a few buildings did not finish, it will wipe the results for all buildings in that job.
    - To avoid this, we can manually go into the job and kill the openstudio task, forcing the hanging buildings to fail and the job completes without wiping all the simulations.
    - Note that this issue has been mostly avoided thourgh the addition of the max_minutes_per_sim field in the yml file, but there still could be reason for you to cancel a job.
    - If you notice a job.out file has been hanging for several hours without updating:
      - ```squeue -u *your HPC username*```: lists your active jobs; job names should look something like r_i_n_ (e.g. r1i7n35)
      - ```ssh *job name*```: going into a specific job to see what its doing
      - ```htop```: allows you to see what tasks the job is currently working on; if there are a few buildings stuck, you'll see most of the nodes do not have any activity, but a few are working on "openstudio" tasks
      - ```exit```: exits htop
      - ```pkill -f openstudio```: force kills all openstudio tasks within that job
      - ```exit```: exits out of job back into normal kestrel interface
   - After ~30 seconds, if you return to your job.out file, you should see that it has now completed and post processing should begin soon

### Looking at your results
- Run output folder:
  - ```housing_characteristics``` folder – contains buildstock.csv and options_lookup.tsv used in simulation
    - If your simulations failed due to an options_lookup error, this is a good place to start - make sure the options lookup used in the simulation is the one you were expecting it to use
  - ```results``` folder:
    - ```parquet``` folder – timeseries parquet file
    - ```results_csvs``` folder – results csv files, one for each upgrade
      - Baseline is up00, each subsequent upgrade is up01, up02, etc., in the order they are listed in the yml file
      - If no results csv files are present, this usually means all datapoints failed
      - Occasionally, the postprocessing errors out and you just need to rerun the postprocessing; check the ```postprocessing.out``` file in the run directory
      - If you want to check why a building failed, you will need to check individual simulation logs located in the simulation_output folder
    - ```simulation_output``` folder – individual simulation results for all buildings and all upgrades
      - to view the datapoint log for a specific buildingid and jobid (located in results.csv, first and second columns), you will need to extract a building from the tar.gz file
        - ```tar xvzf simulations_job*jobid*.tar.gz ./up*upgrade_number*/bldg*buildingid*```
        - buildingid must contain 7 digits, so you will need to add leading zeros (e.g. buildingid is "156", you will input "0000156")
        - example: jobid = 1, buildingid = 12, upgrade = 01
          - ```tar xvzf simulations_job1.tar.gz ./up01/bldg0000012```
  - weather folder – contains weather files used

## Debugging jobs on Kestrel

Kestrel uses [Slurm](https://slurm.schedmd.com/overview.html) for it's job scheduling and cluster management. This software package provides a number of commands than can be run on the command line to submit, inspect, change, and cancel jobs. All of these commands begin with the letter `s` for Slurm, such as `sinfo`, `scancel`, or `squeue`.

When a `buildstock_kestrel` command is run successfully and job is submitted to the slurm using the `srun` command by the python code of buildstockbatch. This job is given a job ID which can be used to retrieve data about the submitted job. BuildStockBatch typically submits three jobs, one for sampling, one for BEM execution, and one for post-processing. These jobs are dependent on each other and if any one fails the downstream jobs are automatically canceled. In addition, a single job that requires `N` many nodes will be split into Job IDs `jobid_1`, `jobid_2`, ..., `jobid_N` as they are each in turn scheduled and executed on Kestrel.

A key thing to understand is which queue the job was submitted to. Kestrel has [8 queues](https://nrel.github.io/HPC/Documentation/Systems/Kestrel/running/) which jobs can be submitted to. In almost all cases the jobs should be queued in the `short` and `standard` queues (unless doing a single node test run) or on occasion the `long` queue, but then only for the long-running ComStock BEMs for Standard Data Releases. If you notice a job in a different queue please reach out to Ry and Andrew.

Computational resources, i.e. Nodes, i.e. blades withing a rack, are shared across many queues. As a result, node `n123iabc_1` may spend two hours scheduled against a job in the `short` queue and then 88 hours scheduled against a job in the `long` queue. This is particularly important because all ResStock and ComStock simulations can only run on the 256 nodes in Kestrel that have [2TB NVMe drives](https://www.nrel.gov/hpc/kestrel-system-configuration.html). What this practically means is that if you have a 250 node job queued in the standard queue but someone else has a higher priority queued in the short queue and also requesting nodes with NVMe drives your jobs will wait until after the high priority job has completed, even though it was in a different queue.

Most information about jobs that have been queued but not started is retrieved through the [`squeue` command](https://nrel.github.io/HPC/Documentation/Slurm/monitor_and_control/#squeue). NREL HPC has documented options for this command, including the incredibly useful `--start` command which allows for inspection of when jobs are expected to, well, start.

If jobs appear to not be prioritized to start for several days / weeks then there is likely a limitation in priority for that job. Historically this has been fixable by using the `--qos=high` flag (see [these commands](https://nrel.github.io/HPC/Documentation/Slurm/monitor_and_control/#scontrol) for examples of how to alter the Quality Of Service - QOC - setting after submitting a job). Now, however, the introduction of a new concept called 'fair use' means that any project which has, within the last two weeks (subject to change), used significant numbers of AUs is substantially less likely to be scheduled for even more compute, largely regardless of QOS setting. Please be aware of this and review the information on [`sprio`](https://nrel.github.io/HPC/Documentation/Slurm/monitor_and_control/#sprio) for details on ascertaining if this is the issue you face. If you believe so please talk to Chris, Ry, and/or Andrew.

## Common Errors and Mistakes
 - Making changes to the ```options_lookup``` and not copying it into both locations
 - ```n_datapoints``` in yml does not match number of datapoints in ```buildstock.csv```
 - Weather zip folder doesn't contain "empty" weather files
 - Change the output directory name in the yml or delete the old output directory if you need to run the same yml again
 - Permission denied – you don't have read/write permissions for a specific file or directory.
   - Use [chmod and chown](https://www.baeldung.com/linux/chown-chmod-permissions) to change permissions.  You may need to contact the original creator of the file or directory.
   - ```chmod 770 name_of_file```
 - InvalidQOS – you ran out of hipri nodes
 - Invalid account or account/partition – you don't have access to the HPC allocation
   - Run ```groups``` command to see which allocations you have access to
 - Try not to make too many changes directly in Kestrel; those changes will be overwritten next time you pull in changes from Github
  - It's okay to make very small changes for testing in Kestrel, but when you get it to work, make those same changes in Github so they don't get lost
