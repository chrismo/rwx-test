#!/usr/bin/env bash
# Run the RWX integration tests.
#
#   test/run.sh              # every validated case
#   test/run.sh 05 06        # just those cases
#
# Each case starts real RWX runs and costs real compute. Nothing here executes
# on push — see README for how spend is contained.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v super >/dev/null 2>&1; then
  echo "super (SuperDB) is required for assertions: https://superdb.org" >&2
  exit 1
fi
if ! rwx whoami >/dev/null 2>&1; then
  echo "not signed in to RWX — run 'rwx login'" >&2
  exit 1
fi

shopt -s nullglob
cases=()
if [[ $# -gt 0 ]]; then
  for want in "$@"; do
    for f in test/cases/"$want"-*.sh; do cases+=("$f"); done
  done
else
  cases=(test/cases/*.sh)
fi

if [[ ${#cases[@]} -eq 0 ]]; then
  echo "no matching cases" >&2
  exit 1
fi

failed=()
for c in "${cases[@]}"; do
  bash "$c" || failed+=("$c")
done

echo
if [[ ${#failed[@]} -eq 0 ]]; then
  printf '\033[32mall cases passed\033[0m\n'
else
  printf '\033[31mfailed cases:\033[0m\n'
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
