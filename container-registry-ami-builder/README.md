## Description
This repo uses [Harbor](https://goharbor.io/) to build a registry AMI. This AMI can be used for setting up an EC2 instance on Snow devices, which could serve as the local registry for EKS Anywhere for Snow service air-gapped use case.
## Build Harbor AMI
In order to initiate a Harbor AMI build, you need to set up the prerequisites, preparing an Amazon Linux 2 EC2 instance setting up prerequisites and pre-loading your container images to start a building process. Please refer the following steps to kick off a building process.
### Prerequisites
Before initiating a Harbor AMI build, you need to start an Amazon Linux 2 EC2 instance, which is the working environment for you to kick off a building process. Please also create an IAM role with proper policy using either AWS CLI or AWS console, which enables you to have permissions and access to do the operations related to the building process.

#### Start an al2 instance
* Create an IAM policy named `harbor-EC2-Permissions` by following this [guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_create-console.html). On the *Create policy* page, paste the following in the *JSON* tab:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "iam:CreatePolicy",
                "iam:CreateRole",
                "iam:AttachRolePolicy"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:iam::*:policy/import-harbor-ami",
                "arn:aws:iam::*:role/import-harbor.role"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AssociateIamInstanceProfile",
            ],
            "Resource": ["*"]
        }
    ]
}
```
* Create an IAM Role by following this public [doc](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user.html), attaching the `harbor-EC2-Permissions` policy you created on the previous step and naming your role as harbor-ami-builder.role
* Log into the EC2 console at https://console.aws.amazon.com/ec2
* In the navigation pane on the left, choose *Instances*. Then choose *Launch Instance*
* Name your instance `harbor-ami-builder.instance`
* Choose *Amazon Linux 2* in quick start
* *Create a key pair* with default setting. It will create a key automatically and download the key file to your device. Save it so you can ssh into the instance.
* Under advanced details section, choose `harbor-ami-builder.role` as IAM instance profile
* Keep the default selections for the other configuration settings for your instance.
* Click Launch Instance button
* If this is your first time following this guide, you will also need to accept the [Terms and Conditions in AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-sf35wbdb37e6q). This AMI will be used to produce your Harbor AMI.
* Save the public IPv4 address of the instance for connection
* Details on setting up Amazon Linux 2 EC2 instance is [here](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html#ec2-launch-instance)
#### Setup IAM role with proper policy
###### Option1 with AWS CLI:
A preferred way to setup your IAM policy is using [AWS CLI](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_create-cli.html). In this section, you will be guided to setup your IAM Role with proper policies for your desired account (the account you are going to order a Snow device with).

**Connect to your AL2 instance**
* Connect to your instance using the instruction [below](#connect-to-amazon-linux-2-instance)

**Create a policy**
* Create `import-harbor-ami.json` within the [container-registry-ami-builder](https://github.com/aws-samples/aws-snow-tools-for-eks-anywhere/tree/main/container-registry-ami-builder) repo. Past following policy into the json file:
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
* Run the following command to create the image builder policy
```
aws iam create-policy \
    --policy-name import-harbor-ami \
    --policy-document file://import-harbor-ami.json
```
The output should be a config like the following and you need to copy the policy Amazon Resource Name (ARN) from the policy metadata in the output. You use this ARN to attach this policy to the core device role in the next step.
```
{
    "Policy": {
        "PolicyName": "import-harbor-ami",
        "PermissionsBoundaryUsageCount": 0, 
        "CreateDate": "2023-01-04T21:27:56Z",
        "AttachmentCount": 0, 
        "IsAttachable": true,
        "PolicyId": "ANPA4BRCOVXJSLE55MYJH",
        "DefaultVersionId": "v1",
        "Path": "/",
        "Arn": "arn:aws:iam::123456789012:policy/import-harbor-ami",
        "UpdateDate": "2023-01-04T21:27:56Z"
    }
}
```
**Create IAM Role for Harbor AMI build**
* In your root directory, creating an trust-policy-file.json file and paste the following content into your json file, changing the arn as your own metadata
```
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Principal": { "AWS": "arn:aws:iam::123456789012:root" },
          "Action": "sts:AssumeRole",
          "Condition": { "Bool": { "aws:MultiFactorAuthPresent": "true" } }
      }
  ]
}
```
* Create the IAM Role named  import-harbor.role for Harbor AMI build with the following command
```
aws iam create-role \
    --role-name import-harbor.role \
    --assume-role-policy-document file://trust-policy-file.json
