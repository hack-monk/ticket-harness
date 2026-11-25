#!/usr/bin/env bash
# Installs the ticket harness into ~/.ticket-harness and links its commands
# into ~/.local/bin. Rerunning it updates the program files and leaves your
# config.env, ticket state, and standup history alone.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
dest="${TICKET_HARNESS_DATA:-$HOME/.ticket-harness}"
bindir="${BIN_DIR:-$HOME/.local/bin}"
stamp=$(date '+%Y%m%d-%H%M%S')

mkdir -p "$dest/bin" "$dest/lib" "$dest/roles" "$dest/prompts" "$bindir"

# Role and prompt files are meant to be edited. Keep a copy of any that differ.
for f in roles/_shared.md roles/lead.md roles/coder.md roles/comms.md prompts/triage.md prompts/standup.md; do
  if [ -f "$dest/$f" ] && ! cmp -s "$src/$f" "$dest/$f"; then
    cp "$dest/$f" "$dest/$f.bak-$stamp"
    echo "kept your edited $f as $f.bak-$stamp"
  fi
  cp "$src/$f" "$dest/$f"
done

cp "$src/lib/common.sh" "$dest/lib/common.sh"
for c in ticket ticket-log ticket-comms ticket-dispatch standup; do
  cp "$src/bin/$c" "$dest/bin/$c"
  chmod +x "$dest/bin/$c"
  ln -sf "$dest/bin/$c" "$bindir/$c"
done

if [ ! -f "$dest/config.env" ]; then
  cp "$src/config.env.example" "$dest/config.env"
  echo "created $dest/config.env"
fi

echo "installed to $dest"
case ":$PATH:" in
  *":$bindir:"*) ;;
  *) echo "add this to your shell profile, then open a new shell:"
     echo "  export PATH=\"$bindir:\$PATH\"" ;;
esac
echo "next: ticket doctor"
