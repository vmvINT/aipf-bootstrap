#!/bin/sh
# AIPF Stage 0, development candidate. No hidden auth or remote code execution.
set -eu
mode=plan
login=no
install_launcher=yes
for arg in "$@"; do
  case "$arg" in
    --plan) mode=plan ;;
    --apply) mode=apply ;;
    --login) login=yes ;;
    --skip-launcher) install_launcher=no ;;
    *) printf 'USAGE: sh aipf-setup.sh [--plan|--apply] [--login] [--skip-launcher]\n' >&2; exit 2 ;;
  esac
done
exists() { command -v "$1" >/dev/null 2>&1; }
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
printf 'AIPF Stage 0 (development) mode=%s\n' "$mode"
[ -r /etc/os-release ] || { printf 'BLOCKED_OS_UNSUPPORTED\n' >&2; exit 4; }
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) manager=apt ;;
  fedora) manager=dnf ;;
  *) printf 'BLOCKED_DISTRO_UNSUPPORTED: %s\n' "${ID:-unknown}" >&2; exit 4 ;;
esac
missing=
for tool in git curl gh; do
  if exists "$tool"; then printf 'TOOL_%s=OK\n' "$tool"
  else missing="$missing $tool"; printf 'TOOL_%s=MISSING\n' "$tool"; fi
done
if [ -n "$missing" ]; then
  if [ "$mode" = plan ]; then
    printf 'PLAN_INSTALL:%s via %s\n' "$missing" "$manager"
  else
    if [ "$(id -u)" -eq 0 ]; then
      elevate=
    elif exists sudo; then
      elevate=sudo
    else
      printf 'BLOCKED_ADMIN_REQUIRED: sudo unavailable\n' >&2; exit 4
    fi
    case "$manager" in
      apt) ${elevate:+$elevate} apt-get update && ${elevate:+$elevate} apt-get install -y $missing ;;
      dnf) ${elevate:+$elevate} dnf install -y $missing ;;
    esac
    for tool in $missing; do
      exists "$tool" || { printf 'BLOCKED_PACKAGE_UNAVAILABLE: %s\n' "$tool" >&2; exit 4; }
    done
  fi
fi
if [ "$install_launcher" = yes ]; then
  target="${AIPF_BIN_DIR:-${HOME:?}/.local/bin}"
  if [ "$mode" = plan ]; then
    printf 'PLAN_LAUNCHER: %s/aipf\n' "$target"
  else
    [ -f "$script_dir/aipf" ] || { printf 'BLOCKED_LAUNCHER_SOURCE_MISSING\n' >&2; exit 4; }
    mkdir -p "$target"
    tmp=$(mktemp "$target/.aipf.tmp.XXXXXX")
    trap 'rm -f "$tmp"' EXIT HUP INT TERM
    cat "$script_dir/aipf" > "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$target/aipf"
    trap - EXIT HUP INT TERM
    printf 'LAUNCHER_INSTALLED=%s/aipf\n' "$target"
    case ":$PATH:" in *":$target:"*) : ;; *) printf 'PATH_NOTE: add %s to PATH in a new shell\n' "$target" ;; esac
  fi
fi
if [ "$login" = yes ]; then
  if [ "$mode" = plan ]; then printf 'PLAN_AUTH: gh auth login --web\n'
  else
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then gh auth login --hostname github.com --web; fi
    gh auth setup-git
    gh auth status --hostname github.com
  fi
fi
printf 'STAGE0_%s_DONE\n' "$(if [ "$mode" = plan ]; then printf PLAN; else printf APPLY; fi)"
