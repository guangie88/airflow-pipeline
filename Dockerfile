ARG AIRFLOW_VERSION=
ARG SPARK_VERSION=
ARG HADOOP_VERSION=

FROM guangie88/test-spark-custom-addons:${SPARK_VERSION}_hadoop-${HADOOP_VERSION}_hive_pyspark_debian AS base

# Build matrix configurable values
ARG SQLALCHEMY_VERSION
ENV SQLALCHEMY_VERSION=${SQLALCHEMY_VERSION}

ARG AIRFLOW_VERSION
ENV AIRFLOW_VERSION=${AIRFLOW_VERSION}

# Default to Python 2.7
ARG SELECTED_PYTHON_MAJOR_VERSION=2

# Values that are better left with defaults

## Default user and group for running Airflow
ARG USER=afpuser
ENV USER=${USER}
ARG GROUP=hadoop
ENV GROUP=${GROUP}

## Airflow uses Postgres as its database, example env vars below
ARG POSTGRES_HOST=localhost
ENV POSTGRES_HOST=${POSTGRES_HOST}

ARG POSTGRES_PORT=5999
ENV POSTGRES_PORT=${POSTGRES_PORT}

ARG POSTGRES_USER=fixme
ENV POSTGRES_USER=${POSTGRES_USER}

ARG POSTGRES_PASSWORD=fixme
ENV POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

ARG POSTGRES_DB=airflow
ENV POSTGRES_DB=${POSTGRES_DB}

## Other Spark / Airflow related defaults
ARG HADOOP_HOME="/opt/hadoop"
ENV HADOOP_HOME ${HADOOP_HOME}

ARG HADOOP_CONF_DIR="/opt/hadoop/etc/hadoop"
ENV HADOOP_CONF_DIR ${HADOOP_CONF_DIR}

ARG SPARK_PY4J

ARG AIRFLOW_HOME=/airflow
ENV AIRFLOW_HOME=${AIRFLOW_HOME}
ENV AIRFLOW_DAG=${AIRFLOW_HOME}/dags

ENV PYTHONPATH=${SPARK_HOME}/${SPARK_PY4J}:${SPARK_HOME}/python:${AIRFLOW_HOME}/config
ENV PYSPARK_SUBMIT_ARGS="--py-files ${SPARK_HOME}/python/lib/pyspark.zip pyspark-shell"

# Select default Python version first
# Airflow script only uses /usr/bin/python, so need to set this symbolic link properly to switch the version
RUN set -euo pipefail && \
    unlink /usr/bin/python; \
    if [ "${SELECTED_PYTHON_MAJOR_VERSION}" = "2" ]; then \
        PYTHON2_MAJOR_MINOR_VERSION="$(python2 --version 2>&1 | cut -d ' ' -f2 | cut -d '.' -f1,2)"; \
        ln -s "/usr/bin/python${PYTHON2_MAJOR_MINOR_VERSION}" /usr/bin/python; \
    elif [ "${SELECTED_PYTHON_MAJOR_VERSION}" = "3" ]; then \
        PYTHON3_MAJOR_MINOR_VERSION="$(python3 --version 2>&1 | cut -d ' ' -f2 | cut -d '.' -f1,2)"; \
        ln -s "/usr/bin/python${PYTHON3_MAJOR_MINOR_VERSION}" /usr/bin/python; \
    else \
        >&2 echo "SELECTED_PYTHON_MAJOR_VERSION must be either 2 or 3 only"; \
        return 1; \
    fi; \
    :

