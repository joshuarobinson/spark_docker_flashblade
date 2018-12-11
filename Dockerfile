FROM openjdk:8

# Variables that define which software versions to install.
ARG SCALA_VER=2.11.8
ARG SPARK_VERSION
ARG HADOOP_VERSION=2.7

# Packages.
RUN apt-get update && apt-get install -y python3 python3-pip 
RUN pip3 install jupyter opencv-python matplotlib sklearn

# Download and install Scala.
RUN curl -O https://www.scala-lang.org/files/archive/scala-$SCALA_VER.deb \
	&& dpkg -i scala-$SCALA_VER.deb \
	&& rm scala-$SCALA_VER.deb

# Download and install Spark.
ARG PACKAGE=spark-$SPARK_VERSION-bin-hadoop$HADOOP_VERSION
RUN curl -O https://archive.apache.org/dist/spark/spark-$SPARK_VERSION/$PACKAGE.tgz \
	&& tar -xzf $PACKAGE.tgz -C /opt/ \
	&& rm $PACKAGE.tgz \
	&& ln -s /opt/$PACKAGE /opt/spark

# Download Hadoop2.7.3 in order to grab the s3a jars.
RUN curl -O  https://archive.apache.org/dist/hadoop/core/hadoop-2.7.3/hadoop-2.7.3.tar.gz \
	&& tar xf hadoop-2.7.3.tar.gz hadoop-2.7.3/share/hadoop/tools/lib/hadoop-aws-2.7.3.jar hadoop-2.7.3/share/hadoop/tools/lib/aws-java-sdk-1.7.4.jar \
	&& mv hadoop-2.7.3/share/hadoop/tools/lib/*.jar /opt/spark/jars/ \
	&& rm -r hadoop-2.7.3/ \
	&& rm hadoop-2.7.3.tar.gz

COPY spark-defaults.conf /opt/spark/conf/

RUN groupadd -g 1080 sparkuser && \
    useradd -r -m -u 1080 -g sparkuser sparkuser && \
    chown -R -L sparkuser /opt/spark && \
    chgrp -R -L sparkuser /opt/spark

USER sparkuser
WORKDIR /home/sparkuser

ENV PYSPARK_PYTHON=python3

ENTRYPOINT ["tail", "-f", "/dev/null"]
