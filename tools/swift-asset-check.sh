#!/usr/bin/env bash
# swift-asset-check.sh - proves the Swift animal targets' sprite sheets and
# license copies are byte-identical to packages/tabpet/assets/, in both
# directions, that each sheet lives in exactly the one animal folder its own
# filename names, and that Package.swift never declares an asset as
# `.process` (only `.copy` is allowed). Runs cheap (no macOS, no
# Xcode) so it lives in the ubuntu `check` job. See CONTRIBUTING's "Adding an
# animal" step 7.
#
# Exit 0: clean. Exit 1: drift found (one line per problem, printed before
# exiting). Exit 2: the check itself could not run (a required file or
# directory is missing, or there was nothing to check).
set -euo pipefail
cd "$(dirname "$0")/.."

ASSETS_DIR="packages/tabpet/assets"
SWIFT_SOURCES="swift/Sources"
ORIGINAL_LICENSE="$ASSETS_DIR/LICENSE-ART.md"
PACKAGE_MANIFEST="Package.swift"

if [ ! -d "$ASSETS_DIR" ]; then
  echo "swift-asset-check: $ASSETS_DIR not found" >&2
  exit 2
fi
if [ ! -d "$SWIFT_SOURCES" ]; then
  echo "swift-asset-check: $SWIFT_SOURCES not found" >&2
  exit 2
fi
if [ ! -f "$ORIGINAL_LICENSE" ]; then
  echo "swift-asset-check: $ORIGINAL_LICENSE not found" >&2
  exit 2
fi
if [ ! -f "$PACKAGE_MANIFEST" ]; then
  echo "swift-asset-check: $PACKAGE_MANIFEST not found" >&2
  exit 2
fi

shopt -s nullglob
asset_sheets=("$ASSETS_DIR"/*-sprite.png)
if [ "${#asset_sheets[@]}" -eq 0 ]; then
  echo "swift-asset-check: $ASSETS_DIR holds no sheet at all - this check found nothing to check" >&2
  exit 2
fi

problems=0
report() {
  echo "swift-asset-check: $1"
  problems=$((problems + 1))
}

# Package.swift must never declare an asset as .process - only .copy proves
# byte identity through the build. Matches any ".process" call at all
# (optional space, then an opening paren) regardless of its arguments, so a
# second positional argument (e.g. localization:) or a bare folder name can't
# dodge the check.
if grep -nE '\.process[[:space:]]*\(' "$PACKAGE_MANIFEST"; then
  report "$PACKAGE_MANIFEST declares an asset as .process - assets must be .copy"
fi

# folder name an id must live in: TabPetAnimal<Name>, lowercased Name == id
expected_dir_for() {
  local id="$1"
  local first rest
  first="$(printf '%s' "$id" | cut -c1 | tr '[:lower:]' '[:upper:]')"
  rest="$(printf '%s' "$id" | cut -c2-)"
  printf 'TabPetAnimal%s%s' "$first" "$rest"
}

# every asset sheet has exactly one Swift copy, and it lives in the one
# folder its own "<id>-<pose>-sprite.png" filename names - not merely
# anywhere under TabPetAnimal*/.
for asset in "${asset_sheets[@]}"; do
  name="$(basename "$asset")"
  base="${name%-sprite.png}"
  id="${base%-*}"
  expected_dir="$(expected_dir_for "$id")"
  expected_copy="$SWIFT_SOURCES/$expected_dir/$name"

  matches=()
  while IFS= read -r -d '' candidate; do
    matches+=("$candidate")
  done < <(find "$SWIFT_SOURCES" -mindepth 2 -maxdepth 2 -path "$SWIFT_SOURCES/TabPetAnimal*/$name" -print0)

  if [ "${#matches[@]}" -eq 0 ]; then
    report "$name: in $ASSETS_DIR but no Swift copy under $SWIFT_SOURCES/$expected_dir/"
    continue
  fi
  if [ "${#matches[@]}" -gt 1 ]; then
    report "$name: found in more than one Swift animal folder: ${matches[*]}"
  fi
  for copy in "${matches[@]}"; do
    if [ "$copy" != "$expected_copy" ]; then
      report "$copy: \"$name\" names id \"$id\", whose only valid home is $SWIFT_SOURCES/$expected_dir/"
      continue
    fi
    if ! cmp -s "$asset" "$copy"; then
      report "$copy: differs from $asset (cmp)"
    fi
  done
done

# every swift copy has a matching original
while IFS= read -r -d '' copy; do
  name="$(basename "$copy")"
  if [ ! -f "$ASSETS_DIR/$name" ]; then
    report "$copy: no matching original at $ASSETS_DIR/$name"
  fi
done < <(find "$SWIFT_SOURCES" -mindepth 2 -maxdepth 2 -path "$SWIFT_SOURCES/TabPetAnimal*/*-sprite.png" -print0)

# the umbrella folder is a bundle of the six targets, not a seventh animal -
# it must hold no sheet of its own
umbrella_sheets=("$SWIFT_SOURCES/TabPetAnimals"/*-sprite.png)
if [ "${#umbrella_sheets[@]}" -gt 0 ]; then
  report "$SWIFT_SOURCES/TabPetAnimals/ holds a sheet - sheets belong in the per-animal folder only: ${umbrella_sheets[*]}"
fi

# every animal folder has a license copy, byte-identical to the original
while IFS= read -r -d '' dir; do
  animal_dir="$(basename "$dir")"
  if [ "$animal_dir" = "TabPetAnimals" ]; then
    continue
  fi
  license="$dir/LICENSE-ART.md"
  if [ ! -f "$license" ]; then
    report "$dir: no LICENSE-ART.md copy"
    continue
  fi
  if ! cmp -s "$ORIGINAL_LICENSE" "$license"; then
    report "$license: differs from $ORIGINAL_LICENSE (cmp)"
  fi
done < <(find "$SWIFT_SOURCES" -mindepth 1 -maxdepth 1 -type d -name 'TabPetAnimal*' -print0)

if [ "$problems" -gt 0 ]; then
  echo "swift-asset-check: $problems problem(s) found" >&2
  exit 1
fi
echo "swift-asset-check: clean"
