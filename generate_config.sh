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

if [ -z "$NODE_HOME" ]; then
    export NODE_HOME="${HOME}/hl"
    echo "NODE_HOME is not set in .env file. Using HOME directory: ${NODE_HOME}/hl"
else
    echo "Using NODE_HOME=$NODE_HOME"
fi

if [ -z "$NODE_BINARY" ]; then
    export NODE_BINARY="${HOME}/hl-visor"
    echo "NODE_BINARY is not set in .env file. Using default path: ${HOME}/hl-visor"
else
    echo "Using NODE_BINARY=$NODE_BINARY"
fi

export BINARY_HOME=$(dirname "$NODE_BINARY")


if [ -z "$GRAFANA_ADMIN_USER" ]; then
    export GRAFANA_ADMIN_USER="admin"
    echo "GRAFANA_ADMIN_USER is not set in .env file. Using user: admin"
else
    echo "Using GRAFANA_ADMIN_USER=$GRAFANA_ADMIN_USER"
fi
if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
    export GRAFANA_ADMIN_PASSWORD="admin"
    echo "GRAFANA_ADMIN_PASSWORD is not set in .env file. Using user: admin"
else
    echo "Using GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD"
fi

# Generate files from templates
envsubst '${USER_ID},${GROUP_ID}' < docker/templates/Dockerfile.tmpl > docker/Dockerfile
envsubst '${USER_ID},${GROUP_ID},${NODE_HOME},${GRAFANA_ADMIN_USER},${GRAFANA_ADMIN_PASSWORD}' < docker/templates/docker-compose.yaml.tmpl > docker/docker-compose.yaml
envsubst < prometheus/prometheus.yml.tmpl > prometheus/prometheus.yml

echo "Dockerfile, docker-compose.yaml and prometheus.yml have been generated successfully."
