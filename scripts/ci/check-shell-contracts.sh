#!/usr/bin/env bash
# Prevent CI regressions from shell portability mismatches.
#
# Ubuntu runners use dash as /bin/sh. Footguns this suite guards:
# 1. Scripts with a `sh` shebang that source bash-only waybar-settings.sh
# 2. Listener lock acquisition that relies on `. file arg` (dash ignores args)
# 3. listener-ctl + status scripts failing silently under dash/minimal PATH
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "=== Shell contract checks ==="

# --- 1) sh shebang must not source bash-only settings helpers ---
while IFS= read -r -d '' file; do
  sheb="$(head -1 "$file" || true)"
  case "$sheb" in
    '#!/usr/bin/env sh'|'#!/bin/sh')
      if grep -q 'waybar-settings\.sh' "$file"; then
        echo "FAIL: $file uses sh shebang but sources/references waybar-settings.sh (bash-only under dash)" >&2
        fail=1
      fi
      ;;
  esac
done < <(find "$ROOT/scripts" -type f -name '*.sh' -print0)

# Known CI regressions: these must stay on bash (they source waybar-settings.sh).
for must_bash in \
  services/i2pd/i2pd-status.sh \
  services/sync/updates-status.sh \
  services/apps/github-status.sh \
  lib/waybar-settings.sh
do
  sheb="$(head -1 "$ROOT/scripts/$must_bash" || true)"
  case "$sheb" in
    '#!/usr/bin/env bash'|'#!/bin/bash')
      ;;
    *)
      echo "FAIL: scripts/$must_bash must use a bash shebang (got: $sheb)" >&2
      fail=1
      ;;
  esac
done

# Meta-test: detector must flag a synthetic sh+settings offender
bad_sample="$WORK/bad-settings-consumer.sh"
printf '%s\n' '#!/usr/bin/env sh' '. "$(dirname "$0")/waybar-settings.sh"' >"$bad_sample"
if ! grep -q 'waybar-settings\.sh' "$bad_sample" || ! head -1 "$bad_sample" | grep -q 'env sh'; then
  echo "FAIL: could not build synthetic offender for detector self-test" >&2
  fail=1
else
  # Inline the same rule used above
  if head -1 "$bad_sample" | grep -qE 'env sh|/bin/sh' && grep -q 'waybar-settings\.sh' "$bad_sample"; then
    echo "PASS: shebang/settings detector self-test"
  else
    echo "FAIL: shebang/settings detector self-test did not match" >&2
    fail=1
  fi
fi

# --- 2) Listener lock must be dash-safe (env var, not `. file arg` only) ---
for listener in \
  "$ROOT/scripts/listeners/device-notifier-listener.sh" \
  "$ROOT/scripts/listeners/privacy-listener.sh" \
  "$ROOT/scripts/listeners/workspaces-hyprland-listener.sh"
do
  if ! grep -q 'WAYBAR_LISTENER_LOCK_NAME=' "$listener"; then
    echo "FAIL: $listener must set WAYBAR_LISTENER_LOCK_NAME before sourcing lock helper" >&2
    fail=1
  fi
  if grep -E 'dock-windows-listener-lock\.sh"[[:space:]]+[A-Za-z0-9_-]+' "$listener" \
    || grep -E "dock-windows-listener-lock\.sh'[[:space:]]+[A-Za-z0-9_-]+" "$listener"; then
    echo "FAIL: $listener still passes lock name as source arg (broken under dash)" >&2
    fail=1
  fi
done

if ! grep -q 'WAYBAR_LISTENER_LOCK_NAME' "$ROOT/scripts/listeners/dock-windows-listener-lock.sh"; then
  echo "FAIL: dock-windows-listener-lock.sh must read WAYBAR_LISTENER_LOCK_NAME" >&2
  fail=1
fi

# --- 3) Runtime: lock + listener-ctl under dash ---
if ! command -v dash >/dev/null 2>&1; then
  echo "FAIL: dash is required for shell contract runtime tests (apt install dash)" >&2
  fail=1
