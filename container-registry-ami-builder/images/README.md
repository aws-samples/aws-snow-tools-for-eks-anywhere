# Images folder
## Description
This is a folder to store all your docker images. Make sure to store them as tar files to initiate a harbor ami build

1. `docker pull` all the images and run `docker save IMAGE_NAME > IMAGE_NAME.tar` to save it as tar file
2. Copy all tar files to your al2 instance under images folder before running build.sh script during the ami build process.
> `scp -i your-pemKey <path-to-your-tar-file/your-tar-file> ec2-user@<instance ip>:~/AwsSnowHarborAmiBuild/images/`
3. build.sh script will automatically read images folder and get your tar file to build up the harbor ami 
