> ⚠️ **Deprecated** — 새 레포로 이전됨: [infrastructure-monitoring](https://github.com/p2bble/infrastructure-monitoring)

# Prometheus & Grafana 기반 통합 모니터링 시스템

이 리포지토리는 Docker Compose를 사용하여 Prometheus, Grafana, Loki 및 관련 Exporter들을 구축하여 통합 모니터링 환경을 구성하는 프로젝트입니다.


## 1. 시스템 아키텍처

본 모니터링 시스템은 다음과 같은 오픈 소스들로 구성됩니다. [cite: 48]

* **Prometheus**: 서버, 애플리케이션, 장비 등에서 발생하는 시계열 데이터(메트릭)를 수집하고 저장하는 핵심 DB입니다.
* **Grafana**: Prometheus, Loki 등에 저장된 데이터를 시각화하여 대시보드를 만드는 도구입니다.
* **Alertmanager**: Prometheus에서 발생한 경고를 수신하여 그룹화, 중복 제거 후 외부 채널(Jandi, Slack 등)로 알림을 발송하는 도구입니다.
* **Loki & Promtail**: 로그를 수집(Promtail)하고 저장(Loki)하는 시스템입니다. 
* **Exporters**: 각 모니터링 대상의 메트릭을 Prometheus가 수집할 수 있도록 노출하는 에이전트입니다.
    * **cAdvisor**: Docker 컨테이너의 성능 메트릭을 수집합니다.
    * **Node Exporter**: 서버의 CPU, 메모리, 디스크 등 하드웨어 및 OS 메트릭을 수집합니다.
    * **Blackbox Exporter**: 웹사이트/엔드포인트의 외부 가용성(UP/DOWN) 및 응답 시간을 점검합니다.
    * **Libvirt Exporter**: KVM/QEMU 가상 머신의 성능 메트릭을 수집합니다.
    * **HAProxy Exporter**: HAProxy의 트래픽 통계를 수집합니다. 
    * **SNMP Exporter**: SNMP를 지원하는 네트워크 장비(스위치, iDRAC 등)의 메트릭을 수집합니다.

## 2. 디렉토리 구조

이 프로젝트는 다음과 같은 디렉토리 구조를 권장합니다.

```
/monitoring-stack/
│
├── docker-compose.yml     # 메인 Docker Compose 파일
│
├── prometheus/
│   ├── prometheus.yml     # Prometheus 메인 설정 (타겟 정의)
│   ├── snmp.yml           # SNMP Exporter 모듈 정의
│   └── rules/
│       └── alert.rules.yml  # Prometheus 알림 규칙
│
├── loki/
│   └── local-config.yaml    # Loki 설정 파일
│
└── promtail/
    └── promtail-config.yml  # Promtail 설정 파일 (로그 수집 대상)
```

## 3. 설치 및 실행

1.  이 리포지토리를 Clone 받거나 파일들을 다운로드합니다.
2.  `prometheus/prometheus.yml` 및 `snmp.yml` 파일 내의 `<PLACEHOLDER>` 값들을 실제 환경에 맞게 수정합니다.
3.  `docker-compose.yml` 파일 내의 `<PLACEHOLDER>` 값들을 수정합니다. (예: Grafana 비밀번호)
4.  아래 명령어를 실행하여 전체 모니터링 스택을 시작합니다.

    ```bash
    docker-compose up -d
    ```

## 4. 기본 명령어

* **전체 서비스 중지 및 컨테이너 삭제**:
    ```bash
    docker-compose down
    ```
* **특정 서비스 재시작 (예: prometheus)**:
    ```bash
    docker-compose restart prometheus
    ```
* **Prometheus 설정만 리로드 (prometheus.yml 변경 시)**:
    ```bash
    docker-compose exec prometheus kill -HUP 1
    ```
* **컨테이너 로그 확인**:
    ```bash
    docker-compose logs <container_name>
    ```

## 5. Grafana 활용

* **접속 정보**: `http://<서버_IP>:38889`
* **초기 계정**: `admin` / `docker-compose.yml`에서 설정한 비밀번호

### 추천 대시보드 ID

Grafana 대시보드는 직접 만들거나, Grafana.com의 공식 대시보드를 가져와서 사용할 수 있습니다.
왼쪽 메뉴 `+` -> `Import` -> `Import via grafana.com`에 ID를 입력하세요.

* **서버 기본 (Node Exporter)**: `1860` 
* **Docker 컨테이너 (cAdvisor)**: `14282`
* **KVM 가상머신 (Libvirt Exporter)**: `893`
* **Loki 로그 통계**: `12290`
