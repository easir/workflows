#!/usr/bin/env bash
#
# Fail when a submodule points somewhere the repository itself does not agree with.
#
#   check-submodules.sh [path]            compare composer.lock against the recorded pointers
#   check-submodules.sh --local [path]    also check the working copy (detached HEAD, wrong branch)
#
# The lock check is the one that belongs in CI: composer installs easir/* from the
# reference written in composer.lock, not from the submodule pointer, so the two
# drifting apart means CI resolves a different commit than the one under modules/.
#
# --local only makes sense in a developer checkout. CI always checks out the recorded
# pointer in a detached HEAD, so there is nothing for it to find there.

set -uo pipefail

local_checks=false
if [ "${1:-}" = "--local" ]; then
    local_checks=true
    shift
fi

cd "${1:-.}" || exit 2

fail() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        printf '::error::%s\n' "$1"
    else
        printf 'error: %s\n' "$1" >&2
    fi
}

warn() {
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        printf '::warning::%s\n' "$1"
    else
        printf 'warning: %s\n' "$1" >&2
    fi
}

package_name() {
    local url=${1%.git}
    url=${url%/}
    local name owner
    name=$(basename "$url")
    owner=$(basename "$(dirname "$url")")
    owner=${owner##*:}
    printf '%s/%s' "$owner" "$name"
}

lock_reference() {
    PACKAGE="$1" python3 -c '
import json, os, sys

package = os.environ["PACKAGE"].lower()
with open("composer.lock") as handle:
    lock = json.load(handle)

for entry in lock.get("packages", []) + lock.get("packages-dev", []):
    if entry["name"].lower() == package:
        print(entry.get("source", {}).get("reference", ""))
        sys.exit(0)
'
}

if [ ! -f .gitmodules ]; then
    echo "no .gitmodules, nothing to check"
    exit 0
fi

status=0
checked=0

while read -r path; do
    url=$(git config -f .gitmodules --get "submodule.$path.url") || continue
    pointer=$(git ls-tree HEAD "$path" | awk '{print $3}')
    if [ -z "$pointer" ]; then
        warn "$path is declared in .gitmodules but not committed as a submodule, the declaration is stale"
        continue
    fi

    if [ -f composer.lock ]; then
        package=$(package_name "$url")
        reference=$(lock_reference "$package")
        if [ -n "$reference" ]; then
            checked=$((checked + 1))
            if [ "$pointer" != "$reference" ]; then
                fail "$path: composer.lock has $package at ${reference:0:12}, the submodule points at ${pointer:0:12}. Run: composer update $package --no-install"
                status=1
            fi
        fi
    fi

    if [ "$local_checks" != true ]; then
        continue
    fi

    [ -d "$path/.git" ] || [ -f "$path/.git" ] || continue

    head=$(git -C "$path" rev-parse HEAD 2>/dev/null) || continue
    if [ "$head" != "$pointer" ]; then
        fail "$path: checked out at ${head:0:12}, the parent records ${pointer:0:12}. Run: git submodule update --init $path"
        status=1
    fi

    branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)
    declared=$(git config -f .gitmodules --get "submodule.$path.branch" || true)
    if [ "$branch" = "HEAD" ]; then
        fail "$path: detached HEAD, composer reads local branches only and will resolve the wrong metadata"
        status=1
    elif [ -n "$declared" ] && [ "$branch" != "$declared" ]; then
        fail "$path: on branch $branch, .gitmodules declares $declared"
        status=1
    fi
done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')

if [ "$status" -eq 0 ]; then
    echo "submodules agree with composer.lock ($checked checked)"
fi

exit "$status"
