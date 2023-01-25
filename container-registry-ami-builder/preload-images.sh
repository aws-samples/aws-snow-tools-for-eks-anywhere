#!/bin/bash
set -euo pipefail

OLD='/'
NEW='-'
FILE="images.txt"
#Check images.txt, skipping empty lines in the file and docker pull all images listed in the file
while IFS= read -r IMAGE
do
  if [ -z "$IMAGE" ]; then
    continue
  fi
  sudo docker pull $IMAGE
  NEW_OUT=$(echo $IMAGE | sed 's/\\$OLD/\\$NEW/g')
  sudo docker save $IMAGE > images/$NEW_OUT.tar
done < "$FILE"
