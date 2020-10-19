# Creating Singularity Image

* Tested with docker version 18.09.2

* Remove all Docker processes, images, and volumes

    ```bash
    docker rm $(docker ps -aq)
    docker image rm $(docker image ls -aq)
    docker volume rm $(docker volume ls -q)
    ```

* Build Singularity/Docker Image

    ```bash
    docker build -t singularity -f singularity/Dockerfile .
    ```

* Build OpenStudio Container (Locally)

    ```bash
    # Set the version of OpenStudio to install
    export OPENSTUDIO_VERSION=2.8.1
    export OPENSTUDIO_SHA=6914d4f590

    docker build -t docker-openstudio --build-arg OPENSTUDIO_VERSION=$OPENSTUDIO_VERSION --build-arg OPENSTUDIO_SHA=$OPENSTUDIO_SHA .
    ```

* Launch the Container (in privileged mode with docker.sock mounted in the container)

    ```bash
    docker run -it --rm --privileged -v $(pwd):/root/build -v /var/run/docker.sock:/var/run/docker.sock singularity bash
    ```

* Inside singularity build the docker container

    ```bash

    # start an instance of the container for export
    docker run --name for_export docker-openstudio /bin/true
    if [ -f docker-openstudio.simg ]; then rm -f docker-openstudio.simg; else echo "File does not exist"; fi
    singularity image.create -s 3000 docker-openstudio.simg
    docker export for_export | singularity image.import docker-openstudio.simg

    # test singularity
    singularity shell -B $(pwd):/singtest docker-openstudio.simg
    bash
    openstudio --bundle /var/oscli/Gemfile --bundle_path /var/oscli/gems gem_list
    # then compare to SHA in Dockerfile

    ```

* Exit out of the container and singularity image will be in the build directory
