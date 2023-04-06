#!/bin/bash

registry_url="${REGISTRY_URL}"

username="${REGISTRY_ID}"
password="${REGISTRY_PASSWORD}"

echo "$password" | docker login -u "$username" "$registry_url" --password-stdin
