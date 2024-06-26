#!/usr/bin/env bash

# Build apptainer container
cd apptainer
APPTAINER_NOHTTPS=1 apptainer build docker-openstudio.sif docker-daemon://127.0.0.1:5000/docker-openstudio:latest
mv docker-openstudio.sif ..
