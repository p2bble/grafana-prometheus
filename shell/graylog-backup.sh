#!/bin/bash
set -uo pipefail

BACKUP_DIR="/storage/backup/graylog"
LOG="/var/log/graylog-backup.log"
PROM_DIR="/var/lib/node_exporter/textfile"
PROM_FILE="${PROM_DIR}/graylog_backup.prom"
DATE=$(date '+%Y%m%d_%H%M%S')
MONGO_VOL="/var/lib/docker/volumes/docker_graylog-mongo-data/_data"
OS_VOL="/var/lib/docker/volumes/docker_graylog-opensearch-data/_data"
RETENTION_DAYS=7

mkdir -p "${BACKUP_DIR}/mongo" "${BACKUP_DIR}/opensearch" "${PROM_DIR}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Graylog 백업 시작" >> "${LOG}"

MONGO_RESULT=0
OS_RESULT=0

# MongoDB: mongodump (핫 백업, 무중단)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] MongoDB dump 시작" >> "${LOG}"
MONGO_EXIT=0
docker exec mongo mongodump --out /tmp/mongodump_${DATE} 2>>"${LOG}" || MONGO_EXIT=$?

if [ ${MONGO_EXIT} -eq 0 ]; then
  docker cp mongo:/tmp/mongodump_${DATE} "${BACKUP_DIR}/mongo/mongodump_${DATE}" 2>>"${LOG}"
  docker exec mongo rm -rf /tmp/mongodump_${DATE}
  MONGO_SIZE=$(du -sh "${BACKUP_DIR}/mongo/mongodump_${DATE}" | cut -f1)
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] MongoDB dump 완료 (${MONGO_SIZE})" >> "${LOG}"
  find "${BACKUP_DIR}/mongo" -maxdepth 1 -name "mongodump_*" -mtime +${RETENTION_DAYS} -exec rm -rf {} +
  MONGO_RESULT=1
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] MongoDB dump 실패 (exit: ${MONGO_EXIT})" >> "${LOG}"
fi

# OpenSearch: 볼륨 디렉토리 rsync (로그 데이터, 정합성 허용 수준)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] OpenSearch 볼륨 rsync 시작" >> "${LOG}"
OS_EXIT=0
rsync -a --delete "${OS_VOL}/" "${BACKUP_DIR}/opensearch/" 2>>"${LOG}" || OS_EXIT=$?

if [ ${OS_EXIT} -eq 0 ]; then
  OS_SIZE=$(du -sh "${BACKUP_DIR}/opensearch" | cut -f1)
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] OpenSearch rsync 완료 (${OS_SIZE})" >> "${LOG}"
  OS_RESULT=1
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] OpenSearch rsync 실패 (exit: ${OS_EXIT})" >> "${LOG}"
fi

RESULT=$(( MONGO_RESULT & OS_RESULT ))

printf '# HELP graylog_backup_success Graylog 백업 성공 여부 (MongoDB+OpenSearch 모두 성공=1)\n# TYPE graylog_backup_success gauge\ngraylog_backup_success %s\n# HELP graylog_backup_last_timestamp 마지막 백업 Unix timestamp\n# TYPE graylog_backup_last_timestamp gauge\ngraylog_backup_last_timestamp %s\n' \
  "${RESULT}" "$(date +%s)" > "${PROM_FILE}"
