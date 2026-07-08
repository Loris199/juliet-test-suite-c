#!/usr/bin/env bash

# Pas de paramètre -e : le script ne s'arrête pas si un outil échoue
set -uo pipefail

# CWE à tester (modifiable)
CWES=(121 122 123 124 126 127 416 415 401)

# Outils à tester (modifiable, valeurs acceptées : gcc clang csa infer filc valgrind asan)
TOOLS=(gcc clang csa infer filc valgrind asan)

# Timeout pour chaque test, utilisé par juliet.py, en secondes
TIMEOUT_PER_TEST=5

# Timeout pour chaque outil, évite de bloquer les suivants
declare -A TIMEOUT_PER_TOOL=(
  [gcc]=7200        # = 2h
  [clang]=7200
  [csa]=7200
  [infer]=7200
  [valgrind]=18000  # = 5h
  [asan]=7200
  [filc]=7200
)

# Dossier où se trouvent les scripts et sous-dossiers Juliet
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

# Dossier de résultats, identifié par la date et l'heure
RESULTS_BASE="results/$(date +%Y%m%d_%H%M)"
mkdir -p "${RESULTS_BASE}"

# Fichier .csv avec le code de sortie et la durée de chaque étape
SUMMARY_CSV="${ROOT_DIR}/${RESULTS_BASE}/run_summary.csv"
echo "cwe,tool,exit_code,duration_s" > "${SUMMARY_CSV}"

# Suppression des codes C++ car le script ne gère que les codes C
echo "Suppression des fichiers .cpp dans ${ROOT_DIR}/testcases/..."
find "${ROOT_DIR}/testcases" -name "*.cpp" -delete

# Crée le fichier contenant l'input des tests (disparait lors d'un reboot!)
printf '%s' "test" > /tmp/in.txt

# Boucle sur chaque CWE testé
for cwe in "${CWES[@]}"; do

  # Boucle sur chaque outil testé
  for tool in "${TOOLS[@]}"; do

    # Dossier de résultats, par outil
    OUTDIR="${RESULTS_BASE}/CWE${cwe}/${tool}"
    mkdir -p "${OUTDIR}"

    # Fichier contenant les logs du script
    LOG="${OUTDIR}/build_run.log"

    # Réinitialise les variables d'environnement
    unset JULIET_CC JULIET_ASAN USE_INFER USE_VALGRIND INFER_RESULTS_DIR VALGRIND_LOG_DIR

    # Exécute le script juliet.py avec divers paramètres selon l'outil
    case "$tool" in

      gcc)
        export JULIET_CC="gcc"
        CMD=(python3 juliet.py "$cwe" -c -g -m -r -o "${OUTDIR}/bin" -t "${TIMEOUT_PER_TEST}")
        ;;

      clang)
        export JULIET_CC="clang"
        CMD=(python3 juliet.py "$cwe" -c -g -m -r -o "${OUTDIR}/bin" -t "${TIMEOUT_PER_TEST}")
        ;;

      csa)
        CMD=(scan-build -o "${OUTDIR}/csa-html" python3 juliet.py "$cwe" -c -g -m -o "${OUTDIR}/bin")
        ;;

      infer)
        export USE_INFER=1
        export INFER_RESULTS_DIR="${ROOT_DIR}/${OUTDIR}/infer-out"
        CMD=(python3 juliet.py "$cwe" -c -g -m -o "${OUTDIR}/bin")
        ;;

      valgrind)
        export USE_VALGRIND=1
        export VALGRIND_LOG_DIR="${ROOT_DIR}/${OUTDIR}/valgrind_logs"
        CMD=(python3 juliet.py "$cwe" -c -g -m -r -o "${OUTDIR}/bin" -t "${TIMEOUT_PER_TEST}")
        ;;

      asan)
        export JULIET_ASAN=1
        CMD=(python3 juliet.py "$cwe" -c -g -m -r -o "${OUTDIR}/bin" -t "${TIMEOUT_PER_TEST}")
        ;;

      filc)
        export JULIET_CC="/opt/fil/bin/filcc" # Basé sur l'installation de FilC
        CMD=(python3 juliet.py "$cwe" -c -g -m -r -o "${OUTDIR}/bin" -t "${TIMEOUT_PER_TEST}")
        ;;

      *)
        echo "outil inconnu: $tool" >&2
        continue
        ;;
    esac

    # Note le code de sortie et la durée de l'outil dans le .csv
    echo "===== CWE${cwe} / ${tool} : $(date) =====" | tee -a "${LOG}"
    start=$(date +%s)
    timeout "${TIMEOUT_PER_TOOL[$tool]}" "${CMD[@]}" >> "${LOG}" 2>&1
    code=$?
    end=$(date +%s)
    echo "${cwe},${tool},${code},$((end-start))" >> "${SUMMARY_CSV}"

    # Parse les résultas obtenus
    BIN_DIR="${ROOT_DIR}/${OUTDIR}/bin/CWE${cwe}"
    [ -f "${BIN_DIR}/bad.run" ]  && python3 parse-cwe-status.py "${BIN_DIR}/bad.run"  > "${OUTDIR}/status_bad.txt"  2>&1
    [ -f "${BIN_DIR}/good.run" ] && python3 parse-cwe-status.py "${BIN_DIR}/good.run" > "${OUTDIR}/status_good.txt" 2>&1

    # Récupération des fichiers .run obtenus (contiennent les codes de sortie de chaque programme)
    mkdir -p "${ROOT_DIR}/${OUTDIR}/run_logs"
    [ -f "${BIN_DIR}/bad.run" ]  && cp "${BIN_DIR}/bad.run"  "${ROOT_DIR}/${OUTDIR}/run_logs/"
    [ -f "${BIN_DIR}/good.run" ] && cp "${BIN_DIR}/good.run" "${ROOT_DIR}/${OUTDIR}/run_logs/"

    # Post-traitement Infer : l'analyse se fait après la capture
    if [ "$tool" = "infer" ]; then
        infer analyze --results-dir "${INFER_RESULTS_DIR}" > "${ROOT_DIR}/${OUTDIR}/infer_analyze.log" 2>&1
    fi

    # Post-traitement Valgrind : compile les outputs obtenus en un seul fichier
    if [ "$tool" = "valgrind" ]; then
        python3 parse_valgrind_summary.py "${ROOT_DIR}/${OUTDIR}/valgrind_logs" > "${ROOT_DIR}/${OUTDIR}/valgrind_summary.txt" 2>&1
    fi

    # Supprime les binaires pour ne pas saturer la mémoire disponible
    rm -rf "${ROOT_DIR}/${OUTDIR}/bin"
  done
done

echo "DONE $(date)" > "${ROOT_DIR}/${RESULTS_BASE}/DONE"
echo "Run terminé. Résultats dans ${RESULTS_BASE}/"
