#!/bin/sh

set -eu

REPOSITORY=${NALI_REPO:-x1t/nali}
REQUESTED_VERSION=${NALI_VERSION:-latest}
INSTALL_DIR=${NALI_INSTALL_DIR:-/usr/bin}
INSTALL_PATH=$INSTALL_DIR/nali

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Install nali from a GitHub release.

Usage:
  install.sh [options]
  install.sh uninstall

Options:
  --version VERSION  Install a specific release tag, for example v0.8.1
  --repo OWNER/REPO  Install from another GitHub repository
  --install-dir DIR  Install into DIR instead of /usr/bin
  -h, --help         Show this help

Environment:
  NALI_VERSION       Same as --version
  NALI_REPO          Same as --repo
  NALI_INSTALL_DIR   Same as --install-dir
EOF
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

download_to() {
    url=$1
    destination=$2

    if has_command curl; then
        curl -fsSL --retry 3 --connect-timeout 10 --max-time 300 \
            -o "$destination" "$url"
    elif has_command wget; then
        wget -q -O "$destination" "$url"
    else
        die 'curl or wget is required'
    fi
}

download_text() {
    url=$1

    if has_command curl; then
        curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 \
            -H 'Accept: application/vnd.github+json' \
            -H 'User-Agent: nali-installer' "$url"
    elif has_command wget; then
        wget -q -O - "$url"
    else
        die 'curl or wget is required'
    fi
}

checksum() {
    file=$1

    if has_command sha256sum; then
        sha256sum "$file" | sed 's/[[:space:]].*$//'
    elif has_command shasum; then
        shasum -a 256 "$file" | sed 's/[[:space:]].*$//'
    else
        die 'sha256sum or shasum is required to verify the release'
    fi
}

run_privileged() {
    if [ "$(id -u)" -eq 0 ] || [ -w "$INSTALL_DIR" ]; then
        "$@"
    elif has_command sudo; then
        sudo "$@"
    else
        die "write access to $INSTALL_DIR is required; run as root or install sudo"
    fi
}

validate_repository() {
    case $REPOSITORY in
        */*/*|/*|*/|*[!A-Za-z0-9_./-]*)
            die "invalid repository: $REPOSITORY (expected OWNER/REPO)"
            ;;
    esac
}

normalize_version() {
    version=$1

    case $version in
        v*) ;;
        *) version=v$version ;;
    esac

    case $version in
        v|*[!A-Za-z0-9._-]*)
            die "invalid release version: $version"
            ;;
    esac

    printf '%s\n' "$version"
}

detect_platform() {
    [ "$(uname -s)" = Linux ] || die 'only Linux is supported'

    case $(uname -m) in
        x86_64|amd64)
            printf '%s\n' linux-amd64
            ;;
        aarch64|arm64)
            printf '%s\n' linux-armv8
            ;;
        *)
            die "unsupported architecture: $(uname -m); supported architectures are amd64 and arm64"
            ;;
    esac
}

uninstall() {
    [ -d "$INSTALL_DIR" ] || die "install directory does not exist: $INSTALL_DIR"

    if [ ! -e "$INSTALL_PATH" ]; then
        printf 'nali is not installed at %s\n' "$INSTALL_PATH"
        return 0
    fi

    run_privileged rm -f "$INSTALL_PATH"
    printf 'removed %s\n' "$INSTALL_PATH"
}

install_nali() {
    validate_repository
    has_command uname || die 'uname is required'
    has_command gzip || die 'gzip is required'
    has_command install || die 'install is required'
    has_command mktemp || die 'mktemp is required'
    [ -d "$INSTALL_DIR" ] || die "install directory does not exist: $INSTALL_DIR"

    platform=$(detect_platform)

    if [ "$REQUESTED_VERSION" = latest ] || [ -z "$REQUESTED_VERSION" ]; then
        release_json=$(download_text "https://api.github.com/repos/$REPOSITORY/releases/latest") \
            || die "could not find a published release for $REPOSITORY"
        version=$(printf '%s\n' "$release_json" |
            sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
            head -n 1)
        [ -n "$version" ] || die "could not determine the latest release for $REPOSITORY"
        version=$(normalize_version "$version")
    else
        version=$(normalize_version "$REQUESTED_VERSION")
    fi

    asset="nali-$platform-$version.gz"
    base_url="https://github.com/$REPOSITORY/releases/download/$version"
    checksum_file=$asset.sha256
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/nali-install.XXXXXX") \
        || die 'could not create a temporary directory'

    cleanup() {
        rm -rf "$tmp_dir"
    }
    trap cleanup 0 1 2 3 15

    archive_path=$tmp_dir/$asset
    checksum_path=$tmp_dir/$checksum_file
    binary_path=$tmp_dir/nali

    printf 'downloading %s/%s\n' "$REPOSITORY" "$version"
    download_to "$base_url/$asset" "$archive_path" \
        || die "failed to download $asset"
    download_to "$base_url/$checksum_file" "$checksum_path" \
        || die "failed to download $checksum_file"

    expected_checksum=$(sed -n '1s/[[:space:]].*$//p' "$checksum_path")
    actual_checksum=$(checksum "$archive_path")
    [ "$expected_checksum" = "$actual_checksum" ] \
        || die "checksum verification failed for $asset"

    gzip -dc "$archive_path" > "$binary_path" \
        || die "failed to decompress $asset"
    [ -s "$binary_path" ] || die 'the downloaded binary is empty'
    chmod 0755 "$binary_path"

    run_privileged install -m 0755 "$binary_path" "$INSTALL_PATH"
    printf 'installed %s\n' "$INSTALL_PATH"
}

command=install
while [ "$#" -gt 0 ]; do
    case $1 in
        uninstall|remove|--uninstall)
            command=uninstall
            shift
            ;;
        --version)
            [ "$#" -ge 2 ] || die '--version requires a value'
            REQUESTED_VERSION=$2
            shift 2
            ;;
        --repo)
            [ "$#" -ge 2 ] || die '--repo requires a value'
            REPOSITORY=$2
            shift 2
            ;;
        --install-dir)
            [ "$#" -ge 2 ] || die '--install-dir requires a value'
            INSTALL_DIR=$2
            INSTALL_PATH=$INSTALL_DIR/nali
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

if [ "$command" = uninstall ]; then
    uninstall
else
    install_nali
fi
