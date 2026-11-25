#!/usr/bin/env bash
# Exercises every command against stand-ins for herdr and claude (tests/stubs).
# This checks the scripts' own logic. It does not prove that the real herdr and
# claude behave as their documentation says; `ticket doctor` and a first real
# ticket do that.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

export PATH="$ROOT/tests/stubs:$ROOT/bin:$PATH"
export STUB_DIR="$T/stub"
export TICKET_HARNESS_DATA="$T/data"
export TH_NOW="2026-11-13 10:00" TH_TODAY="2026-11-13"
unset TICKET_KEY TICKET_DIR TICKET_ROLE TICKETS_ROOT
export HOME="$T/home"; mkdir -p "$HOME"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
t()   { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
tn()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }
has() { grep -qF -- "$2" "$1"; }
count() { grep -c -- "$2" "$1" 2>/dev/null || true; }

REPO="$T/repo"; mkdir -p "$REPO/sub"; git -C "$REPO" init -q
cd "$REPO/sub" || exit 1
TK="$HOME/Desktop/tickets"
D1="$TK/PROJ-1"

echo "1. small ticket, not on disk"
t  "ticket PROJ-1 succeeds"              ticket PROJ-1
t  "seeds log.md"                        test -f "$D1/log.md"
t  "seeds STATUS.md as new"              has "$D1/STATUS.md" "status: new"
t  "seeds comms.md with Summary and Log" has "$D1/comms/comms.md" "## Log"
t  "creates files/ patches/ scripts/"    test -d "$D1/files" -a -d "$D1/patches" -a -d "$D1/scripts"
tn "leaves references.md to the skill"   test -e "$D1/references.md"
tn "does not write ticket.md"            test -e "$D1/ticket.md"
t  "works in the repo top level"         has "$STUB_DIR/calls.log" "workspace create --cwd $REPO --label PROJ-1"
t  "coder can reach the ticket folder"   has "$STUB_DIR/args-proj-1-coder" "$D1"
t  "  ...through --add-dir"              has "$STUB_DIR/args-proj-1-coder" "--add-dir"
t  "one workspace created"               test "$(count "$STUB_DIR/calls.log" '^workspace create')" = 1
t  "workspace gets the ticket env"       has "$STUB_DIR/calls.log" "--env TICKET_DIR=$D1"
t  "coder started on sonnet"             has "$STUB_DIR/args-proj-1-coder" "sonnet"
t  "coder gets appended role file"       has "$STUB_DIR/args-proj-1-coder" "--append-system-prompt-file"
t  "role file has shared + coder text"   has "$TICKET_HARNESS_DATA/run/PROJ-1-coder.md" "Your role: coder"
t  "role file has the folder contract"   has "$TICKET_HARNESS_DATA/run/PROJ-1-coder.md" "The ticket folder"
t  "coder got the solo kickoff"          has "$STUB_DIR/prompts-proj-1-coder" "solo mode"
tn "no lead started"                     test -f "$STUB_DIR/args-proj-1-lead"
t  "index records the ticket"            has "$TICKET_HARNESS_DATA/index.tsv" "PROJ-1"

echo "2. rerun is a no-op"
t  "ticket PROJ-1 again succeeds"        ticket PROJ-1
t  "still one workspace"                 test "$(count "$STUB_DIR/calls.log" '^workspace create')" = 1
t  "coder started once"                  test "$(count "$STUB_DIR/calls.log" '^agent start proj-1-coder')" = 1
t  "kickoff sent once"                   test "$(wc -l < "$STUB_DIR/prompts-proj-1-coder")" = 1

echo "3. escalate to large"
t  "ticket PROJ-1 --size large succeeds" ticket PROJ-1 --size large
t  "lead started on opus"                has "$STUB_DIR/args-proj-1-lead" "opus"
t  "lead may run ticket-dispatch"        has "$STUB_DIR/args-proj-1-lead" "Bash(ticket-dispatch *)"
tn "coder may not run ticket-dispatch"   has "$STUB_DIR/args-proj-1-coder" "ticket-dispatch"
t  "comms started on haiku"              has "$STUB_DIR/args-proj-1-comms" "haiku"
t  "lead pane split right of coder"      has "$STUB_DIR/calls.log" "pane split w1:p1 --direction right"
t  "comms pane split below lead"         has "$STUB_DIR/calls.log" "pane split w1:p2 --direction down"
t  "lead told the coder already began"   has "$STUB_DIR/prompts-proj-1-lead" "already started"
t  "coder not kicked a second time"      test "$(wc -l < "$STUB_DIR/prompts-proj-1-coder")" = 1
t  "size stays large on plain rerun"     ticket PROJ-1
t  "no extra agents on rerun"            test "$(count "$STUB_DIR/calls.log" '^agent start')" = 3

