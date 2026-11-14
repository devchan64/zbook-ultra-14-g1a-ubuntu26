#!/usr/bin/env bash
set -Eeuo pipefail

main() {
  [[ $# == 0 ]] || die '사용법: install.sh gnome'
  [[ ${XDG_CURRENT_DESKTOP:-} == *GNOME* && ${XDG_SESSION_TYPE:-} == wayland &&
    -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || die 'GNOME Wayland 데스크톱에서 실행하세요.'
  local light=/usr/share/backgrounds/Resolute_Raccoon_Wallpaper_Light_3840x2160.png
  local dark=/usr/share/backgrounds/Resolute_Raccoon_Wallpaper_Dimmed_3840x2160.png
  [[ -r $light && -r $dark ]] || die 'Ubuntu 기본 배경 파일이 필요합니다.'
  local -a schemas=(org.gnome.desktop.peripherals.keyboard org.gnome.shell.extensions.dash-to-dock
    org.gnome.desktop.background org.gnome.desktop.background)
  local -a keys=(numlock-state dock-position picture-uri picture-uri-dark)
  local -a values=(true "'BOTTOM'" "'file://$light'" "'file://$dark'")
  local i backup
  for i in "${!keys[@]}"; do
    [[ $(gsettings writable "${schemas[i]}" "${keys[i]}") == true ]] ||
      die "설정을 변경할 수 없습니다: ${schemas[i]} ${keys[i]}"
    gsettings range "${schemas[i]}" "${keys[i]}" >/dev/null
  done

  umask 077
  mkdir -p -- "$state_dir"
  backup="$(mktemp "$state_dir/gnome-before.XXXXXXXX")"
  for i in "${!keys[@]}"; do
    printf 'gsettings set %q %q %q\n' "${schemas[i]}" "${keys[i]}" \
      "$(gsettings get "${schemas[i]}" "${keys[i]}")"
  done > "$backup"
  log "복원 명령 파일: $backup"
  for i in "${!keys[@]}"; do
    gsettings set "${schemas[i]}" "${keys[i]}" "${values[i]}"
    [[ $(gsettings get "${schemas[i]}" "${keys[i]}") == "${values[i]}" ]] ||
      die "적용을 확인할 수 없습니다: ${keys[i]}"
  done
}
