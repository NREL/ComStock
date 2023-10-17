#!/usr/bin/env bash

# Build singularity container
cd singularity
SINGULARITY_NOHTTPS=1 singularity build docker-openstudio.simg docker-daemon://127.0.0.1:5000/docker-openstudio:latest
mv docker-openstudio.simg ..
