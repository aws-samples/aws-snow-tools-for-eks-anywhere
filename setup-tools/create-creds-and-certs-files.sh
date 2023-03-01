#!/bin/bash
########################################################################################################################
# Script for setting up EKS Anywhere credentials and certificates
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

# Check if snowballEdge cli path is provided and valid
if [[ ! -f $SNOWBALLEDGE_CLIENT_PATH ]];
then
  echo "The SnowballEdge client path provided is invalid, please provide a valid one. Exiting..."
  exit
fi

# Create a policy with necessary permission in the tmp folder
cat <<EOF > /tmp/eks-a-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "snowballdevice:DescribeDevice",
        "snowballdevice:CreateDirectNetworkInterface",
        "snowballdevice:DeleteDirectNetworkInterface",
        "snowballdevice:DescribeDirectNetworkInterfaces",
        "snowballdevice:DescribeDeviceSoftware"
      ],
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:DescribeInstances",
        "ec2:TerminateInstances",
        "ec2:ImportKeyPair",
        "ec2:DescribeKeyPairs",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeImages",
        "ec2:DeleteTags"
      ],
      "Resource": ["*"]
    }
  ]
}
EOF

# Retrieving and delete the old device credential and certificate files
CREDS_FILE=/tmp/snowball_creds
rm -f $CREDS_FILE
CERTS_FILE=/tmp/snowball_certs
rm -f $CERTS_FILE

# Create IAM policies and save credentials and certificates for EKS-A for each device in config file
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

  echo "Setting up iam policies for the device with the IP Address: $DEVICE_IP"

  # Setup environment variable
  export AWS_ACCESS_KEY_ID=$($SNOWBALLEDGE_CLIENT_PATH list-access-keys --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | jq -r '.AccessKeyIds[0]')
  export AWS_SECRET_ACCESS_KEY=$($SNOWBALLEDGE_CLIENT_PATH get-secret-access-key --access-key-id $AWS_ACCESS_KEY_ID --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | grep 'aws_secret_access_key' | awk '{print $3}')
  export AWS_DEFAULT_REGION=snow

  # Get timestamp
  TIMESTAMP=$(date '+%s')
  # Create an IAM user for EKS-A
  aws iam create-user --user-name eks-a-user-$TIMESTAMP --endpoint http://$DEVICE_IP:6078

  # Create a policy and get the ARN value
  POLICY_ARN=$(aws iam create-policy --policy-name eks-a-policy-$TIMESTAMP --policy-document file:///tmp/eks-a-policy.json --endpoint http://$DEVICE_IP:6078 | jq -r '.Policy.Arn')

  # Attach EKS-A policy to EKS-A user
  aws iam attach-user-policy --policy-arn $POLICY_ARN --user-name eks-a-user-$TIMESTAMP --endpoint http://$DEVICE_IP:6078

  # Create access key for the EKS-A user
  CREDENTIALS=$(aws iam create-access-key --user-name eks-a-user-$TIMESTAMP --endpoint http://$DEVICE_IP:6078)
  EKS_A_ACCESS_KEY_ID=$(jq -r '.AccessKey.AccessKeyId' <<< "$CREDENTIALS")
  EKS_A_SECRET_ACCESS_KEY=$(jq -r '.AccessKey.SecretAccessKey' <<< "$CREDENTIALS")

  # Save the scope down credentials
  echo -e "[$DEVICE_IP]\naws_access_key_id = $EKS_A_ACCESS_KEY_ID\naws_secret_access_key = $EKS_A_SECRET_ACCESS_KEY\nregion = snow\n\n" >> $CREDS_FILE
  echo "Finish setting up snowball_creds file for the device with the IP Address $DEVICE_IP"

  # Save certificates
  CERTIFICATE_ARN=$($SNOWBALLEDGE_CLIENT_PATH list-certificates --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | jq -r .Certificates[0].CertificateArn)
  $SNOWBALLEDGE_CLIENT_PATH get-certificate --certificate-arn $CERTIFICATE_ARN --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE >> $CERTS_FILE

  echo "Finish setting up snowball_certs file for the device with the IP Address $DEVICE_IP "
done

# Clear environment variable
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION
echo "Scoped down policies and users have been configured for EKS Anywhere on all devices, credentials and CA bundles have been stored at /tmp/snowball_creds and /tmp/snowball_certs"
