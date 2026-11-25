# Ticket harness

One herdr workspace per Jira ticket, with Claude Code sessions on different models sharing a ticket folder:

| Pane | Model | Does |
|---|---|---|
| coder | Sonnet | Implements. This is the pane you watch and steer. |
| lead | Opus (or Fable) | Brainstorms, plans, writes task specs, hands tasks to the coder, reviews. |
| comms | Haiku | Drafts Slack messages and emails; keeps the conversation record. |

Small tickets get only the coder. The sessions never share a conversation; they share the ticket folder, which is the same `~/Desktop/tickets/<KEY>/` folder your `ticket-workspace` skill creates.

## Install

Needs `herdr`, `claude`, `jq`, and `git` on your PATH.

```bash
./install.sh        # copies to ~/.ticket-harness, links commands into ~/.local/bin
ticket doctor       # checks the commands, the herdr server, and the harness files
```

Run `herdr integration install claude` once if you have not already; herdr uses it to restore Claude sessions after a restart.

## Daily use

Start herdr. For a ticket that changes code, `cd` into that repo first; for grants, policies, and other work with no repo, run it from anywhere and the sessions work in the ticket folder.

| Command | What happens |
|---|---|
| `ticket MLOPS-390` | Opens the ticket. A Jira URL works too. If `ticket.md` is already on disk, Haiku sizes the ticket. If not, it starts small: the coder runs `ticket-workspace`, sizes the ticket, and offers to bring in the lead if it is bigger than it looks. |
| `ticket MLOPS-390 --size large` | Adds the lead and comms panes (also how you upgrade a small ticket). |
| `ticket MLOPS-390 --comms` | Adds only the comms pane to a small ticket. |
| `ticket MLOPS-390 --repo ~/code/infra` | Sets the repo the sessions work in. It is remembered per ticket and applies to panes started after the change. |
| `ticket list` | Every ticket with its status and folder. |
| `standup` | Writes your update from the folders. Covers from the last day with any activity, so Monday picks up Friday. `--raw` shows the gathered material without calling Claude. |

`ticket` is safe to rerun. It creates only what is missing, so it is also how you bring back a pane you closed.

On a large ticket the loop is:

1. Talk the approach through with the lead. It writes the plan and tasks into `plan.md`, below any notes of yours already there.
2. The lead runs `ticket-dispatch T1`. The task appears in the coder pane as a prompt.
3. Watch the coder. Type into its pane to redirect it; answer its permission prompts yourself.
4. When it finishes, tell the lead to review. It reads the log and the diff, then approves or sends a fix.

## The ticket folder

```
~/Desktop/tickets/MLOPS-390/
  ticket.md        mirror of Jira, written by ticket-workspace (regenerated on every fetch)
  references.md    links, related tickets, people (ticket-workspace creates it; then yours)
  plan.md          your notes, then the lead's plan and "## Task T1", "## Task T2", ...
  log.md           dated work log, written through ticket-log
  STATUS.md        one-line state: new, planning, in-progress, review, waiting, done
  comms/comms.md   Summary (decisions, open, promised), then the Slack and email log
  files/           exports, query results, screenshots
  patches/         diffs and config changes, including before/after snapshots
  scripts/         helper scripts written for the ticket
```

`ticket-workspace` owns `ticket.md` and creates `references.md`; the harness adds `log.md`, `STATUS.md`, and `comms/`, and creates the three subfolders if they are missing. Following your skill's rule, it never overwrites a file that already exists, and the role instructions tell every session that `ticket.md` is regenerated (so never write to it) and that everything else in the folder is yours.

The status lives in its own file, not in `ticket.md`, because `ticket.md` is rewritten each time the ticket is fetched. Jira comments stay in `ticket.md`; Slack and email go in `comms/comms.md`.

For changes made outside a repo (grants, policies, workspace settings), the coder is told to save the state before and after in `patches/` and to log the commands it ran. That gives each change an audit trail and a way back.

## Settings

`~/.ticket-harness/config.env` sets the model for each role. To use Fable for planning, set `LEAD_MODEL=fable`. `TICKETS_ROOT` defaults to `~/Desktop/tickets`; change it only together with the path in your `ticket-workspace` skill.

What each session is told lives in `~/.ticket-harness/roles/` (`_shared.md` plus one file per role) and `~/.ticket-harness/prompts/` (ticket sizing and the standup). Edit them freely; reinstalling keeps a `.bak` copy of any file you changed. A role edit applies to sessions started after it.

## How the pieces work

- **Folder access**: the ticket folder is outside your repos, so each session is started with `--add-dir` pointing at it. Without that, every read and write there would need approval.
- **Roles** are appended to Claude Code's own system prompt (`--append-system-prompt-file`), so every session keeps its normal behaviour and gains the role on top. Running a session as a custom agent (`--agent`) would have replaced the default prompt entirely.
- **Dispatch** uses `herdr agent prompt`, so the task shows up in the coder pane exactly as if you had typed it. It returns at once and refuses to send while the coder is working or waiting on a question.
- **Timestamps** come from the `ticket-log` and `ticket-comms` scripts, not from the models.
- **Pre-approved commands**: every session may run `ticket-log` and `ticket-comms` without asking, and the lead may run `ticket-dispatch`. Those scripts write only inside the ticket folder (dispatch also sends one prompt to the coder). Everything else follows your normal Claude Code permissions.
- **State** is in `~/.ticket-harness/`: `state/` (workspace and pane ids per ticket), `index.tsv` (where each ticket folder is, for `standup`), `standups/` (one saved update per day), `run/` (the assembled role file for each session).

## Tested and not tested

`tests/run.sh` runs every command against stand-ins for `herdr` and `claude` that follow the JSON and exit codes in herdr's 0.9.5 documentation. It covers the scripts' own logic: 118 checks, all passing.

It has not been run against the real herdr or the real Claude Code. The places most likely to need a tweak on first use:

- **`herdr agent get`'s status field.** The docs do not name it, so the scripts accept `status` or `agent_status` and treat anything else as unknown. If dispatch never refuses while the coder is busy, this is why.
- **`herdr workspace get` and `herdr pane get` on an id that no longer exists.** The scripts assume a non-zero exit.
- **The first start in a repo.** If Claude Code asks whether to trust the folder, herdr reports the session as not ready. `ticket` says so; answer in the pane and rerun `ticket <KEY>`.
- **The pre-approval rule format**, `Bash(ticket-log *)`. If a session still asks before running the helper scripts, allow them once in that session.

- **A mistyped key.** `ticket` creates the folder before the coder fetches the ticket, so a key that does not exist leaves a folder holding only the harness files. The coder will report that the ticket was not found; delete the folder.

Run `ticket doctor`, then try a small ticket before a large one.