echo "4. ticket-log"
export TICKET_KEY=PROJ-1 TICKET_DIR="$D1" TICKET_ROLE=coder
t  "logs an entry with a stdin body"     bash -c 'printf "%s\n" "- changed grants.tf" | ticket-log "T1 done"'
t  "entry has stamp, role, title"        has "$D1/log.md" "## 2026-11-13 10:00 · coder · T1 done"
t  "entry has the body"                  has "$D1/log.md" "- changed grants.tf"
t  "sets status with a note"             ticket-log --status waiting "platform team"
t  "STATUS.md updated"                   has "$D1/STATUS.md" "status: waiting"
t  "status change is logged"             has "$D1/log.md" "status → waiting"
tn "rejects an unknown state"            ticket-log --status finished
tn "rejects a missing title"             ticket-log
t  "--role overrides the role"           ticket-log --role lead "T1 approved" "looks right"
t  "override recorded"                   has "$D1/log.md" "· lead · T1 approved"

echo "5. ticket-comms"
t  "records a received message"          bash -c 'printf "line one\nline two\n" | ticket-comms received "Slack #dp" "Priya" --link https://x.example/t'
t  "received heading"                    has "$D1/comms/comms.md" "### 2026-11-13 10:00 · Slack #dp · RECEIVED · Priya"
t  "body is quoted"                      has "$D1/comms/comms.md" "> line two"
t  "link recorded"                       has "$D1/comms/comms.md" "Link: https://x.example/t"
t  "records a draft"                     bash -c 'echo "will do by Wed" | ticket-comms draft "Slack #dp" me'
t  "draft is marked unsent"              has "$D1/comms/comms.md" "DRAFT (not confirmed sent)"
t  "records a sent message"              bash -c 'echo "will do by Wed" | ticket-comms sent "Slack #dp" me'
tn "rejects an unknown kind"             bash -c 'echo x | ticket-comms posted "Slack" me'
tn "rejects an empty message"            bash -c 'printf "" | ticket-comms draft "Slack" me'

echo "6. ticket-dispatch"
export TICKET_ROLE=lead
tn "fails without a plan"                ticket-dispatch T1
printf 'My notes.\n\n# Plan\n\n## Task T1: Add grants module\n\nspec\n\n## Task T10: Later\n' > "$D1/plan.md"
t  "dispatches T1"                       ticket-dispatch T1
t  "coder received the task"             has "$STUB_DIR/prompts-proj-1-coder" "Implement Task T1 from $D1/plan.md"
t  "dispatch is logged by the lead"      has "$D1/log.md" "· lead · T1 dispatched"
t  "note is passed through"              ticket-dispatch T1 "fix: use the schema"
t  "note reached the coder"              has "$STUB_DIR/prompts-proj-1-coder" "Note from the lead: fix: use the schema."
tn "rejects a task not in the plan"      ticket-dispatch T2
t  "T10 is distinct from T1"             ticket-dispatch T10
tn "rejects a bad task id"               ticket-dispatch 'T1;rm'
sed -i.bak 's/^\(proj-1-coder	.*	\)idle$/\1working/' "$STUB_DIR/agents"
tn "refuses while the coder is working"  ticket-dispatch T1
t  "--force queues anyway"               ticket-dispatch --force T1
sed -i.bak 's/^\(proj-1-coder	.*	\)working$/\1blocked/' "$STUB_DIR/agents"
tn "refuses while the coder is blocked"  ticket-dispatch --force T1
sed -i.bak 's/^\(proj-1-coder	.*	\)blocked$/\1idle/' "$STUB_DIR/agents"
unset TICKET_KEY TICKET_DIR TICKET_ROLE

