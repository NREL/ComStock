#!/usr/bin/env bash

# Build singularity container
cd singularity
APPTAINER_NOHTTPS=1 apptainer build docker-openstudio.simg docker-daemon://127.0.0.1:5000/docker-openstudio:latest
mv docker-openstudio.simg ..
