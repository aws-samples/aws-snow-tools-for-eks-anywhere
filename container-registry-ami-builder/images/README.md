## Description
You can pull all images in your local environment and save them as tar files. Then copy all tar files to the `~/aws-snow-tools-for-eks-anywhere/container-registry-ami-builder/images` directory on the AL2023 instance. The AMI build process will iterate over the `images` folder and upload the tar files to the target AMI.

1. `docker pull` all the images and run `docker save IMAGE_NAME > IMAGE_NAME.tar` to save them as tar files
2. Copy all tar files to your AL2023 instance under the `~/aws-snow-tools-for-eks-anywhere/container-registry-ami-builder/images` folder before running `build.sh` script during the AMI build process.

###### Note: `<path-to-key>` is the path to your private key and `<public-IPv4-address>` is the public ip of your Harbor AMI build instance
```
scp -i <path-to-key> <path-to-your-tar-file/your-tar-file> ec2-user@<public-IPv4-address>:~/aws-snow-tools-for-eks-anywhere/container-registry-ami-builder/images/
```