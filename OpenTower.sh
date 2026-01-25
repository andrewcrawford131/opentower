#!/bin/sh
printf '\033c\033]0;%s\a' OpenTower
base_path="$(dirname "$(realpath "$0")")"
"$base_path/OpenTower.x86_64" "$@"
