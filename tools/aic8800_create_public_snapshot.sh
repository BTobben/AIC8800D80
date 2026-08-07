#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tools/aic8800_create_public_snapshot.sh --output-dir NEW_DIRECTORY

Create a new one-commit Git repository from the current committed tree. No
private development history, untracked files, generated packages, or MCU1
firmware blobs are copied. Tracked files remain included even when a broad
.gitignore pattern also matches their names. The source worktree must be clean.
EOF
}

output_dir=''
while (( $# )); do
    case "$1" in
        --output-dir)
            (( $# >= 2 )) || { echo "ERROR: --output-dir requires a value" >&2; exit 2; }
            output_dir=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$output_dir" ]]; then
    echo "ERROR: --output-dir is required" >&2
    exit 2
fi
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    echo "ERROR: source worktree must be clean before creating a public snapshot" >&2
    exit 4
fi

"$script_dir/check_public_release.sh" --tree "$repo_root"

resolved_output=$(realpath -m -- "$output_dir")
output_parent=$(dirname -- "$resolved_output")
if [[ -e "$resolved_output" ]]; then
    echo "ERROR: output path already exists: $resolved_output" >&2
    exit 3
fi
mkdir -p -- "$output_parent"
staging_dir=$(mktemp -d "$output_parent/.aic8800-public.XXXXXX")
cleanup() {
    if [[ -n "${staging_dir:-}" && -d "$staging_dir" ]]; then
        rm -rf -- "$staging_dir"
    fi
}
trap cleanup EXIT

git -C "$repo_root" archive --format=tar HEAD | tar -xf - -C "$staging_dir"
git -C "$staging_dir" init -b main
git -C "$staging_dir" config user.name "BTobben"
git -C "$staging_dir" config user.email \
    "46655663+BTobben@users.noreply.github.com"
git -C "$staging_dir" add --force --all
if ! diff -u \
    <(git -C "$repo_root" ls-tree -r --name-only HEAD | sort) \
    <(git -C "$staging_dir" ls-files | sort); then
    echo "ERROR: snapshot file manifest differs from the committed source tree" >&2
    exit 5
fi
git -C "$staging_dir" commit -m "Initial public AIC8800D80 Linux release"

"$staging_dir/tools/check_public_release.sh" --tree "$staging_dir" --history
mv -- "$staging_dir" "$resolved_output"
staging_dir=''

printf 'public_snapshot=%s\n' "$resolved_output"
git -C "$resolved_output" log -1 \
    --format='commit=%H%nauthor=%an <%ae>%nsubject=%s'
