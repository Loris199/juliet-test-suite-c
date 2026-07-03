#!/usr/bin/env python3
"""
Résume les logs Valgrind d'un dossier valgrind_logs/ en distinguant
tests "good" et "bad", pour repérer faux positifs / faux négatifs.
Usage: python3 parse_valgrind_summary.py <chemin_valgrind_logs> [> summary.txt]
"""
import sys, re, glob, os

def parse_bytes(s):
    return int(s.replace(",", ""))

def parse_log(path):
    text = open(path, errors="replace").read()
    if not text.strip():
        return None  # log vide (crash/timeout probable avant l'écriture)

    result = {"definitely": 0, "indirectly": 0, "possibly": 0, "errors": 0}
    m = re.search(r"definitely lost:\s*([\d,]+) bytes", text)
    if m: result["definitely"] = parse_bytes(m.group(1))
    m = re.search(r"indirectly lost:\s*([\d,]+) bytes", text)
    if m: result["indirectly"] = parse_bytes(m.group(1))
    m = re.search(r"possibly lost:\s*([\d,]+) bytes", text)
    if m: result["possibly"] = parse_bytes(m.group(1))
    m = re.search(r"ERROR SUMMARY:\s*(\d+) errors", text)
    if m: result["errors"] = int(m.group(1))

    result["flagged"] = (result["definitely"] or result["indirectly"]
                          or result["possibly"] or result["errors"])
    return result

def main():
    if len(sys.argv) != 2:
        print("Usage: parse_valgrind_summary.py <valgrind_logs_dir>", file=sys.stderr)
        sys.exit(1)

    log_dir = sys.argv[1]
    files = sorted(glob.glob(os.path.join(log_dir, "*.log")))
    if not files:
        print(f"Aucun fichier .log trouvé dans {log_dir}")
        return

    bad_flagged, bad_clean, bad_empty = [], [], []
    good_flagged, good_clean, good_empty = [], [], []

    for f in files:
        name = os.path.basename(f)[:-4]  # retire ".log"
        if name.endswith("-bad"):
            kind = "bad"
        elif name.endswith("-good"):
            kind = "good"
        else:
            kind = "unknown"

        res = parse_log(f)
        if res is None:
            (bad_empty if kind == "bad" else good_empty if kind == "good" else good_empty).append(name)
            continue
        if res["flagged"]:
            entry = (name, res)
            (bad_flagged if kind == "bad" else good_flagged).append(entry)
        else:
            (bad_clean if kind == "bad" else good_clean).append(name)

    total_bad = len(bad_flagged) + len(bad_clean) + len(bad_empty)
    total_good = len(good_flagged) + len(good_clean) + len(good_empty)

    print(f"=== Résumé Valgrind ===")
    print(f"Total analysé : {total_bad + total_good}  ({total_bad} bad / {total_good} good)\n")

    print(f"--- Bad SANS leak/erreur détecté (faux négatifs — {len(bad_clean)}) ---")
    for name in bad_clean:
        print(f"  {name}")
    print()

    print(f"--- Good AVEC leak/erreur détecté (faux positifs — {len(good_flagged)}) ---")
    for name, res in good_flagged:
        details = []
        if res["definitely"]: details.append(f"definitely lost {res['definitely']}B")
        if res["indirectly"]: details.append(f"indirectly lost {res['indirectly']}B")
        if res["possibly"]:   details.append(f"possibly lost {res['possibly']}B")
        if res["errors"]:     details.append(f"{res['errors']} erreur(s)")
        print(f"  {name} : {', '.join(details)}")
    print()

    if bad_empty or good_empty:
        print(f"--- Logs vides/absents (crash ou timeout avant écriture — {len(bad_empty)+len(good_empty)}) ---")
        for name in bad_empty: print(f"  {name} (bad)")
        for name in good_empty: print(f"  {name} (good)")
        print()

    print("--- Totaux ---")
    print(f"Bad  : {len(bad_flagged)}/{total_bad} détectés correctement "
          f"({len(bad_clean)} faux négatifs, {len(bad_empty)} logs vides)")
    print(f"Good : {len(good_clean)}/{total_good} propres "
          f"({len(good_flagged)} faux positifs, {len(good_empty)} logs vides)")

if __name__ == "__main__":
    main()
