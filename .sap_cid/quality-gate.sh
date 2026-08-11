#!/usr/bin/env sh
set -u

REPORT_DIR="quality-reports"

lint_failed=0
audit_failed=0

audit_failed_modules=""
audit_passed_modules=""

mkdir -p "$REPORT_DIR"

line() {
  echo "======================================================================"
}

small_line() {
  echo "----------------------------------------------------------------------"
}

section() {
  echo ""
  line
  echo "$1"
  line
}

pass() {
  echo "✅ PASS  $1"
}

fail() {
  echo "❌ FAIL  $1"
}

warn() {
  echo "⚠️  WARN  $1"
}

info() {
  echo "ℹ️  INFO  $1"
}

blocked_notice() {
  echo ""
  line
  echo "🚫 QUALITY GATE FAILED"
  line
  echo ""
  echo "Root cause is shown in the summary above/below."
  echo ""
  echo "Important:"
  echo "The Jenkins/SAP CI/CD error lines after this block are only wrapper output."
  echo "They are caused by this script returning exit code 1."
  echo "They are not the root cause."
  line
}

run_lint() {
  section "🔎 QUALITY GATE: LINT"

  info "Installing root dependencies"
  if ! npm ci > "$REPORT_DIR/lint-npm-ci.log" 2>&1; then
    fail "Lint preparation failed: npm ci"
    echo "    Log: $REPORT_DIR/lint-npm-ci.log"
    lint_failed=1
    return
  fi

  info "Running root ci-lint"
  if npm run ci-lint > "$REPORT_DIR/lint.log" 2>&1; then
    pass "Lint"
  else
    fail "Lint"
    lint_failed=1

    echo ""
    echo "    Log: $REPORT_DIR/lint.log"

    if [ -f "defaultlint.xml" ]; then
      cp defaultlint.xml "$REPORT_DIR/defaultlint.xml"
      echo "    Report: $REPORT_DIR/defaultlint.xml"
    fi

    echo ""
    echo "    Last lint output:"
    small_line
    tail -n 30 "$REPORT_DIR/lint.log"
    small_line
  fi
}

audit_summary_from_json() {
  json_file="$1"

  if command -v node >/dev/null 2>&1; then
    node - "$json_file" <<'NODE'
const fs = require("fs");
const file = process.argv[2];

try {
  const raw = fs.readFileSync(file, "utf8").trim();

  if (!raw) {
    console.log("    Summary: no audit JSON output found");
    process.exit(0);
  }

  const data = JSON.parse(raw);
  const meta = data.metadata && data.metadata.vulnerabilities
    ? data.metadata.vulnerabilities
    : {};

  const critical = meta.critical || 0;
  const high = meta.high || 0;
  const moderate = meta.moderate || 0;
  const low = meta.low || 0;
  const info = meta.info || 0;

  console.log(`    Findings: critical=${critical}, high=${high}, moderate=${moderate}, low=${low}, info=${info}`);

  const vulnerabilities = data.vulnerabilities || {};
  const names = Object.keys(vulnerabilities);

  const blocking = names
    .map(name => ({ name, data: vulnerabilities[name] }))
    .filter(item => {
      const severity = item.data.severity || "";
      return severity === "critical" || severity === "high";
    })
    .slice(0, 5);

  if (blocking.length > 0) {
    console.log("    Blocking findings:");
    for (const item of blocking) {
      console.log(`    - ${item.name}: ${item.data.severity || "unknown"}`);
    }
  }
} catch (error) {
  console.log("    Summary: could not parse audit JSON");
}
NODE
  else
    echo "    Summary: node not available, JSON summary skipped"
  fi
}

run_audit_for_dir() {
  dir="$1"

  safe_name=$(echo "$dir" | sed 's#^\./##' | sed 's#^.$#root#' | sed 's#[/.]#-#g')
  json_file="$REPORT_DIR/audit-${safe_name}.json"
  log_file="$REPORT_DIR/audit-${safe_name}.log"

  echo ""
  echo "🔐 AUDIT $dir"

  # Important:
  # npm audit output is intentionally not printed to console.
  # Full output is stored in JSON/log files instead.
  if (cd "$dir" && npm audit --audit-level=high --json > "../../$json_file" 2> "../../$log_file"); then
    pass "Audit $dir"
    audit_passed_modules="$audit_passed_modules $dir"
  else
    fail "Audit $dir"
    audit_failed=1
    audit_failed_modules="$audit_failed_modules $dir"

    echo "    Reason: high or critical npm vulnerabilities found"
    echo "    Report: $json_file"
    echo "    Log: $log_file"
    audit_summary_from_json "$json_file"
  fi
}

run_audit() {
  section "🛡️ QUALITY GATE: SECURITY AUDIT"

  info "npm audit is executed with --audit-level=high"
  info "Full npm audit output is not printed, only stored in report files"

  run_audit_for_dir "."

  if [ -d "./app" ]; then
    for pkg in $(find ./app -name package.json -not -path "*/node_modules/*" | sort); do
      dir=$(dirname "$pkg")
      run_audit_for_dir "$dir"
    done
  else
    warn "No ./app folder found. UI app audit skipped."
  fi
}

print_summary() {
  section "📌 QUALITY GATE SUMMARY"

  if [ "$lint_failed" -eq 0 ]; then
    pass "Lint"
  else
    fail "Lint"
  fi

  if [ "$audit_failed" -eq 0 ]; then
    pass "Security audit"
  else
    fail "Security audit"
  fi

  echo ""

  if [ -n "$audit_failed_modules" ]; then
    echo "❌ Audit failed modules:"
    for module in $audit_failed_modules; do
      echo "   - $module"
    done
    echo ""
  fi

  if [ -n "$audit_passed_modules" ]; then
    echo "✅ Audit passed modules:"
    for module in $audit_passed_modules; do
      echo "   - $module"
    done
    echo ""
  fi

  echo "📁 Reports:"
  echo "   - $REPORT_DIR/"

  echo ""

  if [ "$lint_failed" -ne 0 ] || [ "$audit_failed" -ne 0 ]; then
    echo "🚫 Result: PIPELINE BLOCKED"

    if [ "$lint_failed" -ne 0 ]; then
      echo "   - Blocked by lint"
    fi

    if [ "$audit_failed" -ne 0 ]; then
      echo "   - Blocked by security audit"
    fi

    blocked_notice
    exit 1
  fi

  echo "✅ Result: QUALITY GATE PASSED"
  line
}

section "🚦 QUALITY GATE START"

run_lint
run_audit
print_summary
