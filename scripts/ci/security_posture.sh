#!/usr/bin/env bash

set -euo pipefail

failures=0

report_failure() {
  echo "::error::$1"
  failures=$((failures + 1))
}

echo "Checking tracked files for secret-bearing names..."
blocked_files="$({
  git ls-files | grep -E '(^|/)\.env($|\.)|(^|/)[^/]+\.(p8|p12|pem|key|mobileprovision)$|(^|/)Secrets\.xcconfig$' || true
} | grep -vE '(^|/)\.env\.example$' || true)"
if [[ -n "${blocked_files}" ]]; then
  echo "${blocked_files}"
  report_failure "Secret-bearing files are tracked by Git."
fi

echo "Scanning repository history for common credential formats..."
credential_pattern='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|sk_live_[A-Za-z0-9]{16,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
if findings="$(git grep -nIE "${credential_pattern}" -- . \
    ':(exclude)scripts/ci/security_posture.sh' \
    ':(exclude).gitignore' 2>/dev/null)"; then
  echo "${findings}"
  report_failure "A likely credential was found in the working tree."
fi
while IFS= read -r revision; do
  if findings="$(git grep -nIE "${credential_pattern}" "${revision}" -- . \
      ':(exclude)scripts/ci/security_posture.sh' \
      ':(exclude).gitignore' 2>/dev/null)"; then
    echo "${findings}"
    report_failure "A likely credential was found in Git history at ${revision}."
  fi
done < <(git rev-list --all)

echo "Checking production code for insecure transport overrides..."
if findings="$(git grep -nE 'http://|NSAllowsArbitraryLoads|allowsAnyHTTPSCertificate|setAllowsAnyHTTPSCertificate' -- '75Hard/**' 2>/dev/null)"; then
  echo "${findings}"
  report_failure "Production code contains an insecure transport pattern."
fi

echo "Checking production code for unsafe ad-hoc logging..."
if findings="$(git grep -nE '(print|debugPrint|dump|NSLog)[[:space:]]*\(' -- '75Hard/**/*.swift' 2>/dev/null)"; then
  echo "${findings}"
  report_failure "Production code contains ad-hoc logging that could expose sensitive data."
fi

echo "Checking GitHub Actions for immutable references..."
while IFS= read -r workflow; do
  while IFS= read -r action_reference; do
    [[ -z "${action_reference}" ]] && continue
    [[ "${action_reference}" == ./* ]] && continue
    action_version="${action_reference##*@}"
    if [[ ! "${action_version}" =~ ^[0-9a-f]{40}$ ]]; then
      report_failure "${workflow} uses mutable Action reference ${action_reference}."
    fi
  done < <(sed -nE 's/^[[:space:]]*-[[:space:]]*uses:[[:space:]]*([^[:space:]#]+).*$/\1/p' "${workflow}")
done < <(find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) -print)

echo "Checking workflow triggers and permissions..."
if grep -R -nE '^[[:space:]]*pull_request_target:' .github/workflows; then
  report_failure "pull_request_target is forbidden because it can expose privileged context to untrusted code."
fi
if grep -R -nE '^[[:space:]]*(contents|actions|checks|deployments|id-token|packages|security-events|statuses):[[:space:]]*write' .github/workflows; then
  report_failure "A workflow requests write permission; document and narrowly isolate it before use."
fi

if (( failures > 0 )); then
  echo "Security posture failed with ${failures} finding(s)."
  exit 1
fi

echo "Security posture checks passed."
