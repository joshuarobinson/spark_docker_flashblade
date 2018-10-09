FROM openjdk:8

RUN apt-get update && apt-get install -y python3 python3-pip 

ARG SCALA_VER=2.11.8
RUN curl -O https://www.scala-lang.org/files/archive/scala-$SCALA_VER.deb \
	&& dpkg -i scala-$SCALA_VER.deb \
	&& rm scala-$SCALA_VER.deb

ARG SPARK_VERSION
ARG HADOOP_VERSION=2.7

ARG PACKAGE=spark-$SPARK_VERSION-bin-hadoop$HADOOP_VERSION

RUN curl -O https://archive.apache.org/dist/spark/spark-$SPARK_VERSION/$PACKAGE.tgz \
	&& tar -xzf $PACKAGE.tgz -C /opt/ \
	&& rm $PACKAGE.tgz \
	&& ln -s /opt/$PACKAGE /opt/spark

COPY aws-java-sdk-1.7.4.jar /opt/spark/jars/
COPY hadoop-aws-2.7.3.jar /opt/spark/jars/

COPY spark-defaults.conf /opt/spark/conf/

RUN pip3 install jupyter opencv-python matplotlib sklearn

RUN groupadd -g 1080 sparkuser && \
    useradd -r -m -u 1080 -g sparkuser sparkuser && \
    chown -R -L sparkuser /opt/spark && \
    chgrp -R -L sparkuser /opt/spark

USER sparkuser
WORKDIR /home/sparkuser

ENV PYSPARK_PYTHON=python3

EXPOSE 8080 8081 7077 7078 6066 4040

ENTRYPOINT ["tail", "-f", "/dev/null"]
