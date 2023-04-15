#!/bin/bash

registry_url="${1:-${REGISTRY_URL}}"
cicd_path="${2:-${CICD_PATH}}"
env="${3:-${ENV}}"

docker pull "$registry_url"/pipe-timer-backend:"$env"
docker run -itd \
  -e NODE_ENV="$env" \
  -v "$cicd_path"/certs:/certs/:ro \
  -p 3000:3000 \
  --env-file "$cicd_path"/env/."$env".env \
  --name backend \
  "$registry_url"/pipe-timer-backend:"$env"
docker ps -a
