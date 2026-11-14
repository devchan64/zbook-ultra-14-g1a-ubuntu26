#!/usr/bin/env bash
set -Eeuo pipefail

main() (
  [[ $# == 0 || ( $# == 1 && $1 == --docker ) ]] || die '사용법: install.sh dev [--docker]'
  apt_update
  apt_install ca-certificates curl gpg git build-essential pkg-config python3.14-venv nodejs npm snapd

  apt_source github-cli https://cli.github.com/packages stable \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg gpg
  if [[ $# == 1 ]]; then
    apt_source docker https://download.docker.com/linux/ubuntu resolute \
      https://download.docker.com/linux/ubuntu/gpg asc stable
  fi

  apt_update
  apt_install gh
  if ! snap list code >/dev/null 2>&1; then
    if [[ $(dpkg-query -W -f='${db:Status-Status}' code 2>/dev/null || true) == installed ]]; then
      die 'APT로 설치된 VS Code가 있습니다. 제거한 후 다시 실행하세요.'
    fi
    sudo snap install code --classic
  fi
  if [[ $# == 1 ]]; then
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    local username
    username="$(id -un)"
    getent group docker >/dev/null || die 'docker 그룹을 찾을 수 없습니다.'
    if ! id -nG "$username" | tr ' ' '\n' | grep -Fxq docker; then
      sudo usermod -aG docker "$username"
    fi
    sudo -u "$username" -- docker info
    if ! id -nG | tr ' ' '\n' | grep -Fxq docker; then
      log '현재 로그인 세션에 Docker 그룹을 적용하려면 로그아웃한 후 다시 로그인하세요.'
    fi
  fi
  git --version
  gh --version
  node --version
  npm --version
  /snap/bin/code --version

  local work
  work="$(mktemp -d)"
  trap 'rm -rf -- "$work"' EXIT
  python3.14 -m venv "$work/venv"
  "$work/venv/bin/python" --version
)
