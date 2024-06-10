#!/bin/bash
set -euo pipefail

CONFIG_FILE="config.json"
SNOWBALLEDGE_CLIENT_PATH=$(jq -r '.SnowballEdgeClientPath' $CONFIG_FILE)

ValidateSshKey() {
  KEY_NAME=$1
  LEN=$(jq '.Devices | length' $CONFIG_FILE)
  KEY_NAME_EXIST=false
  KEY_NAME_EXIST_ON_ALL_DEVICE=true
  for i in $(seq 0 $[LEN - 1])
  do
    DEVICE_IP=$(jq -r '.Devices['$i'].IPAddress' $CONFIG_FILE)
    UNLOCK_CODE=$(jq -r '.Devices['$i'].UnlockCode' $CONFIG_FILE)
    MANIFEST_PATH=$(jq -r '.Devices['$i'].ManifestPath' $CONFIG_FILE)

    KEY_PAIR=$(AWS_ACCESS_KEY_ID=$($SNOWBALLEDGE_CLIENT_PATH list-access-keys --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | jq -r '.AccessKeyIds[0]') \
      AWS_SECRET_ACCESS_KEY=$($SNOWBALLEDGE_CLIENT_PATH get-secret-access-key --access-key-id $AWS_ACCESS_KEY_ID --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | grep 'aws_secret_access_key' | awk '{print $3}') \
      AWS_DEFAULT_REGION=snow \
      aws ec2 describe-key-pairs --key-name $KEY_NAME --endpoint http://$DEVICE_IP:8008 | jq -r '.KeyPairs[]')

    if [[ ! -z $KEY_PAIR ]]; then
      KEY_NAME_EXIST=true
    else
      KEY_NAME_EXIST_ON_ALL_DEVICE=false
    fi
  done
  if [ "$KEY_NAME_EXIST" = true ] && [ "$KEY_NAME_EXIST_ON_ALL_DEVICE" = false ]; then
    echo "ssh key $KEY_NAME does not exist on all devices, existing"
    exit 1
  fi
  if [ "$KEY_NAME_EXIST" = true ] && [ "$KEY_NAME_EXIST_ON_ALL_DEVICE" = true ]; then
    CREATE_NEW_KEY=false
  fi
}

CreateAndImportSshKey() {
  KEY_NAME=$1
  CREATE_NEW_KEY=true
  ValidateSshKey $KEY_NAME
  if [ "$CREATE_NEW_KEY" = true ]; then
    echo "ssh key $KEY_NAME do not exist, generating and importing a new key"
    ssh-keygen -q -t rsa -N '' -f /tmp/$KEY_NAME <<<y >/dev/null 2>&1
    LEN=$(jq '.Devices | length' $CONFIG_FILE)
    for i in $(seq 0 $[LEN - 1])
    do
      DEVICE_IP=$(jq -r '.Devices['$i'].IPAddress' $CONFIG_FILE)
      UNLOCK_CODE=$(jq -r '.Devices['$i'].UnlockCode' $CONFIG_FILE)
      MANIFEST_PATH=$(jq -r '.Devices['$i'].ManifestPath' $CONFIG_FILE)

      AWS_ACCESS_KEY_ID=$($SNOWBALLEDGE_CLIENT_PATH list-access-keys --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | jq -r '.AccessKeyIds[0]') \
      AWS_SECRET_ACCESS_KEY=$($SNOWBALLEDGE_CLIENT_PATH get-secret-access-key --access-key-id $AWS_ACCESS_KEY_ID --manifest-file $MANIFEST_PATH --endpoint https://$DEVICE_IP --unlock-code $UNLOCK_CODE | grep 'aws_secret_access_key' | awk '{print $3}') \
      AWS_DEFAULT_REGION=snow \
      aws ec2 import-key-pair --key-name $KEY_NAME --public-key-material fileb:///tmp/$KEY_NAME.pub --endpoint http://$DEVICE_IP:8008

    done
    echo "generated node ssh key with name $KEY_NAME, and imported to all devices"
    echo "private key saved at /tmp/$KEY_NAME"
  else
    echo "ssh key $KEY_NAME exists on all devices"
  fi
}

KEY_PATH=$1
INSTANCE_IP=$2

CLUSTER_NAME=$(jq -r '.ClusterName' $CONFIG_FILE)
DEVICE_LIST=""

LEN=$(jq '.Devices | length'  $CONFIG_FILE)
for i in $(seq 0 $[LEN - 1])
do
    IP=$(jq -r '.Devices['$i'].IPAddress' $CONFIG_FILE)
    DEVICE_LIST+="  - $IP\n"
done

# generate cluster config
cat <<EOF> /tmp/generate-cluster-config.sh
#!/bin/bash
set -euo pipefail

EOF

printf "eksctl anywhere generate clusterconfig $CLUSTER_NAME -p snow > ~/eksa-cluster-$CLUSTER_NAME.yaml\n" >> /tmp/generate-cluster-config.sh

# add control plane endpoint if provided
CONTROL_PLANE_ENDPOINT=$(jq -r '.ControlPlaneEndpoint' $CONFIG_FILE)
if [[ ! -z $CONTROL_PLANE_ENDPOINT ]]
then
  printf "sed -i 's/      host: \"\"/      host: \"$CONTROL_PLANE_ENDPOINT\"/' ~/eksa-cluster-$CLUSTER_NAME.yaml\n" >> /tmp/generate-cluster-config.sh
fi

# modify kubernetes version if provided
KUBERNETES_VERSION=$(jq -r '.KubernetesVersion' $CONFIG_FILE)
if [[ ! -z $KUBERNETES_VERSION ]]
then
  printf "sed -i '/kubernetesVersion:/s/.*/  kubernetesVersion: $KUBERNETES_VERSION/' ~/eksa-cluster-$CLUSTER_NAME.yaml\n" >> /tmp/generate-cluster-config.sh
fi

# modify pod cidr if provided
POD_CIDR=$(jq -r '.PodCIDR' $CONFIG_FILE)
if [[ ! -z $POD_CIDR ]]
then
  POD_CIDR=$(echo $POD_CIDR | sed 's/\//\\\//')
  printf "sed -i 's/      - 192.168.0.0\/16/      - $POD_CIDR/' ~/eksa-cluster-$CLUSTER_NAME.yaml\n" >> /tmp/generate-cluster-config.sh
fi

# modify service cidr if provided
SERVICE_CIDR=$(jq -r '.ServiceCIDR' $CONFIG_FILE)
if [[ ! -z $SERVICE_CIDR ]]
then
  SERVICE_CIDR=$(echo $SERVICE_CIDR | sed 's/\//\\\//')
  printf "sed -i 's/      - 10.96.0.0\/12/      - $SERVICE_CIDR/' ~/eksa-cluster-$CLUSTER_NAME.yaml\n" >> /tmp/generate-cluster-config.sh
fi

# modify instance type if provided
INSTANCE_TYPE=$(jq -r '.InstanceType' $CONFIG_FILE)
if [[ ! -z $INSTANCE_TYPE ]]
then
  printf "sed -i '/instanceType:/s/.*/  instanceType: $INSTANCE_TYPE/' ~/eksa-cluster-$CLUSTER_NAME.yaml\n" >> /tmp/generate-cluster-config.sh
fi

# modify physical network connector type if provided
PHYSICAL_NETWORK_CONNECTOR=$(jq -r '.PhysicalNetworkConnector' $CONFIG_FILE)
if [[ ! -z $PHYSICAL_NETWORK_CONNECTOR ]]
then
  printf "sed -i '/physicalNetworkConnector:/s/.*/  physicalNetworkConnector: $PHYSICAL_NETWORK_CONNECTOR/' ~/eksa-cluster-$CLUSTER_NAME.yaml\n" >> /tmp/generate-cluster-config.sh
fi

# validate and add node ssh key name
SSH_KEY_NAME=$(jq -r '.SshKeyName' $CONFIG_FILE)
if [[ -z $SSH_KEY_NAME ]]
then
  SSH_KEY_NAME="$CLUSTER_NAME-key-$(date '+%s')"
fi
CreateAndImportSshKey $SSH_KEY_NAME
printf "sed -i '/instanceType:/a\ \ sshKeyName: $SSH_KEY_NAME' ~/eksa-cluster-$CLUSTER_NAME.yaml\n" >> /tmp/generate-cluster-config.sh

# TODO add registry mirror if provided

# add device ips to machine template device list
cat <<EOF>> /tmp/generate-cluster-config.sh
sed -i 's/  - \"\"/$DEVICE_LIST/' ~/eksa-cluster-$CLUSTER_NAME.yaml
EOF

# remove empty lines
printf "sed -i '/^$/d' ~/eksa-cluster-$CLUSTER_NAME.yaml" >> /tmp/generate-cluster-config.sh


# TODO add image import command if registry mirror information is provided
# generate and scp cluster creation script to eksa admin instance
cat <<EOF> /tmp/create-cluster-$CLUSTER_NAME.sh
#!/bin/bash
set -euxo pipefail

export EKSA_AWS_CREDENTIALS_FILE=/home/ec2-user/snowball_creds
export EKSA_AWS_CA_BUNDLES_FILE=/home/ec2-user/snowball_certs
eksctl anywhere create cluster -f /home/ec2-user/eksa-cluster-$CLUSTER_NAME.yaml -v4
EOF

scp -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY_PATH  /tmp/generate-cluster-config.sh /tmp/create-cluster-$CLUSTER_NAME.sh ec2-user@$INSTANCE_IP:~
ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY_PATH ec2-user@$INSTANCE_IP "sh ~/generate-cluster-config.sh > /tmp/generate-cluster-config.log && rm -rf ~/generate-cluster-config.sh"
