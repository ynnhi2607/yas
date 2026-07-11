#!/usr/bin/env bash
set -euo pipefail

if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source . --config gitleaks.toml --verbose --no-git
  exit 0
fi

if [[ ! -x ./gitleaks ]]; then
  curl -ssfL https://github.com/gitleaks/gitleaks/releases/download/v8.18.2/gitleaks_8.18.2_linux_x64.tar.gz | tar -xz gitleaks
  chmod +x ./gitleaks
fi

./gitleaks detect --source . --config gitleaks.toml --verbose --no-git
