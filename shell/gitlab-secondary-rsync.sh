#!/bin/bash
set -uo pipefail

SRC="/data/docker/gitlab/backups/"
DST="/storage/backup/gitlab/secondary"
LOG="/var/log/gitlab-secondary-rsync.log"
PROM_DIR="/var/lib/node_exporter/textfile"
PROM_FILE="${PROM_DIR}/gitlab_secondary_rsync.prom"

mkdir -p "${DST}" "${PROM_DIR}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 2차 rsync 시작 (로컬 → NAS)" >> "${LOG}"

EXIT_CODE=0
rsync -av "${SRC}" "${DST}/" >> "${LOG}" 2>&1 || EXIT_CODE=$?

if [ ${EXIT_CODE} -eq 0 ]; then
  RESULT=1
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 2차 rsync 완료 (성공)" >> "${LOG}"
else
  RESULT=0
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 2차 rsync 실패 (exit: ${EXIT_CODE})" >> "${LOG}"
fi

printf '# HELP gitlab_secondary_rsync_success NAS 2차 rsync 성공 여부\n# TYPE gitlab_secondary_rsync_success gauge\ngitlab_secondary_rsync_success %s\n# HELP gitlab_secondary_rsync_last_timestamp 마지막 완료 Unix timestamp\n# TYPE gitlab_secondary_rsync_last_timestamp gauge\ngitlab_secondary_rsync_last_timestamp %s\n' \
  "${RESULT}" "$(date +%s)" > "${PROM_FILE}"
