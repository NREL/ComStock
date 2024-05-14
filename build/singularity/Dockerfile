# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# debian image with the go tools
FROM golang:1.22.3-bookworm

# Install apptainer per installation directions from: https://github.com/apptainer/apptainer/blob/main/INSTALL.md

# Ensure repositories are up-to-date
RUN apt-get update
# Install debian packages for dependencies
RUN apt-get install -y \
    build-essential \
    libseccomp-dev \
    pkg-config \
    uidmap \
    squashfs-tools \
    fakeroot \
    cryptsetup \
    tzdata \
    curl wget git

# Download and install apptainer
ENV APPTAINER_VERSION=1.3.1
LABEL Maintainer andrew.parker@nrel.gov
RUN mkdir -p /usr/local/var/apptainer/mnt && \
    mkdir -p $GOPATH/src/github.com/apptainer && \
    cd $GOPATH/src/github.com/apptainer && \
    wget https://github.com/apptainer/apptainer/releases/download/v${APPTAINER_VERSION}/apptainer-${APPTAINER_VERSION}.tar.gz && \
    tar -xzvf apptainer-${APPTAINER_VERSION}.tar.gz && \
    cd apptainer-${APPTAINER_VERSION} && \
    ./mconfig -p /usr/local --with-suid && \
    make -C builddir && \
    make -C builddir install

WORKDIR /root/build
CMD ['/bin/bash']
