# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

FROM ubuntu:16.04 AS base

MAINTAINER Henry (Ry) Horsey henry.horsey@nrel.gov

# If installing a CI build version of OpenStudio, then pass in the CI path into the build command. For example:
#   docker build --build-arg DOWNLOAD_PREFIX="_CI/OpenStudio"
ARG DOWNLOAD_PREFIX=""

# Set the version of OpenStudio when building the container. For example `docker build --build-arg
# OPENSTUDIO_VERSION=2.6.0 --build-arg OPENSTUDIO_SHA=e3cb91f98a .` in the .travis.yml. Set with the ENV keyword to
# inherit the variables into child containers
ARG OPENSTUDIO_VERSION
ARG OPENSTUDIO_SHA
ARG OS_BUNDLER_VERSION=1.17.1
ENV OPENSTUDIO_VERSION=$OPENSTUDIO_VERSION
ENV OPENSTUDIO_SHA=$OPENSTUDIO_SHA
ENV OS_BUNDLER_VERSION=$OS_BUNDLER_VERSION


# Modify the OPENSTUDIO_VERSION and OPENSTUDIO_SHA for new versions
ENV RUBY_VERSION=2.2.4 \
    RUBY_SHA=b6eff568b48e0fda76e5a36333175df049b204e91217aa32a65153cc0cdcb761

# Don't combine with above since ENV vars are not initialized until after the above call
ENV OPENSTUDIO_DOWNLOAD_FILENAME=OpenStudio-$OPENSTUDIO_VERSION.$OPENSTUDIO_SHA-Linux.deb

# Install gdebi, then download and install OpenStudio, then clean up.
# gdebi handles the installation of OpenStudio's dependencies including Qt5,
# Boost, and Ruby 2.2.4.
# OpenStudio 2.4.3 requires libwxgtk3.0-0 -- install manually for now

# install locales and set to en_US.UTF-8. This is needed for running the CLI on some machines
# such as singularity.
RUN apt-get update && apt-get install -y autoconf \
        build-essential \
        ca-certificates \
        curl \
        gdebi-core \
        git \
        libfreetype6 \
        libjpeg8 \
        libdbus-glib-1-2 \
        libfontconfig1 \
        libglu1 \
        libreadline-dev \
        libsm6 \
        libssl-dev \
        libtool \
        libwxgtk3.0-0v5 \
        libxi6 \
        libxml2-dev \
        locales \
        sudo \
        zlib1g-dev \
    && curl -sL https://raw.githubusercontent.com/NREL/OpenStudio-server/develop/docker/deployment/scripts/install_ruby.sh -o /usr/local/bin/install_ruby.sh \
    && chmod +x /usr/local/bin/install_ruby.sh \
    && /usr/local/bin/install_ruby.sh $RUBY_VERSION $RUBY_SHA \
    && if [ -z "${DOWNLOAD_PREFIX}" ]; then \
            export OPENSTUDIO_DOWNLOAD_URL=https://openstudio-builds.s3.amazonaws.com/$OPENSTUDIO_VERSION/OpenStudio-$OPENSTUDIO_VERSION.$OPENSTUDIO_SHA-Linux.deb; \
       else \
            export OPENSTUDIO_DOWNLOAD_URL=https://openstudio-builds.s3.amazonaws.com/$DOWNLOAD_PREFIX/OpenStudio-$OPENSTUDIO_VERSION.$OPENSTUDIO_SHA-Linux.deb; \
       fi \
    && echo "OpenStudio Package Download URL is ${OPENSTUDIO_DOWNLOAD_URL}" \
    && curl -SLO $OPENSTUDIO_DOWNLOAD_URL \
    # Verify that the download was successful (not access denied XML from s3)
    && grep -v -q "<Code>AccessDenied</Code>" ${OPENSTUDIO_DOWNLOAD_FILENAME} \
    && gdebi -n $OPENSTUDIO_DOWNLOAD_FILENAME \
    # Cleanup
    && rm -f /usr/local/bin/install_ruby.sh \
    && rm -f $OPENSTUDIO_DOWNLOAD_FILENAME \
    && rm -rf /var/lib/apt/lists/* \
    && if dpkg --compare-versions "${OPENSTUDIO_VERSION}" "gt" "2.5.1"; then \
            rm -rf /usr/local/openstudio-${OPENSTUDIO_VERSION}/SketchUpPlugin; \
       else \
            rm -rf /usr/SketchUpPlugin; \
       fi \
    && locale-gen en_US en_US.UTF-8 \
    && dpkg-reconfigure locales


## Add RUBYLIB link for openstudio.rb. Support new location and old location.
ENV RUBYLIB=/usr/local/openstudio-${OPENSTUDIO_VERSION}/Ruby:/usr/Ruby
ENV ENERGYPLUS_EXE_PATH=/usr/local/openstudio-${OPENSTUDIO_VERSION}/EnergyPlus/energyplus

# The OpenStudio Gemfile contains a fixed bundler version, so you have to install and run specific to that version
RUN gem install bundler -v $OS_BUNDLER_VERSION && \
    mkdir /var/oscli && \
    cp /usr/local/openstudio-${OPENSTUDIO_VERSION}/Ruby/Gemfile /var/oscli && \
    cp /usr/local/openstudio-${OPENSTUDIO_VERSION}/Ruby/openstudio-gems.gemspec /var/oscli && \
    sed -i '/openstudio-standards/d' /var/oscli/openstudio-gems.gemspec
WORKDIR /var/oscli
RUN OLDSTD="gem 'openstudio-standards'" && \
    NEWSTD="gem 'openstudio-standards', github: 'NREL/openstudio-standards', branch: 'la100_merge'" && \
    sed -i -e "s|$OLDSTD.*|$NEWSTD|g" /var/oscli/Gemfile
RUN bundle _${OS_BUNDLER_VERSION}_ install --path=gems --jobs=4 --retry=3
RUN rm -rf /var/oscli/gems/ruby/2.2.0/bundler/gems/openstudio-standards-05f92903f9bb/.git \
    /var/oscli/gems/ruby/2.2.0/bundler/gems/openstudio-standards-05f92903f9bb/test \
    /var/oscli/gems/ruby/2.2.0/cache/bundler

# Configure the bootdir & confirm that openstudio is able to load the bundled gem set in /var/gemdata
VOLUME /var/simdata/openstudio
WORKDIR /var/simdata/openstudio
RUN openstudio --verbose --bundle /var/oscli/Gemfile --bundle_path /var/oscli/gems openstudio_version

CMD [ "/bin/bash" ]

FROM ubuntu:16.04 AS cli

ARG OPENSTUDIO_VERSION

# copy executable and energyplus from install
COPY --from=base /usr/local/openstudio-${OPENSTUDIO_VERSION}/bin/openstudio /usr/local/openstudio-${OPENSTUDIO_VERSION}/bin/
COPY --from=base /usr/local/openstudio-${OPENSTUDIO_VERSION}/EnergyPlus /usr/local/openstudio-${OPENSTUDIO_VERSION}/EnergyPlus
COPY --from=base /var/oscli/ /var/oscli/

RUN apt-get update && apt-get install -y --no-install-recommends \
            libdbus-glib-1-2 \
            libglu1 \
            libssl-dev \
            libgdbm-dev \
            libpng-dev \
     && rm -rf /var/lib/apt/lists/*

# link executable from /usr/local/bin
RUN ln -s /usr/local/openstudio-${OPENSTUDIO_VERSION}/bin/openstudio /usr/local/bin/openstudio

VOLUME /var/simdata/openstudio
WORKDIR /var/simdata/openstudio
