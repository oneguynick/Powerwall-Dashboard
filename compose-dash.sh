#!/bin/bash
#
# Convenience script for podman-compose
# Enables
#   - podman-compose and podman compose (v1, v2)
#   - moves multiple versions of unweildy compose invocation to one place
#   - very convenient for starting and stopping containers when developing.
# Takes up to two arguments, typicallly "up -d", "start", and "stop"
# Always verifies podman and podman-compose, as it is run infrequently.
# by BuongiornoTexas 16 Oct 2022

# Stop on Errors
set -e

# Check for Arguments
if [ -z "$1" ]
  then
    echo "Powerwall-Dashboard helper script for podman-compose"
    echo ""
    echo "Usage:"
    echo "  ${0} [COMMAND] [ARG]"
    echo ""
    echo "Commands (see podman-compose for full list):"
    echo "  up -d              Create and start containers"
    echo "  start              Start services"
    echo "  stop               Stop services"
    echo "  down               Remove services"
    exit 1
fi

# podman Dependency Check
if ! podman info > /dev/null 2>&1; then
    echo "ERROR: podman is not available or not runnning."
    echo "This script requires podman, please install and try again."
    exit 1
fi

# Load enviroment variables for compose
if [ ! -f "compose.env" ]; then
    echo "ERROR: Missing compose.env file."
    echo "Please run setup.sh or copy compose.env.sample to compose.env."
    exit 1
fi
set -a
. compose.env
set +a

# podman Compose Extension Check
if [ -f "powerwall.extend.yml" ]; then
    echo "Including powerwall.extend.yml"
    pwextend="-f powerwall.extend.yml"
else
    pwextend=""
fi

echo "Running podman Compose..."
if podman-compose version > /dev/null 2>&1; then
    # Build podman (v1)
    podman-compose -f powerwall.yml $pwextend $1 $2
else
    if podman compose version > /dev/null 2>&1; then
        # Build podman (v2)
        podman compose -f powerwall.yml $pwextend $1 $2
    else
        echo "ERROR: podman-compose/podman compose is not available or not runnning."
        echo "This script requires podman-compose or podman compose."
        echo "Please install and try again."
        exit 1
    fi
fi
