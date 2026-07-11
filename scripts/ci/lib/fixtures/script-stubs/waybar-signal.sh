#!/usr/bin/env sh
printf 'waybar-signal %s\n' "$*" >>"${WAYBAR_HOME}/bin/calls.log"
