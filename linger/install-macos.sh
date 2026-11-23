#!/bin/bash
set -euo pipefail

version=0.1.6
asset="Linger-$version-macos-arm64.dmg"
expected_sha256=509287d1a04c10969764a6a98a809b7d90ab2fe686a01ce6f2ff5a999e5c0de7
release="https://github.com/simplexai-labs/linger/releases/download/desktop-v$version"
mode=install
runtime=none
minimum_memory=0
cache_dir="$HOME/Library/Caches/linger-local-deploy"
app_dir="$HOME/Applications"
work_dir=
app_stage=
mounted=0

usage() {
  cat <<'USAGE'
Usage: bash install-macos.sh [--check [--minimum-memory-gib GiB] | --download-only]
                            [--runtime codex|claude|pi|antigravity] [--help]
Default: verify and install the pinned Linger desktop app for the current user.
--check: inventory only. Optionally fail if available unified memory is below GiB.
--download-only: cache the verified DMG without installing.
--runtime: also install the selected CLI if it is missing. Account sign-in is separate.
USAGE
}

fail() { printf '%s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|--download-only)
      [[ "$mode" == install ]] || fail 'Choose only one check or download mode.'
      mode="${1#--}"
      shift ;;
    --minimum-memory-gib)
      [[ $# -ge 2 && "$2" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail 'Specify a nonnegative number in GiB.'
      minimum_memory="$2"
      shift 2 ;;
    --runtime)
      [[ $# -ge 2 ]] || fail 'Specify a runtime name.'
      case "$2" in codex|claude|pi|antigravity) runtime="$2" ;; *) fail 'Unknown runtime.' ;; esac
      shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ "$mode" == check || "$minimum_memory" == 0 ]] || fail '--minimum-memory-gib requires --check.'
[[ "$mode" == install || "$runtime" == none ]] || fail '--runtime is available in install mode.'
[[ "$(uname -s)" == Darwin ]] || fail 'Run this script on the target Mac.'
[[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] || fail 'This release requires Apple silicon.'
os_version="$(sw_vers -productVersion)"
[[ "${os_version%%.*}" -ge 14 ]] || fail 'Linger requires macOS 14 or newer.'
[[ "$(id -u)" -ne 0 ]] || fail 'Run as your usual user, without sudo.'

if [[ "$mode" == check ]]; then
  printf 'macOS %s (build %s)\n' "$os_version" "$(sw_vers -buildVersion)"
  sysctl -n machdep.cpu.brand_string
  system_profiler SPDisplaysDataType | /usr/bin/grep -E 'Chipset Model|Metal' || true
  sysctl -n hw.memsize | awk '{ printf "Unified memory installed: %.2f GiB\n", $1 / 1073741824 }'
  df -h "$HOME"
  available_bytes="$(LC_ALL=C vm_stat | awk '
    NR == 1 { size = $8 }
    /^Pages (free|inactive|speculative):/ { pages += $NF; found++ }
    END { if (size > 0 && found == 3) printf "%.0f\n", size * pages; else exit 1 }
  ')" || fail 'Could not measure available unified memory.'
  LC_ALL=C awk -v bytes="$available_bytes" -v minimum="$minimum_memory" 'BEGIN {
    available = bytes / 1073741824
    printf "Unified memory available (vm_stat): %.2f GiB\n", available
    if (available < minimum) {
      printf "Shortfall for your plan: %.2f GiB. Release resources yourself and retry.\n", minimum - available > "/dev/stderr"
      exit 2
    }
  }'
  exit 0
fi

cleanup() {
  if [[ "$mounted" == 1 ]]; then
    if /usr/bin/hdiutil detach "$work_dir/mount" >/dev/null 2>&1; then mounted=0; fi
  fi
  if [[ -n "$app_stage" ]]; then
    rm -rf -- "$app_stage/Linger.app"
    rmdir "$app_stage" 2>/dev/null || true
  fi
  if [[ -n "$work_dir" && "$mounted" == 0 ]]; then rm -rf -- "$work_dir"; fi
}
trap cleanup EXIT
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/linger-install.XXXXXXXX")"

