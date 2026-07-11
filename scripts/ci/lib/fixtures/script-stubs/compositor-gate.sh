#!/usr/bin/env sh
while [ $# -gt 0 ]; do
  case "$1" in
    --)
      shift
      break
      ;;
    *) shift ;;
  esac
done
exec "$@"
