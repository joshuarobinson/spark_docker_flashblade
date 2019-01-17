#!/bin/bash

# This script creates and tears down a Spark Standalone cluster.

# ==== CONFIGURABLES ===============

# Spark image to use: docker repository and tag.
SPARKIMG=joshuarobinson/fb-spark-2.4.0

# Where to find the configuration values for Spark.
# Note, this must be an absolute path for the volume mapping to work.
SPARKCFG=${PWD}/spark-defaults.conf

# NFS datahub mount details that should be exposed to Spark. Assumes this
# filesystem already exists.
DATAHUB_IP="10.62.64.200"
DATAHUB_FS="root"

# PUREBACKEND can either be 'block' (FlashArray) or 'file' (FlashBlade) for
# per-node scratch space.
PUREBACKEND=file

# Designate the Spark cluster master as the node this script is run from.
MASTER=$(hostname)

# Ansible hostgroup for the Spark workers.
HOSTGROUP="irp210"

# === Constants that should not need to be changed. ====

# Directory for Spark binary, assumes this layout inside the docker image.
SPARKDIR=/opt/spark

# Name for the docker volumes created for per-node scratch space.
SCRATCHVOL=sparkscratch

# === Control Code ====

if [ "$1" == "start" ]; then

	# Sanity checking to ensure the Spark config exists.
	if [ ! -e $SPARKCFG ]; then
		echo "Spark config $SPARKCFG not found."
		exit 1
	fi

	# Startup Spark cluster services.
	echo "Starting Standalone cluster"

	echo "Syncing latest container image on all hosts."
	ansible $HOSTGROUP -o -a "docker pull $SPARKIMG"

	echo "Starting Spark master..."
	docker volume create --driver local --opt type=nfs --opt o=addr=$DATAHUB_IP,rw \
		--opt=device=:/$DATAHUB_FS spark-datahub
	docker run -d --rm --net=host \
		-v spark-datahub:/datahub \
		-e SPARK_LOG_DIR=/datahub/sparklogs/nodes \
		--name fbsparkmaster \
		$SPARKIMG
	docker exec fbsparkmaster /opt/spark/sbin/start-master.sh

	echo "Creating node-local volumes for workers using class=$PUREBACKEND..."
	ansible $HOSTGROUP -o -a "docker volume create --driver=pure -o size=1TiB \
		-o volume_label_selector=\"purestorage.com/backend=$PUREBACKEND\" \
		$SCRATCHVOL"
	echo "Attaching NFS datahub mount to workers..."	
	ansible $HOSTGROUP -o -a"docker volume create --driver local --opt type=nfs --opt o=addr=$DATAHUB_IP,rw \
		--opt=device=:/$DATAHUB_FS spark-datahub"
	
	echo "Starting workers..."
	ansible $HOSTGROUP -o -a "docker run -d --rm --net=host \
		-v spark-datahub:/datahub \
		-v $SCRATCHVOL:/local \
		-e SPARK_LOCAL_DIRS=/local \
		-e SPARK_WORKER_DIR=/datahub/sparklogs \
		-e SPARK_LOG_DIR=/datahub/sparklogs/nodes \
		--name fbsparkworker \
		$SPARKIMG"
	ansible $HOSTGROUP -o -a "docker exec fbsparkworker /opt/spark/sbin/start-slave.sh \
		spark://$MASTER:7077"

	echo "Access Spark Cluster UI at http://$MASTER:8080"

	echo "Starting Jupyter notebook server..."
	docker run -d --name fbsparkjupyter --rm --net=host \
		--entrypoint=/opt/spark/bin/pyspark \
		-e PYSPARK_PYTHON=python3 \
		-e PYSPARK_DRIVER_PYTHON=jupyter \
		-e PYSPARK_DRIVER_PYTHON_OPTS="notebook --ip=$(hostname) --no-browser --notebook-dir=/datahub/" \
		--env-file ./credentials \
		-v spark-datahub:/datahub \
		-v $SPARKCFG:/opt/spark/conf/spark-defaults.conf \
		$SPARKIMG \
		--conf spark.driver.port=7099 \
		--master spark://$MASTER:7077 \
		--executor-memory 128G \
		--driver-memory 32G

	docker logs -f fbsparkjupyter
	
elif [ "$1" == "stop" ]; then
	echo "Stopping all"

	docker stop fbsparkjupyter

	echo "Stopping Standalone cluster"
	ansible $HOSTGROUP -o -a "docker exec fbsparkworker /opt/spark/sbin/stop-slave.sh"
	docker exec fbsparkmaster /opt/spark/sbin/stop-master.sh

	echo "Stopping all running containers"
	ansible $HOSTGROUP -o -a "docker stop fbsparkworker"
	docker stop fbsparkmaster

	ansible $HOSTGROUP -o -a "docker volume rm spark-datahub"
	docker volume rm spark-datahub

	echo "Removing node-local volumes"
	ansible $HOSTGROUP -o -a "docker volume rm $SCRATCHVOL"

else
	echo "Usage: $0 [start|stop]"
fi
