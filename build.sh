#!/usr/bin/env bash
# Builds dist/Referral-Dash-<version>-Mac-<chip>.zip on a Mac, from a clean checkout.
# The chip is the Mac running the build: Apple Silicon (M1 and later) or Intel.
set -euo pipefail
cd "$(dirname "$0")"

PYTHON="${PYTHON:-python3}"
[ -d .venv ] || "$PYTHON" -m venv .venv
.venv/bin/python -m pip install --quiet --disable-pip-version-check -r requirements.txt pyinstaller
.venv/bin/python -m unittest discover -s tests || { echo "Tests failed; nothing was built." >&2; exit 1; }

[ -f drive_oauth_client.json ] || echo "warning: drive_oauth_client.json is missing: this build hides Connect Google Drive." >&2
version="$(.venv/bin/python -c 'from referral_dash.settings import VERSION; print(VERSION)')"
case "$(uname -m)" in
  arm64) chip="Apple-Silicon" ;;
  *) chip="Intel" ;;
esac
.venv/bin/python -m PyInstaller --noconfirm --clean ReferralDash.spec

release="dist/Referral Dash $version"
rm -rf "$release"
mkdir -p "$release"
ditto "dist/Referral Dash.app" "$release/Referral Dash.app"
cp -R licenses "$release/Licenses"
cp "docs/START HERE.txt" "$release/"

# The exact packaged app must render the sample before the ZIP is made.
check="$(mktemp -d)"
"$release/Referral Dash.app/Contents/MacOS/Referral Dash" --self-test \
  "$PWD/referral_dash/sample-data/sample-referrals.csv" "$check" 2026-10-01 2026-10-08 || true
.venv/bin/python - "$check/self-test-result.json" <<'EOF'
import json, sys
result = json.load(open(sys.argv[1], encoding="utf-8"))
if result["status"] != "passed":
    sys.exit(f"Packaged self-test failed: {result['error']}")
if not result["facts"].get("comparison_period"):
    sys.exit("Packaged self-test made no week-before comparison.")
print(f"Self-test passed: {result['facts']['images']} sample images rendered by the packaged app.")
EOF

zip="dist/Referral-Dash-$version-Mac-$chip.zip"
rm -f "$zip"
# ditto keeps the app's links and permissions, which a plain zip can break.
(cd dist && ditto -c -k --keepParent "Referral Dash $version" "../$zip")
echo "Built $zip"