else
  runtime="$WORK/runtime"
  mkdir -p "$runtime"
  lock_pid="$runtime/waybar-dock-listener-contract-test.lock.d/pid"
  if ! XDG_RUNTIME_DIR="$runtime" WAYBAR_LISTENER_LOCK_NAME=contract-test \
    dash -c ". \"$ROOT/scripts/listeners/dock-windows-listener-lock.sh\"; test -f \"$lock_pid\"; kill -0 \"\$(cat \"$lock_pid\")\""; then
    echo "FAIL: dash could not acquire listener lock via WAYBAR_LISTENER_LOCK_NAME" >&2
    fail=1
  else
    echo "PASS: dash lock acquisition"
  fi

  # Old pattern must fail under dash (documents why env var is required)
  if XDG_RUNTIME_DIR="$runtime" dash -c ". \"$ROOT/scripts/listeners/dock-windows-listener-lock.sh\" should-not-work" 2>/dev/null; then
    echo "FAIL: unexpected: dash accepted sourced lock args (contract assumption changed)" >&2
    fail=1
  else
    echo "PASS: dash rejects/ignores sourced lock args as expected"
  fi

  # Full listener-ctl start/stop with a dash shebang mock (mirrors Ubuntu CI)
  scripts_stub="$WORK/scripts"
  mkdir -p "$scripts_stub"
  cp "$ROOT/scripts/infra/listener-ctl.sh" "$ROOT/scripts/listeners/dock-windows-listener-lock.sh" "$scripts_stub/"
  cat >"$scripts_stub/mock-listener.sh" <<'MOCK'
