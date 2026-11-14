#!/usr/bin/env bash
set -Eeuo pipefail

main() {
  [[ $# == 0 ]] || die '사용법: install.sh gnome'
  [[ ${XDG_CURRENT_DESKTOP:-} == *GNOME* && ${XDG_SESSION_TYPE:-} == wayland &&
    -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || die 'GNOME Wayland 데스크톱에서 실행하세요.'
  local background="$root/background/background1.jpg"
  [[ -r $background ]] || die '배경 이미지가 필요합니다.'
  apt_update
  apt_install fonts-jetbrains-mono gnome-terminal

  local uuid profile image_uri
  uuid="$(gsettings get org.gnome.Terminal.ProfilesList default)"
  uuid="${uuid#\'}"
  uuid="${uuid%\'}"
  [[ $uuid =~ ^[0-9a-fA-F-]{36}$ ]] || die 'GNOME Terminal 기본 프로필을 확인하세요.'
  profile="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$uuid/"
  image_uri="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve().as_uri())' "$data_dir/backgrounds/background1.jpg")"
  local -a schemas=(org.gnome.desktop.peripherals.keyboard org.gnome.shell.extensions.dash-to-dock
    org.gnome.shell.extensions.dash-to-dock org.gnome.desktop.interface org.gnome.desktop.interface
    org.gnome.desktop.background org.gnome.desktop.background org.gnome.desktop.background
    "$profile" "$profile" "$profile" "$profile" "$profile" "$profile" "$profile" "$profile" "$profile" "$profile" "$profile")
  local -a keys=(numlock-state dock-position extend-height color-scheme monospace-font-name
    picture-uri picture-uri-dark picture-options use-theme-colors palette background-color foreground-color
    bold-color-same-as-fg bold-color cursor-colors-set cursor-foreground-color cursor-background-color
    use-transparent-background visible-name)
  local -a values=(true "'BOTTOM'" false "'prefer-dark'" "'JetBrains Mono 12'"
    "'$image_uri'" "'$image_uri'" "'zoom'" false
    "['#3B4252', '#BF616A', '#A3BE8C', '#EBCB8B', '#81A1C1', '#B48EAD', '#88C0D0', '#E5E9F0', '#4C566A', '#BF616A', '#A3BE8C', '#EBCB8B', '#81A1C1', '#B48EAD', '#8FBCBB', '#ECEFF4']"
    "'#2E3440'" "'#D8DEE9'" false "'#ECEFF4'" true "'#2E3440'" "'#D8DEE9'" false "'Nord'")
  local i backup
  for i in "${!keys[@]}"; do
    [[ $(gsettings writable "${schemas[i]}" "${keys[i]}") == true ]] ||
      die "설정을 변경할 수 없습니다: ${schemas[i]} ${keys[i]}"
  done

  umask 077
  mkdir -p -- "$state_dir" "$data_dir/backgrounds"
  backup="$(mktemp "$state_dir/gnome-before.XXXXXXXX")"
  for i in "${!keys[@]}"; do
    printf 'gsettings set %q %q %q\n' "${schemas[i]}" "${keys[i]}" \
      "$(gsettings get "${schemas[i]}" "${keys[i]}")"
  done > "$backup"
  log "복원 명령 파일: $backup"
  for background in "$root"/background/background[1-6].jpg; do
    install -m 0644 "$background" "$data_dir/backgrounds/"
  done
  for i in "${!keys[@]}"; do
    gsettings set "${schemas[i]}" "${keys[i]}" "${values[i]}"
    [[ $(gsettings get "${schemas[i]}" "${keys[i]}") == "${values[i]}" ]] ||
      die "적용을 확인할 수 없습니다: ${keys[i]}"
  done
}
