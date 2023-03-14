#!/bin/bash
########################################################################################################################
# Script for creating an EKS Anywhere admin instance
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

CONFIG_FILE="config.json"
# Use the first device in config file to launch ec2 instance
SNOWBALLEDGE_CLIENT_PATH=$(jq -r '.SnowballEdgeClientPath' $CONFIG_FILE)
# Check if snowballEdge cli path is provided and valid
if [[ ! -f $SNOWBALLEDGE_CLIENT_PATH ]];
then
  echo "The SnowballEdge client path provided is invalid, please provide a valid one. Exiting..."
  exit
fi

# Check if the first device's IP address and unlock code are provided and valid
DEVICE_IP=$(jq -r '.Devices[0].IPAddress' $CONFIG_FILE)
UNLOCK_CODE=$(jq -r '.Devices[0].UnlockCode' $CONFIG_FILE)
if [[ -z $DEVICE_IP ]]
then
  echo "The IP address provided for the first device is invalid, please provide valid information, Exiting..."
  exit
fi

if [[ -z $UNLOCK_CODE ]]
then
  echo "The Unlock code provided for the first device is invalid, please provide valid information, Exiting..."
  exit
fi

echo "Using the first device in config file to launch EKS-A admin instance"

# Get the first device's manifest path, IP address and unlock code from config.json and use it to launch an eks-a admin instance
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

# Get the latest EKS Anywhere admin AMI id
IMAGE_ID=$(jq -r '.EKSAAdminImageId' $CONFIG_FILE)
if [ -z $IMAGE_ID ]
then
  IMAGE_ID=$(aws ec2 describe-images --endpoint http://$DEVICE_IP:8008 | jq -r --arg IMAGE_NAME "eks-a-admin-ami" '.Images[] | select(.Name | startswith($IMAGE_NAME)) | "\(.Name) \(.ImageId)"' | sort -r | head -1 | awk '{print $2}')
  if [ -z $IMAGE_ID ]
  then
    echo "No EKS-A admin AMI found on the first device with the ip address: $DEVICE_IP. Exiting..."
    exit
  fi
fi

echo "The EKS-A admin image id is $IMAGE_ID"

# Get timestamp
TIMESTAMP=$(date '+%s')
# Create ssh key for the eks-a admin instance
KEY_NAME=eksa-admin-instance-key-$TIMESTAMP
aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --endpoint http://$DEVICE_IP:8008 --output text > /tmp/$KEY_NAME.pem
chmod 400 /tmp/$KEY_NAME.pem
echo "The instance ssh key is created and saved at: /tmp/$KEY_NAME.pem"

# Start an eks-a admin instance and get its instance id
INSTANCE_ID=$(aws ec2 run-instances --image-id $IMAGE_ID --key-name $KEY_NAME --instance-type sbe-c.large --endpoint http://$DEVICE_IP:8008 | jq -r '.Instances[].InstanceId')
echo "Starting an EKS Anywhere admin instance with instance id $INSTANCE_ID"

# Wait the instance to be running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --endpoint http://$DEVICE_IP:8008
echo "EKS Anywhere admin instance is in running state"

# After the instance is in running state, setup public ip for ec2 instance
DEVICE_INFO=$($SNOWBALLEDGE_CLIENT_PATH describe-device  --endpoint https://$DEVICE_IP --manifest-file $MANIFEST_PATH --unlock-code $UNLOCK_CODE)
ACTIVE_NETWORK_IP=$(jq -r '.ActiveNetworkInterface.IpAddress' <<< "$DEVICE_INFO")

# Find the active network interface
PHYSICAL_NETWORK_INTERFACE=$(jq -r --arg ACTIVE_NETWORK_IP "$ACTIVE_NETWORK_IP" '.PhysicalNetworkInterfaces[] | select(.IpAddress==$ACTIVE_NETWORK_IP) | .PhysicalNetworkInterfaceId' <<< "$DEVICE_INFO")
PUBLIC_IP=$($SNOWBALLEDGE_CLIENT_PATH create-virtual-network-interface --ip-address-assignment dhcp --physical-network-interface-id $PHYSICAL_NETWORK_INTERFACE --endpoint https://$DEVICE_IP --manifest-file $MANIFEST_PATH --unlock-code $UNLOCK_CODE | jq -r '.VirtualNetworkInterface.IpAddress')

# Associate the public address to the eks-a admin instance
aws ec2 associate-address --instance-id $INSTANCE_ID --public-ip $PUBLIC_IP --endpoint http://$DEVICE_IP:8008
echo "Attached public ip $PUBLIC_IP to eks anywhere instance $INSTANCE_ID"

# SCP the files to EKS-A Admin instance
echo "Sending formatted credentials and certificates to EKS-A Admin instance ..."
sleep 10

CREDS_FILE=/tmp/snowball_creds
CERTS_FILE=/tmp/snowball_certs

# Check if snowball_creds and snowball_certs exist
if [ ! -f  $CREDS_FILE ]; then
    echo "snowball_creds file does not exist. Exiting..."
    exit
fi

if [ ! -f  $CERTS_FILE ]; then
    echo "snowball_certs file does not exist. Exiting..."
    exit
fi
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /tmp/$KEY_NAME.pem $CREDS_FILE $CERTS_FILE ec2-user@$PUBLIC_IP:~

# Clear environment variable
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION
echo "Successfully created EKS Anywhere EC2 instance $INSTANCE_ID on device with ip $DEVICE_IP and attached public ip $PUBLIC_IP on it"

# Generate cluster config if cluster name is provided
CLUSTER_NAME=$(jq -r '.ClusterName' $CONFIG_FILE)

if [[ ! -z $CLUSTER_NAME ]]
then
  echo "Creating cluster config on the eksa admin instance"
  sh ./generate-cluster-config.sh /tmp/$KEY_NAME.pem $PUBLIC_IP
  echo "Successfully created cluster config file /home/ec2-user/eksa-cluster-$CLUSTER_NAME.yaml on the EKS Anywhere admin instance"
  echo -e "Once your are on the admin instance, run the following command to create a cluster: \nsh ~/create-cluster-$CLUSTER_NAME.sh"
fi

echo -e "EKS Anywhere admin instance was successfully configured, you can ssh to it now using command: \nssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /tmp/$KEY_NAME.pem ec2-user@$PUBLIC_IP"
