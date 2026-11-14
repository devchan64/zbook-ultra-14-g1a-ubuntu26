#!/usr/bin/env bash
set -Eeuo pipefail

main() {
  [[ $# == 0 ]] || die '사용법: install.sh net-monitor'
  apt_update
  apt_install iproute2 bind9-dnsutils mtr-tiny iftop tcpdump
  local tool
  for tool in ip ss dig mtr iftop tcpdump; do
    command -v "$tool" || die "설치한 명령을 찾을 수 없습니다: $tool"
  done
  ip -brief address
  ss -lntu
}
