#!/usr/bin/env bash
# Each line: who, verb, resource, namespace, expected
cd "$(dirname "$0")/.."
OUT=evidence/rbac-test.log; : > $OUT; pass=0; fail=0
t() { got=$(kubectl auth can-i "$2" "$3" -n "$4" --as "$1" 2>/dev/null)
      [ "$got" = "$5" ] && { s=PASS; pass=$((pass+1)); } || { s=FAIL; fail=$((fail+1)); }
      printf '%-5s %-6s %-7s %-12s in %-11s expected=%-3s got=%s\n' $s "$1" "$2" "$3" "$4" "$5" "$got" | tee -a $OUT; }
t alice create deployments dev        yes
t alice delete pods        dev        yes
t alice create deployments staging    no
t alice get    pods        production no
t bob   get    pods        production yes
t bob   create deployments dev        no
t bob   delete pods        staging    no
t nobody get   pods        dev        no
echo "RESULT: $pass passed, $fail failed" | tee -a $OUT
