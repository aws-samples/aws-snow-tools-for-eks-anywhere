# EKS Anywhere on Snow cleanup tools
When there are previous clusters which were not deleted well, you need to clean your EKS Anywhere admin instance and your snowball devices by following these:

## EKS Anywhere resources cleaner
`eks-a-resource-cleaner.sh` helps to clean the zombie instances, tags and DirectNetworkInterfaces from previsous EKS-A clusters. Please make sure you delete the cluster you don't need anymore.
### Prerequisite
1. Install jq `curl -qL -o jq https://stedolan.github.io/jq/download/linux64/jq && chmod +x ./jq`
2. Add jq to your PATH
3. Install snowballEdge cli https://docs.aws.amazon.com/snowball/latest/developer-guide/download-the-client.html
4. Install aws cli
5. Add absolute SnowballEdge client path and devices' information in `config.json` file
6. Add the cluster name you want to clean in `config.json` file
### How to use this script
```
$ chmod +x eks-a-resource-cleaner.sh
$ ./eks-a-resource-cleaner.sh 
```

## Clean kind clusters
If clusters failed before moving it to workerload cluster, it would be zombie kind clusters. You need to clean them manually
### Connected to external network
If your Snowball devices are connected to external network, you can install kind and use it
```
$ curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.17.0/kind-linux-amd64
$ chmod +x ./kind

# add kind to your PATH
$ sudo mv ./kind /usr/local/bin/kind
$ kind get clusters

# If you know the cluster name
$ kind delete cluster --name <cluster-name>

# If you don't know the cluster name
$ kind delete clusters --all
```
### Air-gapped environment
If your Snowball devices are not connected to external network, you need to use the kind installed inside EKS Anywhere cli tools.
#### Find eks-anywhere-cli-tools image
```
$ docker images | grep eks-anywhere-cli-tools
public.ecr.aws/l0g8r8j6/eks-anywhere-cli-tools          v0.14.1-eks-a-v0.0.0-dev-build.5819                 a1931be7d19e   22 hours ago   365MB
```
#### Start a container with *eks-anywhere-cli-tools* image
```
 $ docker run -d --name <container-name> --network host -w /home/ec2-user -v /var/run/docker.sock:/var/run/docker.sock -v /home/ec2-user:/home/ec2-user -v /home/ec2-user:/home/ec2-user --entrypoint sleep <image>:<Tag> infinity
 
 # example
 $ docker run -d --name test --network host -w /home/ec2-user -v /var/run/docker.sock:/var/run/docker.sock -v /home/ec2-user:/home/ec2-user -v /home/ec2-user:/home/ec2-user --entrypoint sleep public.ecr.aws/l0g8r8j6/eks-anywhere-cli-tools:v0.14.1-eks-a-v0.0.0-dev-build.5819 infinity
```
#### Get all kind clusters
```
# get all existing kind clusters
$ docker exec -i <container-name> kind get clusters

# example
$ docker exec -i test kind get clusters
br-test-eks-a-cluster
br-test-gpu-eks-a-cluster
br-test-static-2-eks-a-cluster
br-test-static-eks-a-cluster
test-snow-eks-a-cluster
```
#### Delete specific kind cluster
if you know which kind cluster is zombie and you want to delete it

```
$ docker exec -i <container-name> kind delete cluster --name <cluster-name>

# example
$ docker exec -i test kind delete cluster --name br-test-static-eks-a-cluster
Deleting cluster "br-test-static-eks-a-cluster" ...
```
#### Delete all kind clusters
If you don't know the kind cluster name, you can use following command to delete all kind clusters.

*IMPORTANT*: Make sure you don't have ongoing clusters operation including creating/upgrading/deleting. Otherwise, the ongoing cluster operation may fail.
```
$ docker exec -i <container-name> kind delete clusters --all

# example
$ docker exec -i test kind delete clusters --all
Deleted clusters: ["br-test-gpu-eks-a-cluster" "test-snow-eks-a-cluster"]
```
