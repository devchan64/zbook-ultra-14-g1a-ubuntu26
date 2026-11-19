#!/usr/bin/env bash
set -Eeuo pipefail

rocm=/opt/rocm/core-10.1
ml_dir="$data_dir/ml"
llama_tag=v1.0.0
bench="$ml_dir/llama.cpp-$llama_tag/build/bin/llama-bench"
python="$ml_dir/venv-rocm10.1/bin/python"

check_gpu_nodes() {
  local kernel node driver module_path loaded_src available_src
  kernel="$(uname -r)"
  [[ $kernel == 7.0.*-generic ]] || die "AMD 지원 Ubuntu 26.04 GA 커널(7.0 generic)이 필요합니다. 현재: $kernel"
  [[ -d /sys/module/amdgpu ]] || die 'amdgpu 커널 모듈이 로드되지 않았습니다.'
  module_path="$(modinfo -k "$kernel" -F filename amdgpu)" || die 'amdgpu 모듈 경로를 확인할 수 없습니다.'
  loaded_src="$(cat /sys/module/amdgpu/srcversion 2>/dev/null || true)"
  available_src="$(modinfo -k "$kernel" -F srcversion amdgpu)" || die 'amdgpu 모듈 버전을 확인할 수 없습니다.'
  if [[ -n $loaded_src && -n $available_src && $loaded_src != "$available_src" ]]; then
    die "현재 로드된 amdgpu와 다음 부팅에 선택될 모듈이 다릅니다: $module_path. 커널 모듈 상태를 확인하고 재부팅 후 다시 실행하세요."
  fi
  case "$module_path" in
    */updates/*|*/extra/*)
      die "Ubuntu 기본 커널 외부의 amdgpu 모듈이 선택되어 있습니다: $module_path. Ryzen APU에 지원되는 드라이버 구성을 확인하세요."
      ;;
    */kernel/*|\(builtin\)) ;;
    *) die "amdgpu 모듈의 출처를 확인할 수 없습니다: $module_path" ;;
  esac
  [[ -c /dev/kfd ]] || die 'AMD GPU 장치 /dev/kfd가 없습니다.'
  [[ -r /dev/kfd && -w /dev/kfd ]] || die "/dev/kfd 접근 권한이 없습니다. 장치 그룹과 현재 세션 그룹($(id -nG))을 확인하고, 그룹을 변경했다면 다시 로그인하세요."
  for node in /dev/dri/renderD*; do
    [[ -c $node && -r $node && -w $node ]] || continue
    driver="$(readlink -f "/sys/class/drm/${node##*/}/device/driver")"
    [[ ${driver##*/} == amdgpu ]] && return 0
  done
  die '접근 가능한 amdgpu 렌더링 장치가 없습니다. render 및 video 그룹을 확인하세요.'
}

check_rocm() {
  [[ $(dpkg-query -W -f='${db:Status-Status}' amdrocm-core-dev10.1-gfx1151 2>/dev/null || true) == installed ]] ||
    die 'ROCm 10.1 개발 패키지가 설치되어 있지 않습니다. install.sh ml setup을 실행하세요.'
  [[ -x $rocm/bin/rocminfo ]] || die '먼저 install.sh ml setup을 실행하세요.'
  local info
  info="$("$rocm/bin/rocminfo")"
  grep -Eq '^[[:space:]]*Name:[[:space:]]+gfx1151([[:space:]]|$)' <<< "$info" ||
    die 'ROCm에서 gfx1151 GPU를 찾을 수 없습니다.'
}

verify_torch() {
  [[ -x $python ]] || die '먼저 install.sh ml setup을 실행하세요.'
  "$python" - <<'PY'
import torch

if not torch.version.hip or not torch.cuda.is_available():
    raise SystemExit("오류: PyTorch에서 AMD GPU를 사용할 수 없습니다.")

for index in range(torch.cuda.device_count()):
    properties = torch.cuda.get_device_properties(index)
    if properties.gcnArchName.split(":")[0] == "gfx1151":
        break
else:
    raise SystemExit("오류: PyTorch에서 gfx1151 GPU를 찾을 수 없습니다.")

device = torch.device("cuda", index)
matrix = torch.ones((128, 128), device=device)
result = matrix @ matrix
torch.cuda.synchronize(device)
torch.testing.assert_close(result.cpu(), torch.full((128, 128), 128.0))
print(f"GPU 연산 검증 완료: {properties.name}, PyTorch {torch.__version__}, HIP {torch.version.hip}")
PY
}

setup_ml() {
  check_gpu_nodes
  apt_update
  apt_install ca-certificates curl gpg git build-essential cmake ninja-build \
    python3.14-venv libatomic1 libquadmath0
  apt_source amdrocm-stable https://stable.repo.amd.com/rocm/core/packages/ubuntu2604/ stable \
    https://stable.repo.amd.com/rocm/gpg/packages.gpg dearmor
  apt_update
  apt_install amdrocm-core-dev10.1-gfx1151
  [[ ! -e /run/reboot-required ]] || die '시스템에 재부팅이 예약되어 있습니다. 재부팅 후 ml setup을 다시 실행하세요.'
  check_rocm

  mkdir -p -- "$ml_dir"
  local source="$ml_dir/llama.cpp-$llama_tag"
  exec {ml_lock}>"$ml_dir/setup.lock"
  flock -n "$ml_lock" || die '다른 ML 설치가 진행 중입니다.'
  python3.14 -m venv "${python%/bin/python}"
  "$python" -m pip --isolated install --index-url https://stable.repo.amd.com/rocm/whl-next/ \
    'torch[device-gfx1151]==2.14.0+rocm10.1.0'
  verify_torch

  if [[ ! -d $source/.git ]]; then
    git clone --depth 1 --branch "$llama_tag" https://github.com/ggml-org/llama.cpp.git "$source"
  fi
  [[ $(git -C "$source" describe --tags --exact-match HEAD) == "$llama_tag" ]] ||
    die "llama.cpp 체크아웃이 $llama_tag 버전과 일치하지 않습니다."
  local compiler="$rocm/lib/llvm/bin/clang++"
  if [[ -x $rocm/bin/amdclang++ ]]; then
    compiler="$rocm/bin/amdclang++"
  fi
  [[ -x $compiler ]] || die 'AMD ROCm Clang 컴파일러를 찾을 수 없습니다.'
  cmake -S "$source" -B "$source/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$rocm" -DCMAKE_HIP_COMPILER_ROCM_ROOT="$rocm" \
    -DCMAKE_HIP_COMPILER="$compiler" -DCMAKE_CXX_COMPILER="$compiler" \
    -DCMAKE_C_COMPILER="${compiler%++}" -DGPU_TARGETS=gfx1151 -DCMAKE_HIP_ARCHITECTURES=gfx1151 \
    -DGGML_HIP=ON -DLLAMA_CURL=OFF
  cmake --build "$source/build" --target llama-bench --parallel 4
  "$bench" --list-devices
}

run_bench() {
  local model="$1" devices device report
  [[ -f $model && -r $model && $(head -c 4 -- "$model") == GGUF ]] ||
    die '읽을 수 있는 GGUF 모델 파일을 지정하세요.'
  check_gpu_nodes
  check_rocm
  [[ -x $bench ]] || die '먼저 install.sh ml setup을 실행하세요.'
  devices="$("$bench" --list-devices 2>&1)"
  device="$(awk -F: '/gfx1151|Radeon.*8060S/ && $1 ~ /^[[:space:]]*ROCm[0-9]+$/ {
    gsub(/[[:space:]]/, "", $1); print $1; exit
  }' <<< "$devices")"
  [[ -n $device ]] || die "llama.cpp에서 AMD HIP 장치를 찾을 수 없습니다. $devices"

  umask 077
  mkdir -p -- "$state_dir"
  report="$(mktemp "$state_dir/llama-bench.XXXXXXXX")"
  log "벤치마크 로그: $report"
  {
    printf '모델: %s\nllama.cpp: %s\nROCm: %s\nGPU: %s\n커널: %s\n' \
      "$(realpath -- "$model")" "$llama_tag" "$(dpkg-query -W amdrocm-core-dev10.1-gfx1151)" \
      "$device" "$(uname -r)"
    "$bench" -m "$(realpath -- "$model")" -dev "$device" -ngl 999 -p 512 -n 128 -r 3 -v
  } 2>&1 | tee "$report"
  grep -Eq 'offloaded [1-9][0-9]*/[0-9]+ layers to GPU' "$report" ||
    die '로그에서 GPU 레이어 오프로딩을 확인하지 못했습니다.'
}

main() {
  case "${1:-setup}" in
    setup)
      [[ $# -le 1 ]] || die '사용법: install.sh ml setup'
      setup_ml
      ;;
    verify)
      [[ $# == 1 ]] || die '사용법: install.sh ml verify'
      check_gpu_nodes
      check_rocm
      verify_torch
      [[ -x $bench ]] || die 'llama.cpp 벤치마크가 없습니다. install.sh ml setup을 실행하세요.'
      "$bench" --list-devices
      ;;
    bench)
      [[ $# == 3 && $2 == --model ]] || die '사용법: install.sh ml bench --model 파일.gguf'
      run_bench "$3"
      ;;
    *) die '사용법: install.sh ml [setup|verify|bench --model 파일.gguf]' ;;
  esac
}
