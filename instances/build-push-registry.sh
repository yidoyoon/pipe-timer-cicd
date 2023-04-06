#!/bin/bash

registry_url="${REGISTRY_URL}"

image_name="${REGISTRY_URL}/pipe-timer-backend"
image_tag="${ENV}"
path="${PATH}"

docker build --build-arg NODE_ENV="$image_tag" -t "$image_name":"$image_tag" "$path"

docker tag "$image_name":"$image_tag" "$registry_url"/"$image_name":"$image_tag"

docker push "$registry_url"/"$image_name":"$image_tag"
