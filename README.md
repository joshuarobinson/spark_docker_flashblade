# Spark Standalone cluster on Docker with FlashBlade 

The scripts and tools in this repository demonstrate automation for a Spark
Standalone cluster that uses FlashBlade NFS/S3 for persistent storage.

config_s3.py : automates the creation of S3 users, keys, and buckets.
    
Dockerfile, build_image.sh : create a docker image for running Spark.

control_sparkstandalone.sh : shell script to start and stop a dockerized
Spark Standalone cluster.

{GenerateTestData|RunClustering}.ipynb : Python notebooks demonstrating clustering algorithm.

Requirements for using these scripts:
  * node_list.txt: a list of hostnames, one per line, to use in the Spark cluster.
  * spark-defaults.conf: configuration for Spark, can be created with config_s3.py