echo "7. ticket already on disk is sized by the model"
D2="$TK/PROJ-2"; mkdir -p "$D2"
printf '# PROJ-2: Build ingestion pipeline\n\nDetails.\n' > "$D2/ticket.md"
t  "ticket PROJ-2 succeeds"              env STUB_TRIAGE=large ticket PROJ-2
t  "triage read the ticket file"         has "$STUB_DIR/triage-stdin" "Build ingestion pipeline"
t  "lead started"                        test -f "$STUB_DIR/args-proj-2-lead"
t  "lead got the fresh-start kickoff"    has "$STUB_DIR/prompts-proj-2-lead" "The coder is proj-2-coder"
tn "coder not kicked in team mode"       test -f "$STUB_DIR/prompts-proj-2-coder"
D3="$TK/PROJ-3"; mkdir -p "$D3"; printf '# PROJ-3: Grant access\n' > "$D3/ticket.md"
t  "ticket PROJ-3 sized small"           env STUB_TRIAGE=small ticket PROJ-3
tn "no lead for the small ticket"        test -f "$STUB_DIR/args-proj-3-lead"
t  "--comms adds only the comms pane"    ticket PROJ-3 --comms
t  "comms started for PROJ-3"            test -f "$STUB_DIR/args-proj-3-comms"
tn "still no lead"                       test -f "$STUB_DIR/args-proj-3-lead"

echo "8. a session that is not ready at startup"
tn "ticket PROJ-4 reports the problem"   env STUB_BLOCK_START=proj-4-coder ticket PROJ-4
tn "kickoff was not sent"                test -f "$STUB_DIR/prompts-proj-4-coder"
sed -i.bak 's/^\(proj-4-coder	.*	\)blocked$/\1idle/' "$STUB_DIR/agents"
t  "rerun after answering succeeds"      ticket PROJ-4
t  "kickoff sent on the rerun"           has "$STUB_DIR/prompts-proj-4-coder" "solo mode"
t  "agent not started twice"             test "$(count "$STUB_DIR/calls.log" '^agent start proj-4-coder')" = 1

echo "9. a closed coder pane is recreated"
grep -v '^proj-1-coder' "$STUB_DIR/agents" > "$STUB_DIR/agents.new"; mv "$STUB_DIR/agents.new" "$STUB_DIR/agents"
grep -vx 'w1:p1' "$STUB_DIR/panes" > "$STUB_DIR/panes.new"; mv "$STUB_DIR/panes.new" "$STUB_DIR/panes"
t  "ticket PROJ-1 succeeds"              ticket PROJ-1
t  "new coder pane split from the lead"  has "$STUB_DIR/calls.log" "pane split w1:p2 --direction right"
t  "coder started again"                 test "$(count "$STUB_DIR/calls.log" '^agent start proj-1-coder')" = 2

echo "10. input checks and listing"
tn "rejects a lowercase key"             ticket proj-9
tn "rejects a bad --size"                ticket PROJ-9 --size huge
tn "rejects an unknown option"           ticket PROJ-9 --fast
t  "ticket list shows PROJ-1"            bash -c 'ticket list | grep -q "PROJ-1 .*waiting"'
t  "ticket --help works"                 ticket --help
t  "ticket doctor passes with stubs"     ticket doctor

