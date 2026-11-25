#!/usr/bin/env bash
# Shared helpers for the ticket harness. Sourced by the scripts in bin/.
# Written for bash 3.2 (the macOS default) and POSIX awk/sed.

TH_DATA="${TICKET_HARNESS_DATA:-$HOME/.ticket-harness}"
TH_STATE="$TH_DATA/state"
TH_INDEX="$TH_DATA/index.tsv"

die()  { printf 'ticket-harness: %s\n' "$*" >&2; exit 1; }
warn() { printf 'ticket-harness: %s\n' "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

# Defaults, then the user's overrides from config.env.
load_config() {
  LEAD_MODEL=opus
  CODER_MODEL=sonnet
  COMMS_MODEL=haiku
  TRIAGE_MODEL=haiku
  STANDUP_MODEL=haiku
  if [ -f "$TH_DATA/config.env" ]; then
    # shellcheck disable=SC1091
    . "$TH_DATA/config.env"
  fi
}

valid_key() { printf '%s' "$1" | grep -Eq '^[A-Z][A-Z0-9]*-[0-9]+$'; }
slug_of()   { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# TH_NOW / TH_TODAY let the tests pin the clock.
now()   { if [ -n "${TH_NOW:-}" ]; then printf '%s' "$TH_NOW"; else date '+%Y-%m-%d %H:%M'; fi; }
today() { if [ -n "${TH_TODAY:-}" ]; then printf '%s' "$TH_TODAY"; else date '+%Y-%m-%d'; fi; }

# --- per-ticket state: tab-separated "field<TAB>value" lines -----------------

state_file() { printf '%s/%s.state' "$TH_STATE" "$1"; }

state_get() { # <key> <field>
  local f
  f=$(state_file "$1")
  [ -f "$f" ] || return 0
  awk -F'\t' -v k="$2" '$1==k {v=$2} END {if (v!="") print v}' "$f"
}

state_set() { # <key> <field> <value>
  local f tmp
  f=$(state_file "$1")
  mkdir -p "$TH_STATE"
  tmp="$f.tmp.$$"
  {
    if [ -f "$f" ]; then awk -F'\t' -v k="$2" '$1!=k' "$f"; fi
    printf '%s\t%s\n' "$2" "$3"
  } > "$tmp"
  mv "$tmp" "$f"
}

# --- where the ticket folder lives -------------------------------------------

git_top() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; }

# Must match where the ticket-workspace skill writes: ~/Desktop/tickets/<KEY>/.
resolve_root() {
  local root="${TICKETS_ROOT:-$HOME/Desktop/tickets}"
  case "$root" in
    "~/"*) root="$HOME/${root#\~/}" ;;
  esac
  printf '%s' "$root"
}

# Accepts PROJ-123 or a Jira URL (.../browse/PROJ-123, ...?selectedIssue=PROJ-123).
key_from_arg() {
  case "$1" in
    http://*|https://*)
      printf '%s' "$1" | sed -n \
        -e 's#.*/browse/\([A-Z][A-Z0-9]*-[0-9][0-9]*\).*#\1#p' \
        -e 's#.*[?&]selectedIssue=\([A-Z][A-Z0-9]*-[0-9][0-9]*\).*#\1#p' | head -n 1 ;;
    *) printf '%s' "$1" ;;
  esac
}

# Used by ticket-log / ticket-comms / ticket-dispatch, which run inside a pane
# that `ticket` started (TICKET_KEY and TICKET_DIR are in its environment).
ticket_ctx() {
  [ -n "${TICKET_KEY:-}" ] || die "TICKET_KEY is not set. Run this inside a pane started by 'ticket', or pass --ticket KEY."
  valid_key "$TICKET_KEY" || die "not a Jira key: $TICKET_KEY"
  if [ -z "${TICKET_DIR:-}" ]; then TICKET_DIR=$(state_get "$TICKET_KEY" TICKET_DIR); fi
  if [ -z "${TICKET_DIR:-}" ] || [ ! -d "$TICKET_DIR" ]; then
    die "ticket folder not found for $TICKET_KEY. Run: ticket $TICKET_KEY"
  fi
}

# --- herdr -------------------------------------------------------------------

h_ok() { herdr "$@" >/dev/null 2>&1; }
agent_exists() { h_ok agent get "$1"; }

# herdr's docs don't pin the status field name, so accept either and fall back.
agent_status() {
  local out
  out=$(herdr agent get "$1" 2>/dev/null) || { printf 'missing'; return 0; }
  printf '%s' "$out" | jq -r '.result.agent | (.status // .agent_status // "unknown")' 2>/dev/null || printf 'unknown'
}
