## Description
This repo contains instructions and scripts that can be used to build a local [Harbor](https://goharbor.io/) AMI. This AMI can be used for setting up an EC2 instance on Snowball devices, which can serve as the local registry for EKS Anywhere for Snow in air-gapped use cases.
## Build Harbor AMI
### Prepare an AL2 instance
#### Setup IAM role with proper policy
* Create an IAM policy named `harbor-image-builder.permissions` by following this [guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_create-console.html). This will be used to create the AL2 instance, and allows it to access the necessary AWS resources to create the Harbor AMI. On the *Create policy* page, paste the following in the *JSON* tab:
```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AttachVolume",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CopyImage",
        "ec2:CopySnapshot",
        "ec2:CreateImage",
        "ec2:CreateKeypair",
        "ec2:CreateSecurityGroup",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteKeyPair",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteSnapshot",
        "ec2:DeleteVolume",
        "ec2:DeregisterImage",
        "ec2:DescribeImageAttribute",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeRegions",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSnapshots",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DetachVolume",
        "ec2:GetPasswordData",
        "ec2:ModifyImageAttribute",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifySnapshotAttribute",
        "ec2:RegisterImage",
        "ec2:RunInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
        "ssm:GetParameters"
      ],
      "Resource": "*"
    }
  ]
}
```
* Create an IAM Role by following this public [doc](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html#working-with-iam-roles), attaching the `harbor-image-builder.permissions` policy you created on the previous step. Name this role as `harbor-image-builder.role`
#### Start an AL2 instance with created IAM role
* Create an AL2 EC2 instance named `harbor-ami-builder.instance` by following this [guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html).
  - Select an existing key pair or select Create a key pair with the default setting, which will create a key and download the private key file to your device automatically. Save this private key so that you can SSH into the instance.
  - Under the Advanced details section, choose `harbor-image-builder.role` for the IAM instance profile. Keep the default selections for the other configuration settings.
* Launch the instance and save the public IPv4 address of the instance for connection

### Connect to Amazon Linux 2 Instance
* Use the private key you create above ssh to the instance([ref](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AccessingInstancesLinux.html))
###### Note: `<path-to-key>` is the path to your ssh key pair file of your AL2 instance
```
ssh -i <path-to-key>/<key-file-name> ec2-user@<public-IPv4-address>
```
* Download the [aws-snow-tools-for-eks-anywhere](https://github.com/aws-samples/aws-snow-tools-for-eks-anywhere) repo onto your AL2 instance
```
sudo yum install -y git
git clone https://github.com/aws-samples/aws-snow-tools-for-eks-anywhere.git
```
* Navigate to `aws-snow-tools-for-eks-anywhere/container-registry-ami-builder`
```
cd aws-snow-tools-for-eks-anywhere/container-registry-ami-builder
```
* Change the permission of all scripts file by running the following command
```
chmod +x *.sh
```
* Modify the AMI configuration file `ami.json` that contains various AMI parameters
```
{
  "instance_type":<Amazon EC2 instance you choosed to build the Harbor ami: https://aws.amazon.com/ec2/instance-types/> 
  "subnet_id": <Add your subnet id in the field if you have a target one. If not, leave the field blank and the repo will pick one to finish the AMI build>
  "region":<The AWS region in which to launch the EC2 instance to create the AMI>   
  "volume_size_in_gb": <The size of the root volume size in GB. If importing eksa container images to the Harbor instance, the disk space is used as 9G, which is 30% of the total space. Customers have 22G space for using.  Please change the volume size to the target value if more volume size is needed> 
  "export_ami": <The field to define if you want to export the AMI to S3 bucket. Modify the field to true if you want to export AMI to a target S3 bucket>  
  "s3_bucket":<The target S3 bucket for exporting AMI. Modifying this field if set export_ami to true. Please leave this field empty if no need to export AMI to S3>
  "harbor_version":<The latest Harbor version from https://github.com/goharbor/harbor/releases>
 }
```
### Pre-load Container Images
There are two ways to pre-load your customer container images. You can use either of them or use both in a single build. The images will be pushed to your Harbor registry after the Harbor registry is started on a Snowball device.
#### Script assisted
This only works if your AMI build EC2 instance has access to the specific registry where your images are hosted. Put each container image's NAME[:TAG|@DIGEST] in `images.txt` file. The AMI build process will iterate over `images.txt`, pull and save the images as tar files to the `~/aws-snow-tools-for-eks-anywhere/container-registry-ami-builder/images` directory. 

1. Open `images.txt` file at `~/aws-snow-tools-for-eks-anywhere/container-registry-ami-builder/images.txt`
2. Delete the examples `hello-world` and `alpine` in the file
3. Paste your container images’ NAME[:TAG|@DIGEST] on a new line in `images.txt`, `ubuntu:22.04` for example

#### Manual Load
You can pull all images in your local environment and save them as tar files. Then copy all tar files to the `~/aws-snow-tools-for-eks-anywhere/container-registry-ami-builder/images` directory on the AL2 instance. The AMI build process will iterate over the `images` folder and upload the tar files to the target AMI.

1. `docker pull` all the images and run `docker save IMAGE_NAME > IMAGE_NAME.tar` to save them as tar files
2. Copy all tar files to your AL2 instance under the `~/aws-snow-tools-for-eks-anywhere/container-registry-ami-builder/images` folder before running `build.sh` script during the AMI build process.
```
scp -i <path-to-key>/<key-file-name> <path-to-your-tar-file/your-tar-file> ec2-user@<public-IPv4-address>:~/aws-snow-tools-for-eks-anywhere/container-registry-ami-builder/images/
```

### Export AMI to S3 Bucket (Optional)
AMI export is only needed when you already have Snowball devices and need to side load Harbor AMI onto it.  In this section, you will be guided to set up IAM role with proper policy and initiate a Harbor AMI build to export to S3 bucket.
* Set the "export_ami" field as true in `ami.json` file
* Enter the target S3 bucket for exporting AMI in `ami.json` file
* Setup permissions for VM Import/Export following the [instruction](https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html)

Now you set up all the IAM permissions for exporting AMI. Follow the steps in [Initiate a Harbor AMI Build](#initiate-a-harbor-ami-build) and you’ll see exported Harbor AMI on S3 bucket for downloading.
### Initiate a Harbor AMI Build
Follow the following steps to initiate a Snow Harbor AMI build
1. [Subscribe to the Snow AL2 AMI](https://aws.amazon.com/marketplace/pp/prodview-sf35wbdb37e6q) if this is your first time following this guide
2. (Optional) Follow [Export AMI to S3 Bucket](#export-ami-to-s3-bucket-optional) if you want to export ami to S3 bucket
3. Run `build.sh` to start Harbor AMI build process.
```
./build.sh
```
Once the script is finished, you successfully build a Harbor AMI. You should see a new AMI whose name has the prefix `snow-harbor-image` in your AWS console. This is the Harbor AMI you can add when you order Snowball devices in AWS console.
## Configure Harbor on a Snowball Edge device
Prerequisites:

1. Snowball device is received and unlocked
2. Harbor AMI pre-installed on device
3. Refer to this [guilde](https://docs.aws.amazon.com/snowball/latest/developer-guide/using-ec2-cli-specify-region.html) to set up AWS profile and save the profile name for future use

### Import the exported Harbor AMI from S3 bucket(optional)
Refer to this [guide](https://docs.aws.amazon.com/snowball/latest/developer-guide/ec2-ami-import-cli.html) for importing your Harbor AMI into your snowball device as an Amazon EC2 AMI if you have an exported Harbor AMI in S3 bucket
### Launch an EC2 Instance from the Harbor AMI
After unlocking your Snowball device, launch an EC2 instance ([REF](https://docs.aws.amazon.com/snowball/latest/developer-guide/manage-ec2.html#launch-instance)) with the preinstalled Harbor AMI.
* Create an ssh key pair for the Harbor AMI EC2 instance
```
aws ec2 create-key-pair --key-name <key-name> --query 'KeyMaterial' --output text --endpoint http://<snowball-ip>:8008 --profile <profile name> > <path-to-key>/<key-file-name>
```
###### Note: key file will be saved at <path-to-key>/<key-file-name>.
* Describe images to find your Harbor AMI id, whose prefix is `snow-harbor-image`
```
aws ec2 describe-images --endpoint http://<snowball-ip>:8008 --profile <profile name>
```
* Run an EC2 instance with the Harbor AMI
```
aws ec2 run-instances --image-id <your-harbor-ami-id> --instance-type sbe-c.xlarge --key-name <key-name> --endpoint http://<snowball-ip>:8008 --profile <profile name>
```
* Check the instance status
```
aws ec2 describe-instances --instance-id <instance id> --endpoint http://<snowball-ip>:8008 --profile <profile name>
```
* After the instance is in running state, describe the device and active physical network interface will be found in the output. Save the `PhysicalNetworkInterfaceId` corresponding to the IPAddress of `ActiveNetworkInterface`
###### Note: `$SNOWBALLEDGE_CLIENT_PATH` is the absolute SnowballEdge client path
```
$SNOWBALLEDGE_CLIENT_PATH describe-device --endpoint https://<snowball-ip> --manifest-file <manifest-path> --unlock-code <unlock-code>
```
* Create Virtual Network Interface(VNI) with the `PhysicalNetworkInterfaceId` and get the Public-IP from the output
```
$SNOWBALLEDGE_CLIENT_PATH create-virtual-network-interface --physical-network-interface-id <physical-network-interface-id> --ip-address-assignment DHCP --endpoint https://<snowball-ip> --manifest-file <manifest-path> --unlock-code <unlock-code>
```
* Associate the public ip with the EC2 instance
```
aws ec2 associate-address --public-ip <Public-IP> --instance-id <instance-id> --endpoint http://<snowball-ip>:8008 --profile <profile name>
```
* [SSH into the EC2 instance](https://docs.aws.amazon.com/snowball/latest/developer-guide/ssh-ec2-edge.html), note that the user name is `ec2-user`
```
ssh -i <path-to-key>/<key-file-name> ec2-user@<Public-IP>
```
* Run `harbor-configuration.sh` to start Harbor registry and push the preloaded container images to the registry. Remember to record the password you set during the process. The script will generate the certificate, key, and CA files in the home directory.
```
./harbor-configuration.sh 
```
## Import EKS Anywhere Container Images to the Local Harbor Registry on a Snowball Device
Prerequisites:

1. EKS-A admin instance is set up successfully and is in running status.
2. Harbor is running. To check Harbor registry status, ssh to the registry instance, then run `sudo docker-compose ps` in `~/harbor` directory and check whether all Harbor containers are in the `Up (healthy)` state.  If it's not running, please [Stop and restart Harbor](https://goharbor.io/docs/1.10/install-config/reconfigure-manage-lifecycle/).
```
sudo docker-compose ps
```
An example of a running Harbor
```
[ec2-user@ip-xxx-xx-xx-xx harbor]$ sudo docker-compose ps
      Name                     Command                  State                                          Ports                                    
------------------------------------------------------------------------------------------------------------------------------------------------
harbor-core         /harbor/entrypoint.sh            Up (healthy)                                                                               
harbor-db           /docker-entrypoint.sh  13        Up (healthy)                                                                               
harbor-jobservice   /harbor/entrypoint.sh            Up (healthy)                                                                               
harbor-log          /bin/sh -c /usr/local/bin/ ...   Up (healthy)   xxx.x.x.x:xxxx->xxxxx/tcp                                                   
harbor-portal       nginx -g daemon off;             Up (healthy)                                                                               
nginx               nginx -g daemon off;             Up (healthy)   0.0.0.0:80->8080/tcp,:::80->8080/tcp, 0.0.0.0:443->8443/tcp,:::443->8443/tcp
redis               redis-server /etc/redis.conf     Up (healthy)                                                                               
registry            /home/harbor/entrypoint.sh       Up (healthy)                                                                               
registryctl         /home/harbor/start.sh            Up (healthy)     
```
### Provide the certificates to local registry on the EKS-A admin instance
* Copy the server certificate, key and CA files from Harbor EC2 instance to the EKS-A admin instance
###### Note: `<path-to-key>` is the path to your ssh key pair file of your EKS-A admin instance
```
scp -i <path-to-key>/<key-file-name> ca.crt <HARBOR_INSTANCE_IP>.key <HARBOR_INSTANCE_IP>.cert ec2-user@<EKS_A_ADMIN_INSTANCE_IP>:~
```
* On the EKS-A admin instance, copy the server certificate, key and CA files into the Docker certificates folder and restart docker
```
export REGISTRY_IP=<harbor instance public ip>
export REGISTRY_USERNAME=admin
export REGISTRY_PASSWORD=<REGISTRY_PASSWORD>

sudo mkdir -p /etc/docker/certs.d/$REGISTRY_IP:443
sudo cp $REGISTRY_IP.cert /etc/docker/certs.d/$REGISTRY_IP:443/
sudo cp $REGISTRY_IP.key /etc/docker/certs.d/$REGISTRY_IP:443/
sudo cp ca.crt /etc/docker/certs.d/$REGISTRY_IP:443/
sudo systemctl restart docker
docker login $REGISTRY_IP:443 --username $REGISTRY_USERNAME --password $REGISTRY_PASSWORD
```
* Populate the local registry with the container images and artifacts required for provisioning an EKS-A cluster
```
# from eks-a admin instance
export REGISTRY_IP=<harbor instance public ip>
sudo cp ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust extract

eksctl anywhere import images \
-i /usr/lib/eks-a/artifacts/artifacts.tar.gz \
-r $REGISTRY_IP:443 \
--bundles /usr/lib/eks-a/manifests/bundle-release.yaml \
--insecure=true
```
## License
This repository is licensed under the MIT-0 License. See the LICENSE file.
