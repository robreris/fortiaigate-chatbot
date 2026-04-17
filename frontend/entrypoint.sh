#!/bin/sh
set -e

if [ -z "$NGINX_USERNAME" ] || [ -z "$NGINX_PASSWORD" ]; then
  echo "ERROR: NGINX_USERNAME and NGINX_PASSWORD must be set"
  exit 1
fi

BACKEND_HOST="${BACKEND_HOST:-backend}"

htpasswd -bc /etc/nginx/.htpasswd "$NGINX_USERNAME" "$NGINX_PASSWORD"

envsubst '${BACKEND_HOST}' < /etc/nginx/conf.d/default.conf > /tmp/default.conf
cp /tmp/default.conf /etc/nginx/conf.d/default.conf

exec nginx -g "daemon off;"
