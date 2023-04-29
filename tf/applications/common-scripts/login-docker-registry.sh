#!/bin/bash

registry_url="${1:-${REGISTRY_URL}}"

username="${2:-${REGISTRY_ID}}"
password="${3:-${REGISTRY_PASSWORD}}"

echo "$password" | docker login -u "$username" "$registry_url" --password-stdin
