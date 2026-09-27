#!/usr/bin/env bash
# swift-isolation-check.sh - proves "importing one animal never bundles the
# others" beyond the day it's written. Reads `swift package describe --type
# json` and fails if:
#   1. no non-animal, non-umbrella target exists to guard at all (the guard
#      can't run, which is a failure, not a silent skip);
#   2. any such guarded target (TabPetCore, TabPetUIKit, and whatever is
#      added later - never a hardcoded name) has a TabPetAnimal* target
#      anywhere in its dependency closure;
#   3. any TabPetAnimal* target depends on anything other than TabPetCore;
#   4. any product except the umbrella - an animal product, TabPetCore's own
#      product, TabPetUIKit's, or a later one - lists, or depends through its
#      targets' own dependency closures on, an animal target other than its
#      own single animal target (a non-animal product allows none at all).
#      This is the one a product manifest can smuggle an extra animal
#      through even when every target's own dependencies are clean.
# Runs in the macOS `swift` CI job (needs the swift toolchain).
set -euo pipefail
cd "$(dirname "$0")/.."

DESCRIBE_JSON="$(mktemp "${TMPDIR:-/tmp}/swift-isolation-check.XXXXXX.json")"
trap 'rm -f "$DESCRIBE_JSON"' EXIT
swift package describe --type json > "$DESCRIBE_JSON"

python3 - "$DESCRIBE_JSON" <<'PYEOF'
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)
targets = {t["name"]: t for t in data["targets"]}
products = {p["name"]: p for p in data.get("products", [])}


def deps(name):
    t = targets.get(name, {})
    return list(t.get("target_dependencies") or []) + list(t.get("product_dependencies") or [])


def closure(name):
    seen = set()
    stack = list(deps(name))
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        seen.add(n)
        stack.extend(deps(n))
    return seen


UMBRELLA = "TabPetAnimals"


def is_animal_target(name):
    return name.startswith("TabPetAnimal") and name != UMBRELLA and not name.endswith("Tests")


problems = []

# guard every target that is not an animal target and not the umbrella -
# computed from what's actually in the manifest, never a hardcoded name list,
# so a target added later (a "TabPetWidgets" alongside TabPetCore) is guarded
# without anyone editing this script.
guarded_targets = [
    name for name in targets if not is_animal_target(name) and name != UMBRELLA and not name.endswith("Tests")
]
if not guarded_targets:
    problems.append("no non-animal, non-umbrella target found in the package description - the isolation guard did not run")
for guarded in guarded_targets:
    animals_in_closure = [n for n in closure(guarded) if is_animal_target(n)]
    if animals_in_closure:
        problems.append(
            f"{guarded}: TabPetAnimal* target(s) in its dependency closure: {sorted(animals_in_closure)}"
        )

for name in targets:
    if not is_animal_target(name):
        continue
    d = deps(name)
    if d != ["TabPetCore"]:
        problems.append(f"{name}: depends on {sorted(d)}, want exactly ['TabPetCore']")

# every product except the umbrella must list, and depend through its
# targets' own closures on, no animal target beyond its own single one (a
# non-animal product's own animal allowance is empty) - this is the check a
# product manifest can dodge even when every target's own dependencies are
# clean, e.g. a product that simply lists two targets side by side.
for name, product in products.items():
    if name == UMBRELLA:
        continue
    product_targets = product.get("targets") or []
    own_animal = name if is_animal_target(name) else None
    if own_animal is not None and product_targets != [own_animal]:
        problems.append(f"product {name}: lists targets {sorted(product_targets)}, want exactly ['{own_animal}']")
    reachable = set(product_targets)
    for t in product_targets:
        reachable |= closure(t)
    smuggled = sorted(a for a in reachable if is_animal_target(a) and a != own_animal)
    if smuggled:
        problems.append(f"product {name}: pulls in animal target(s) other than its own: {smuggled}")

if problems:
    for p in problems:
        print(f"swift-isolation-check: {p}")
    sys.exit(1)
print("swift-isolation-check: clean")
PYEOF
