#!/bin/sh
# Ensure /config exists for optional bind-mount; gallery-dl is configured via app handlers and -o flags only.
mkdir -p /config
