#!/usr/bin/env bash
# run-one.sh <variant-file> <run-name>  - SYNTHETIC verification run
set -e
REPO=/home/losses/Development/tq-workspace/boring-wt-architecture
EV=/home/losses/Development/tq-workspace/dc-warn/out/flake-synthetic/evidence
STEP=$EV/step-report-from-yaml.sh
V=$1
NAME=$2
D=$EV/run-$NAME
mkdir -p "$D"
LOGPATH=$REPO/out/collected-suite.log
rm -f "$LOGPATH"
test ! -e "$LOGPATH"
cp "$V" "$LOGPATH"
sha256sum "$LOGPATH" | awk '{print $1}' > "$D/installed-log.sha256.before"
cat "$LOGPATH" > "$D/log-installed-at-LOG-path-SYNTHETIC.log"
: > "$D/step-summary-SYNTHETIC.md"
cd "$REPO"
export GITHUB_STEP_SUMMARY="$D/step-summary-SYNTHETIC.md"
set +e
bash -e "$STEP" > "$D/step-stdout-SYNTHETIC.log" 2>&1
RC=$?
set -e
echo "$RC" > "$D/step-exit-code.txt"
unset GITHUB_STEP_SUMMARY
sha256sum "$LOGPATH" | awk '{print $1}' > "$D/installed-log.sha256.after"
if cmp -s "$D/installed-log.sha256.before" "$D/installed-log.sha256.after"; then
  echo "IDENTICAL: the step read only the log this run installed (sha256 $(cat "$D/installed-log.sha256.before"))" > "$D/log-unchanged-during-run.txt"
else
  echo "CHANGED - INVESTIGATE" > "$D/log-unchanged-during-run.txt"
fi
rm -f "$LOGPATH"
echo "run $NAME done rc=$RC"
