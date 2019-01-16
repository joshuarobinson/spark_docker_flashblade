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


# ==== HELPER FUNCTION =============
# Run the same command on all non-master nodes.
# Could also use Ansible ad-hoc commands.
function multicmd {
	for node in $(cat node_list.txt); do
		ssh $node $@
	done
}						

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
	if [ "$2" == "cluster" ]; then
		echo "Starting Standalone cluster"

		echo "Syncing latest container image on all hosts."
		multicmd docker pull $SPARKIMG

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
		multicmd docker volume create --driver=pure -o size=1TiB \
			-o volume_label_selector="purestorage.com/backend=$PUREBACKEND" \
			$SCRATCHVOL
		echo "Attaching NFS datahub mount to workers..."	
		multicmd docker volume create --driver local --opt type=nfs --opt o=addr=$DATAHUB_IP,rw \
			--opt=device=:/$DATAHUB_FS spark-datahub
		
		echo "Starting workers..."
		multicmd sudo docker run -d --rm --net=host \
			-v spark-datahub:/datahub \
			-v $SCRATCHVOL:/local \
			-e SPARK_LOCAL_DIRS=/local \
			-e SPARK_WORKER_DIR=/datahub/sparklogs \
			-e SPARK_LOG_DIR=/datahub/sparklogs/nodes \
			--name fbsparkworker \
			$SPARKIMG
		multicmd docker exec fbsparkworker /opt/spark/sbin/start-slave.sh \
			spark://$MASTER:7077
	
		echo "Access Spark Cluster UI at http://$MASTER:8080"
	
	elif [ "$2" == "jupyter" ]; then
		echo "Starting Jupyter notebook server..."
		docker run -d --name fbsparkjupyter --rm --net=host \
			--entrypoint=/opt/spark/bin/pyspark \
			-e PYSPARK_PYTHON=python3 \
			-e PYSPARK_DRIVER_PYTHON=jupyter \
		       	-e PYSPARK_DRIVER_PYTHON_OPTS="notebook --ip=irvm-joshua --no-browser --notebook-dir=/datahub/" \
			--env-file ./credentials \
			-v spark-datahub:/datahub \
			-v $SPARKCFG:/opt/spark/conf/spark-defaults.conf \
			$SPARKIMG \
		       	--conf spark.driver.port=7099 \
			--master spark://$MASTER:7077 \
			--executor-memory 128G \
			--driver-memory 32G
	
		docker logs -f fbsparkjupyter
	
	elif [ "$2" == "shell" ]; then
		echo "Starting Scala shell..."
		docker run -it --name fbsparkdriver --rm --net=host \
			--entrypoint=/opt/spark/bin/spark-shell \
			--env-file ./credentials \
			-v spark-datahub:/datahub \
			-v $SPARKCFG:/opt/spark/conf/spark-defaults.conf \
			$SPARKIMG \
			--conf spark.driver.port=7099 \
			--master spark://$MASTER:7077 \
			--executor-memory 128G \
			--driver-memory 32G
	else
		echo "Usage: $0 $1 [cluster|jupyter|shell]"
	fi
	
elif [ "$1" == "stop" ]; then
	echo "Stopping all"

	docker stop fbsparkdriver fbsparkjupyter

	echo "Stopping Standalone cluster"
	multicmd docker exec fbsparkworker /opt/spark/sbin/stop-slave.sh
	docker exec fbsparkmaster /opt/spark/sbin/stop-master.sh

	echo "Stopping all running containers"
	multicmd docker stop fbsparkworker
	docker stop fbsparkmaster

	multicmd docker volume rm spark-datahub
	docker volume rm spark-datahub

	echo "Removing node-local volumes"
	multicmd docker volume rm $SCRATCHVOL

else
	echo "Usage: $0 [start|stop]"
fi
