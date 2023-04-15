#!/bin/bash

registry_url="${1:-${REGISTRY_URL}}"
cicd_path="${2:-${CICD_PATH}}"
env="${3:-${ENV}}"

docker pull "$registry_url"/pipe-timer-frontend:staging
docker run -itd \
  -e NODE_ENV="$env" \
  -e NGINX_ENVSUBST_OUTPUT_DIR=/etc/nginx \
  -e FRONT_URL=pipetimer.com \
  --env-file "$cicd_path"/env/."$env".env \
  -p 443:443 \
  -p 80:80 \
  -v "$cicd_path"/certs:/etc/nginx/certs/:ro \
  -v "$cicd_path"/nginx.conf:/etc/nginx/nginx.conf \
  -v "$cicd_path"/public:/public:ro \
  --name frontend \
  "$registry_url"/pipe-timer-frontend:"$env"
docker ps -a