echo "11. standup"
# Friday 13th has the entries above. Pretend it is now Monday 16th.
export TH_NOW="2026-11-16 09:00" TH_TODAY="2026-11-16"
TICKET_KEY=PROJ-3 TICKET_DIR="$D3" TICKET_ROLE=coder ticket-log --status "done" >/dev/null
export TH_NOW="2026-11-10 09:00"
D5="$TK/PROJ-5"; ticket PROJ-5 >/dev/null 2>&1
TICKET_KEY=PROJ-5 TICKET_DIR="$D5" TICKET_ROLE=coder ticket-log "old work" "from last Tuesday" >/dev/null
TICKET_KEY=PROJ-5 TICKET_DIR="$D5" TICKET_ROLE=coder ticket-log --status "done" >/dev/null
export TH_NOW="2026-11-16 09:00"
raw=$(standup --raw 2>&1)
t  "covers from the last active day"     bash -c 'printf "%s" "$1" | grep -q "COVERING FROM: 2026-11-13"' _ "$raw"
t  "includes Friday work on PROJ-1"      bash -c 'printf "%s" "$1" | grep -q "T1 done"' _ "$raw"
t  "includes the plan task headings"     bash -c 'printf "%s" "$1" | grep -q "## Task T10: Later"' _ "$raw"
t  "includes the recorded messages"      bash -c 'printf "%s" "$1" | grep -q "RECEIVED · Priya"' _ "$raw"
t  "includes the ticket title"           bash -c 'printf "%s" "$1" | grep -q "title: PROJ-2: Build ingestion pipeline"' _ "$raw"
t  "includes PROJ-3, finished today"     bash -c 'printf "%s" "$1" | grep -q "=== TICKET PROJ-3 ==="' _ "$raw"
tn "leaves out PROJ-5, done and quiet"   bash -c 'printf "%s" "$1" | grep -q "=== TICKET PROJ-5 ==="' _ "$raw"
tn "leaves out PROJ-5's old entry"       bash -c 'printf "%s" "$1" | grep -q "old work"' _ "$raw"
t  "--since widens the window"           bash -c 'standup --raw --since 2026-11-01 | grep -q "old work"'
tn "rejects a bad --since"               standup --since yesterday
t  "standup writes the update"           bash -c 'standup 2>/dev/null | grep -q "STUB UPDATE"'
t  "update saved by date"                test -f "$TICKET_HARNESS_DATA/standups/2026-11-16.md"
t  "model was given the material"        has "$STUB_DIR/standup-stdin" "=== TICKET PROJ-1 ==="
t  "standup uses haiku with no tools"    has "$STUB_DIR/claude-calls.log" "--model haiku --tools  --disallowedTools mcp__*"

echo "12. folders, working directory, and keys"
NG="$T/notrepo"; mkdir -p "$NG"
t  "outside a repo, works in the ticket folder" bash -c "cd '$NG' && ticket OPS-7 >/dev/null 2>&1 && grep -qF 'workspace create --cwd $TK/OPS-7 ' '$STUB_DIR/calls.log'"
tn "  ...and needs no --add-dir"         has "$STUB_DIR/args-ops-7-coder" "--add-dir"
t  "--repo sets the working directory"   bash -c "cd '$NG' && ticket OPS-8 --repo '$REPO/sub' >/dev/null 2>&1 && grep -qF 'workspace create --cwd $REPO --label OPS-8' '$STUB_DIR/calls.log'"
t  "accepts a browse URL"                bash -c "ticket https://idexx.atlassian.net/browse/MLOPS-390 >/dev/null 2>&1 && test -d '$TK/MLOPS-390'"
t  "accepts a board URL"                 bash -c "ticket 'https://idexx.atlassian.net/jira/software/c/projects/MLE/boards/1?selectedIssue=MLE-489' >/dev/null 2>&1 && test -d '$TK/MLE-489'"
tn "rejects a URL with no key"           ticket https://idexx.atlassian.net/jira/your-work
printf 'my own notes\n' > "$TK/MLOPS-390/references.md"; printf 'old\n' > "$TK/MLOPS-390/log.md"
t  "rerun keeps the user's files"        bash -c "ticket MLOPS-390 >/dev/null 2>&1 && grep -qx 'my own notes' '$TK/MLOPS-390/references.md' && grep -qx 'old' '$TK/MLOPS-390/log.md'"
t  "TICKETS_ROOT moves the folders"      bash -c "TICKETS_ROOT='$T/central' ticket OPS-9 >/dev/null 2>&1 && test -f '$T/central/OPS-9/log.md'"
t  "warns if the folder is in a repo and not ignored" bash -c "cd '$REPO' && TICKETS_ROOT='$REPO/t' ticket OPS-10 2>&1 | grep -q 'not git-ignored'"

echo "13. install"
H="$T/home"; mkdir -p "$H"
t  "install.sh runs"                     env HOME="$H" TICKET_HARNESS_DATA="$H/.ticket-harness" BIN_DIR="$H/.local/bin" "$ROOT/install.sh"
t  "commands are linked"                 test -L "$H/.local/bin/ticket-dispatch"
t  "config.env created"                  test -f "$H/.ticket-harness/config.env"
t  "linked command finds its library"    "$H/.local/bin/ticket" --help
echo "edited" >> "$H/.ticket-harness/roles/lead.md"
t  "reinstall runs"                      env HOME="$H" TICKET_HARNESS_DATA="$H/.ticket-harness" BIN_DIR="$H/.local/bin" "$ROOT/install.sh"
t  "reinstall keeps an edited role file" bash -c "ls '$H/.ticket-harness/roles/' | grep -q 'lead.md.bak-'"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
