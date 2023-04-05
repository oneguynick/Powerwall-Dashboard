#!/bin/bash
#
# Interactive Setup Script for Powerwall Dashboard
# by Jason Cox - 21 Jan 2022
# updates by Nicholas Schmidt - 5 April 2023

# Stop on Errors
set -e

if [ ! -f VERSION ]; then
  echo "ERROR: Missing VERSION file. Setup must run from installation directory."
  echo ""
  exit 1
fi
VERSION=`cat VERSION`

echo "Powerwall Dashboard (v${VERSION}) - SETUP"
echo "-----------------------------------------"

# Verify not running as root
if [ "$EUID" -eq 0 ]; then
  echo "ERROR: Running this as root will cause permission issues."
  echo ""
  echo "Please ensure your local user in in the podman group and run without sudo."
  echo "   sudo usermod -aG podman \$USER"
  echo "   $0"
  echo ""
  exit 1
fi

# Service Running Helper Function
running() {
    local url=${1:-http://localhost:80}
    local code=${2:-200}
    local status=$(curl --head --location --connect-timeout 5 --write-out %{http_code} --silent --output /dev/null ${url})
    [[ $status == ${code} ]]
}

# Podman Dependency Check
if ! podman info > /dev/null 2>&1; then
    echo "ERROR: podman is not available or not runnning."
    echo "This script requires podman, please install and try again."
    exit 1
fi
if ! podman-compose version > /dev/null 2>&1; then
    if ! podman compose version > /dev/null 2>&1; then
        echo "ERROR: podman-compose is not available or not runnning."
        echo "This script requires podman-compose or podman compose."
        echo "Please install and try again."
        exit 1
    fi
fi

# Check for RPi Issue with Buster
if [[ -f "/etc/os-release" ]]; then
    OS_VER=`grep PRETTY /etc/os-release | cut -d= -f2 | cut -d\" -f2`
    if [[ "$OS_VER" == "Raspbian GNU/Linux 10 (buster)" ]]
    then
        echo "WARNING: You are running ${OS_VER}"
        echo "    This OS version has a bug in the libseccomp2 library that"
        echo "    causes the pypowerwall container to fail."
        echo "    See details: https://github.com/jasonacox/Powerwall-Dashboard/issues/56"
        echo ""
        read -r -p "Setup - Proceed? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
        then
            echo ""
        else
            echo "Cancel"
            exit 1
        fi
    fi
fi

PW_ENV_FILE="pypowerwall.env"
COMPOSE_ENV_FILE="compose.env"
TELEGRAF_LOCAL="telegraf.local"
GF_ENV_FILE="grafana.env"
CURRENT=`cat tz`

echo "Timezone (leave blank for ${CURRENT})"
read -p 'Enter Timezone: ' TZ
echo ""

# Powerwall Credentials
if [ -f ${PW_ENV_FILE} ]; then
    echo "Current Powerwall Credentials:"
    echo ""
    cat ${PW_ENV_FILE}
    echo ""
    read -r -p "Update these credentials? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        rm ${PW_ENV_FILE}
    else
        echo "Using existing ${PW_ENV_FILE}."
    fi
fi

# Create Powerwall Settings
if [ ! -f ${PW_ENV_FILE} ]; then
    echo "Enter credentials for Powerwall..."
    read -p 'Password: ' PASSWORD
    read -p 'Email: ' EMAIL
    read -p 'IP Address: ' IP
    echo "PW_EMAIL=${EMAIL}" > ${PW_ENV_FILE}
    echo "PW_PASSWORD=${PASSWORD}" >> ${PW_ENV_FILE}
    echo "PW_HOST=${IP}" >> ${PW_ENV_FILE}
    echo "PW_TIMEZONE=America/Los_Angeles" >> ${PW_ENV_FILE}
    echo "TZ=America/Los_Angeles" >> ${PW_ENV_FILE}
    echo "PW_DEBUG=no" >> ${PW_ENV_FILE}
fi

# Create Grafana Settings if missing (required in 2.4.0)
if [ ! -f ${GF_ENV_FILE} ]; then
    cp "${GF_ENV_FILE}.sample" "${GF_ENV_FILE}"
fi

# Create default podman compose env file if needed.
if [ ! -f ${COMPOSE_ENV_FILE} ]; then
    cp "${COMPOSE_ENV_FILE}.sample" "${COMPOSE_ENV_FILE}"
fi

# Create default telegraf local file if needed.
if [ ! -f ${TELEGRAF_LOCAL} ]; then
    cp "${TELEGRAF_LOCAL}.sample" "${TELEGRAF_LOCAL}"
fi

echo ""
if [ -z "${TZ}" ]; then
    echo "Using ${CURRENT} timezone...";
    ./tz.sh "${CURRENT}";
else
    echo "Setting ${TZ} timezone...";
    ./tz.sh "${TZ}";
fi
echo "-----------------------------------------"
echo ""

# Optional - Setup Weather Data
if [ -f weather.sh ]; then
    ./weather.sh setup
fi

# Build Podman in current environment
./compose-dash.sh up -d
echo "-----------------------------------------"

# Set up Influx
echo "Waiting for InfluxDB to start..."
until running http://localhost:8086/ping 204 2>/dev/null; do
    printf '.'
    sleep 5
done
echo " up!"
sleep 2
echo "Setup InfluxDB Data for Powerwall..."
podman exec --tty influxdb sh -c "influx -import -path=/var/lib/influxdb/influxdb.sql"
sleep 2
# Execute Run-Once queries for initial setup.
cd influxdb
for f in run-once*.sql; do
    if [ ! -f "${f}.done" ]; then
        echo "Executing single run query $f file...";
        podman exec --tty influxdb sh -c "influx -import -path=/var/lib/influxdb/${f}"
        echo "OK" > "${f}.done"
    fi
done
cd ..

# Restart weather411 to force a sample
if [ -f weather/weather411.conf ]; then
    echo "Fetching local weather..."
    podman restart weather411
fi

# Display Final Instructions
cat << EOF
------------------[ Final Setup Instructions ]-----------------

Open Grafana at http://localhost:9000/ ... use admin/admin for login.
  - If you are running podman rootless you will need to chown the ./grafana folder with your SUID/SGID

Follow these instructions for *Grafana Setup*:

* From 'Configuration\Data Sources' add 'InfluxDB' database with:
  - Name: 'InfluxDB'
  - URL: 'http://influxdb:8086'
  - Database: 'powerwall'
  - Min time interval: '5s'
  - Click "Save & test" button

* From 'Configuration\Data Sources' add 'Sun and Moon' database with:
  - Name: 'Sun and Moon'
  - Enter your latitude and longitude (tool here: https://bit.ly/3wYNaI1 )
  - Click "Save & test" button

* From 'Dashboard\Browse', select 'New/Import', and upload 'dashboard.json' from
EOF
pwd
