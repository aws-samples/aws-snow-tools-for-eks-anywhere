#!/bin/bash

########################################################################################################################
# Script to setup a local Harbor registry on a snowball ec2 instance
#
# Prerequisite:
# Start an ec2 instance with harbor artifacts pre-baked AMI, create and attach a vni,
# then ssh into the instance to run this script
#
# Run the script
# `./harbor-configuration.sh`
#
########################################################################################################################

TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
INSTANCE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/public-ipv4)
read -p "Please set up the Harbor UI Admin Password: " ADMIN_PASSWORD
read -p "Please set up the Harbor DB Root Password: " DB_PASSWORD

cat <<EOF > /tmp/ifcfg-lo:1
DEVICE=lo:1
IPADDR=${INSTANCE_IP}
NETMASK=255.255.255.255
NETWORK=127.0.0.0
BROADCAST=127.255.255.255
ONBOOT=yes
NAME=loopback
EOF

sudo mv /tmp/ifcfg-lo:1 /etc/sysconfig/network-scripts/ifcfg-lo:1

sudo systemctl restart network

### configure https access to harbor

## Generate a Certificate Authority Certificate
# Generate a CA certificate private key
openssl genrsa -out ca.key 4096

# Generate the CA certificate using instance-ip as CN
openssl req -x509 -new -nodes -sha512 -days 3650 \
 -subj "/CN=$INSTANCE_IP" \
 -key ca.key \
 -out ca.crt

## Generate a Server Certificate
# Generate a private key
openssl genrsa -out $INSTANCE_IP.key 4096

# Generate a certificate signing request (CSR)
openssl req -sha512 -new \
    -subj "/CN=$INSTANCE_IP" \
    -key $INSTANCE_IP.key \
    -out $INSTANCE_IP.csr

# Generate an
cat > v3.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = IP:$INSTANCE_IP
EOF

# Use the v3.ext file to generate a certificate for your Harbor host
openssl x509 -req -sha512 -days 3650 \
    -extfile v3.ext \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -in $INSTANCE_IP.csr \
    -out $INSTANCE_IP.crt

## Provide the Certificates to Harbor
# Copy the server certificate and key into the certificates folder on your Harbor host.
sudo mkdir -p /data/cert
sudo cp $INSTANCE_IP.crt /data/cert/
sudo cp $INSTANCE_IP.key /data/cert/

## Provide the Certificates to Docker
# Convert .crt file to .cert file, for use by Docker
openssl x509 -inform PEM -in $INSTANCE_IP.crt -out $INSTANCE_IP.cert

# Copy the server certificate, key and CA files into the Docker certificates folder on the Harbor host
sudo mkdir -p /etc/docker/certs.d/$INSTANCE_IP
sudo cp $INSTANCE_IP.cert /etc/docker/certs.d/$INSTANCE_IP/
sudo cp $INSTANCE_IP.key /etc/docker/certs.d/$INSTANCE_IP/
sudo cp ca.crt /etc/docker/certs.d/$INSTANCE_IP/

# Restart docker
sudo systemctl restart docker

### Configure the Harbor YML File
sed "s/hostname: reg.mydomain.com/hostname: $INSTANCE_IP/" /home/ec2-user/harbor/harbor.yml.tmpl | \
sed "s/\/your\/certificate\/path/\/data\/cert\/$INSTANCE_IP.crt/" | \
sed "s/\/your\/private\/key\/path/\/data\/cert\/$INSTANCE_IP.key/" | \
sed "s/root123/$DB_PASSWORD/" | \
sed "s/Harbor12345/$ADMIN_PASSWORD/" > /home/ec2-user/harbor/harbor.yml

## Run the harbor install script
sudo /home/ec2-user/harbor/prepare
sudo /home/ec2-user/harbor/install.sh
sleep 30
## Create needed Projects in Harbor
curl -u admin:$ADMIN_PASSWORD -k -X 'POST' https://$INSTANCE_IP/api/v2.0/projects -H 'Content-Type: application/json' -d '{ "project_name": "eks-anywhere", "public": true }'
curl -u admin:$ADMIN_PASSWORD -k -X 'POST' https://$INSTANCE_IP/api/v2.0/projects -H 'Content-Type: application/json' -d '{ "project_name": "eks-distro", "public": true }'
curl -u admin:$ADMIN_PASSWORD -k -X 'POST' https://$INSTANCE_IP/api/v2.0/projects -H 'Content-Type: application/json' -d '{ "project_name": "isovalent", "public": true }'
curl -u admin:$ADMIN_PASSWORD -k -X 'POST' https://$INSTANCE_IP/api/v2.0/projects -H 'Content-Type: application/json' -d '{ "project_name": "bottlerocket", "public": true }'
curl -u admin:$ADMIN_PASSWORD -k -X 'POST' https://$INSTANCE_IP/api/v2.0/projects -H 'Content-Type: application/json' -d '{ "project_name": "cilium-chart", "public": true }'

## login to harbor from local docker
sleep 30
sudo docker login $INSTANCE_IP --username admin --password $ADMIN_PASSWORD

## Load images from images file from customer
for file in /home/ec2-user/images/*
    do
        sudo docker load --input "$file"
    done

# Iterate over images in the docker excluding habor images
IMAGES=$(sudo docker images --format "{{.Repository}}:{{.Tag}}" | grep -v goharbor)
for image in $IMAGES; do
  # Tag the image with a new name
    docker tag $image $INSTANCE_IP/library/$image

    # Push the image to a registry
    docker push $INSTANCE_IP/library/$image
done

echo "All images are uploaded"
