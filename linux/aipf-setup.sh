#!/bin/sh
# AIPF Bootstrap 0 / Linux. POSIX sh; no git/gh/python prerequisite.
# Stage 0 only. Does not fetch private project code or use secrets.
set -eu
mode=plan
login=no
for arg in "$@"; do
  case "$arg" in
    --plan) mode=plan ;;
    --apply) mode=apply ;;
    --login) login=yes ;;
    *) printf 'USAGE: sh aipf-setup.sh [--plan|--apply] [--login]\n' >&2; exit 2 ;;
  esac
done
command_exists() { command -v "$1" >/dev/null 2>&1; }
printf 'AIPF Bootstrap 0 / Linux mode=%s\n' "$mode"
if [ ! -r /etc/os-release ]; then
  printf 'BLOCKED_UNSUPPORTED_OS: /etc/os-release missing\n' >&2
  exit 3
fi
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  ubuntu|debian)
    installer=apt
    ;;
  fedora)
    installer=dnf
    ;;
  *)
    printf 'BLOCKED_UNSUPPORTED_DISTRO: %s\n' "${ID:-unknown}" >&2
    exit 3
    ;;
esac
printf 'Distribution: %s (%s)\n' "${ID:-unknown}" "$installer"
missing=
for tool in git curl; do
  if command_exists "$tool"; then
    printf 'OK: %s\n' "$tool"
  else
    printf 'MISSING: %s\n' "$tool"
    missing="$missing $tool"
  fi
done
if [ -n "$missing" ]; then
  if [ "$mode" = plan ]; then
    printf 'PLAN: install prerequisites:%s (using distribution package manager with explicit admin authorization)\n' "$missing"
  else
    # Do not silently escalate privileges. Explicit root mode only.
    if [ "$(id -u)" -ne 0 ]; then
      printf 'BLOCKED_ADMIN_REQUIRED: rerun approved installer as root for system packages\n' >&2
      exit 4
    fi
    case "$installer" in
      apt) apt-get update && apt-get install -y $missing ;;
      dnf) dnf install -y $missing ;;
    esac
  fi
fi
# gh packaging/repos vary by distro; never add third-party signing keys without approval.
if command_exists gh; then
  printf 'OK: gh\n'
else
  printf 'BLOCKED_GH_NOT_INSTALLED: install verified GitHub CLI using your approved source.\n'
  if [ "$mode" = apply ]; then exit 5; fi
fi
if [ "$login" = yes ]; then
  if [ "$mode" = plan ]; then
    printf 'PLAN: gh auth login --hostname github.com --web\n'
  elif command_exists gh; then
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
      gh auth login --hostname github.com --web
    fi
    gh auth setup-git
    gh auth status --hostname github.com
  fi
fi
printf 'STAGE0_%s_DONE\n' "$(if [ "$mode" = plan ]; then printf PLAN; else printf PREREQUISITES; fi)"
printf 'NEXT: private, authenticated pinned manifest + private project installer; not part of Stage 0\n'
