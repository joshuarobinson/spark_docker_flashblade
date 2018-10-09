#!/bin/bash


# ==== CONFIGURABLES ===============

# How to find the docker image
REPONAME=joshuarobinson
SPARKVER=2.4.0

# List of mounted NFS paths that should be exposed to Spark as datahub paths.
# Assumes some other mechanism ensures mounting.
VOLUMEMAPS="-v /mnt/acadia:/datahub-acadia -v /mnt/irp210:/datahub-210"

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

		# Check for need to build image.
		echo "Checking for latest container image."
		./build_image.sh
		multicmd docker pull $SPARKIMG

		# Start master and slaves.
		docker run -d --rm --net=host -p 8080:8080 -p 7077:7077 -p 6066:6066 \
			$VOLUMEMAPS \
			--name fbsparkmaster \
			$SPARKIMG
		docker exec fbsparkmaster /opt/spark/sbin/start-master.sh
		
		# Start workers.
		multicmd docker run --privileged -d --rm --net=host \
			-p 8081:8081 -p 7078:7078 -p 4040:4040 \
			$VOLUMEMAPS \
			--name fbsparkworker \
			$SPARKIMG
		multicmd docker exec fbsparkworker /opt/spark/sbin/start-slave.sh spark://$MASTER:7077
	
	elif [ "$2" == "jupyter" ]; then
		docker run -d --name fbsparkjupyter --rm --net=host -p 7099:7099 -p 8888:8888 \
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
		docker run -it --name fbsparkdriver --rm --net=host -p 7099:7099 \
			--entrypoint=/opt/spark/bin/spark-shell \
			$VOLUMEMAPS \
			$SPARKIMG \
			--conf spark.driver.port=7099 \
			--master spark://$MASTER:7077 \
			--executor-memory 128G
	fi

	echo "Access Spark Cluster UI at http://$MASTER:8080"
	
elif [ "$1" == "stop" ]; then
	echo "Stopping all"

	docker stop fbsparkdriver fbsparkjupyter

	multicmd docker exec fbsparkworker /opt/spark/sbin/stop-slave.sh
	docker exec fbsparkmaster /opt/spark/sbin/stop-master.sh

	multicmd docker stop fbsparkworker
	docker stop fbsparkmaster

else
	echo "Usage: $0 [start|stop]"
fi

