#!/usr/bin/env bash
# Ensure docs/README.md lists every docs/*.md page (except itself).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INDEX="$ROOT/docs/README.md"
DOCS_DIR="$ROOT/docs"

if [[ ! -f "$INDEX" ]]; then
  echo "FAIL: missing $INDEX" >&2
  exit 1
fi

index_text=$(cat "$INDEX")
fail=0

while IFS= read -r -d '' f; do
  base=$(basename "$f")
  [[ "$base" == "README.md" ]] && continue
  # Accept ](name.md), ](./name.md), or with #fragment
  if ! grep -qE "\]\(\.?/?${base//./\\.}(#[^)]*)?\)" <<<"$index_text"; then
    echo "FAIL: docs/README.md does not link to $base" >&2
    fail=1
  else
    echo "ok index → $base"
  fi
done < <(find "$DOCS_DIR" -maxdepth 1 -type f -name '*.md' -print0 | sort -z)

# Hub should also mention root briefs + scripts README (anti-orphan).
for need in "../README.md" "../CONTRIBUTING.md" "../AGENTS.md" "../scripts/README.md"; do
  if ! grep -qF "]($need)" <<<"$index_text"; then
    echo "FAIL: docs/README.md missing link $need" >&2
    fail=1
  else
    echo "ok index → $need"
  fi
done

# Leaf docs under docs/ (except README) should point back at the hub.
while IFS= read -r -d '' f; do
  base=$(basename "$f")
  [[ "$base" == "README.md" ]] && continue
  if ! grep -qE '\]\(\.?/?README\.md\)|Documentation index|docs/README' "$f"; then
    echo "FAIL: $base does not link back to docs/README.md (hub)" >&2
    fail=1
  else
    echo "ok hub ← $base"
  fi
done < <(find "$DOCS_DIR" -maxdepth 1 -type f -name '*.md' -print0 | sort -z)

# Root briefs + scripts README should link to the docs hub.
for root_doc in AGENTS.md CONTRIBUTING.md README.md scripts/README.md; do
  path="$ROOT/$root_doc"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing $root_doc" >&2
    fail=1
    continue
  fi
  if ! grep -qE 'docs/README\.md|Documentation index' "$path"; then
    echo "FAIL: $root_doc does not link to docs/README.md" >&2
    fail=1
  else
    echo "ok hub ← $root_doc"
  fi
done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "PASS: docs index sync"
