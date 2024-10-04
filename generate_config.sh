#!/bin/bash

set -e

# Load environment variables from .env file
if [ -f .env ]; then
    set -a  # Automatically export all variables
    source .env
    set +a
else
    echo ".env file not found!"
    exit 1
fi

# Get the current user's UID and GID
export USER_ID=$(id -u)
export GROUP_ID=$(id -g)

echo "Using USER_ID=$USER_ID and GROUP_ID=$GROUP_ID"

# Use $HOME if NODE_HOME is unset or empty
if [ -z "$NODE_HOME" ]; then
    export NODE_HOME="$HOME"
    echo "NODE_HOME is not set in .env file. Using HOME directory: $NODE_HOME"
else
    echo "Using NODE_HOME=$NODE_HOME"
fi

# Generate files from templates
envsubst '${USER_ID},${GROUP_ID}' < docker/templates/Dockerfile.tmpl > docker/Dockerfile
envsubst '${USER_ID},${GROUP_ID},${NODE_HOME}' < docker/templates/docker-compose.yaml.tmpl > docker/docker-compose.yaml
envsubst < prometheus/prometheus.yml.tmpl > prometheus/prometheus.yml

echo "Dockerfile, docker-compose.yaml and prometheus.yml have been generated successfully."
