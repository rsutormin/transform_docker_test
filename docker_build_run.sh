#!/bin/bash
IMAGE=transform
DIR=$(pwd)
mkdir -p $DIR/workdir
rm -rf $DIR/workdir/*
echo "Deleting old Docker containers"
docker ps -a | grep test/$IMAGE:latest | awk '{print $1}' | xargs docker rm -v
echo ""
echo "Building new Docker image"
docker build --rm -t test/$IMAGE:latest .
echo ""
echo "Deleting old Docker images"
docker images -q --filter "dangling=true" | xargs docker rmi
echo ""
echo "Running new Docker container"
docker run -d -p 9000:5000 --dns 8.8.8.8 -v $DIR/workdir:/scratch test/$IMAGE:latest
#docker run -i -t -p 9000:5000 --dns 8.8.8.8 -v $DIR/workdir:/scratch test/$IMAGE:latest mc
