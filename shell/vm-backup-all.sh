#!/bin/bash
# vm-backup-all.sh: 서버 전체 VM 병렬 백업 (cron용)
# 사용: sudo /usr/local/bin/vm-backup-all.sh
# 동시 실행 VM 수: MAX_PARALLEL (기본 3)

set -uo pipefail
[ "$EUID" -ne 0 ] && { echo "[에러] sudo로 실행하세요."; exit 1; }

LOG="/var/log/vm-backup.log"
MAX_PARALLEL=3

# 백업 대상 지정 (비어 있으면 전체 VM, 지정하면 해당 VM만 백업)
VM_INCLUDE=(
    "sonarQube"
    "finance-vm-01"
    "clobot-chatbot"
    # "vm-name"
)

VM_EXCLUDE=(
    # "vm-name-to-skip"
)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG}"; }

RESULT_DIR=$(mktemp -d /tmp/vm-backup-result-XXXXXX)
cleanup() { rm -rf "${RESULT_DIR}"; }
trap cleanup EXIT

log ""
log "========== 전체 VM 백업 시작 (최대 병렬: ${MAX_PARALLEL}) =========="

mapfile -t ALL_VMS < <(virsh list --all --name | grep -v '^$')

declare -a PIDS=()
declare -a VNAMES=()
SUCCESS=0; FAIL=0; SKIP=0

# 빈 슬롯이 생길 때까지 대기 (완료된 PID 수확)
wait_slot() {
    while [ "${#PIDS[@]}" -ge "${MAX_PARALLEL}" ]; do
        local np=() nn=()
        for i in "${!PIDS[@]}"; do
            if kill -0 "${PIDS[$i]}" 2>/dev/null; then
                np+=("${PIDS[$i]}"); nn+=("${VNAMES[$i]}")
            fi
        done
        PIDS=("${np[@]+"${np[@]}"}"); VNAMES=("${nn[@]+"${nn[@]}"}")
        [ "${#PIDS[@]}" -ge "${MAX_PARALLEL}" ] && sleep 60
    done
}

for VM in "${ALL_VMS[@]}"; do
    # VM_INCLUDE 지정 시 해당 VM만 처리
    if [ "${#VM_INCLUDE[@]}" -gt 0 ]; then
        INCLUDED=0
        for INC in "${VM_INCLUDE[@]}"; do
            [ "${VM}" = "${INC}" ] && INCLUDED=1 && break
        done
        if [ "${INCLUDED}" -eq 0 ]; then
            log "[SKIP] ${VM}"; (( SKIP++ )) || true; continue
        fi
    fi

    EXCLUDED=0
    for EX in "${VM_EXCLUDE[@]+"${VM_EXCLUDE[@]}"}"; do
        [ "${VM}" = "${EX}" ] && EXCLUDED=1 && break
    done
    if [ "${EXCLUDED}" -eq 1 ]; then
        log "[SKIP] ${VM}"; (( SKIP++ )) || true; continue
    fi

    wait_slot

    SAFE_NAME="${VM//\//-}"
    ( /usr/local/bin/vm-live-backup.sh "${VM}"; echo $? > "${RESULT_DIR}/${SAFE_NAME}" ) &
    PIDS+=($!); VNAMES+=("${VM}")
    log "[LAUNCH] ${VM} (PID: $!)"
done

# 잔여 프로세스 대기
for pid in "${PIDS[@]+"${PIDS[@]}"}"; do
    wait "${pid}" 2>/dev/null || true
done

# 결과 집계
for VM in "${ALL_VMS[@]}"; do
    SAFE_NAME="${VM//\//-}"
    f="${RESULT_DIR}/${SAFE_NAME}"
    [ -f "${f}" ] || continue
    rc=$(<"${f}")
    if (( rc == 0 )); then (( SUCCESS++ )) || true
    else (( FAIL++ )) || true
    fi
done

log "========== 완료: 성공 ${SUCCESS} / 실패 ${FAIL} / 제외 ${SKIP} =========="
