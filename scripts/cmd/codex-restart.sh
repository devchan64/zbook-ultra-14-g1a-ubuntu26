#!/usr/bin/env bash
set -Eeuo pipefail

main() {
  [[ $# == 0 ]] || die '사용법: install.sh codex-restart'
  [[ -x /usr/bin/chatgpt ]] || die 'Codex Desktop의 /usr/bin/chatgpt가 필요합니다.'
  systemctl --user show-environment >/dev/null || die '사용자 systemd에 연결할 수 없습니다.'
  local unit=chatgpt-restart.service
  local units_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p -- "$units_dir"
  cat > "$units_dir/$unit" <<'UNIT'
[Unit]
Description=Codex Desktop 자동 재실행
PartOf=graphical-session.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
ExecStart=/usr/bin/chatgpt
Restart=always
RestartSec=5

[Install]
WantedBy=graphical-session.target
UNIT
  systemctl --user daemon-reload
  systemctl --user enable "$unit"
  systemctl --user is-enabled "$unit"
  if systemctl --user is-active --quiet "$unit"; then
    log '자동 재실행 서비스가 실행 중입니다.'
  elif systemctl --user is-active --quiet graphical-session.target &&
    ! pgrep -x 'ChatGPT|chatgpt' >/dev/null; then
    systemctl --user start "$unit"
  else
    log '다음 그래픽 로그인부터 자동 실행됩니다.'
  fi
}
