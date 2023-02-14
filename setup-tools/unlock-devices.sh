#!/bin/bash
########################################################################################################################
# Script for unlocking Snow devices
# Prerequisites:
# 1. Install jq `curl -qL -o jq https://stedolan.github.io/jq/download/linux64/jq && chmod +x ./jq`
# 2. Add jq to your PATH
# 3. Install snowballEdge cli https://docs.aws.amazon.com/snowball/latest/developer-guide/download-the-client.html
# 4. Update your absolute SnowballEdge client path in config.json
# 5. Install aws cli
########################################################################################################################
set -euo pipefail

# Check dependencies
DEPENDENCIES=("jq" "aws")
for DEPENDENCY in ${DEPENDENCIES[@]}; do
  if ! command -v $DEPENDENCY &> /dev/null
  then
    echo "Please install $DEPENDENCY and add it in your PATH."
    echo "Exiting..."
    exit
  fi
done

# Collect information from config.json
CONFIG_FILE="config.json"
# Get the snowball cli path from config.json
SNOWBALLEDGE_CLIENT_PATH=$(jq -r '.SnowballEdgeClientPath' $CONFIG_FILE)
# Check if snowballEdge cli path is provided and valid
if [[ ! -f $SNOWBALLEDGE_CLIENT_PATH ]];
then
  echo "The SnowballEdge client path provided is invalid, please provide a valid one. Exiting..."
  exit
fi

# Get the number of devices in config.json
LEN=$(jq '.Devices | length'  $CONFIG_FILE)

# Check the device information, exit if information is incorrect
for i in $(seq 0 $[LEN - 1])
do
    DEVICE_IP=$(jq -r '.Devices['$i'].IPAddress' $CONFIG_FILE)

    if [[ -z $DEVICE_IP ]]
    then
      echo "The NO.$[i+1]'s IP address is invalid, please provide valid information, Exiting..."
      exit
    fi

    UNLOCK_CODE=$(jq -r '.Devices['$i'].UnlockCode' $CONFIG_FILE)
    if [[ -z $UNLOCK_CODE ]]
    then
      echo "The NO.$[i+1]'s unlock code is invalid, please provide valid information, Exiting..."
      exit
    fi

    # Check if manifest path is provided and valid
    MANIFEST_PATH=$(jq -r '.Devices['$i'].ManifestPath' $CONFIG_FILE)
    if [[ ! -f $MANIFEST_PATH ]];
    then
      echo  "The manifest path of the device with the IP Address $DEVICE_IP is invalid, please provide a valid one. Exiting..."
      exit
    fi
done

# Unlock each device
for i in $(seq 0 $[LEN - 1])
do
  (
    # Get the device information
    DEVICE_IP=$(jq -r '.Devices['$i'].IPAddress' $CONFIG_FILE)
    UNLOCK_CODE=$(jq -r '.Devices['$i'].UnlockCode' $CONFIG_FILE)
    MANIFEST_PATH=$(jq -r '.Devices['$i'].ManifestPath' $CONFIG_FILE)

    echo "Start unlocking the device with ip address $DEVICE_IP"

    # Unlock device
    if ! $SNOWBALLEDGE_CLIENT_PATH unlock-device --endpoint https://$DEVICE_IP --manifest-file $MANIFEST_PATH --unlock-code $UNLOCK_CODE; then
      echo "Failed to unlock the device: $DEVICE_IP"
      exit
    fi

    # Check unlock status
    UNLOCK_STATUS=$($SNOWBALLEDGE_CLIENT_PATH describe-device --endpoint https://$DEVICE_IP --manifest-file $MANIFEST_PATH --unlock-code $UNLOCK_CODE | jq -r '.UnlockStatus.State')
    while [ $UNLOCK_STATUS != UNLOCKED ]
    do
      sleep 30
      UNLOCK_STATUS=$($SNOWBALLEDGE_CLIENT_PATH describe-device --endpoint https://$DEVICE_IP --manifest-file $MANIFEST_PATH --unlock-code $UNLOCK_CODE | jq -r '.UnlockStatus.State')
      if [ $UNLOCK_STATUS == LOCKED ]
      then
        echo "Failed to unlock device: $DEVICE_IP"
        exit
      fi
    done

    if [ $UNLOCK_STATUS == UNLOCKED ]
    then
      echo "The device with ip address: $DEVICE_IP has been unlocked"
    fi
  )&
done

# Waiting for pending jobs to complete
wait
