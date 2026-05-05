#!/bin/bash
set -uo pipefail

# vm-live-backup.sh: KVM VM 무중단 백업
# - running VM: external snapshot → backing 복사 → blockcommit 병합
# - shut off VM: qemu-img convert 직접 복사
# - mtime 기반 변경 감지: 마지막 백업 이후 디스크 변경 없으면 스킵
# 사용: sudo /usr/local/bin/vm-live-backup.sh <VM_NAME>

[ "$EUID" -ne 0 ] && { echo "[에러] sudo로 실행하세요."; exit 1; }

VM_NAME="${1:?사용법: sudo $0 <VM_NAME>}"
BACKUP_BASE="/storage/vm_backup"
LOG="/var/log/vm-backup.log"
PROM_DIR="/var/lib/node_exporter/textfile"
DATE=$(date '+%Y%m%d_%H%M%S')
BACKUP_DIR="${BACKUP_BASE}/${VM_NAME}/${DATE}"
SNAP_TAG="bkp_${DATE}"
RETENTION=3

mkdir -p "${BACKUP_DIR}" "${PROM_DIR}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${VM_NAME}] $*" | tee -a "${LOG}"; }

# libvirt volume 타입 소스를 실제 파일 경로로 변환
resolve_vol_path() {
    local vol_name="$1"
    while read -r pool; do
        local resolved
        resolved=$(virsh vol-path "${vol_name}" --pool "${pool}" 2>/dev/null) && echo "${resolved}" && return 0
    done < <(virsh pool-list --name 2>/dev/null)
    return 1
}

# VM 디스크 목록을 병렬 배열로 수집: DISK_PATHS[], DISK_TARGETS[]
# file 타입: 경로 그대로, volume 타입: virsh vol-path로 실제 경로 변환
collect_disks() {
    local vm="$1"
    DISK_PATHS=()
    DISK_TARGETS=()
    while read -r dtype ddevice dtarget dsource; do
        [ "${ddevice}" != "disk" ] && continue
        [ -z "${dsource}" ] || [ "${dsource}" = "-" ] && continue
        local resolved_path
        if [ "${dtype}" = "volume" ]; then
            resolved_path=$(resolve_vol_path "${dsource}") || { log "볼륨 경로 변환 실패: ${dsource}"; continue; }
        else
            resolved_path="${dsource}"
        fi
        DISK_PATHS+=("${resolved_path}")
        DISK_TARGETS+=("${dtarget}")
    done < <(virsh domblklist "${vm}" --details 2>/dev/null | tail -n +3)
}

# 마지막 백업 이후 디스크 변경 여부 확인 (mtime 기반)
# 반환: 0 = 백업 필요, 1 = 변경 없음(스킵)
needs_backup() {
    local last_dir
    last_dir=$(ls -dt "${BACKUP_BASE}/${VM_NAME}"/[0-9]* 2>/dev/null | head -1)
    [ -z "${last_dir}" ] && return 0  # 첫 백업이면 무조건 진행

    declare -a DISK_PATHS=() DISK_TARGETS=()
    collect_disks "${VM_NAME}"

    [ "${#DISK_PATHS[@]}" -eq 0 ] && return 0  # 디스크 정보 없으면 안전하게 진행

    for path in "${DISK_PATHS[@]}"; do
        [ "${path}" -nt "${last_dir}" ] && return 0  # 변경 감지 → 진행
    done

    log "=== 변경 없음 — 스킵 (마지막 백업: $(basename "${last_dir}")) ==="
    rm -rf "${BACKUP_DIR}"
    return 1
}

# 변경 없으면 여기서 종료 (exit 0 → 성공으로 처리)
needs_backup || exit 0

RESULT=0
VM_STATE=$(virsh domstate "${VM_NAME}" 2>/dev/null || echo "unknown")
log "=== 백업 시작 (상태: ${VM_STATE}) ==="

