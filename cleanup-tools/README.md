# EKS Anywhere on Snow cleanup tools
When there are previous clusters which were not deleted well, you need to clean your EKS Anywhere admin instance and your snowball devices by following these:

## EKS Anywhere resources cleaner
`eks-a-resource-cleaner.sh` helps to clean the orphaned instances, tags and direct network interfaces from previous EKS Anywhere clusters. Please make sure you delete the cluster you don't need anymore.

### Prerequisites
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
7. Add the cluster name you want to clean in `config.json` file
```
# config.json example
{
  "SnowballEdgeClientPath": "/home/xxx/snowball-client-linux-x.x.x-xxx/bin/snowballEdge",  # the absolute path to snowballEdge client
  "ClusterName": "", # the name of cluster you want to clean
  "Devices": [
    {
      "IPAddress": "192.168.1.123", # ip adress of Snowball device
      "ManifestPath": "/tmp/manifest-final-123.bin", # absolute path to manifest file you download and save
      "UnlockCode": "snowball" # unlock code
    },
    {
      "IPAddress": "192.168.1.124",
      "ManifestPath": "/tmp/manifest-final-124.bin",
      "UnlockCode": "snowball"
    }
  ]
}
```

### How to use this script
* check [prerequisites](#prerequisites)
```
sh eks-a-resource-cleaner.sh
```

## Clean local management cluster
If creating a clusters fails before moving the management cluster to the workload cluster, you may also need to clean the orphaned local management cluster
### Find eks-anywhere-cli-tools image
```
docker images | grep cli-tools
public.ecr.aws/eks-anywhere/cli-tools   v0.14.1-eks-a-27   56a168a45941   2 weeks ago   365MB
```
### Start a container with *eks-anywhere-cli-tools* image
```
docker run -d --name <container-name> --network host -w /home/ec2-user -v /var/run/docker.sock:/var/run/docker.sock -v /home/ec2-user:/home/ec2-user -v /home/ec2-user:/home/ec2-user --entrypoint sleep <image>:<Tag> infinity
```
```
# example
docker run -d --name test --network host -w /home/ec2-user -v /var/run/docker.sock:/var/run/docker.sock -v /home/ec2-user:/home/ec2-user -v /home/ec2-user:/home/ec2-user --entrypoint sleep public.ecr.aws/eks-anywhere/cli-tools:v0.14.1-eks-a-27 infinity
```
### Get all existing local management clusters
```
docker exec -i <container-name> kind get clusters
```
```
# example
docker exec -i test kind get clusters
test-eks-a-cluster
test-gpu-eks-a-cluster
test-static-2-eks-a-cluster
test-static-eks-a-cluster
test-snow-eks-a-cluster
```
### Delete specific local management cluster
if you know which local management cluster is orphaned and you want to delete it

```
docker exec -i <container-name> kind delete cluster --name <cluster-name>
```
```
# example
docker exec -i test kind delete cluster --name test-static-eks-a-cluster
Deleting cluster "test-static-eks-a-cluster" ...
```
#### Delete all local management clusters
If you don't know the local management cluster name, you can use following command to delete all local management clusters.

*IMPORTANT*: Make sure you don't have ongoing clusters operation including creating/upgrading/deleting. Otherwise, the ongoing cluster operation may fail.
```
docker exec -i <container-name> kind delete clusters --all
```
```
# example
docker exec -i test kind delete clusters --all
Deleted clusters: ["test-gpu-eks-a-cluster" "test-snow-eks-a-cluster"]
```
