#!/bin/bash

sed -i s/^DB_BASE_URL=.*/DB_BASE_URL="${MYSQL_HOST}"/ "${ENV_PATH}"/."${ENV}".env
sed -i s/^DB_NAME=.*/DB_NAME="${MYSQL_DB_NAME}"/ "${ENV_PATH}"/."${ENV}".env
sed -i s/^DB_USERNAME=.*/DB_USERNAME="${MYSQL_USERNAME}"/ "${ENV_PATH}"/."${ENV}".env
sed -i s/^DB_PASSWORD=.*/DB_PASSWORD="${MYSQL_PASSWORD}"/ "${ENV_PATH}"/."${ENV}".env