```
You’ll get an output like the following config:
```
{
    "Role": {
        "AssumeRolePolicyDocument": {
            "Version": "2012-10-17", 
            "Statement": [
                {
                    "Action": "sts:AssumeRole", 
                    "Effect": "Allow", 
                    "Condition": {
                        "Bool": {
                            "aws:MultiFactorAuthPresent": "true"
                        }
                    }, 
                    "Principal": {
                        "AWS": "arn:aws:iam::123456789012:root"
                    }
                }
            ]
        }, 
        "RoleId": "XXXXXXXXXXXXXXXX", 
        "CreateDate": "2023-01-04T22:18:32Z", 
        "RoleName": "import-harbor.role", 
        "Path": "/", 
        "Arn": "arn:aws:iam::123456789012:role/import-harbor.role"
    }
}
```
* Attach the import-harbor-ami you created above to import-harbor.role by running the following command, changing the arn to the one you got from creating policy step
```
aws iam attach-role-policy \
    --role-name import-harbor.role \
    --policy-arn arn:aws:iam::123456789012:policy/import-harbor-ami
```
If the command has no output, it succeeded.
* Attach the role to the instance
```
aws ec2 associate-iam-instance-profile \
    --instance-id <instance-id> \
    --iam-instance-profile Name="import-harbor.role" \
    --region <region>
