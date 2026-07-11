#!/usr/bin/env sh
printf 'app-open %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
