#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
worktree_parent=$(mktemp -d /tmp/aic8800-public-audit-test.XXXXXX)
worktree="$worktree_parent/tree"

cleanup() {
    git -C "$repo_root" worktree remove --force "$worktree" >/dev/null 2>&1 || true
    rm -rf -- "$worktree_parent"
}
trap cleanup EXIT

git -C "$repo_root" worktree add --detach "$worktree" HEAD >/dev/null
audit="$worktree/tools/check_public_release.sh"

expect_rejection() {
    local name=$1
    local expected=$2
    local output

    set +e
    output=$($audit --tree "$worktree" 2>&1)
    status=$?
    set -e
    if (( status == 0 )); then
        echo "ERROR: audit accepted unsafe fixture: $name" >&2
        exit 1
    fi
    if ! grep -Fq "$expected" <<<"$output"; then
        printf 'ERROR: audit rejected %s for the wrong reason:\n%s\n' \
            "$name" "$output" >&2
        exit 1
    fi
    git -C "$worktree" restore --worktree -- .
    printf 'audit_fixture=%s result=rejected\n' "$name"
}

printf '\n%s%s\n' '/home/' 'unexpected-user/private/file' >>"$worktree/README.md"
expect_rejection workstation-path 'unexpected workstation path'

printf '\ncontact: %s%s\n' 'release-owner@' 'gmail.com' >>"$worktree/README.md"
expect_rejection personal-mail 'unexpected personal-mail address'

printf '\n%s%s\n' 'github_' 'pat_0123456789abcdefghijklmnop' >>"$worktree/README.md"
expect_rejection credential 'possible credential or private key'

printf '\npersist.service.bdroid.bdaddr=%s%s\n' '02:00:' '00:00:00:01' >>"$worktree/README.md"
expect_rejection shared-bt-address 'shared Android Bluetooth address'

btsnoop_source=$(git -C "$worktree" ls-files | grep '/aic_btsnoop_net[.]c$' | head -n1)
printf '\n%s%s\n' 'AicBtsnoop' 'NetDump=true' >>"$worktree/$btsnoop_source"
expect_rejection enabled-network-snoop 'experimental Android network btsnoop is enabled'

sed -i '/EXPERIMENTAL_DIAGNOSTIC_ONLY/d' "$worktree/$btsnoop_source"
expect_rejection unmarked-network-snoop 'unmarked experimental network btsnoop source'

$audit --tree "$worktree"
echo 'public_audit_regressions=passed'
