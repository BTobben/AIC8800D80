#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tools/check_public_release.sh [--tree [DIRECTORY]] [--history]

--tree checks the current publication tree for private MCU1 blobs, local paths,
       package artifacts, and common high-confidence credential formats.
--history additionally requires a Git repository whose complete reachable
          history contains neither MCU1 blobs nor unexpected author/committer
          metadata.
EOF
}

check_tree=0
check_history=0
tree_root=''
while (( $# )); do
    case "$1" in
        --tree)
            check_tree=1
            if (( $# >= 2 )) && [[ ${2:-} != --* ]]; then
                tree_root=$2
                shift 2
            else
                shift
            fi
            ;;
        --history)
            check_history=1
            shift
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

if (( ! check_tree && ! check_history )); then
    check_tree=1
fi

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)
if [[ -z "$tree_root" ]]; then
    tree_root=$repo_root
fi
tree_root=$(realpath -e -- "$tree_root")

if (( check_tree )); then
    if git -C "$tree_root" rev-parse --show-toplevel >/dev/null 2>&1; then
        mapfile -t firmware_blobs < <(
            git -C "$tree_root" ls-files '*_mcu1.bin'
        )
        mapfile -t package_artifacts < <(
            git -C "$tree_root" ls-files '*.pkg.tar.*' '*.deb'
        )
    else
        mapfile -t firmware_blobs < <(
            find "$tree_root" -type f -name '*_mcu1.bin' -print
        )
        mapfile -t package_artifacts < <(
            find "$tree_root" -type f \( -name '*.pkg.tar.*' -o -name '*.deb' \) -print
        )
    fi
    if (( ${#firmware_blobs[@]} )); then
        printf 'ERROR: private MCU1 firmware blob in publication tree: %s\n' \
            "${firmware_blobs[@]}" >&2
        exit 10
    fi

    if (( ${#package_artifacts[@]} )); then
        printf 'ERROR: generated package in publication tree: %s\n' \
            "${package_artifacts[@]}" >&2
        exit 11
    fi

    # Scan the complete inherited tree for high-confidence additions while
    # preserving the two known vendor workstation paths and one attribution
    # address already present in the imported SDK. Any new identity fails.
    if git -C "$tree_root" grep -I -n -E \
        'gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' \
        -- . ':!tools/check_public_release.sh' 2>/dev/null; then
        echo "ERROR: possible credential or private key in complete publication tree" >&2
        exit 12
    fi

    if git -C "$tree_root" grep -I -n -E \
        '/(home|Users)/[^/[:space:]]+/|[A-Za-z]:\\Users\\[^\\[:space:]]+\\|\.codex/(attachments|visualizations)/' \
        -- . ':!tools/check_public_release.sh' 2>/dev/null \
        | grep -Ev '/home/(yaya|aiden)/'; then
        echo "ERROR: unexpected workstation path in complete publication tree" >&2
        exit 12
    fi

    if git -C "$tree_root" grep -I -n -E \
        '[[:alnum:]._%+-]+@(gmail|outlook|hotmail|icloud|protonmail)[.]com' \
        -- . ':!tools/check_public_release.sh' 2>/dev/null \
        | grep -Fiv 'ek9852@gmail.com'; then
        echo "ERROR: unexpected personal-mail address in complete publication tree" >&2
        exit 12
    fi

    if git -C "$tree_root" grep -I -n -E \
        'persist[.]service[.]bdroid[.]bdaddr[[:space:]]*=[[:space:]]*([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}' \
        -- . ':!tools/check_public_release.sh' 2>/dev/null; then
        echo "ERROR: shared Android Bluetooth address in publication tree" >&2
        exit 12
    fi

    if git -C "$tree_root" grep -I -n -E \
        'AicBtsnoopNetDump[[:space:]]*=[[:space:]]*true' -- src 2>/dev/null; then
        echo "ERROR: experimental Android network btsnoop is enabled by default" >&2
        exit 12
    fi

    mapfile -t btsnoop_sources < <(
        git -C "$tree_root" ls-files | grep '/aic_btsnoop_net[.]c$' || true
    )
    for source in "${btsnoop_sources[@]}"; do
        if ! grep -Fq 'EXPERIMENTAL_DIAGNOSTIC_ONLY' "$tree_root/$source"; then
            echo "ERROR: unmarked experimental network btsnoop source: $source" >&2
            exit 12
        fi
    done

    audit_paths=(README.md SECURITY.md docs tools firmware packaging .github debian/control)
    if git -C "$tree_root" grep -I -n -E \
        '/(home|Users)/[^/[:space:]]+/|[A-Za-z]:\\Users\\[^\\[:space:]]+\\|\.codex/(attachments|visualizations)/' -- \
        "${audit_paths[@]}" ':!tools/check_public_release.sh' 2>/dev/null; then
        echo "ERROR: workstation-specific path in publication tree" >&2
        exit 12
    fi

    if git -C "$tree_root" grep -I -n -E \
        'gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' \
        -- "${audit_paths[@]}" ':!tools/check_public_release.sh' 2>/dev/null; then
        echo "ERROR: possible credential or private key in publication tree" >&2
        exit 13
    fi

    if git -C "$tree_root" grep -I -n -E \
        '[[:alnum:]._%+-]+@(gmail|outlook|hotmail|icloud|protonmail)[.]com' -- \
        "${audit_paths[@]}" ':!tools/check_public_release.sh' 2>/dev/null; then
        echo "ERROR: personal-mail provider address in publication tree" >&2
        exit 13
    fi

    if git -C "$tree_root" grep -I -n -E \
        '(^|[^[:xdigit:]])([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}([^[:xdigit:]]|$)|(^|[^0-9])((25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})[.]){3}(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})([^0-9]|$)' -- \
        README.md SECURITY.md docs tools firmware packaging .github 2>/dev/null; then
        echo "ERROR: network address in project-owned publication content" >&2
        exit 13
    fi

    if git -C "$tree_root" grep -I -n -E \
        'logs/[0-9]{8}-[0-9]{6}|kernel[^\n]*[0-9]+[.][0-9]+[.][0-9]+[^[:space:]]*|https?://[^[:space:]]*(amazon|aliexpress)[.]' -- \
        README.md SECURITY.md docs tools firmware packaging .github 2>/dev/null; then
        echo "ERROR: host fingerprint or retail tracking reference in publication content" >&2
        exit 13
    fi

    if git -C "$tree_root" grep -I -n -E \
        '@users[.]noreply[.]github[.]com' -- \
        README.md SECURITY.md docs tools firmware packaging .github debian/control \
        ':!tools/check_public_release.sh' \
        2>/dev/null \
        | grep -Fv -e '46655663+BTobben@users.noreply.github.com' \
                    -e '41898282+github-actions[bot]@users.noreply.github.com'; then
        echo "ERROR: unexpected GitHub noreply identity in project-owned content" >&2
        exit 13
    fi

    if ! grep -Fxq \
        'Maintainer: BTobben <46655663+BTobben@users.noreply.github.com>' \
        "$tree_root/debian/control"; then
        echo "ERROR: Debian maintainer identity must use the GitHub account and noreply address" >&2
        exit 13
    fi

    if grep -En 'src/USB/driver_fw/fw|/usr/lib/firmware' \
        "$tree_root/packaging/arch/aic8800-usb-dkms/PKGBUILD"; then
        echo "ERROR: public driver package must not bundle firmware" >&2
        exit 14
    fi

    manifest="$tree_root/firmware/aic8800d80-mcu1.manifest"
    if [[ ! -f "$manifest" ]]; then
        echo "ERROR: MCU1 hash manifest is missing" >&2
        exit 15
    fi
    manifest_records=$(awk 'NF && $1 !~ /^#/ {count++} END {print count+0}' "$manifest")
    if [[ "$manifest_records" != 5 ]]; then
        echo "ERROR: MCU1 manifest must contain exactly five artifacts" >&2
        exit 15
    fi

    fetcher="$tree_root/tools/aic8800_fetch_mcu1_firmware.sh"
    pinned_commit='fffad12a26ba562435783e1be855736e1dec8c1b'
    if [[ ! -x "$fetcher" ]] || ! grep -Fq \
        "readonly upstream_commit='$pinned_commit'" "$fetcher"; then
        echo "ERROR: MCU1 fetcher is missing or does not pin the reviewed commit" >&2
        exit 16
    fi
    if ! grep -Fq 'upstream_raw_base="https://raw.githubusercontent.com/shenmintao/aic8800d80/${upstream_commit}/fw/aic8800D80"' \
        "$fetcher"; then
        echo "ERROR: MCU1 fetcher does not use the reviewed upstream path" >&2
        exit 16
    fi
    if grep -En 'raw\.githubusercontent\.com/[^/]+/[^/]+/(main|legacy-mcu1)/' \
        "$fetcher"; then
        echo "ERROR: MCU1 fetcher must not follow a moving branch" >&2
        exit 16
    fi
    if git -C "$tree_root" grep -I -n -F \
        'aic8800_fetch_mcu1_firmware.sh' -- .github 2>/dev/null; then
        echo "ERROR: CI and release automation must not fetch MCU1 firmware" >&2
        exit 17
    fi

    echo "public_tree_audit=passed"
fi

if (( check_history )); then
    if [[ ! -d "$repo_root/.git" ]]; then
        echo "ERROR: --history requires a non-bare Git checkout" >&2
        exit 20
    fi

    if git -C "$repo_root" rev-list --objects --all \
        | awk '{print $2}' | grep -Eq '(^|/)[^/]*_mcu1\.bin$'; then
        echo "ERROR: MCU1 firmware remains in reachable Git history" >&2
        exit 21
    fi

    metadata_error=0
    while IFS=$'\t' read -r author_name author_email committer_name committer_email; do
        case "$author_email" in
            *@users.noreply.github.com|noreply@github.com) ;;
            *) metadata_error=1 ;;
        esac
        case "$committer_email" in
            *@users.noreply.github.com|noreply@github.com) ;;
            *) metadata_error=1 ;;
        esac
    done < <(git -C "$repo_root" log --all \
        --format='%an%x09%ae%x09%cn%x09%ce')
    if (( metadata_error )); then
        echo "ERROR: Git history contains unexpected identity metadata" >&2
        exit 22
    fi

    echo "public_history_audit=passed"
fi