install_runtime() {
  local executable package
  case "$runtime" in
    none) return 0 ;;
    codex) executable=codex; package=@openai/codex ;;
    claude) executable=claude; package=@anthropic-ai/claude-code ;;
    pi) executable=pi; package=@earendil-works/pi-coding-agent ;;
    antigravity) executable=agy; package= ;;
  esac
  if command -v "$executable" >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/$executable" ]]; then
    printf 'Runtime already installed: %s\n' "$executable"
    return 0
  fi
  if [[ "$runtime" == antigravity ]]; then
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
      https://antigravity.google/cli/install.sh -o "$work_dir/antigravity-install.sh"
    /bin/bash "$work_dir/antigravity-install.sh"
  else
    command -v npm >/dev/null 2>&1 || fail 'Install Node.js with npm first, or see the runtime installation guide.'
    if [[ "$runtime" == pi ]]; then
      npm install --global --ignore-scripts --registry=https://registry.npmjs.org "$package"
    else
      npm install --global --registry=https://registry.npmjs.org "$package"
    fi
  fi
  printf 'Runtime installer finished: %s. Open a new terminal to verify the version and sign in if needed.\n' "$executable"
}

if [[ "$mode" == install ]] && { [[ -e /Applications/Linger.app || -e "$app_dir/Linger.app" ]] || pgrep -x Linger >/dev/null 2>&1; }; then
  printf 'Existing Linger detected. Open it from Applications.\n'
  install_runtime
  exit 0
fi

mkdir -p "$cache_dir"
package_path="$cache_dir/$asset"
sha256() { /usr/bin/shasum -a 256 < "$1" | awk '{print $1}'; }

if [[ ! -f "$package_path" ]] || [[ "$(sha256 "$package_path")" != "$expected_sha256" ]]; then
  partial="$(mktemp "$cache_dir/.$asset.XXXXXXXX")"
  if ! curl --fail --show-error --location --proto '=https' --proto-redir '=https' \
    --retry 3 --connect-timeout 20 "$release/$asset" -o "$partial"; then
    rm -f -- "$partial"
    fail 'Download failed. Run again to retry.'
  fi
  if [[ "$(sha256 "$partial")" != "$expected_sha256" ]]; then
    rm -f -- "$partial"
    fail 'SHA-256 mismatch. The download was discarded.'
  fi
  mv -f -- "$partial" "$package_path"
fi
[[ "$(sha256 "$package_path")" == "$expected_sha256" ]] || fail 'Cached DMG did not pass verification.'
printf 'SHA-256 verified: %s\n' "$package_path"
[[ "$mode" != download-only ]] || exit 0

mkdir -p "$app_dir" "$work_dir/mount"
/usr/bin/hdiutil attach "$package_path" -readonly -nobrowse -noautoopen -mountpoint "$work_dir/mount" >/dev/null
mounted=1
[[ -d "$work_dir/mount/Linger.app" ]] || fail 'The verified DMG does not contain Linger.app.'
app_stage="$(mktemp -d "$app_dir/.linger-stage.XXXXXXXX")"
/usr/bin/ditto "$work_dir/mount/Linger.app" "$app_stage/Linger.app"
if [[ ! -e /Applications/Linger.app ]]; then
  mv -n -- "$app_stage/Linger.app" "$app_dir/"
fi
if [[ -d "$app_stage/Linger.app" ]]; then
  printf 'Existing Linger detected during install. Open it from Applications.\n'
else
  printf 'Installed: %s\n' "$app_dir/Linger.app"
fi
/usr/bin/hdiutil detach "$work_dir/mount" >/dev/null
mounted=0
printf 'Open Linger in Finder and follow the official first-launch and setup instructions.\n'
install_runtime