#!/usr/bin/env dash
set -eu
script_dir="${0%/*}"
WAYBAR_LISTENER_LOCK_NAME="${WAYBAR_MOCK_LOCK_NAME:-mock-listener}"
. "$script_dir/dock-windows-listener-lock.sh"
sleep 30
MOCK
  chmod +x "$scripts_stub"/*

  runtime2="$WORK/runtime2"
  mkdir -p "$runtime2"
  XDG_RUNTIME_DIR="$runtime2" "$scripts_stub/listener-ctl.sh" start "$scripts_stub/mock-listener.sh" mock-listener
  mock_pid_file="$runtime2/waybar-dock-listener-mock-listener.lock.d/pid"
  sleep 0.5
  if [ ! -f "$mock_pid_file" ] || ! kill -0 "$(cat "$mock_pid_file")" 2>/dev/null; then
    echo "FAIL: listener-ctl start with dash mock left no live lock pid" >&2
    fail=1
  else
    XDG_RUNTIME_DIR="$runtime2" "$scripts_stub/listener-ctl.sh" stop mock-listener
    sleep 0.3
    if [ -f "$mock_pid_file" ] && kill -0 "$(cat "$mock_pid_file" 2>/dev/null)" 2>/dev/null; then
      echo "FAIL: listener-ctl stop left dash mock running" >&2
      fail=1
    else
      echo "PASS: listener-ctl start/stop under dash mock"
    fi
  fi

  WAYBAR_MOCK_LOCK_NAME=device-notifier XDG_RUNTIME_DIR="$runtime2" \
    "$scripts_stub/listener-ctl.sh" start "$scripts_stub/mock-listener.sh" device-notifier
  dn_pid_file="$runtime2/waybar-dock-listener-device-notifier.lock.d/pid"
  sleep 0.5
  if [ ! -f "$dn_pid_file" ] || ! kill -0 "$(cat "$dn_pid_file")" 2>/dev/null; then
    echo "FAIL: listener-ctl start device-notifier dash mock failed" >&2
    fail=1
  else
    XDG_RUNTIME_DIR="$runtime2" "$scripts_stub/listener-ctl.sh" stop-all
    sleep 0.3
    if [ -f "$dn_pid_file" ] && kill -0 "$(cat "$dn_pid_file" 2>/dev/null)" 2>/dev/null; then
      echo "FAIL: listener-ctl stop-all left dash device-notifier mock running" >&2
      fail=1
    else
      echo "PASS: listener-ctl stop-all under dash mock"
    fi
  fi
fi

# --- 4) Status scripts that source settings must emit JSON via their shebang ---
tmpdir="$WORK/status-home"
mkdir -p "$tmpdir/data" "$tmpdir/cache" "$tmpdir/scripts"/{lib,services/{i2pd,sync,apps}}
cp "$ROOT/scripts/services/i2pd/i2pd-status.sh" "$tmpdir/scripts/services/i2pd/" 2>/dev/null || true
cp "$ROOT/scripts/services/sync/updates-status.sh" "$tmpdir/scripts/services/sync/" 2>/dev/null || true
cp "$ROOT/scripts/services/apps/github-status.sh" "$tmpdir/scripts/services/apps/" 2>/dev/null || true
cp "$ROOT/scripts/lib/waybar-cache-helpers.sh" \
  "$ROOT/scripts/lib/waybar-settings.sh" \
  "$ROOT/scripts/lib/unicode-animations-lib.sh" \
  "$tmpdir/scripts/lib/" 2>/dev/null || true
cp "$ROOT/data/waybar-settings.json" "$tmpdir/data/" 2>/dev/null || true
cp "$ROOT/data/waybar-settings.jsonc" "$tmpdir/data/" 2>/dev/null || true
if [ ! -f "$tmpdir/data/waybar-settings.json" ] && [ -f "$tmpdir/data/waybar-settings.jsonc" ]; then
  WAYBAR_HOME="$tmpdir" WAYBAR_SCRIPTS="$tmpdir/scripts" bash "$tmpdir/scripts/lib/waybar-settings.sh" >/dev/null 2>&1 || true
fi
find "$tmpdir/scripts" -name '*.sh' -exec chmod +x {} +

# Stub package tools so updates-status can finish offline
mkdir -p "$tmpdir/bin"
cat >"$tmpdir/bin/checkupdates" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat >"$tmpdir/bin/paru" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat >"$tmpdir/bin/flatpak" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat >"$tmpdir/bin/gh" <<'EOF'
#!/usr/bin/env sh
printf '[]\n'
EOF
# updates-status signals waybar after refresh; keep hermetic
cat >"$tmpdir/scripts/lib/waybar-signal.sh" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
# timeout may be missing in stripped PATH; provide a passthrough
if ! command -v timeout >/dev/null 2>&1; then
  cat >"$tmpdir/bin/timeout" <<'EOF'
#!/usr/bin/env sh
shift
exec "$@"
EOF
fi
chmod +x "$tmpdir"/bin/* "$tmpdir/scripts/lib/waybar-signal.sh"

for script in services/i2pd/i2pd-status.sh services/sync/updates-status.sh services/apps/github-status.sh; do
  out="$(
    PATH="$tmpdir/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$tmpdir" \
    WAYBAR_HOME="$tmpdir" \
    WAYBAR_SCRIPTS="$tmpdir/scripts" \
    XDG_CACHE_HOME="$tmpdir/cache" \
    WAYBAR_BACKGROUND=1 \
    "$tmpdir/scripts/$script" --refresh 2>/dev/null | tail -n 1 || true
  )"
  if [ -z "$out" ] || ! printf '%s\n' "$out" | jq -e '.text != null and .tooltip != null and .class != null' >/dev/null 2>&1; then
    echo "FAIL: $script --refresh did not emit valid JSON under minimal PATH (shebang/settings regression). out=$out" >&2
    fail=1
  else
    echo "PASS: $script --refresh JSON smoke"
  fi
done

# Negative regression: same i2pd body with a forced sh shebang must fail under dash
neg="$tmpdir/scripts/services/i2pd/i2pd-status-forced-sh.sh"
sed '1s|.*|#!/usr/bin/env sh|' "$tmpdir/scripts/services/i2pd/i2pd-status.sh" >"$neg"
chmod +x "$neg"
neg_out="$(
  PATH="/usr/bin:/bin" HOME="$tmpdir" WAYBAR_HOME="$tmpdir" WAYBAR_SCRIPTS="$tmpdir/scripts" XDG_CACHE_HOME="$tmpdir/cache-neg" \
    dash "$neg" --refresh 2>/dev/null | tail -n 1 || true
)"
if printf '%s\n' "$neg_out" | jq -e '.text and .tooltip and .class' >/dev/null 2>&1; then
  echo "FAIL: forced-sh i2pd-status unexpectedly succeeded under dash (negative test invalid)" >&2
  fail=1
else
  echo "PASS: forced-sh i2pd-status fails under dash (documents bash shebang requirement)"
fi

# --- listener-ctl: missing script must not leave a lock / must exit cleanly ---
miss_rt=$(mktemp -d)
miss_out=$(
  XDG_RUNTIME_DIR="$miss_rt" \
    "$WAYBAR_SCRIPTS/infra/listener-ctl.sh" start "$miss_rt/no-such-listener.sh" missing-test 2>&1 || true
)
if [ -d "$miss_rt/waybar-dock-listener-missing-test.lock.d" ]; then
  echo "FAIL: listener-ctl start of missing script left a lock dir" >&2
  fail=1
else
  echo "PASS: listener-ctl start missing script is a no-op"
fi
rm -rf "$miss_rt"

# --- healthcheck: heal dead privacy listener (stub systemctl/logger + mock listener) ---
hc_rt=$(mktemp -d)
hc_bin=$(mktemp -d)
hc_home=$(mktemp -d)
mkdir -p "$hc_home/scripts/infra" "$hc_home/scripts/listeners" "$hc_home/scripts/lib"
cp "$WAYBAR_SCRIPTS/infra/listener-ctl.sh" "$WAYBAR_SCRIPTS/infra/waybar-healthcheck.sh" "$hc_home/scripts/infra/"
cp "$WAYBAR_SCRIPTS/listeners/dock-windows-listener-lock.sh" "$hc_home/scripts/listeners/"
cp "$WAYBAR_SCRIPTS/lib/compositor-session.sh" "$hc_home/scripts/lib/"
chmod +x "$hc_home/scripts/infra/"*.sh
cat >"$hc_home/scripts/listeners/privacy-listener.sh" <<'EOF'
#!/usr/bin/env sh
set -eu
: "${WAYBAR_SCRIPTS:=}"
WAYBAR_LISTENER_LOCK_NAME=privacy
. "$WAYBAR_SCRIPTS/listeners/dock-windows-listener-lock.sh"
sleep 30
EOF
chmod +x "$hc_home/scripts/listeners/privacy-listener.sh"
# Long-lived fake waybar MainPID (systemctl stub exits immediately, so $$ would be gone)
sleep 300 &
hc_waybar_pid=$!
printf '%s\n' "$hc_waybar_pid" >"$hc_bin/waybar.pid"
cat >"$hc_bin/systemctl" <<EOF
#!/usr/bin/env sh
case "\$*" in
  *is-active*waybar*) exit 0 ;;
  *show*MainPID*) cat "$hc_bin/waybar.pid" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$hc_bin/systemctl"
cat >"$hc_bin/logger" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$hc_bin/logger"
PATH="$hc_bin:/usr/bin:/bin" XDG_RUNTIME_DIR="$hc_rt" \
  WAYBAR_HOME="$hc_home" WAYBAR_SCRIPTS="$hc_home/scripts" \
  "$hc_home/scripts/infra/waybar-healthcheck.sh" >/dev/null 2>&1 || true
sleep 0.4
if [ ! -f "$hc_rt/waybar-dock-listener-privacy.lock.d/pid" ]; then
  echo "FAIL: healthcheck should start privacy listener when lock is dead" >&2
  fail=1
else
  XDG_RUNTIME_DIR="$hc_rt" "$hc_home/scripts/infra/listener-ctl.sh" stop privacy >/dev/null 2>&1 || true
  echo "PASS: healthcheck heals dead privacy listener"
fi
kill "$hc_waybar_pid" 2>/dev/null || true
rm -rf "$hc_rt" "$hc_bin" "$hc_home"

if [ "$fail" -ne 0 ]; then
  echo "FAIL: shell contract checks failed" >&2
  exit 1
fi

echo "PASS: shell contract checks"
exit 0
