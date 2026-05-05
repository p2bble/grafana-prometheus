#!/bin/bash
set -uo pipefail

SRC_DIR="/source/gitlab/current/backups"
DST="/data/docker/gitlab/backups"
LOG="/var/log/gitlab-rsync.log"
PROM_DIR="/var/lib/node_exporter/textfile"
PROM_FILE="${PROM_DIR}/gitlab_rsync.prom"

mkdir -p "${PROM_DIR}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] rsync 시작" >> "${LOG}"

LATEST=$(ls -t ${SRC_DIR}/*.tar 2>/dev/null | head -1)
LATEST_FILE=$(basename "${LATEST}")

if [ -z "${LATEST_FILE}" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 오류: 소스 백업 파일 없음" >> "${LOG}"
  exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 대상 파일: ${LATEST_FILE}" >> "${LOG}"

if [ -f "${DST}/${LATEST_FILE}" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 이미 최신 상태 (${LATEST_FILE}), 건너뜀" >> "${LOG}"
  RESULT=1
else
  find "${DST}" -maxdepth 1 -name "*.tar" -delete
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 구버전 삭제 완료" >> "${LOG}"

  EXIT_CODE=0
  rsync -av "${LATEST}" "${DST}/" >> "${LOG}" 2>&1 || EXIT_CODE=$?

  if [ ${EXIT_CODE} -eq 0 ]; then
    RESULT=1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] rsync 완료 (성공)" >> "${LOG}"
  else
    RESULT=0
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] rsync 실패 (exit: ${EXIT_CODE})" >> "${LOG}"
  fi
fi

printf '# HELP gitlab_rsync_success gitlab rsync 성공 여부\n# TYPE gitlab_rsync_success gauge\ngitlab_rsync_success %s\n# HELP gitlab_rsync_last_timestamp 마지막 rsync 완료 Unix timestamp\n# TYPE gitlab_rsync_last_timestamp gauge\ngitlab_rsync_last_timestamp %s\n' \
  "${RESULT}" "$(date +%s)" > "${PROM_FILE}"
