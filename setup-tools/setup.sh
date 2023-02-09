#!/bin/bash
########################################################################################################################
# Script for unlocking Snow devices, configuring EKS Anywhere credentials and certificates, and creating an EKS Anywhere admin instance
#
# Prerequisites:
# 1. Install jq `curl -qL -o jq https://stedolan.github.io/jq/download/linux64/jq && chmod +x ./jq`
# 2. Add jq to your PATH
# 3. Install snowballEdge cli https://docs.aws.amazon.com/snowball/latest/developer-guide/download-the-client.html
# 4. Update your absolute SnowballEdge client path in config.json
# 5. Install aws cli
########################################################################################################################
set -euo pipefail

sh unlock-devices.sh
sh create-creds-and-certs-files.sh
sh create-eks-a-admin-instance.sh
