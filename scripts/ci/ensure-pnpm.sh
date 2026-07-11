#!/usr/bin/env bash
# Ensure Corepack + pnpm from package.json "packageManager", then install deps.
# Sourced or executed from repo-root-aware CI helpers.
set -euo pipefail

waybar_ci_repo_root() {
  cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
}

waybar_ci_enable_corepack_pnpm() {
  if ! command -v node >/dev/null 2>&1; then
    echo "FAIL: node is required (Corepack ships with Node)" >&2
    return 1
  fi
  if command -v corepack >/dev/null 2>&1; then
    # Ignore EACCES when Corepack can't rewrite a managed prefix (e.g. vite-plus);
    # pnpm may already be on PATH from that toolchain or a prior prepare.
    corepack enable >/dev/null 2>&1 || true
    corepack prepare pnpm@11.11.0 --activate >/dev/null 2>&1 || true
  fi
  if ! command -v pnpm >/dev/null 2>&1; then
    echo "FAIL: pnpm not on PATH. Enable Corepack or install pnpm@11.11.0." >&2
    return 1
  fi
  echo "ok: pnpm $(pnpm --version) via $(command -v pnpm)"
}

waybar_ci_pnpm_install() {
  if [ ! -f pnpm-lock.yaml ]; then
    echo "FAIL: missing pnpm-lock.yaml (run: pnpm install && commit the lockfile)" >&2
    return 1
  fi
  # CI and local: reproducible installs from the lockfile.
  pnpm install --frozen-lockfile
}

# Allow `bash scripts/ci/ensure-pnpm.sh` to install for make targets.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  waybar_ci_repo_root
  waybar_ci_enable_corepack_pnpm
  waybar_ci_pnpm_install
fi
