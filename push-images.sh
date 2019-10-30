#!/usr/bin/env bash
set -euo pipefail

docker login -u="${DOCKER_USERNAME}" -p="${DOCKER_PASSWORD}"

IMAGE_NAME=${IMAGE_NAME:-airflow-pipeline}

TAG_NAME="${SELF_VERSION}_${AIRFLOW_VERSION}_spark-${SPARK_VERSION}_hadoop-${HADOOP_VERSION}_python-${PYTHON_VERSION}_sqlalchemy-${SQLALCHEMY_VERSION}"
docker tag "${IMAGE_NAME}:${TAG_NAME}" "${DOCKER_USERNAME}/${IMAGE_NAME}:${TAG_NAME}"
docker push "${DOCKER_USERNAME}/${IMAGE_NAME}:${TAG_NAME}"

ALT_TAG_NAME="${AIRFLOW_VERSION}_spark-${SPARK_VERSION}_hadoop-${HADOOP_VERSION}_python-${PYTHON_VERSION}_sqlalchemy-${SQLALCHEMY_VERSION}"
docker tag "${IMAGE_NAME}:${TAG_NAME}" "${DOCKER_USERNAME}/${IMAGE_NAME}:${ALT_TAG_NAME}"
docker push "${DOCKER_USERNAME}/${IMAGE_NAME}:${ALT_TAG_NAME}"
