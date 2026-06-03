#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PACKAGES=(
  "local-otel-workbench"
)
TARGET_VERSION="$(node -p "require('./packages/cli/package.json').version")"

echo "== target version =="
echo "local-otel-workbench@$TARGET_VERSION"
echo

echo "== npm identity =="
if npm whoami; then
  echo
else
  echo "Not logged in. Run 'npm login' before the real publish."
  echo
fi

echo "== package/version availability =="
for package_name in "${PACKAGES[@]}"; do
  if npm view "$package_name" name version --json >/tmp/local-otel-npm-view.json 2>/tmp/local-otel-npm-view.err; then
    echo "registered: $package_name"
    cat /tmp/local-otel-npm-view.json
  fi
  if grep -q "E404" /tmp/local-otel-npm-view.err; then
    echo "new package: $package_name"
  elif [ -s /tmp/local-otel-npm-view.err ]; then
    echo "Unable to confirm $package_name:"
    cat /tmp/local-otel-npm-view.err
    exit 1
  fi

  if npm view "$package_name@$TARGET_VERSION" version --json >/tmp/local-otel-npm-version.json 2>/tmp/local-otel-npm-version.err; then
    echo "VERSION EXISTS: $package_name@$TARGET_VERSION"
    cat /tmp/local-otel-npm-version.json
    exit 1
  fi
  if grep -q "E404" /tmp/local-otel-npm-version.err; then
    echo "target version available: $package_name@$TARGET_VERSION"
  else
    echo "Unable to confirm target version $package_name@$TARGET_VERSION:"
    cat /tmp/local-otel-npm-version.err
    exit 1
  fi
done
echo

echo "== repo release dry-run =="
pnpm release:dry-run
echo

echo "== npm publish dry-run =="
pnpm --filter local-otel-workbench publish --dry-run --access public --no-git-checks
echo

echo "Preflight complete. Real publish command:"
echo "  pnpm --filter local-otel-workbench publish --access public"
