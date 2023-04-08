#!/bin/bash

registry_url="${REGISTRY_URL}"

image_name="${REGISTRY_URL}/pipe-timer-backend"
image_tag="${ENV}"
path="${PATH}"

docker build --build-arg NODE_ENV="$image_tag" -t "$image_name":"$image_tag" --no-cache "$path"
docker push "$image_name":"$image_tag"
