#!/usr/bin/env bash
set -uo pipefail

CWES=(121)
SSH_PORT=10022
SSH_HOST="root@localhost"
CHERI_DIR="$HOME/cheribuild"
CHERI_BUILD_ROOT="/mnt/cheri-data/cheri/build"

RESULTS_BASE="$(pwd)/results_cheri/$(date +%Y%m%d_%H%M)"
mkdir -p "${RESULTS_BASE}"
SUMMARY_CSV="${RESULTS_BASE}/run_summary.csv"
echo "cwe,phase,exit_code,duration_s" > "${SUMMARY_CSV}"

CHERI_TESTCASES_DIR="/mnt/cheri-data/cheri/juliet-test-suite/testcases"
echo "Suppression des fichiers .cpp dans ${CHERI_TESTCASES_DIR}..."
find "${CHERI_TESTCASES_DIR}" -name "*.cpp" -delete

PARSE_SCRIPT="$(pwd)/parse-cwe-status.py"

run_phase() {
  local cwe="$1" phase="$2"; shift 2
  local start end code
  start=$(date +%s)
  "$@"
  code=$?
  end=$(date +%s)
  echo "${cwe},${phase},${code},$((end-start))" >> "${SUMMARY_CSV}"
  return $code
}

cd "${CHERI_DIR}"

for cwe in "${CWES[@]}"; do
  OUTDIR="${RESULTS_BASE}/CWE${cwe}"
  mkdir -p "${OUTDIR}"
  LOG="${OUTDIR}/build_run.log"
  SOURCE_BIN="${CHERI_BUILD_ROOT}/juliet-cwe-${cwe}-riscv64-purecap-build/bin"
  DEST_REMOTE="/root/tests/juliet/cwe-${cwe}"

  echo "===== CWE${cwe} : $(date) =====" | tee -a "${LOG}"

  # 1. Compilation
  run_phase "$cwe" build \
    ./cheribuild.py "juliet-cwe-${cwe}-riscv64-purecap" --build >> "${LOG}" 2>&1

  # 2. Transfert — on crée le dossier distant d'abord, pour garantir que "bin"
  #    atterrit bien EN TANT QUE sous-dossier (comportement scp sinon ambigu
  #    selon que le dossier de destination existe déjà ou non)
  ssh -p "${SSH_PORT}" "${SSH_HOST}" "mkdir -p ${DEST_REMOTE}"
  run_phase "$cwe" transfer \
    scp -P "${SSH_PORT}" -r "${SOURCE_BIN}" "${SSH_HOST}:${DEST_REMOTE}/" >> "${LOG}" 2>&1

  # 3. Exécution sur CheriBSD — CWE passé en paramètre
  run_phase "$cwe" execute \
    ssh -p "${SSH_PORT}" "${SSH_HOST}" "/root/tests/juliet/cheri_juliet.bash ${cwe}" >> "${LOG}" 2>&1

  # 4. Rapatriement direct depuis le dossier du CWE (plus de /root à nettoyer)
  scp -P "${SSH_PORT}" "${SSH_HOST}:${DEST_REMOTE}/bad.run"  "${OUTDIR}/" 2>>"${LOG}"
  scp -P "${SSH_PORT}" "${SSH_HOST}:${DEST_REMOTE}/good.run" "${OUTDIR}/" 2>>"${LOG}"

  # 5. Parsing
  [ -f "${OUTDIR}/bad.run" ]  && python3 "${PARSE_SCRIPT}" "${OUTDIR}/bad.run"  > "${OUTDIR}/status_bad.txt"  2>&1
  [ -f "${OUTDIR}/good.run" ] && python3 "${PARSE_SCRIPT}" "${OUTDIR}/good.run" > "${OUTDIR}/status_good.txt" 2>&1
done

echo "DONE $(date)" > "${RESULTS_BASE}/DONE"
