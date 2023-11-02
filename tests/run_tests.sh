#!/usr/bin/env bash

# Define some variables to use in this script
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
TEST_RESOURCES_DIR="${SCRIPT_DIR}/resources"
TEST_RESOURCES_PRETRAINED_DIR="${TEST_RESOURCES_DIR}/pretrained/Task004_Hippocampus"
CODEBASE_DIR=`realpath "${SCRIPT_DIR}/../"`
DOCKER_DEV_IMAGE="nnunet_dev_image:latest"
BUILD_DOCKER=0
FORCE_BOOTSTRAP=0
CPU_TEST="--runtime=nvidia"

# Process optional arguments
while [ $# -ne 0 ]
do
  case "$1" in
    --build-docker)
      BUILD_DOCKER=1
      ;;
    --force-bootstrap)
      FORCE_BOOTSTRAP=1
      ;;
    --cpu-test)
      CPU_TEST=""
      ;;
    *)
      echo "invalid option: $1"
      exit 0
      ;;
  esac
  shift
done


# Display help and warnings
echo "!!! Warning: This script generates a Docker image and downloads and bootstraps the required test files if they aren't present."
echo "!!! This script assumes you are running from a Linux machine with docker installed."
echo "!!! The required test files (that will be downloaded) take approximately 300MB of disk space and will be downloaded to: "
echo "!!! ${TEST_RESOURCES_PRETRAINED_DIR}"
echo "!!! The other test files are bootstrapped from a 28MB tar file and require approximately 160MB of disk space to store them."
echo "!!! The required Docker image can take up to 11GB and will be given the tag: ${DOCKER_DEV_IMAGE}"

# Test if test environment docker image is present, otherwise build it
if [ $BUILD_DOCKER -eq 1 ]; then
  echo "# --build-docker option specified, building '${DOCKER_DEV_IMAGE}'..."
  docker build "${SCRIPT_DIR}/docker" --tag="${DOCKER_DEV_IMAGE}"
fi
if [[ "`docker images -q nnunet_dev_image:latest`" == "" ]]; then
  echo "# no '${DOCKER_DEV_IMAGE}' docker image found, building..."
  docker build "${SCRIPT_DIR}/docker" --tag="${DOCKER_DEV_IMAGE}"
else
  echo "# Reusing '${DOCKER_DEV_IMAGE}' docker image..."
fi
if [[ "`docker images -q ${DOCKER_DEV_IMAGE}`" == "" ]]; then
  echo "# No '${DOCKER_DEV_IMAGE}' docker image found after build step, something went wrong, aborting now..."
  exit 1
fi

# Test if all required test files are present, otherwise download/bootstrap them...
if [ $FORCE_BOOTSTRAP -eq 0 ]; then
  echo "# Testing if test resources are present..."
  docker run -t --rm -v "${CODEBASE_DIR}:${CODEBASE_DIR}" -w "${CODEBASE_DIR}" ${DOCKER_DEV_IMAGE} python3.8 "${CODEBASE_DIR}/tests/resources/check_integrity.py"
  integrityResult="$?"
  if [ $integrityResult -eq 2 ]; then
    echo "# Missing the source TAR file, please download and install that first..."
    exit 1
  fi
  if [ $integrityResult -ne 0 ]; then
    echo "# Test resources are missing, start bootstrapping all test files..."
  fi
else
  echo "# Force bootstrap specified, start bootstrapping all test files..."
  integrityResult=1
fi
if [ $integrityResult -ne 0 ]; then
  docker run -t --rm -e "PYTHONPATH=${CODEBASE_DIR}" -v "${CODEBASE_DIR}:${CODEBASE_DIR}" -w "${CODEBASE_DIR}" ${DOCKER_DEV_IMAGE} python3.8 "${CODEBASE_DIR}/tests/resources/bootstrap.py"
  echo "# Testing if bootstrapped test resources are valid..."
  docker run -t --rm -v "${CODEBASE_DIR}:${CODEBASE_DIR}" -w "${CODEBASE_DIR}" ${DOCKER_DEV_IMAGE} python3.8 "${CODEBASE_DIR}/tests/resources/check_integrity.py"
  integrityResult="$?"
  if [ $integrityResult -ne 0 ]; then
    echo "Integrity test failed after bootstrapping the files, aborting now..."
    exit 1
  fi
fi
echo "# All required test resources present..."

# Run all tests
echo "# Running all tests using docker image: '${DOCKER_DEV_IMAGE}'"
docker run -t --rm ${CPU_TEST} --shm-size=8g -v "${CODEBASE_DIR}:${CODEBASE_DIR}" -w "${CODEBASE_DIR}" ${DOCKER_DEV_IMAGE} python3.8 -m pytest "${CODEBASE_DIR}/tests"
