#!/bin/bash
########################################################################################################################
# Script for cleaning cluster node instance and network resources with provided cluster name from snowball devices
#
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
# Get the number of devices from config.json
LEN=$(jq '.Devices | length'  $CONFIG_FILE)

# Get the snowballEdge cli path
SNOWBALLEDGE_CLIENT_PATH=$(jq -r '.SnowballEdgeClientPath' $CONFIG_FILE)

# Get the cluster name from config file
CLUSTER_NAME=$(jq -r '.ClusterName' $CONFIG_FILE)
TAG_KEY=sigs.k8s.io/cluster-api-provider-aws-snow/cluster/$CLUSTER_NAME

# Check if snowballEdge cli path is provided and valid
if [[ ! -f $SNOWBALLEDGE_CLIENT_PATH ]];
then
  echo "The SnowballEdge client path provided is invalid, please provide a valid one. Exiting..."
  exit
fi

for i in $(seq 0 $[LEN - 1])
do
  # Check the device's IP address and unlock code are provided and valid
  DEVICE_IP=$(jq -r '.Devices['$i'].IPAddress' $CONFIG_FILE)
  UNLOCK_CODE=$(jq -r '.Devices['$i'].UnlockCode' $CONFIG_FILE)
  if [[ -z $DEVICE_IP ]]
  then
    echo "The NO.$[i+1]'s IP address is invalid, please provide valid information, Exiting..."
    exit
  fi

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

  # Setup environment variable
  export AWS_ACCESS_KEY_ID=$($SNOWBALLEDGE_CLIENT_PATH list-access-keys --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | jq -r '.AccessKeyIds[0]')
  export AWS_SECRET_ACCESS_KEY=$($SNOWBALLEDGE_CLIENT_PATH get-secret-access-key --access-key-id $AWS_ACCESS_KEY_ID --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | grep 'aws_secret_access_key' | awk '{print $3}')
  export AWS_DEFAULT_REGION=snow

  echo "Cleaning node instances resources on device $DEVICE_IP"

  # Get instance id list with the cluster name
  INSTANCE_ID_LIST=$(aws ec2 describe-instances --endpoint http://$DEVICE_IP:8008 | jq -r --arg TAG_KEY $TAG_KEY '.Reservations[].Instances[] | select(.Tags != null) | select(.Tags[].Key == $TAG_KEY) | .InstanceId')
  for INSTANCE_ID in $INSTANCE_ID_LIST
  do
    # Get DNI list
    DIRECT_NETWORK_INTERFACE_ARN_LIST=$($SNOWBALLEDGE_CLIENT_PATH describe-direct-network-interfaces --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | jq -r --arg INSTANCE_ID "$INSTANCE_ID" '.DirectNetworkInterfaces[] | select(.InstanceId==$INSTANCE_ID) | .DirectNetworkInterfaceArn')
    for ARN in $DIRECT_NETWORK_INTERFACE_ARN_LIST
    do
      echo "Deleting direct network interface with arn: $ARN"
      $SNOWBALLEDGE_CLIENT_PATH delete-direct-network-interface --direct-network-interface-arn $ARN --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE
    done
    echo "Deleting tags of instance with id: $INSTANCE_ID"
    aws ec2 delete-tags --resources $INSTANCE_ID --endpoint http://$DEVICE_IP:8008
    echo "Deleting instance with id: $INSTANCE_ID"
    aws ec2 terminate-instances --instance-id $INSTANCE_ID --endpoint http://$DEVICE_IP:8008
    aws ec2 wait instance-terminated --instance-id $INSTANCE_ID --endpoint http://$DEVICE_IP:8008
  done
done

echo "Cleaning process finished."
