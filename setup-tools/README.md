
# EKS Anywhere on Snow setup tools
There are 4 scripts in this folder which can help to setup a EKS Anywhere on Snow working environment on Snow devices.

`unlock-devices.sh`, `create-creds-and-certs-files.sh` and `create-eks-a-admin-instance.sh` are 3 separate script tools. You can use them separately or run `setup.sh` which combine the former 3 scripts.

## Prerequisites
1. Install jq
```
curl -qL -o jq https://stedolan.github.io/jq/download/linux64/jq && chmod +x ./jq
```
2. Add jq to your PATH
```
export PATH=$PATH:<path to jq>
```
3. Install snowballEdge cli at [Downloading and Installing the Snowball Edge Client](https://docs.aws.amazon.com/snowball/latest/developer-guide/using-client.html#download-client)
4. Install aws cli at [Installing or updating the latest version of the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
5. Add absolute SnowballEdge client path in `config.json` file
6. Add unlock code and manifest path of each Snowball devices you want to use in `config.json` file. You can find unlock code and manifest at [Unlocking the Snowball Edge](https://docs.aws.amazon.com/snowball/latest/developer-guide/unlockdevice.html)
```
# config.json example
{
  "SnowballEdgeClientPath": "/home/xxx/snowball-client-linux-x.x.x-xxx/bin/snowballEdge",  # the absolute path to snowballEdge client
  "EKSAAdminImageId": "", # optional, the EKS Anywhere admin image id if you want to specify it
  "Devices": [
    {
      "IPAddress": "192.168.1.123", # ip adress of Snowball device
      "ManifestPath": "/tmp/manifest-final-123.bin", # absolute path to job manifest file
      "UnlockCode": "snowball" # unlock code
    },
    {
      "IPAddress": "192.168.1.124",
      "ManifestPath": "/tmp/manifest-final-124.bin",
      "UnlockCode": "snowball"
    }
  ],
  "ClusterName": "", # optional, if provided, the tool will generate a cluster config using this cluster name on eks-a admin instance
  "ControlPlaneEndpoint": "", # optional, ip address of control plane endpoint, if provided, this static ip will be added in the cluster config
  "PodCIDR": "", # optional, Pod CIDR of the cluster, default value is "192.168.0.0/16" if left empty
  "ServiceCIDR": "", # optional, Service CIDR of the cluster, default value is "10.96.0.0/12" if left empty
  "KubernetesVersion": "", # optional, Kubernetes version of the cluster, default value is "1.24" if left empty
  "InstanceType": "", # optional, instance type of both control plane and worker nodes, default value is "sbe-c.large" if left empty
  "PhysicalNetworkConnector": "" # optional, physical network connector type for cluster network, default value is "SFP_PLUS" if left empty
}
```

## Unlock devices and setup environment for EKS Anywhere
`setup.sh` helps to unlock devices, get credentials and certificates, create eks anywhere admin instance and scp credential and certidicate file onto it. This script helps to setup a working eksa environment by running the following scripts in order
* [unlock device](#unlock-devices)
* [configure credentials and certificates](#create-credentials-and-certificates-file)
* [create eksa instance](#create-eks-anywhere-admin-instance)

### How to use this script
* check [prerequisites](#prerequisites)
* (Optional) If you need to specify an EKS Anywhere admin AMI id in `config.json`. You can find the AMI id by referring to [pending pub lic snow doc link]. Otherwise, it will use the latest EKS Anywhere admin AMI on your first Snowball device in `config.json`.
```
sh setup.sh
```
Look into the printed log carefully, use the command in the last line to ssh into your EKS Anywhere admin instance. Remember to save the instance id, private key and public ip of the EKS Anywhere admin instance for future usages.

Note: If you see "Failed to add the host to the list of known hosts ($HOME/.ssh/known_hosts)." in the printed log, it's not an error.

## Unlock devices
`unlock-devices.sh` helps to unlock Snowball devices
### How to use this script
* check [prerequisites](#prerequisites)
```
sh unlock-devices.sh
```

## Create credentials and certificates file
`create-creds-and-certs-files.sh` helps to configure credentials and certificates of Snowball devices and save them in corresponding paths:
* credentials: `/tmp/snowball_creds`
* certificates: `/tmp/snowball_certs`

### Hot to use this script
check prerequisites at [here](#prerequisites)
```
sh create-creds-and-certs-files.sh
```

## Create EKS Anywhere admin instance
`create-eks-a-admin-instance.sh` helps to create an EKS Anywhere admin instance on the first Snowball device specified in `config.json` and send credential and certificate files onto the EKS Anywhere admin instance.

### How to use this script
* check [prerequisites](#prerequisites)
* (Optional) If you need to specify an EKS Anywhere admin AMI id in `config.json`. Otherwise, it will use the latest EKS Anywhere admin AMI on your first Snowball device in `config.json`.
* (Optional) If cluster name is provided in the config.json file, this script will create a cluster config file with the provided cluster name on the eks-a admin instance. A script with commands for creating the cluster will also be created. Please manually modify the cluster config file generated by this script if you need customize other fields. Please refer to [EKS Anywhere public doc](https://anywhere.eks.amazonaws.com/docs/reference/clusterspec/snow/) for details of all configurable fields in the cluster config file.
* (Optional) Save credentials and certificates manually
    
    If you don't run `create-creds-and-certs-files.sh` before. You need to prepare credentials and certificates files by yourself.
    1. Get credentials by following [pending public snow doc], and save it to `/tmp/snowball_creds`. 
    2. Get certificates by following [pending public snow doc], and save it to `/tmp/snowball_certs`.


```
sh create-eks-a-admin-instance.sh
``` 
Look into the printed log carefully, use the command provided in the last line of the log to ssh into your EKS Anywhere admin instance. Remember to save the instance id, private key and public ip of the EKS Anywhere admin instance for future usages.
