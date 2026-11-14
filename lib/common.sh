#!/usr/bin/env bash
set -Eeuo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/zbook-ultra-14-g1a-ubuntu26"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zbook-ultra-14-g1a-ubuntu26"

log() { printf '%s\n' "$*"; }
die() { printf '오류: %s\n' "$*" >&2; exit 1; }

require_ubuntu() {
  [[ $EUID != 0 ]] || die 'sudo 없이 일반 사용자로 실행하세요.'
  source /etc/os-release
  [[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 26.04 && $(dpkg --print-architecture) == amd64 ]] ||
    die 'Ubuntu 26.04 LTS amd64가 필요합니다.'
}

apt_update() {
  sudo apt-get -o APT::Update::Error-Mode=any update
}

apt_install() {
  sudo apt-get install -y --no-install-recommends --no-remove "$@"
}

# 이미 등록된 공식 소스는 기존 키 설정과 함께 유지한다.
apt_source() (
  local name="$1" uri="$2" suite="$3" key_url="$4" key_type="$5"
  local component="${6:-main}"
  local source="/etc/apt/sources.list.d/$name.sources"
  local key="/etc/apt/keyrings/$name.gpg"
  [[ $key_type != asc ]] || key="/etc/apt/keyrings/$name.asc"
  local work existing
  for existing in /etc/apt/sources.list /etc/apt/sources.list.d/*.{sources,list}; do
    [[ -r $existing && $existing != "$source" ]] || continue
    if grep -E '^[[:blank:]]*(URIs:|deb[[:blank:]])' "$existing" | grep -F -- "$uri" >/dev/null; then
      return 0
    fi
  done
  work="$(mktemp -d)"
  trap 'rm -rf -- "$work"' EXIT
  curl -fsSL "$key_url" -o "$work/key"
  if [[ $key_type == dearmor ]]; then
    gpg --batch --dearmor --output "$work/signing-key" "$work/key"
    mv -- "$work/signing-key" "$work/key"
  fi
  gpg --batch --show-keys "$work/key" >/dev/null
  sudo install -d -m 0755 /etc/apt/keyrings
  sudo install -m 0644 "$work/key" "$key"
  printf 'Types: deb\nURIs: %s\nSuites: %s\nComponents: %s\nArchitectures: amd64\nSigned-By: %s\n' \
    "$uri" "$suite" "$component" "$key" | sudo tee "$source" >/dev/null
)
