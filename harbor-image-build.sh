#!/bin/bash

########################################################################################################################
# Script to download harbor artifacts on an ec2 instance
#
# Prerequisite:
# Start an ec2 instance with either ubuntu or al2 os, create and attach a vni,
# then ssh into the instance to run this script
#
# Run the script to download artifacts
# `./harbor-image-build.sh`
########################################################################################################################

sleep 30

### Install Docker
sudo yum update -y
sudo yum -y install docker

### Allow user to run docker without sudo
sudo usermod -a -G docker $USER

### Restart Docker and enable on boot
sudo systemctl enable docker
sudo systemctl daemon-reload
sudo systemctl restart docker

### Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

### Download Harbor, can change the version to the latest harbor version from https://github.com/goharbor/harbor/releases
# Check version
echo "The version is $version"

wget --no-verbose https://github.com/goharbor/harbor/releases/download/$version/harbor-offline-installer-$version.tgz
tar xzvf harbor-offline-installer-$version.tgz
rm harbor-offline-installer-$version.tgz

#Pre-Pull Harbor Images
sudo docker pull goharbor/harbor-exporter:$version
sudo docker pull goharbor/chartmuseum-photon:$version
sudo docker pull goharbor/redis-photon:$version
sudo docker pull goharbor/trivy-adapter-photon:$version
sudo docker pull goharbor/notary-server-photon:$version
sudo docker pull goharbor/notary-signer-photon:$version
sudo docker pull goharbor/harbor-registryctl:$version
sudo docker pull goharbor/registry-photon:$version
sudo docker pull goharbor/nginx-photon:$version
sudo docker pull goharbor/harbor-log:$version
sudo docker pull goharbor/harbor-jobservice:$version
sudo docker pull goharbor/harbor-core:$version
sudo docker pull goharbor/harbor-portal:$version
sudo docker pull goharbor/harbor-db:$version
sudo docker pull goharbor/prepare:$version
