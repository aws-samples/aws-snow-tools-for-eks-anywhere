
# EKS Anywhere on Snow setup tools
There are 4 scripts in this folder which can help to handle manual work in the process of using EKS Anywhere on Snowball devices. 

`unlock-devices.sh`, `create-creds-and-certs-files.sh` and `create-eks-a-admin-instance.sh` are 3 separate script tools. You can use them separately or run `setup.sh` which combine the former 3 scripts.

## Unlock devices
`unlock-devices.sh` helps to unlock Snowball devices
### Prerequisite
1. Install jq `curl -qL -o jq https://stedolan.github.io/jq/download/linux64/jq && chmod +x ./jq`
2. Add jq to your PATH
3. Install snowballEdge cli https://docs.aws.amazon.com/snowball/latest/developer-guide/download-the-client.html
4. Install aws cli
5. Add absolute SnowballEdge client path and devices' information in `config.json` file
### How to use this script
```
$ chmod +x unlock-devices.sh
$ ./unlock-devices.sh 
```

## Create credentials and certificates file
`create-creds-and-certs-files.sh` helps to get credentails and certificates of Snowball devices and save them in corresponding path:
* credentails: `/tmp/snowball_creds`
* certifictaes: `/tmp/snowball_certs`
### Prerequisite
1. Install jq `curl -qL -o jq https://stedolan.github.io/jq/download/linux64/jq && chmod +x ./jq`
2. Add jq to your PATH
3. Install snowballEdge cli https://docs.aws.amazon.com/snowball/latest/developer-guide/download-the-client.html
4. Install aws cli
5. Add absolute SnowballEdge client path and devices' information in `config.json` file
### Hot to use this script
```
$ chmod +x create-creds-and-certs-files.sh
$ ./create-creds-and-certs-files.sh
```

## Create EKS Anywhere admin instance
`create-eks-a-admin-instance.sh` helps to start an EKS Anywhere admin instance on the first Snowball device in `config.json` and send credential and certificate files onto EKS Anywhere admin instance.
### Prerequisite
1. Install jq `curl -qL -o jq https://stedolan.github.io/jq/download/linux64/jq && chmod +x ./jq`
2. Add jq to your PATH
3. Install snowballEdge cli https://docs.aws.amazon.com/snowball/latest/developer-guide/download-the-client.html
4. Install aws cli
5. Add absolute SnowballEdge client path and devices' information in `config.json` file
6. (Optioanl) If you need to specify an EKS Anywhere admin AMI id in `config.json`. You can find the AMI id by referring to [pending pub lic snow doc link]. Otherwise, it will use the latest EKS Anywhere admin AMI on your first Snowball device in `config.json`.
### (Optional)Save credentials and certificates mauanlly
If you don't run `create-creds-and-certs-files.sh` before. You need to prepare credentail and certificate files by yourself.
1.  Get credentials by referring to [pending public snow doc], save it under `/tmp` and name it `snowball_creds`. 
2. Get certificates by referring to [pending public snow doc], save it under `/tmp` and name it `snowball_certs`.
### How to use this script
```
$ chmod +x create-eks-a-admin-instance-test.sh
$ ./create-eks-a-admin-instance-test.sh
``` 
Look into the printed log carefully, use the command in the last line to ssh into your EKS Anywhere admin instance. There are two files in the home path: `snowball_creds` and `snowball_certs`.

If you see "Failed to add the host to the list of known hosts (/home/awsie/.ssh/known_hosts)." in the printed log, it's not an error.

## Unlock devices and setup envorinment for EKS Anywhere
`setup.sh` helps to unlock devices, get credentials and certificates, create eks anywhere admin instance and scp credential and certidicate file onto it.
### Prerequisite
1. Install jq `curl -qL -o jq https://stedolan.github.io/jq/download/linux64/jq && chmod +x ./jq`
2. Add jq to your PATH
3. Install snowballEdge cli https://docs.aws.amazon.com/snowball/latest/developer-guide/download-the-client.html
4. Install aws cli
5. Add absolute SnowballEdge client path and devices' information in `config.json` file
6. (Optioanl) If you need to specify an EKS Anywhere admin AMI id in `config.json`. You can find the AMI id by referring to [pending pub lic snow doc link]. Otherwise, it will use the latest EKS Anywhere admin AMI on your first Snowball device in `config.json`.
### Hot to use this script
```
$ chmod +x setup-tooling.sh
$ ./setup-tooling.sh
```
Look into the printed log carefully, use the command in the last line to ssh into your EKS Anywhere admin instance. There are two files in the home path: `snowball_creds` and `snowball_certs`.

If you see "Failed to add the host to the list of known hosts (/home/awsie/.ssh/known_hosts)." in the printed log, it's not an error.