#!/bin/sh
CWE="$1"
BIN_DIR=~/tests/juliet/cwe-${CWE}/bin
OUT_DIR=~/tests/juliet/cwe-${CWE}

printf '%s' "test" > /tmp/in.txt

echo "===== GOOD =====" > "${OUT_DIR}/good.run"
for t in "${BIN_DIR}"/good/*-good; do
    [ -f "$t" ] || continue
    timeout 10s "$t" < /tmp/in.txt
    echo "$t $?" >> "${OUT_DIR}/good.run"
done

echo "===== BAD =====" > "${OUT_DIR}/bad.run"
for t in "${BIN_DIR}"/bad/*-bad; do
    [ -f "$t" ] || continue
    timeout 10s "$t" < /tmp/in.txt
    echo "$t $?" >> "${OUT_DIR}/bad.run"
done

echo "Done."
