#!/bin/bash

set -e

SPARKVER=2.4.0
REPONAME=joshuarobinson

# Build docker image.
docker build --build-arg SPARK_VERSION=$SPARKVER \
	-t fb-spark-$SPARKVER .

# Push to docker repository.
docker tag fb-spark-$SPARKVER $REPONAME/fb-spark-$SPARKVER
docker push $REPONAME/fb-spark-$SPARKVER
