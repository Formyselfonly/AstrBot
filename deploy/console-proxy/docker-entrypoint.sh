#!/bin/sh
set -eu

if [ -z "${CONSOLE_PROXY_PASSWORD:-}" ]; then
    echo "CONSOLE_PROXY_PASSWORD is required" >&2
    exit 1
fi

user="${CONSOLE_PROXY_USER:-kerryzheng}"
pass="$CONSOLE_PROXY_PASSWORD"
hash=$(openssl passwd -apr1 "$pass")
printf '%s:%s\n' "$user" "$hash" > /etc/nginx/.htpasswd

cp /etc/nginx/templates/default.conf.template /etc/nginx/conf.d/default.conf

exec nginx -g 'daemon off;'
