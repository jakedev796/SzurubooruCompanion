#!/bin/sh
# Always update config.json from the image defaults.
# This file is app infrastructure (gallery-dl site handlers, extractors, etc.)
# and the app depends on it being current. Site credentials come from env vars,
# not from this file.
cp /defaults/config.json /config/config.json
echo "init-config: updated config.json from image defaults"
