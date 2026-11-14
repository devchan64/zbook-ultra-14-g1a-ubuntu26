#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$root/lib/common.sh"

usage() {
  cat <<'HELP'
사용법: ./scripts/install.sh <명령>
  dev [--docker]             개발 도구 설치
  gnome                      현재 GNOME 세션 설정
  security [--enable-ufw]    자동 보안 업데이트 설정 및 UFW 점검
  net-monitor                개발용 네트워크 진단 도구 설치
  ml [setup]                 ROCm, PyTorch, llama.cpp 설치 및 GPU 검증
  ml verify                  AMD GPU와 PyTorch 연산 검증
  ml bench --model 파일.gguf  GPU 추론 벤치마크
  codex-restart              Codex Desktop 자동 재실행 설정
  all                        전체 설치를 순서대로 실행하고 이어하기
HELP
}

case "${1:-help}" in
  help|-h|--help) usage; exit 0 ;;
  dev|gnome|security|net-monitor|ml|codex-restart|all) domain="$1"; shift ;;
  *) usage >&2; die "알 수 없는 명령입니다: $1" ;;
esac

require_ubuntu
if [[ $domain == all ]]; then
  [[ $# == 0 ]] || die '사용법: install.sh all'
  umask 077
  mkdir -p -- "$state_dir/all"
  exec {all_lock}>"$state_dir/all.lock"
  flock -n "$all_lock" || die '다른 전체 설치가 실행 중입니다.'
  for step in dev gnome security net-monitor ml codex-restart; do
    marker="$step"
    [[ $step != dev ]] || marker=dev-snap-docker-group
    [[ $step != gnome ]] || marker=gnome-nord
    [[ ! -e /run/reboot-required ]] || die '재부팅 후 install.sh all을 다시 실행하세요.'
    if [[ -f $state_dir/all/$marker.done ]]; then
      log "완료된 단계 건너뜀: $step"
      continue
    fi
    log "단계 실행: $step"
    (
      trap 'printf "오류: %s 단계가 실패했습니다. 원인을 해결하고 install.sh all을 다시 실행하세요. 이후 단계는 아직 실행되지 않았습니다.\\n" "$step" >&2' ERR
      source "$root/scripts/cmd/$step.sh"
      if [[ $step == dev ]]; then
        main --docker
      else
        main
      fi
    )
    touch "$state_dir/all/$marker.done"
  done
  log '전체 설치가 완료되었습니다.'
  exit 0
fi
source "$root/scripts/cmd/$domain.sh"
main "$@"
