#!/usr/bin/env sh
set -u

echo "=== QUALITY GATE: LINT (BLOCKING, ROOT) ==="
lint_failed=0
echo "[LINT] Installing root dependencies"
if npm ci; then
  echo "[LINT] Running root ci-lint"
  if npm run ci-lint; then
    echo "[PASS] LINT ."
  else
    echo "[FAIL] LINT ."
    lint_failed=1
  fi
else
  echo "[FAIL] LINT . (npm ci failed)"
  lint_failed=1
fi

echo "=== QUALITY GATE: AUDIT (HIGH/CRITICAL BLOCKING) ==="
audit_failed=0
audit_failed_modules=""
for pkg in $(find . -name package.json -not -path "*/node_modules/*" -not -path "./gen/*" | sort); do
  dir=$(dirname "$pkg")
  echo "[AUDIT] $dir"
  if (cd "$dir" && npm run ci-audit); then
    echo "[PASS] AUDIT $dir"
  else
    echo "[FAIL] AUDIT $dir"
    audit_failed=1
    audit_failed_modules="$audit_failed_modules $dir"
  fi
done

echo "=== QUALITY GATE SUMMARY ==="
echo "LINT_FAILED=$lint_failed"
echo "AUDIT_FAILED=$audit_failed"
if [ -n "$audit_failed_modules" ]; then
  echo "AUDIT_FAILED_MODULES:$audit_failed_modules"
fi

if [ "$lint_failed" -ne 0 ] || [ "$audit_failed" -ne 0 ]; then
  if [ "$lint_failed" -ne 0 ]; then
    echo "PIPELINE BLOCKED BY LINT"
  fi
  if [ "$audit_failed" -ne 0 ]; then
    echo "PIPELINE BLOCKED BY AUDIT"
  fi
  exit 1
fi

echo "QUALITY GATE PASSED"
