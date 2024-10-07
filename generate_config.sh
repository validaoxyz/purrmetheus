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

if [ "$USE_DOCKER" = "true" ]; then
    export NODE_HOME="/home/hluser/hl"
    export BINARY_HOME="/home/hluser"
    export VOLUME_MOUNTS="      - hyperliquid_hl-data:/home/hluser/hl/data:ro"
    export EXTRA_VOLUMES="  hyperliquid_hl-data:
    external: true"
    echo "Using Docker setup for Hyperliquid node"
else
    if [ -z "$NODE_HOME" ]; then
        export NODE_HOME="${HOME}/hl"
        echo "NODE_HOME is not set in .env file. Using default path: ${NODE_HOME}"
    else
        echo "Using NODE_HOME=$NODE_HOME"
    fi

    if [ -z "$NODE_BINARY" ]; then
        export NODE_BINARY="${HOME}/hl-visor"
        echo "NODE_BINARY is not set in .env file. Using default path: ${NODE_BINARY}"
    else
        echo "Using NODE_BINARY=$NODE_BINARY"
    fi

    export BINARY_HOME=$(dirname "$NODE_BINARY")
    export VOLUME_MOUNTS="      - ${NODE_HOME}:/home/hluser/hl:ro
      - ${BINARY_HOME}:/home/hluser:ro"
    export EXTRA_VOLUMES=""
    echo "Using local setup for Hyperliquid node"
fi

if [ -z "$GRAFANA_ADMIN_USER" ]; then
    export GRAFANA_ADMIN_USER="admin"
    echo "GRAFANA_ADMIN_USER is not set in .env file. Using user: admin"
else
    echo "Using GRAFANA_ADMIN_USER=$GRAFANA_ADMIN_USER"
fi

if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
    export GRAFANA_ADMIN_PASSWORD="admin"
    echo "GRAFANA_ADMIN_PASSWORD is not set in .env file. Using password: admin"
else
    echo "Using GRAFANA_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD"
fi

# Generate files from templates
envsubst '${USER_ID},${GROUP_ID}' < docker/templates/Dockerfile.tmpl > docker/Dockerfile
envsubst '${USER_ID},${GROUP_ID},${NODE_HOME},${BINARY_HOME},${GRAFANA_ADMIN_USER},${GRAFANA_ADMIN_PASSWORD},${VOLUME_MOUNTS},${EXTRA_VOLUMES}' < docker/templates/docker-compose.yaml.tmpl > docker/docker-compose.yaml
envsubst < prometheus/prometheus.yml.tmpl > prometheus/prometheus.yml

echo "Dockerfile, docker-compose.yaml and prometheus.yml have been generated successfully."