# Setup airflow
RUN set -euo pipefail && \
    # Set up Python packages variables
    if [ "${SELECTED_PYTHON_MAJOR_VERSION}" = "2" ]; then PY_PKG_SUFFIX=""; else PY_PKG_SUFFIX="3"; fi; \
    PYTHON_PIP_PKG="python${PY_PKG_SUFFIX}-pip"; \
    PYTHON_SETUPTOOLS_PKG="python${PY_PKG_SUFFIX}-setuptools"; \
    PYTHON_DEV_PKG="python${PY_PKG_SUFFIX}-dev"; \
    # Apt
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        # For setup purposes only
        curl \
        "${PYTHON_PIP_PKG}" \
        "${PYTHON_SETUPTOOLS_PKG}" \
        unzip \
        # Intended packages
        build-essential \
        default-libmysqlclient-dev \
        gosu \
        krb5-user \
        libffi-dev \
        libkrb5-dev \
        libpq-dev \
        libsasl2-dev \
        "${PYTHON_DEV_PKG}" \
        vim-tiny \
        ; \
    rm -rf /var/lib/apt/lists/*; \
    # Update pip
    python -m pip install --upgrade pip; \
    # Airflow and SQLAlchemy
    ## These two version numbers can take MAJ.MIN[.PAT]
    AIRFLOW_NORM_VERSION="$(printf "%s.%s" "${AIRFLOW_VERSION}" "*" | cut -d '.' -f1,2,3)"; \
    python -m pip install --no-cache-dir "apache-airflow[all]==${AIRFLOW_NORM_VERSION}" psycopg2 flask_bcrypt; \
    SQLALCHEMY_NORM_VERSION="$(printf "%s.%s" "${SQLALCHEMY_VERSION}" "*" | cut -d '.' -f1,2,3)"; \
    python -m pip install --no-cache-dir "sqlalchemy==${SQLALCHEMY_NORM_VERSION}"; \
    # Hadoop external installation
    mkdir -p $(dirname "${HADOOP_HOME}"); \
    curl -LO https://archive.apache.org/dist/hadoop/core/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz; \
    tar xf hadoop-${HADOOP_VERSION}.tar.gz; \
    mv hadoop-${HADOOP_VERSION} ${HADOOP_HOME}; \
    rm hadoop-${HADOOP_VERSION}.tar.gz; \
    # Install JARs to Hadoop external
    ## AWS S3 JARs
    AWS_JAVA_SDK_VERSION="$(curl -sL https://raw.githubusercontent.com/apache/hadoop/branch-${HADOOP_VERSION}/hadoop-project/pom.xml | grep aws-java-sdk -A 1 | grep version | head -n 1 | grep -oE '[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+')"; \
    cd ${HADOOP_HOME}/share/hadoop/hdfs/; \
    curl -LO http://central.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar; \
    curl -LO https://sdk-for-java.amazonwebservices.com/aws-java-sdk-${AWS_JAVA_SDK_VERSION}.zip; \
    unzip -qq aws-java-sdk-${AWS_JAVA_SDK_VERSION}.zip; \
    mv ./aws-java-sdk-${AWS_JAVA_SDK_VERSION}/lib/aws-java-sdk-${AWS_JAVA_SDK_VERSION}.jar ./; \
    mv ./aws-java-sdk-${AWS_JAVA_SDK_VERSION}/third-party/lib/*.jar ./; \
    rm -r ./aws-java-sdk-${AWS_JAVA_SDK_VERSION}; \
    rm ./aws-java-sdk-${AWS_JAVA_SDK_VERSION}.zip; \
    cd -; \
    printf "\
<?xml version="1.0" encoding="UTF-8"?>\n\
<configuration>\n\
<property>\n\
    <name>fs.s3a.impl</name>\n\
    <value>org.apache.hadoop.fs.s3a.S3AFileSystem</value>\n\
</property>\n\
</configuration>\n" > ${HADOOP_CONF_DIR}/core-site.xml; \
    ## Google Storage JAR
    cd ${HADOOP_HOME}/share/hadoop/hdfs/; \
    curl -sLO https://storage.googleapis.com/hadoop-lib/gcs/gcs-connector-hadoop2-latest.jar; \
    cd -; \
    ## MariaDB JAR
    cd ${HADOOP_HOME}/share/hadoop/tools/lib; \
    curl -sLO https://downloads.mariadb.com/Connectors/java/connector-java-2.4.0/mariadb-java-client-2.4.0.jar; \
    cd -; \
    # Remove unused apt packages
    DEBIAN_FRONTEND=noninteractive apt-get remove --no-install-recommends -y \
        curl \
        "${PYTHON_PIP_PKG}" \
        "${PYTHON_SETUPTOOLS_PKG}" \
        unzip \
        ; \
    rm -rf /var/lib/apt/lists/*; \
    :

ENV PATH ${PATH}:${HADOOP_HOME}/bin

WORKDIR ${AIRFLOW_HOME}

# Setup airflow dags path
RUN mkdir -p ${AIRFLOW_DAG}

COPY setup_auth.py ${AIRFLOW_HOME}/setup_auth.py
VOLUME ${AIRFLOW_HOME}/logs
COPY airflow.cfg ${AIRFLOW_HOME}/airflow.cfg
COPY unittests.cfg ${AIRFLOW_HOME}/unittests.cfg

# Create default user and group
RUN groupadd -r "${GROUP}" && useradd -rmg "${GROUP}" "${USER}"

# Less verbose logging
COPY log4j.properties ${SPARK_HOME}/conf/log4j.properties

# for optional S3 logging
COPY ./config/ ${AIRFLOW_HOME}/config/

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
