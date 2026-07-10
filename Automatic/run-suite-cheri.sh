#!/usr/bin/env bash

# Pas de paramètre -e : le script ne s'arrête pas si un outil échoue
set -uo pipefail

# NOTE : Le script considère que CHERI (QEMU) tourne sur root avec une connexion SSH active

# CWE à tester (modifiable)
CWES=(123 121 401)

SSH_HOST="root@localhost"
SSH_PORT=10022

# Dossier où se trouve cheribuild
CHERI_DIR="$HOME/cheribuild"

# Dossier racine où le script génèrera des fichiers par CWE 
CHERI_BUILD_ROOT="/mnt/cheri-data/cheri/build"

# Dossier où se trouvent les codes sources par CWE
CHERI_TESTCASES_DIR="/mnt/cheri-data/cheri/juliet-test-suite/testcases"

# Suppression des codes C++ car le script ne gère que les codes C
echo "Suppression des fichiers .cpp dans ${CHERI_TESTCASES_DIR}..."
find "${CHERI_TESTCASES_DIR}" -name "*.cpp" -delete

# Script de parsing des fichiers .run générés (fourni par Juliet)
PARSE_SCRIPT="/mnt/cheri-data/cheri/juliet-test-suite/parse-cwe-status.py"

# Script d'exécution de chaque CWE sur CHERI
REMOTE_RUN_SCRIPT="/root/tests/juliet/run_juliet_cwe.bash"

# Dossier de résultats, identifié par la date et l'heure
RESULTS_BASE="$(pwd)/results_cheri/$(date +%Y%m%d_%H%M)"
mkdir -p "${RESULTS_BASE}"

# Fichier .csv avec le code de sortie et la durée de chaque étape
SUMMARY_CSV="${RESULTS_BASE}/run_summary.csv"
echo "cwe,phase,exit_code,duration_s" > "${SUMMARY_CSV}"

# Timeout pour chaque étape pour éviter que ça bloque l'exécution des CWE suivants
TIMEOUT_PHASE=10800 # = 3h

# Fonction pour exécuter chaque étape en notant le de sortie et la durée dans le .csv
run_phase() {
  local cwe="$1" phase="$2"; shift 2
  local start end code
  start=$(date +%s)
  timeout "${TIMEOUT_PHASE}" "$@"
  code=$?
  end=$(date +%s)
  echo "${cwe},${phase},${code},$((end-start))" >> "${SUMMARY_CSV}"
  return $code
}

# Exécute le script depuis le dossier cheribuild
cd "${CHERI_DIR}"

# Boucle pour chaque CWE testé
for cwe in "${CWES[@]}"; do

  # Vérifie que la connexion SSH est bien active
  if ! ssh -p "${SSH_PORT}" -o ConnectTimeout=5 "${SSH_HOST}" true 2>/dev/null; then
    echo "CheriBSD injoignable, arrêt du run à $(date)" | tee -a "${RESULTS_BASE}/ABORTED.txt"
    break
  fi

  # Dossier de résultats par CWE
  OUTDIR="${RESULTS_BASE}/CWE${cwe}"
  mkdir -p "${OUTDIR}"

  # Fichier contenant les logs du script
  LOG="${OUTDIR}/build_run.log"

  # Dossier où les binaires de ce CWE seront générés
  SOURCE_BIN="${CHERI_BUILD_ROOT}/juliet-cwe-${cwe}-riscv64-purecap-build/bin"
  
  # Dossier où seront exécutés les binaires sur l'infrastructure CHERI
  DEST_REMOTE="/root/tests/juliet/cwe-${cwe}"

  echo "===== CWE${cwe} : début $(date) ====="

  # 1. Compilation des codes sources
  if ! run_phase "$cwe" build \
    ./cheribuild.py "juliet-cwe-${cwe}-riscv64-purecap" --build >> "${LOG}" 2>&1; then
    echo "Build échoué pour CWE${cwe}, transfert / execution non fiables" | tee -a "${LOG}"
    continue
  fi
  echo "  [CWE${cwe}] build terminé ($(date +%H:%M:%S))"

  # 2. Transfert des binaires compilés à CHERI
  ssh -p "${SSH_PORT}" "${SSH_HOST}" "mkdir -p ${DEST_REMOTE}"
  if ! run_phase "$cwe" transfer \
    scp -P "${SSH_PORT}" -r "${SOURCE_BIN}" "${SSH_HOST}:${DEST_REMOTE}/" >> "${LOG}" 2>&1; then
    echo "Transfert échoué pour CWE${cwe}" | tee -a "${LOG}"
    continue
  fi
  echo "  [CWE${cwe}] transfert terminé ($(date +%H:%M:%S))"

  # 3. Exécution des binaires sur CHERI
  run_phase "$cwe" execute \
    ssh -p "${SSH_PORT}" "${SSH_HOST}" "${REMOTE_RUN_SCRIPT} ${cwe}" >> "${LOG}" 2>&1
  echo "  [CWE${cwe}] exécution terminée ($(date +%H:%M:%S))"

  # Récupération des fichiers .run obtenus (contiennent les codes de sortie de chaque programme)
  scp -P "${SSH_PORT}" "${SSH_HOST}:${DEST_REMOTE}/bad.run"  "${OUTDIR}/" 2>>"${LOG}"
  scp -P "${SSH_PORT}" "${SSH_HOST}:${DEST_REMOTE}/good.run" "${OUTDIR}/" 2>>"${LOG}"

  # Supprime les binaires sur CHERI pour ne pas saturer la mémoire disponible
  ssh -p "${SSH_PORT}" "${SSH_HOST}" "rm -rf ${DEST_REMOTE}"
  echo "  [CWE${cwe}] résultats récupérés ($(date +%H:%M:%S))"

  # Parse les résultas obtenus
  [ -f "${OUTDIR}/bad.run" ]  && python3 "${PARSE_SCRIPT}" "${OUTDIR}/bad.run"  > "${OUTDIR}/status_bad.txt"  2>&1
  [ -f "${OUTDIR}/good.run" ] && python3 "${PARSE_SCRIPT}" "${OUTDIR}/good.run" > "${OUTDIR}/status_good.txt" 2>&1
  echo "===== CWE${cwe} : terminé $(date +%H:%M:%S) ====="
done

echo "DONE $(date)" > "${RESULTS_BASE}/DONE"
