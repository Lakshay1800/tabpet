#!/usr/bin/env bash
# Leak gate: fails when any string matching the private pattern appears in the
# tree. The pattern itself lives outside the tree: tools/.leak-pattern
# (gitignored) for local runs, the LEAK_PATTERN secret in CI. No pattern is a
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."
PATTERN="${LEAK_PATTERN:-}"
if [ -z "$PATTERN" ] && [ -f tools/.leak-pattern ]; then
  PATTERN="$(tr -d '\n' < tools/.leak-pattern)"
fi
if [ -z "$PATTERN" ]; then
  echo "leak-check: no pattern configured (tools/.leak-pattern or LEAK_PATTERN)" >&2
  exit 1
fi
if git grep -n -i -E "$PATTERN" -- . ':(exclude)tools/check-no-private-strings.sh' ':(exclude)LICENSE' ':(exclude)packages/tabpet/LICENSE' ':(exclude)bun.lock' ':(exclude)packages/tabpet/package.json' ':(exclude)packages/tabpet/README.md' ':(exclude)README.md' ':(exclude)apps/example/README.md' ':(exclude)CHANGELOG.md'; then
  echo "leak-check: private identifiers found (see above)" >&2
  exit 1
fi
echo "leak-check: clean"
