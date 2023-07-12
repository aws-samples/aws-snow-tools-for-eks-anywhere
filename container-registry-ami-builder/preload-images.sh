#!/bin/bash
set -euo pipefail

FILE="images.txt"

#Check images.txt, skipping empty lines in the file and docker pull all images listed in the file
while IFS= read -r IMAGE
do
  if [ -z "$IMAGE" ]; then
    continue
  fi
  sudo docker pull $IMAGE
  sudo docker save $IMAGE > images/$(echo $IMAGE | sed 's/\//\-/g').tar
done < "$FILE"
