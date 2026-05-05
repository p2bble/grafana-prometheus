#!/bin/bash
set -uo pipefail

# server-file-backup.sh: 서버 설정/스크립트 파일 NAS rsync 백업
# - /etc, /usr/local/bin, /data/docker 구성 파일 → NAS /storage/backup/servers/<hostname>/
# - 대용량 데이터 볼륨·바이너리는 제외 (별도 백업 존재)
# - Prometheus textfile 메트릭 기록
# 사용: sudo /usr/local/bin/server-file-backup.sh

[ "$EUID" -ne 0 ] && { echo "[에러] sudo로 실행하세요."; exit 1; }

HOST=$(hostname -s)
BACKUP_BASE="/storage/backup/servers"
DST="${BACKUP_BASE}/${HOST}"
LOG="/var/log/server-file-backup.log"
PROM_DIR="/var/lib/node_exporter/textfile"
PROM_FILE="${PROM_DIR}/server_file_backup.prom"

mkdir -p "${DST}" "${PROM_DIR}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${HOST}] $*" | tee -a "${LOG}"; }

log "=== 서버 파일 백업 시작 ==="
RESULT=0

# crontab 덤프
crontab -l > "${DST}/root_crontab.txt" 2>/dev/null || true
crontab -u clobot -l > "${DST}/clobot_crontab.txt" 2>/dev/null || true
log "crontab 덤프 완료"

# /etc
EXIT_C=0
rsync -a --delete \
    --exclude='*.swp' --exclude='*.bak' \
    /etc/ "${DST}/etc/" >> "${LOG}" 2>&1 || EXIT_C=$?
[ ${EXIT_C} -ne 0 ] && { log "/etc 실패 (exit: ${EXIT_C})"; RESULT=1; } || log "/etc 완료"

# /usr/local/bin (대형 바이너리 제외)
EXIT_C=0
rsync -a --delete \
    --exclude='node_exporter' \
    --exclude='snmp_exporter' \
    --exclude='docker-compose' \
    --exclude='dropwatch' \
    --exclude='dwdump' \
    /usr/local/bin/ "${DST}/usr_local_bin/" >> "${LOG}" 2>&1 || EXIT_C=$?
[ ${EXIT_C} -ne 0 ] && { log "/usr/local/bin 실패 (exit: ${EXIT_C})"; RESULT=1; } || log "/usr/local/bin 완료"

# /data/docker (대용량 데이터 볼륨·바이너리 제외)
if [ -d "/data/docker" ]; then
    EXIT_C=0
    rsync -a --delete \
        --exclude='prometheus/data/' \
        --exclude='grafana/data/' \
        --exclude='loki/data/' \
        --exclude='alertmanager/data/' \
        --exclude='sonarqube-data/' \
        --exclude='n8n/' \
        --exclude='mariadb/' \
        --exclude='storage/' \
        --exclude='gitlab-runner/builds/' \
        --exclude='gitlab-runner/cache/' \
        --exclude='amr_monitor/build/' \
        --exclude='*.iso' --exclude='*.tar' --exclude='*.tar.gz' \
        /data/docker/ "${DST}/data_docker/" >> "${LOG}" 2>&1 || EXIT_C=$?
    [ ${EXIT_C} -ne 0 ] && { log "/data/docker 실패 (exit: ${EXIT_C})"; RESULT=1; } || log "/data/docker 완료"
fi

SIZE=$(du -sh "${DST}" 2>/dev/null | cut -f1)

if [ ${RESULT} -eq 0 ]; then
    log "=== 완료: ${SIZE} → ${DST} ==="
else
    log "=== 일부 실패 ==="
fi

printf '# HELP server_file_backup_success 서버 파일 백업 성공 여부\n# TYPE server_file_backup_success gauge\nserver_file_backup_success{server="%s"} %s\n# HELP server_file_backup_last_timestamp 마지막 백업 Unix timestamp\n# TYPE server_file_backup_last_timestamp gauge\nserver_file_backup_last_timestamp{server="%s"} %s\n' \
    "${HOST}" "$(( 1 - RESULT ))" "${HOST}" "$(date +%s)" \
    > "${PROM_FILE}"

exit ${RESULT}