if [ "${VM_STATE}" = "running" ]; then
    log "방식: external snapshot (무중단)"

    # 1. 스냅샷 전 원본 디스크 경로·장치명 기록
    declare -a DISK_PATHS=() DISK_TARGETS=()
    collect_disks "${VM_NAME}"
    PRE_PATHS=("${DISK_PATHS[@]}")
    PRE_TARGETS=("${DISK_TARGETS[@]}")

    # 2. External snapshot -- diskspec으로 overlay 경로 명시 (volume 타입 disk 지원)
    DISKSPEC_ARGS=()
    for i in "${!PRE_PATHS[@]}"; do
        DISKSPEC_ARGS+=(--diskspec "${PRE_TARGETS[$i]},file=${PRE_PATHS[$i]}.${SNAP_TAG}")
    done
    virsh snapshot-create-as "${VM_NAME}" "${SNAP_TAG}" \
        --disk-only --atomic --no-metadata \
        "${DISKSPEC_ARGS[@]}" >> "${LOG}" 2>&1

    # 3. 스냅샷 후 overlay 경로 수집 (blockcommit 후 삭제용)
    declare -a DISK_PATHS=() DISK_TARGETS=()
    collect_disks "${VM_NAME}"
    OVERLAY_PATHS=("${DISK_PATHS[@]}")

    # 4. 원본 디스크 복사 (snapshot 후 frozen backing file)
    for BACKING in "${PRE_PATHS[@]}"; do
        DISK_NAME=$(basename "${BACKING}")
        log "복사 중: ${DISK_NAME}"
        EXIT_C=0
        qemu-img convert -O qcow2 -c "${BACKING}" "${BACKUP_DIR}/${DISK_NAME}" >> "${LOG}" 2>&1 || EXIT_C=$?
        [ ${EXIT_C} -ne 0 ] && { log "복사 실패: ${DISK_NAME}"; RESULT=1; }
    done

    # 5. XML 설정 저장
    virsh dumpxml "${VM_NAME}" > "${BACKUP_DIR}/${VM_NAME}_config.xml"

    # 6. Blockcommit: overlay → original 병합 후 pivot
    for i in "${!PRE_TARGETS[@]}"; do
        DEV="${PRE_TARGETS[$i]}"
        OVERLAY="${OVERLAY_PATHS[$i]:-}"
        log "blockcommit 병합: ${DEV}"
        EXIT_C=0
        virsh blockcommit "${VM_NAME}" "${DEV}" --active --pivot --wait >> "${LOG}" 2>&1 || EXIT_C=$?
        if [ ${EXIT_C} -ne 0 ]; then
            log "blockcommit 실패: ${DEV} — 수동 확인 필요 (overlay: ${OVERLAY})"
            RESULT=1
        else
            [ -n "${OVERLAY}" ] && rm -f "${OVERLAY}" && log "overlay 삭제: $(basename "${OVERLAY}")"
        fi
    done

elif [ "${VM_STATE}" = "shut off" ]; then
    log "방식: 직접 복사 (VM 정지 상태)"

    declare -a DISK_PATHS=() DISK_TARGETS=()
    collect_disks "${VM_NAME}"

    for DISK_PATH in "${DISK_PATHS[@]}"; do
        DISK_NAME=$(basename "${DISK_PATH}")
        log "복사 중: ${DISK_NAME}"
        EXIT_C=0
        qemu-img convert -O qcow2 -c "${DISK_PATH}" "${BACKUP_DIR}/${DISK_NAME}" >> "${LOG}" 2>&1 || EXIT_C=$?
        [ ${EXIT_C} -ne 0 ] && { log "복사 실패: ${DISK_NAME}"; RESULT=1; }
    done

    virsh dumpxml "${VM_NAME}" > "${BACKUP_DIR}/${VM_NAME}_config.xml"

else
    log "지원하지 않는 VM 상태: ${VM_STATE}"
    rm -rf "${BACKUP_DIR}"
    RESULT=1
fi

# 세대 관리: 최신 RETENTION개만 유지
if [ ${RESULT} -eq 0 ]; then
    OLD_DIRS=$(ls -dt "${BACKUP_BASE}/${VM_NAME}"/[0-9]* 2>/dev/null | tail -n +$(( RETENTION + 1 )))
    for OLD_DIR in ${OLD_DIRS}; do
        rm -rf "${OLD_DIR}"
        log "구버전 삭제: $(basename "${OLD_DIR}")"
    done
    SIZE=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1)
    log "=== 완료: ${SIZE} → ${BACKUP_DIR} ==="
else
    log "=== 실패 ==="
fi

# Prometheus 메트릭 (VM별 개별 파일)
SAFE_NAME="${VM_NAME//-/_}"
printf '# HELP vm_backup_success VM 백업 성공 여부\n# TYPE vm_backup_success gauge\nvm_backup_success{vm="%s"} %s\n# HELP vm_backup_last_timestamp 마지막 백업 Unix timestamp\n# TYPE vm_backup_last_timestamp gauge\nvm_backup_last_timestamp{vm="%s"} %s\n' \
    "${VM_NAME}" "$(( 1 - RESULT ))" "${VM_NAME}" "$(date +%s)" \
    > "${PROM_DIR}/vm_backup_${SAFE_NAME}.prom"

exit ${RESULT}
