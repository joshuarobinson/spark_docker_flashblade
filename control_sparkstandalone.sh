#!/bin/bash


# ==== CONFIGURABLES ===============

# How to find the docker image
REPONAME=joshuarobinson
SPARKVER=2.4.0

# List of mounted NFS paths that should be exposed to Spark as datahub paths.
# Assumes some other mechanism ensures mounting.
VOLUMEMAPS="-v /mnt/acadia:/datahub-acadia -v /mnt/irp210:/datahub-210"

# PUREBACKEND can either be 'block' (FlashArray) or 'file' (Flashblade)
PUREBACKEND=file

# ==== HELPER FUNCTION =============
# Run the same command on all non-master nodes.
function multicmd {
	for node in $(cat node_list.txt); do
		ssh $node $@
	done
}						

#  Designate the Spark cluster master as the node this script is run from.
MASTER=$(hostname)

# Spark image to use: docker repository and tag.
SPARKIMG=$REPONAME/fb-spark-$SPARKVER

# Directory for Spark binary, assumes this layout inside the docker image.
SPARKDIR=/opt/spark

if [ "$1" == "start" ]; then

	if [ "$2" == "cluster" ]; then
		echo "Starting Standalone cluster"

		echo "Checking for latest container image."
		./build_image.sh
		multicmd docker pull $SPARKIMG

		echo "Starting Spark master..."
		docker run -d --rm --net=host \
			$VOLUMEMAPS \
			--name fbsparkmaster \
			$SPARKIMG
		docker exec fbsparkmaster /opt/spark/sbin/start-master.sh

		echo "Creating node-local volumes for workers using class=$PUREBACKEND..."
		multicmd docker volume create --driver=pure -o size=1TiB \
			-o volume_label_selector="purestorage.com/backend=$PUREBACKEND" \
			sparklocal
		
		echo "Starting workers..."
		multicmd docker run --privileged -d --rm --net=host \
			$VOLUMEMAPS \
			-v sparklocal:/local \
			-e SPARK_LOCAL_DIRS=/local \
			-e SPARK_WORKER_DIR=/local \
			--name fbsparkworker \
			$SPARKIMG
		multicmd docker exec fbsparkworker /opt/spark/sbin/start-slave.sh \
			spark://$MASTER:7077
	
		echo "Access Spark Cluster UI at http://$MASTER:8080"
	
	elif [ "$2" == "jupyter" ]; then
		docker run -d --name fbsparkjupyter --rm --net=host \
			--entrypoint=/opt/spark/bin/pyspark \
			-e PYSPARK_PYTHON=python3 \
			-e PYSPARK_DRIVER_PYTHON=jupyter \
		       	-e PYSPARK_DRIVER_PYTHON_OPTS="notebook --ip=irvm-joshua --no-browser --notebook-dir=/datahub-210/" \
			$VOLUMEMAPS \
			$SPARKIMG \
		       	--conf spark.driver.port=7099 \
			--master spark://$MASTER:7077 \
			--executor-memory 128G \
			--driver-memory 32G
	
		docker logs -f fbsparkjupyter
	
	elif [ "$2" == "shell" ]; then
		docker run -it --name fbsparkdriver --rm --net=host \
			--entrypoint=/opt/spark/bin/spark-shell \
			$VOLUMEMAPS \
			$SPARKIMG \
			--conf spark.driver.port=7099 \
			--master spark://$MASTER:7077 \
			--executor-memory 128G
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

	echo "Removing node-local volumes"
	multicmd docker volume rm sparklocal

else
	echo "Usage: $0 [start|stop]"
fi
