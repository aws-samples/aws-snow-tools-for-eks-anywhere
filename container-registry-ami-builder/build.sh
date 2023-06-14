#!/bin/bash
set -euo pipefail

# install jq and docker
sudo yum install -y jq docker

# Add group membership for the default ec2-user so you can run all docker commands without using the sudo command
sudo usermod -a -G docker ec2-user
sudo systemctl enable docker.service
sudo systemctl start docker.service

# Install packer
echo "Install Packer"
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install packer

# Collect information from ami.json
CONFIG_FILE="ami.json"
REGION=$(jq -r '.region' $CONFIG_FILE)
VOLUME=$(jq -r '.volume_size_in_gb' $CONFIG_FILE)
INSTANCE_TYPE=$(jq -r '.instance_type' $CONFIG_FILE)
SUBNET_ID=$(jq -r '.subnet_id' $CONFIG_FILE)
HARBOR_VERSION=$(jq -r '.harbor_version' $CONFIG_FILE)
EXPORT_AMI=$(jq -r '.export_ami' $CONFIG_FILE)

AMI_ID=""

if [ "$EXPORT_AMI" = true ]
then
  AMI_ID=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query 'Parameters[*].[Value]'  --output text  --region $REGION)
  echo "Using latest AL2 AMI $AMI_ID to create local registry AMI"
  S3BUCKET=$(jq -r '.s3_bucket' $CONFIG_FILE)
  EXPORT_AMI=true
else
  AMI_ID=$(aws ec2 describe-images --filters "Name=name, Values=amzn2-ami-snow-family-hvm*" --query 'sort_by(Images, &CreationDate)[-1].ImageId'  --output text --region $REGION)
  echo "Using latest Snow AL2 AMI $AMI_ID to create local registry AMI"
fi

#Check if images.txt file exists in the repo
IMAGES_FILE="images.txt"
if [[ ! -f $IMAGES_FILE ]]
then
  touch $IMAGES_FILE
fi
echo "Preloading images on images.txt"
sh ./preload-images.sh
/usr/bin/packer init harbor.pkr.hcl
AMI_NAME=snow-harbor-image-$(date '+%s')
/usr/bin/packer build -color=true -var "region=$REGION" -var "ami_name=$AMI_NAME" -var "source_ami=$AMI_ID" -var "instance_type=$INSTANCE_TYPE" -var "subnet_id=$SUBNET_ID" -var "harbor_version=$HARBOR_VERSION" -var "volume_size=$VOLUME" -machine-readable harbor.pkr.hcl | tee build-$AMI_NAME.log
IMAGE_ID=$(aws ec2 describe-images --owners self --filters "Name=name,Values=$AMI_NAME" --region $REGION | jq -r '.Images[0].ImageId')

if [ "$EXPORT_AMI" = true ]
then
    echo Exporting AMI to S3 bucket $S3BUCKET
    echo "Waiting for AMI $IMAGE_ID to become ready"

    EXPORT_TASK_JSON=$(aws ec2 export-image --disk-image-format raw --s3-export-location S3Bucket=$S3BUCKET,S3Prefix=$IMAGE_ID/ --image-id $IMAGE_ID --region $REGION)
    EXPORT_TASK_ID=$(echo $EXPORT_TASK_JSON | jq -r '.ExportImageTaskId')
    echo "EXPORT_TASK_ID=$EXPORT_TASK_ID"

    function wait_for_complete {
      local TASK_ID=$1
      echo -n "Waiting for export task $TASK_ID to complete"
      while true; do
          sleep 30
          DESCRIBE_JSON=$(aws ec2 describe-export-image-tasks --export-image-task-ids $TASK_ID --region $REGION)
          EXPORT_STATUS=$(echo $DESCRIBE_JSON | jq -r '.ExportImageTasks[0].Status')
          echo "AMI exporting in process"
          if [ "$EXPORT_STATUS" = "completed" ]; then
              echo "AMI successfully exported to s3 bucket $S3BUCKET"
              break
          fi
      done
    }

    wait_for_complete "$EXPORT_TASK_ID"
fi

echo "Habor AMI has been created"
