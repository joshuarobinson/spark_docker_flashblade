#!/bin/bash

set -e

SPARKVER=2.4.0
REPONAME=joshuarobinson

# Download Hadoop2.7.3 in order to grab the s3a jars.
if [ ! -e /tmp/hadoop-2.7.3.tar.gz ]; then
	wget -P /tmp https://archive.apache.org/dist/hadoop/core/hadoop-2.7.3/hadoop-2.7.3.tar.gz 
fi
tar xf /tmp/hadoop-2.7.3.tar.gz hadoop-2.7.3/share/hadoop/tools/lib/hadoop-aws-2.7.3.jar hadoop-2.7.3/share/hadoop/tools/lib/aws-java-sdk-1.7.4.jar
mv hadoop-2.7.3/share/hadoop/tools/lib/*.jar .
rmdir -p hadoop-2.7.3/share/hadoop/tools/lib/

docker build --build-arg SPARK_VERSION=$SPARKVER \
	-t fb-spark-$SPARKVER .

docker tag fb-spark-$SPARKVER $REPONAME/fb-spark-$SPARKVER
docker push $REPONAME/fb-spark-$SPARKVER
