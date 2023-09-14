#!/bin/bash
########################################################################################################################
# Script for setting up a harbor registry instance
#
# Prerequisites:
# 1. Install jq `curl -qL -o jq https://stedolan.github.io/jq/download/linux64/jq && chmod +x ./jq`
# 2. Add jq to your PATH
# 3. Install snowballEdge cli https://docs.aws.amazon.com/snowball/latest/developer-guide/download-the-client.html
# 4. Update your absolute SnowballEdge client path in config.json
# 5. Install aws cli
########################################################################################################################
set -euo pipefail

# unlock device
sh unlock-devices.sh

# Collect information from config.json
CONFIG_FILE="config.json"
# Get the snowball cli path from config.json
SNOWBALLEDGE_CLIENT_PATH=$(jq -r '.SnowballEdgeClientPath' $CONFIG_FILE)
# Get the device ip
DEVICE_IP=$(jq -r '.Devices[0].IPAddress' $CONFIG_FILE)
# Get the unlock code
UNLOCK_CODE=$(jq -r '.Devices[0].UnlockCode' $CONFIG_FILE)
# Get the manifest file
MANIFEST_PATH=$(jq -r '.Devices[0].ManifestPath' $CONFIG_FILE)

echo "Using the first device in config file to launch harbor registry instance"

# Get the first device's manifest path, IP address and unlock code from config.json and use it to launch a harbor registry instance
MANIFEST_PATH=$(jq -r '.Devices[0].ManifestPath' $CONFIG_FILE)
# Check if the first device's manifest file path is provided and valid
if [[ ! -f $MANIFEST_PATH ]];
then
  echo  "The manifest path provided for the first device with the ip address $DEVICE_IP is invalid, please provide a valid one. Exiting..."
  exit
fi

# Setup environment variable
export AWS_ACCESS_KEY_ID=$($SNOWBALLEDGE_CLIENT_PATH list-access-keys --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | jq -r '.AccessKeyIds[0]')
export AWS_SECRET_ACCESS_KEY=$($SNOWBALLEDGE_CLIENT_PATH get-secret-access-key --access-key-id $AWS_ACCESS_KEY_ID --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | grep 'aws_secret_access_key' | awk '{print $3}')
export AWS_DEFAULT_REGION=snow

# Get the harbor registry AMI id
IMAGE_ID=$(aws ec2 describe-images --endpoint http://$DEVICE_IP:8008 | jq -r --arg IMAGE_NAME "snow-harbor-image" '.Images[] | select(.Name | startswith($IMAGE_NAME)) | "\(.ImageId)"')
if [ -z $IMAGE_ID ]
then
  echo "No harbor AMI found on the first device with the ip address: $DEVICE_IP. Exiting..."
  exit
fi

echo "The harbor image id is $IMAGE_ID"

# Get timestamp
TIMESTAMP=$(date '+%s')
# Create ssh key for the harbor registry instance
KEY_NAME=harbor-registry-instance-key-$TIMESTAMP
aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --endpoint http://$DEVICE_IP:8008 --output text > /tmp/$KEY_NAME.pem
chmod 400 /tmp/$KEY_NAME.pem
echo "The instance ssh key is created and saved at: /tmp/$KEY_NAME.pem"

# Start an harbor registry instance and get its instance id
INSTANCE_ID=$(aws ec2 run-instances --image-id $IMAGE_ID --key-name $KEY_NAME --instance-type sbe-c.large --endpoint http://$DEVICE_IP:8008 | jq -r '.Instances[].InstanceId')
echo "Starting a harbor registry instance with instance id $INSTANCE_ID"

# Wait the instance to be running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --endpoint http://$DEVICE_IP:8008
echo "Harbor registry instance is in running state"

# After the instance is in running state, setup public ip for ec2 instance
DEVICE_INFO=$($SNOWBALLEDGE_CLIENT_PATH describe-device  --endpoint https://$DEVICE_IP --manifest-file $MANIFEST_PATH --unlock-code $UNLOCK_CODE)
ACTIVE_NETWORK_IP=$(jq -r '.ActiveNetworkInterface.IpAddress' <<< "$DEVICE_INFO")

# Find the active network interface
PHYSICAL_NETWORK_INTERFACE=$(jq -r --arg ACTIVE_NETWORK_IP "$ACTIVE_NETWORK_IP" '.PhysicalNetworkInterfaces[] | select(.IpAddress==$ACTIVE_NETWORK_IP) | .PhysicalNetworkInterfaceId' <<< "$DEVICE_INFO")
PUBLIC_IP=$($SNOWBALLEDGE_CLIENT_PATH create-virtual-network-interface --ip-address-assignment dhcp --physical-network-interface-id $PHYSICAL_NETWORK_INTERFACE --endpoint https://$DEVICE_IP --manifest-file $MANIFEST_PATH --unlock-code $UNLOCK_CODE | jq -r '.VirtualNetworkInterface.IpAddress')

# Associate the public address to the harbor registry instance
aws ec2 associate-address --instance-id $INSTANCE_ID --public-ip $PUBLIC_IP --endpoint http://$DEVICE_IP:8008
echo "Attached public ip $PUBLIC_IP to harbor registry instance $INSTANCE_ID"

# wait 10 for associate-address
sleep 10

# Clear environment variable
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION
echo "Successfully created harbor registry instance $INSTANCE_ID on device with ip $DEVICE_IP and attached public ip $PUBLIC_IP on it"

printf "Harbor registry instance was successfully configured, you can ssh to it now using command: \nssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /tmp/$KEY_NAME.pem ec2-user@$PUBLIC_IP"