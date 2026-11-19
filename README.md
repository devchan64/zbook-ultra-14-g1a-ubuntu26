# ZBook Ultra 14 G1a Ubuntu 26.04 설정

Ubuntu 26.04 LTS의 HP ZBook Ultra 14 G1a에서 개발, 데스크톱 설정, 네트워크 진단, AMD GPU 테스트를 준비한다. 아래 명령은 일반 사용자로 실행한다.

```bash
./scripts/install.sh help
./scripts/install.sh all
./scripts/install.sh dev
./scripts/install.sh gnome
./scripts/install.sh security
./scripts/install.sh security check
./scripts/install.sh net-monitor
./scripts/install.sh ml setup
./scripts/install.sh ml verify
./scripts/install.sh ml bench --model /절대/경로/모델.gguf
./scripts/install.sh codex-restart
```

- **개발 환경.** Git, Python 3.14 가상환경(`python3.14-venv`), `python3-huggingface-hub`, Node.js와 npm은 Ubuntu 패키지로 설치한다. Hugging Face 패키지는 시스템 Python에 설치되며 기본 가상환경에는 포함되지 않는다. GitHub CLI는 공식 APT 저장소를 사용하고 VS Code는 공식 Snap 패키지로 설치한다. 기존 APT 버전이 있으면 제거 후 다시 실행한다. Docker Engine이 필요하면 `dev --docker`를 실행한다. [Ubuntu Node.js 패키지](https://packages.ubuntu.com/resolute/nodejs) · [GitHub CLI](https://github.com/cli/cli/blob/trunk/docs/install_linux.md) · [VS Code](https://code.visualstudio.com/docs/setup/linux) · [Docker Engine](https://docs.docker.com/engine/install/ubuntu/)

  Docker 설치 시 현재 사용자를 `docker` 그룹에 추가하고 새 그룹 목록을 적용한 사용자 프로세스에서 `docker info`를 확인한다. 현재 로그인 세션에서 권한을 사용하려면 로그아웃한 후 다시 로그인한다. `docker` 그룹은 관리자 수준의 권한을 부여한다.
- **GNOME.** GNOME Wayland 세션에 Legion5 배경 이미지, 다크 모드, JetBrains Mono 글꼴, 하단 도크와 GNOME Terminal Nord 팔레트를 적용한다. 배경 이미지 6개는 사용자 데이터 디렉터리의 `backgrounds/`에 복사하며 첫 번째 이미지를 사용한다. GNOME Terminal과 글꼴은 Ubuntu 패키지로 설치한다. 출력된 백업 파일을 `bash <백업 파일 경로>`로 실행하면 이전 값을 복원한다.
- **보안.** Ubuntu의 APT 자동 업데이트 타이머와 unattended-upgrades를 설정하고 UFW 상태를 출력한다. 방화벽을 켜려면 로컬 세션에서 `security --enable-ufw`를 실행한다. [Ubuntu 자동 업데이트](https://ubuntu.com/server/docs/how-to/software/automatic-updates/)

  `security check`는 AppArmor 상태, 최근 APT 이력과 자동 업데이트 서비스 로그, TCP·UDP 수신 포트, 실행 중인 Docker 컨테이너의 공개 포트를 출력한다. 로그와 프로세스 정보를 읽기 위해 `sudo` 인증이 필요하다. 일부 항목을 확인하지 못하면 나머지 항목도 출력한 뒤 오류로 종료한다.
- **네트워크 모니터링.** Ubuntu APT로 iproute2, DNS 조회, MTR, iftop, tcpdump를 설치하고 로컬 인터페이스 및 수신 소켓을 표시한다. 패킷 캡처는 사용자가 직접 실행한다. [Ubuntu 네트워크 패키지](https://packages.ubuntu.com/resolute/net/)
- **AMD ML.** Ubuntu 기본 7.0 generic 커널과 amdgpu를 사용한다. `ml setup`은 ROCm 10.1의 gfx1151 개발 패키지, AMD PyTorch 2.14.0 휠, llama.cpp v1.0.0 HIP 빌드를 준비한다. GPU 장치 권한 오류가 나면 `/dev/kfd`와 렌더링 장치의 그룹을 확인하고, 그룹 자격이 바뀐 경우 다시 로그인한다. `ml verify`는 GPU 행렬곱 결과를 검사한다. `ml bench`는 로컬 GGUF의 GPU 레이어 오프로딩을 확인하고 프롬프트 처리와 생성 처리량을 로그로 남긴다. [AMD 호환성](https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html) · [ROCm 설치](https://rocm.docs.amd.com/en/latest/install/rocm.html) · [AMD PyTorch](https://rocm.docs.amd.com/projects/ai-ecosystem/en/latest/frameworks/pytorch/install.html) · [llama.cpp 벤치마크](https://github.com/ggml-org/llama.cpp/blob/v1.0.0/tools/llama-bench/README.md)
- **Codex Desktop.** 설치된 `/usr/bin/chatgpt`를 사용자 서비스로 관리한다. 관리 중인 앱이 종료되면 5초 뒤 다시 실행한다. 명령 실행 시 앱이 이미 열려 있으면 다음 그래픽 로그인부터 관리한다. 해제하려면 `systemctl --user disable --now chatgpt-restart.service`를 실행한다.

백업과 벤치마크 로그는 기본적으로 `~/.local/state/zbook-ultra-14-g1a-ubuntu26/`에, ML 가상환경과 빌드는 `~/.local/share/zbook-ultra-14-g1a-ubuntu26/ml/`에 저장한다.

`all`은 `dev --docker → gnome → security → net-monitor → ml setup → codex-restart` 순서로 실행한다. 완료된 단계는 상태 디렉터리의 `all/`에 기록되며, 실패하거나 중단된 뒤 같은 명령을 다시 실행하면 해당 단계부터 이어진다. 완료된 ML 단계도 재실행 시 GPU와 ROCm 상태를 검증한다. ML 명령은 Ryzen APU에 지원되는 Ubuntu 기본 amdgpu 모듈을 확인하며 외부 모듈이나 로드된 모듈과 디스크의 모듈이 다른 경우 중단한다. 재부팅이 필요한 상태에서는 실행을 중단하고 재부팅 후 이어간다. UFW 활성화는 `security --enable-ufw`로 별도 실행한다. GGUF 벤치마크는 모델 경로를 지정해 별도 실행한다. 전체 단계를 다시 실행하려면 `all/`의 완료 기록을 삭제한다.
