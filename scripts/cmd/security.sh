#!/usr/bin/env bash
set -Eeuo pipefail

main() {
  [[ $# == 0 || ( $# == 1 && $1 == --enable-ufw ) ]] || die '사용법: install.sh security [--enable-ufw]'
  if [[ $# == 1 && -n ${SSH_CONNECTION:-}${SSH_TTY:-} ]]; then
    die '방화벽은 로컬 세션에서 활성화하세요.'
  fi
  apt_update
  apt_install unattended-upgrades ufw
  sudo tee /etc/apt/apt.conf.d/52zbook-periodic >/dev/null <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT
  sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
  apt-config dump | awk '
    $1 == "APT::Periodic::Update-Package-Lists" && $2 == "\"1\";" { lists = 1 }
    $1 == "APT::Periodic::Unattended-Upgrade" && $2 == "\"1\";" { upgrades = 1 }
    END { exit !(lists && upgrades) }
  ' || die 'APT 자동 업데이트 설정을 확인할 수 없습니다.'
  systemctl is-active apt-daily.timer apt-daily-upgrade.timer
  if [[ $# == 1 ]]; then
    sudo ufw enable
  fi
  sudo ufw status verbose
}
