#!/bin/bash
set -uo pipefail

SRC="/data/docker/n8n"
BACKUP_DIR="/storage/backup/n8n"
LOG="/var/log/n8n-backup.log"
PROM_DIR="/var/lib/node_exporter/textfile"
PROM_FILE="${PROM_DIR}/n8n_backup.prom"
DATE=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="${BACKUP_DIR}/n8n_${DATE}.tar.gz"
RETENTION_DAYS=14

mkdir -p "${BACKUP_DIR}" "${PROM_DIR}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] n8n 백업 시작" >> "${LOG}"

EXIT_CODE=0
tar -czf "${BACKUP_FILE}" -C "$(dirname ${SRC})" "$(basename ${SRC})" 2>>"${LOG}" || EXIT_CODE=$?

if [ ${EXIT_CODE} -eq 0 ] && [ -s "${BACKUP_FILE}" ]; then
  RESULT=1
  SIZE=$(du -sh "${BACKUP_FILE}" | cut -f1)
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 백업 완료: ${BACKUP_FILE} (${SIZE})" >> "${LOG}"
  find "${BACKUP_DIR}" -name "n8n_*.tar.gz" -mtime +${RETENTION_DAYS} -delete
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${RETENTION_DAYS}일 초과 파일 삭제 완료" >> "${LOG}"
else
  RESULT=0
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 백업 실패 (exit: ${EXIT_CODE})" >> "${LOG}"
  rm -f "${BACKUP_FILE}"
fi

printf '# HELP n8n_backup_success n8n 백업 성공 여부\n# TYPE n8n_backup_success gauge\nn8n_backup_success %s\n# HELP n8n_backup_last_timestamp 마지막 백업 Unix timestamp\n# TYPE n8n_backup_last_timestamp gauge\nn8n_backup_last_timestamp %s\n' \
  "${RESULT}" "$(date +%s)" > "${PROM_FILE}"
