#!/usr/bin/env bash
set -uo pipefail   # pas de -e : un outil qui échoue ne doit pas stopper les autres

CWES=(401)                        # numéros de CWE, sans le préfixe "CWE"
TOOLS=(csa infer filc valgrind asan)

TIMEOUT_PER_TEST=5                    # secondes, passé à juliet.py -t (timeout par test individuel)
TIMEOUT_PER_BUILD=7200                # secondes, garde-fou pour generate+make+run d'un CWE entier

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d_%H%M)"
RESULTS_BASE="results/${TS}"          # relatif à ROOT_DIR (= dossier contenant juliet.py)
SUMMARY_CSV="${ROOT_DIR}/${RESULTS_BASE}/run_summary.csv"

cd "${ROOT_DIR}"
mkdir -p "${RESULTS_BASE}"
echo "cwe,tool,exit_code,duration_s" > "${SUMMARY_CSV}"

# suppression des fichiers C++
echo "Suppression des fichiers .cpp dans testcases/..."
find "${ROOT_DIR}/testcases" -name "*.cpp" -delete

# les tests lisent leur entrée depuis ce fichier fixe
# (peut disparaître après un redémarrage de la VM si /tmp est vidé au boot)
printf '%s' "test" > /tmp/in.txt

for cwe in "${CWES[@]}"; do
  for tool in "${TOOLS[@]}"; do
    OUTDIR="${RESULTS_BASE}/CWE${cwe}/${tool}"
    mkdir -p "${OUTDIR}"
    LOG="${OUTDIR}/build_run.log"

    unset JULIET_CC JULIET_ASAN USE_INFER USE_VALGRIND INFER_RESULTS_DIR VALGRIND_LOG_DIR

    case "$tool" in
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
        export JULIET_CC="/opt/fil/bin/filcc"   # à confirmer / adapter selon ton install
        CMD=(python3 juliet.py "$cwe" -c -g -m -r -o "${OUTDIR}/bin" -t "${TIMEOUT_PER_TEST}")
        ;;
      *)
        echo "outil inconnu: $tool" >&2
        continue
        ;;
    esac

    echo "===== CWE${cwe} / ${tool} : $(date) =====" | tee -a "${LOG}"
    start=$(date +%s)
    timeout "${TIMEOUT_PER_BUILD}" "${CMD[@]}" >> "${LOG}" 2>&1
    code=$?
    end=$(date +%s)
    echo "${cwe},${tool},${code},$((end-start))" >> "${SUMMARY_CSV}"

    # résumé good/bad via le script Juliet existant
    BIN_DIR="${ROOT_DIR}/${OUTDIR}/bin/CWE${cwe}"
    [ -f "${BIN_DIR}/bad.run" ]  && python3 parse-cwe-status.py "${BIN_DIR}/bad.run"  > "${OUTDIR}/status_bad.txt"  2>&1
    [ -f "${BIN_DIR}/good.run" ] && python3 parse-cwe-status.py "${BIN_DIR}/good.run" > "${OUTDIR}/status_good.txt" 2>&1

    if [ "$tool" = "valgrind" ]; then
        python3 parse_valgrind_summary.py "${ROOT_DIR}/${OUTDIR}/valgrind_logs" > "${ROOT_DIR}/${OUTDIR}/valgrind_summary.txt" 2>&1
    fi

    # post-traitement Infer : l'analyse se fait après la capture
    if [ "$tool" = "infer" ]; then
        infer analyze --results-dir "${INFER_RESULTS_DIR}" > "${ROOT_DIR}/${OUTDIR}/infer_analyze.log" 2>&1
    fi
  done
done

echo "DONE $(date)" > "${ROOT_DIR}/${RESULTS_BASE}/DONE"
echo "Run terminé. Résultats dans ${RESULTS_BASE}/"