```
If the command has no output, it succeeded.

###### Option2 with AWS console:
**Create a policy**
In this section, you will be guided to setup your IAM Policies using [AWS console](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_create-console.html) for your desired account (the account you are going to order a Snow device with).
* Sign in to the AWS Management Console with your desired account (the account you are going to order a device with)
* Open the IAM console at https://console.aws.amazon.com/iam/
* In the navigation pane on the left, choose *Policies*
* Choose *Create policy*
* Choose the *JSON* tab beside Visual editor
* Paste the below permission json([REF](https://developer.hashicorp.com/packer/plugins/builders/amazon#iam-task-or-instance-role)) into the policy JSON editor
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
* Name your policy image-builder.policy.json

**Create the IAM Role and attach the Role to Amazon Linux 2 instance**
* In the navigation pane on the left of IAM console, choose *Roles* and click *Create role* button
* Choose Trusted Entity Type as *AWS service*, Use Case as *EC2* in step 1
* Attach the `image-builder.policy`  you created above in step 2
* Name your role `import-harbor.role` in step 3
* Attach import-harbor.role to the instance ([ref](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html#attach-iam-role:~:text=security%2Dcredentials/role_name-,Attach%20an%20IAM%20role%20to%20an%20instance,-To%20attach%20an))
* Detail instructions on how to create this IAM role [here](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user.html)

Now the IAM policies are all set up for kicking off an Harbor AMI build
### Connect to Amazon Linux 2 Instance
* Use the key pair you create above ssh to the instance([ref](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AccessingInstancesLinux.html))

`ssh -i <path-to-key> ec2-user@<public-IPv4-address>`
* Download the [container-registry-ami-builder](https://github.com/aws-samples/aws-snow-tools-for-eks-anywhere/tree/main/container-registry-ami-builder) repo onto your al2 instance and enter into the directory of aws-snow-tools-for-eks-anywhere/container-registry-ami-builder
```
sudo yum install -y git
git clone https://github.com/aws-samples/aws-snow-tools-for-eks-anywhere.git
```
* Modify the AMI configuration file ami.json that contains various AMI parameters
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
#### Pre-load Docker Container Images
There are two ways to pre-load your customer docker container images. Both ways export your container images into the ./image folder as tar files, which get imported into your Harbor registry. Regardless of which method you choose, at the end of each, make sure the ./image directory container images only and all the tar files you want to include in your Harbor registry.
##### Script assisted
This is the simplest method and is used by the quick start. If your workstation has access to pull in your containers, put each container image's in images.txt file. The packer file in the repo will iterate over images.txt and docker pull/export the images to the images directory. You can follow the steps below to paste your images into the file.

1. Open images.txt file under ~/aws-snow-tools-for-eks-anywhere/container-registry-ami-builder/images.txt
2. Delete hello-world and alpine in the file if needed
3. Paster your container images’  NAME[:TAG|@DIGEST] on a new line in images.txt

###### NOTE: This only works if your al2 instance has access to the specific container registry that your images, and assumes that they're all
##### Manual Load
This is the most robust method. You can docker pull all images in your local environment and save images as tar file. Then copy all tar files to the images folder on the al2 instance. The packer file in the repo will iterate over images folder and docker pull/export the images to the images directory. You can follow the steps below to manual load your images.

1. `docker pull` all the images and run `docker save IMAGE_NAME > IMAGE_NAME.tar` to save it as tar file
2. Copy all tar files to your al2 instance under images folder before running build.sh script during the AMI build process.
```
scp -i <path-to-key> <path-to-your-tar-file/your-tar-file> ec2-user@<public-IPv4-address>:~/aws-snow-tools-for-eks-anywhere/container-registry-ami-builder/images/
```

#### Export AMI to S3 Bucket (Optional)
AMI export is only needed when you already have Snow devices and need to side load Harbor onto it.  In this section, you will be guided to setup IAM role with proper policy and initiate an Harbor AMI build to export to S3 bucket.
* Set the "export_ami" field as true in ami.json file
* Enter the target S3 bucket for exporting AMI in ami.json file
* Setup permissions for VM Import/Export following the [instruction](https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html)

Now you set up all the IAM permissions for exporting AMI. Run build.sh script to initiate the Harbor AMI build and you’ll see exported Harbor AMI on S3 bucket for downloading.
### Initiate a Harbor AMI Build
Follow the following steps to initiate a Snow harbor AMI build
1. [Subscribe to the Snow AL2 AMI](https://aws.amazon.com/marketplace/pp/prodview-sf35wbdb37e6q) if this is your first time following this guide
2. (Optional) Follow [Export AMI to S3 Bucket](#export-ami-to-s3-bucket-optional) if you want to export ami to S3 bucket
3. Change the permission of all scripts file by running the following command
```
chmod +x build.sh harbor-configuration.sh harbor-image-build.sh preload-images.sh
```
4. Run `build.sh` to start Harbor AMI build process.

Once the script is done running, you should see a new AMI whose name has the prefix snow-harbor-image  in your AWS console that you can add to your Snow device order.
## Configure Harbor on a Snowball Edge device
Prerequisites:

1. Snow device is received and unlocked
2. SnowGlobal Harbor AMI pre-installed on device

### Import the exported Harbor AMI in S3 bucket(optional)
Please refer this [guide](https://docs.aws.amazon.com/snowball/latest/developer-guide/ec2-ami-import-cli.html) to importing your Harbor AMI into your snowball device as an Amazon EC2 AMI if you have an exported Harbor AMI in S3 bucket
### Launch Amazon Linux 2 EC2 Instance with Harbor AMI
After getting your Snow device ready, launching an ec2 instance ([REF](https://docs.aws.amazon.com/snowball/latest/developer-guide/manage-ec2.html#launch-instance)) with the Harbor AMI preinstalled on your device
* Create ssh key pair for the Harbor AMI ec2 instance
```
aws ec2 create-key-pair --key-name <key-name> --query 'KeyMaterial' --output text --endpoint http://<snowball-ip>:8008 --profile <profile name> > <key-file-name>
```
* Describe images to find your Harbor AMI id
```
aws ec2 describe-images --endpoint http://<snowball-ip>:8008 --profile <profile name>
```
* Run an al2 instance with the Harbor AMI
```
aws ec2 run-instances --image-id <your-harbor-ami-id> --instance-type sbe-c.xlarge --key-name <key-name> --endpoint http://<snowball-ip>:8008 --profile <profile name>
```
* Check instance status
```
aws ec2 describe-instances --instance-id <instance id> --endpoint http://<snowball-ip>:8008 --profile <profile name>
```
* After the instance is in running state, describe the device and physical network interface will be found in the output of describe-device
```
./$SNOWBALLEDGE_CLIENT_PATH/bin/snowballEdge describe-device --profile <profile name>
```
* Create Virtual Network Interface(VNI) with the physical network interface id corresponding with the corp ip and get the Public-IP from the output
```
./$SNOWBALLEDGE_CLIENT_PATH/bin/snowballEdge create-virtual-network-interface --physical-network-interface-id <your-physical-network-interface-id> --profile <profile name> --ip-address-assignment DHCP
```
* Associate the public ip with the ec2 instance
```
aws ec2 associate-address --public-ip <Public-IP> --instance-id <instance-id> --endpoint http://<snowball-ip>:8008 --profile <profile name>
```
* [SSH into the EC2 instance](https://docs.aws.amazon.com/snowball/latest/developer-guide/ssh-ec2-edge.html), note that the user name is ec2-user
```
ssh -i <path-to-key> ec2-user@<Public-IP>
```
* Run `harbor-configuration.sh`  on the ec2 instance and you’ll see your Harbor registry, recording the password you set during the process. The script will generate the certificate, key and CA files in your home directory
```
./harbor-configuration.sh 
```
## Using a harbor local registry on an eks-a admin instance
Prerequisites:

1. EKS-A admin instance is set up successfully and is in running status.
2. Harbor service is in running status

### Provide the certificates to local registry on the EKS-A admin instance
* Copy the server certificate, key and CA files from Harbor ec2 instance to the EKS-A admin instance
###### Note: <path-to-key> here is the path to your ssh key pair file of your EKS-A admin instance
```
scp -i <path-to-key> ca.crt <HARBOR_INSTANCE_IP>.key <HARBOR_INSTANCE_IP>.cert ec2-user@<EKS_A_ADMIN_INSTANCE_IP>:~
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
sudo cp ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust extract

eksctl anywhere import images \
-i /usr/lib/eks-a/artifacts/artifacts.tar.gz \
-r $REGISTRY_IP:443 \
--bundles /usr/lib/eks-a/manifests/bundle-release.yaml \
--insecure=true \
-v6
```
* Set up your EKS-A cluster for snow
## License
This repository is licensed under the MIT-0 License. See the LICENSE file.