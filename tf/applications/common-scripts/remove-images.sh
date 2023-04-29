#!/bin/bash

REPO_URL="registry.yidoyoon.com"

IMAGE_IDS=$(docker images --filter=reference="$REPO_URL/pipe-*" --format="{{.ID}}")

for IMAGE_ID in $IMAGE_IDS
do
  docker rmi "$IMAGE_ID"
done
