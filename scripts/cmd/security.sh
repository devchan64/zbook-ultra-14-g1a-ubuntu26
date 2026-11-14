#!/usr/bin/env bash
set -Eeuo pipefail

security_check() {
  local failed=0 history
  log '=== AppArmor 상태 ==='
  if ! command -v aa-status >/dev/null; then
    log 'AppArmor 점검 명령을 찾을 수 없습니다.' >&2
    failed=1
  elif ! sudo aa-status; then
    log 'AppArmor 상태를 확인하지 못했거나 AppArmor가 비활성 상태입니다.' >&2
    failed=1
  fi

  log '=== 최근 APT 업데이트 이력 ==='
  history=/var/log/apt/history.log
  if sudo test -r "$history"; then
    if ! sudo tail -n 100 "$history"; then
      log 'APT 업데이트 이력을 읽지 못했습니다.' >&2
      failed=1
    fi
  else
    log 'APT 업데이트 이력 파일이 없거나 읽을 수 없습니다.' >&2
    failed=1
  fi

  log '=== 최근 자동 업데이트 서비스 이력 ==='
  if ! sudo journalctl --no-pager -u apt-daily-upgrade.service -n 50; then
    log '자동 업데이트 서비스 이력을 읽지 못했습니다.' >&2
    failed=1
  fi

  log '=== TCP 및 UDP 수신 포트 ==='
  if ! sudo ss -lntup; then
    log '수신 포트를 확인하지 못했습니다.' >&2
    failed=1
  fi

  log '=== Docker 컨테이너 공개 포트 ==='
  if ! command -v docker >/dev/null; then
    log 'Docker가 설치되어 있지 않습니다.'
  elif ! sudo docker ps --format 'table {{.Names}}\t{{.Ports}}'; then
    log 'Docker 데몬에 접근하지 못해 공개 포트를 확인하지 못했습니다.' >&2
    failed=1
  fi

  (( failed == 0 )) || die '일부 보안 점검을 완료하지 못했습니다.'
}

main() {
  if [[ ${1:-} == check ]]; then
    [[ $# == 1 ]] || die '사용법: install.sh security check'
    security_check
    return
  fi
  [[ $# == 0 || ( $# == 1 && $1 == --enable-ufw ) ]] || die '사용법: install.sh security [--enable-ufw|check]'
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
