#!/bin/bash
set -euo pipefail

KEY_PATH=$1
INSTANCE_IP=$2

CONFIG_FILE="config.json"

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

echo -e "eksctl anywhere generate clusterconfig $CLUSTER_NAME -p snow > ~/eksa-cluster-$CLUSTER_NAME.yaml" >> /tmp/generate-cluster-config.sh

# add control plane endpoint if provided
CONTROL_PLANE_ENDPOINT=$(jq -r '.ControlPlaneEndpoint' $CONFIG_FILE)
if [[ ! -z $CONTROL_PLANE_ENDPOINT ]]
then
  echo -e "sed -i 's/      host: \"\"/      host: \"$CONTROL_PLANE_ENDPOINT\"/' ~/eksa-cluster-$CLUSTER_NAME.yaml" >> /tmp/generate-cluster-config.sh
fi

# modify kubernetes version if provided
KUBERNETES_VERSION=$(jq -r '.KubernetesVersion' $CONFIG_FILE)
if [[ ! -z $KUBERNETES_VERSION ]]
then
  echo -e "sed -i '/kubernetesVersion:/s/.*/  kubernetesVersion: $KUBERNETES_VERSION/' ~/eksa-cluster-$CLUSTER_NAME.yaml" >> /tmp/generate-cluster-config.sh
fi

# modify pod cidr if provided
POD_CIDR=$(jq -r '.PodCIDR' $CONFIG_FILE)
if [[ ! -z $POD_CIDR ]]
then
  POD_CIDR=$(echo $POD_CIDR | sed 's/\//\\\//')
  echo -e "sed -i 's/      - 192.168.0.0\/16/      - $POD_CIDR/' ~/eksa-cluster-$CLUSTER_NAME.yaml" >> /tmp/generate-cluster-config.sh
fi

# modify service cidr if provided
SERVICE_CIDR=$(jq -r '.ServiceCIDR' $CONFIG_FILE)
if [[ ! -z $SERVICE_CIDR ]]
then
  SERVICE_CIDR=$(echo $SERVICE_CIDR | sed 's/\//\\\//')
  echo -e "sed -i 's/      - 10.96.0.0/12/      - $SERVICE_CIDR/' ~/eksa-cluster-$CLUSTER_NAME.yaml" >> /tmp/generate-cluster-config.sh
fi

# modify instance type if provided
INSTANCE_TYPE=$(jq -r '.InstanceType' $CONFIG_FILE)
if [[ ! -z $INSTANCE_TYPE ]]
then
  echo -e "sed -i '/instanceType:/s/.*/  instanceType: $INSTANCE_TYPE/' ~/eksa-cluster-$CLUSTER_NAME.yaml" >> /tmp/generate-cluster-config.sh
fi

# modify physical network connector type if provided
PHYSICAL_NETWORK_CONNECTOR=$(jq -r '.PhysicalNetworkConnector' $CONFIG_FILE)
if [[ ! -z $PHYSICAL_NETWORK_CONNECTOR ]]
then
  echo -e "sed -i '/physicalNetworkConnector:/s/.*/  physicalNetworkConnector: $PHYSICAL_NETWORK_CONNECTOR/' ~/eksa-cluster-$CLUSTER_NAME.yaml" >> /tmp/generate-cluster-config.sh
fi

# TODO add registry mirror if provided

# add device ips to machine template device list
echo "sed -i 's/  - \"\"/$DEVICE_LIST/' ~/eksa-cluster-$CLUSTER_NAME.yaml" >> /tmp/generate-cluster-config.sh

# remove empty lines
echo -e "sed -i '/^$/d' ~/eksa-cluster-$CLUSTER_NAME.yaml" >> /tmp/generate-cluster-config.sh


# TODO add image import command if registry mirror information is provided
# generate and scp cluster creation script to eksa admin instance
cat <<EOF> /tmp/create-cluster-$CLUSTER_NAME.sh
#!/bin/bash
set -euxo pipefail

export EKSA_AWS_CREDENTIALS_FILE=/home/ec2-user/snowball_creds
export EKSA_AWS_CA_BUNDLES_FILE=/home/ec2-user/snowball_certs
eksctl anywhere create cluster -f /home/ec2-user/eksa-cluster-$CLUSTER_NAME.yaml -v4
EOF

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY_PATH  /tmp/generate-cluster-config.sh /tmp/create-cluster-$CLUSTER_NAME.sh ec2-user@$INSTANCE_IP:~
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY_PATH ec2-user@$INSTANCE_IP "sh ~/generate-cluster-config.sh > /tmp/generate-cluster-config.log && rm -rf ~/generate-cluster-config.sh"
