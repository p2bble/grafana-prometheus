#!/bin/bash
set -uo pipefail

BACKUP_DIR="/storage/backup/sonarqube"
LOG="/var/log/sonarqube-backup.log"
PROM_DIR="/var/lib/node_exporter/textfile"
PROM_FILE="${PROM_DIR}/sonarqube_backup.prom"
DATE=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="${BACKUP_DIR}/sonarqubedb_${DATE}.sql.gz"
RETENTION_DAYS=7

mkdir -p "${BACKUP_DIR}" "${PROM_DIR}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] SonarQube 백업 시작" >> "${LOG}"

EXIT_CODE=0
docker exec -e PGPASSWORD='sonarqube158#$!' sonarqube-db \
  pg_dump -U cromsteamuser sonarqubedb 2>>"${LOG}" | gzip > "${BACKUP_FILE}" || EXIT_CODE=$?

if [ ${EXIT_CODE} -eq 0 ] && [ -s "${BACKUP_FILE}" ]; then
  RESULT=1
  SIZE=$(du -sh "${BACKUP_FILE}" | cut -f1)
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 백업 완료: ${BACKUP_FILE} (${SIZE})" >> "${LOG}"
  find "${BACKUP_DIR}" -name "sonarqubedb_*.sql.gz" -mtime +${RETENTION_DAYS} -delete
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${RETENTION_DAYS}일 초과 파일 삭제 완료" >> "${LOG}"
else
  RESULT=0
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 백업 실패 (exit: ${EXIT_CODE})" >> "${LOG}"
  rm -f "${BACKUP_FILE}"
fi

printf '# HELP sonarqube_backup_success SonarQube DB 백업 성공 여부\n# TYPE sonarqube_backup_success gauge\nsonarqube_backup_success %s\n# HELP sonarqube_backup_last_timestamp 마지막 백업 Unix timestamp\n# TYPE sonarqube_backup_last_timestamp gauge\nsonarqube_backup_last_timestamp %s\n' \
  "${RESULT}" "$(date +%s)" > "${PROM_FILE}"
