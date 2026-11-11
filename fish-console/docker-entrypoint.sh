#!/bin/sh
set -eu

if [ -z "${FISH_SITE_HOST:-}" ]; then
    echo "FISH_SITE_HOST is required (e.g. fish.kerryzhengai.com)" >&2
    exit 1
fi

export FISH_EXTRA_SERVER_NAMES="${FISH_EXTRA_SERVER_NAMES:-}"
envsubst '${FISH_SITE_HOST} ${FISH_EXTRA_SERVER_NAMES}' \
    < /etc/nginx/templates/default.conf.template \
    > /etc/nginx/conf.d/default.conf

exec nginx -g 'daemon off;'
