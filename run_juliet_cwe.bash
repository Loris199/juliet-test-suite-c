#!/bin/sh

# Ce script est utilisé par CHERI pour exécuter un dossier contenant un CWE du repos Juliet
# Pour envoyer le script à CHERI : scp -P 10022 run_juliet_cwe.bash root@localhost:/root/tests/juliet/

CWE="$1"
BIN_DIR=~/tests/juliet/cwe-${CWE}/bin
OUT_DIR=~/tests/juliet/cwe-${CWE}

# Crée le fichier contenant l'input des tests (disparait lors d'un reboot!)
printf '%s' "test" > /tmp/in.txt

# Exécute tous les binaires "good"
echo "===== GOOD =====" > "${OUT_DIR}/good.run"
for t in "${BIN_DIR}"/good/*-good; do
    [ -f "$t" ] || continue
    timeout 20s "$t" < /tmp/in.txt
    echo "$t $?" >> "${OUT_DIR}/good.run"
done

#Exécute tous les binaires "bad"
echo "===== BAD =====" > "${OUT_DIR}/bad.run"
for t in "${BIN_DIR}"/bad/*-bad; do
    [ -f "$t" ] || continue
    timeout 20s "$t" < /tmp/in.txt
    echo "$t $?" >> "${OUT_DIR}/bad.run"
done

echo "Done."
