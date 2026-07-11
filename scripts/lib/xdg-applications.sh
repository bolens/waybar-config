#!/usr/bin/env bash
# FreeDesktop application directory discovery (XDG_DATA_* + Flatpak exports).
# Used by window-switcher and kde-notifications-rofi for desktop-file / icon maps.

# Print unique application dirs, one per line (directories need not exist yet).
xdg_application_dirs() {
  local -a ordered=() data_dirs=()
  local d
  local -A seen=()
  local oifs="$IFS"

  # XDG_DATA_DIRS is colon-separated; must split on ':' (default IFS would not).
  IFS=':'
  # shellcheck disable=SC2206
  data_dirs=(${XDG_DATA_DIRS:-/usr/local/share:/usr/share})
  IFS="$oifs"

  # Order: user data → each XDG_DATA_DIRS entry → system/user Flatpak exports.
  # ${arr[@]/%//applications} appends /applications to every data_dirs element.
  for d in \
    "${XDG_DATA_HOME:-$HOME/.local/share}/applications" \
    "${data_dirs[@]/%//applications}" \
    "/var/lib/flatpak/exports/share/applications" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share/applications" \
    "$HOME/.local/share/flatpak/exports/share/applications"
  do
    [ -n "$d" ] || continue
    # Empty XDG_DATA_DIRS segment becomes "/applications" — skip that junk path.
    [ "$d" = "/applications" ] && continue
    if [ -n "${seen[$d]+x}" ]; then
      continue
    fi
    seen[$d]=1
    ordered+=("$d")
  done

  printf '%s\n' "${ordered[@]}"
}
