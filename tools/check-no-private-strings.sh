#!/usr/bin/env bash
# Leak gate: fails when any string matching the private pattern appears in the
# tree. Pattern lookup order: LEAK_PATTERN env, then tools/.leak-pattern in
# this checkout, then tools/.leak-pattern in the primary worktree (so a
# linked worktree inherits the maintainer's pattern; skipped for a bare common
# dir, or outside a git repo). Forks and fresh clones never receive the
# pattern; the gate then skips (not enforced) unless LEAK_CHECK_REQUIRED=1,
# which fails closed instead. A configured pattern that fails to search
# (bad regex, no repository, a tree nested in some other repository) is
# always an error, regardless of that flag. Untracked files are searched too,
# so a new file is gated before it is staged; ignored files are not.
set -euo pipefail
cd "$(dirname "$0")/.."
PATTERN="${LEAK_PATTERN:-}"
if [ -z "$PATTERN" ] && [ -f tools/.leak-pattern ]; then
  PATTERN="$(tr -d '\n' < tools/.leak-pattern)"
fi
if [ -z "$PATTERN" ]; then
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -n "$common_dir" ]; then
    common_dir="$(cd "$common_dir" && pwd -P)"
    is_bare="$(git -C "$common_dir" rev-parse --is-bare-repository 2>/dev/null || echo true)"
    if [ "$is_bare" != "true" ]; then
      primary_pattern="$(dirname "$common_dir")/tools/.leak-pattern"
      if [ -f "$primary_pattern" ] && [ "$primary_pattern" != "$(cd tools && pwd)/.leak-pattern" ]; then
        PATTERN="$(tr -d '\n' < "$primary_pattern")"
      fi
    fi
  fi
fi
if [ -z "$PATTERN" ]; then
  if [ "${LEAK_CHECK_REQUIRED:-}" = "1" ]; then
    echo "leak-check: no pattern configured (tools/.leak-pattern or LEAK_PATTERN) and LEAK_CHECK_REQUIRED=1" >&2
    exit 1
  fi
  echo "leak-check: skipped, not enforced (no pattern configured)"
  echo "leak-check: maintainers set tools/.leak-pattern (gitignored) or LEAK_PATTERN"
  exit 0
fi
# git grep searches the enclosing repository, which must be this tree
top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$top" ] || [ "$(cd "$top" && pwd -P)" != "$(pwd -P)" ]; then
  echo "leak-check: the pattern or the search failed, nothing was checked" >&2
  exit 2
fi
set +e
matches="$(git grep --untracked -n -i -E -e "$PATTERN" -- . ':(exclude)tools/check-no-private-strings.sh' ':(exclude)LICENSE' ':(exclude)packages/tabpet/LICENSE' ':(exclude)bun.lock' ':(exclude)packages/tabpet/package.json' ':(exclude)packages/tabpet/README.md' ':(exclude)README.md' ':(exclude)apps/example/README.md' ':(exclude)CHANGELOG.md' 2>/dev/null)"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "$matches"
  echo "leak-check: private identifiers found (see above)" >&2
  exit 1
elif [ "$rc" -eq 1 ]; then
  echo "leak-check: clean"
  exit 0
else
  echo "leak-check: the pattern or the search failed, nothing was checked" >&2
  exit 2
fi
