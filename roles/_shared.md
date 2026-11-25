# Ticket harness: how this session fits in

This session is one of up to three Claude Code sessions working on the same Jira ticket, each in its own terminal pane inside herdr. One engineer is running all of them, can see every pane, and types into whichever one they want.

- The **lead** plans and reviews. It runs on the most capable model, so its time is the expensive part.
- The **coder** implements. It runs on a faster model, in the pane the engineer watches most closely.
- The **comms** session drafts Slack messages and emails about the ticket and keeps a record of them. It runs on the smallest model.

Small tickets have only the coder. The sessions do not share a conversation. Everything one session needs to know about another's work has to be in the ticket folder, because that folder is the only memory they have in common. It is also what tomorrow's standup update is written from.

Your environment has `TICKET_KEY` (the Jira key), `TICKET_DIR` (the ticket folder), and `TICKET_ROLE` (which of the three you are).

## The ticket folder

The folder is `~/Desktop/tickets/<KEY>/`, the one the engineer's `ticket-workspace` skill creates. It sits outside any code repository. Your working directory is the repository the ticket touches, or the ticket folder itself when the work has no repository (grants, policies, access requests); either way you have access to both.

| Path | What it holds | Written by |
|---|---|---|
| `ticket.md` | A full mirror of the Jira ticket: fields, description, acceptance criteria, linked work, Confluence and other links, comments, history | the `ticket-workspace` skill |
| `references.md` | Links, related tickets, and the people involved and their roles | `ticket-workspace` creates it; then it is the engineer's |
| `plan.md` | The plan, followed by task specs under `## Task T1`, `## Task T2`, ... | the lead, with the engineer |
| `log.md` | The dated work log: what was done, decided, or blocked | everyone, through `ticket-log` |
| `STATUS.md` | The ticket's current state in one line | `ticket-log --status` |
| `comms/comms.md` | Summary of Slack and email conversations, then the message log | comms |
| `files/` | Inputs and outputs: CSVs, exports, query results, screenshots | anyone |
| `patches/` | Diffs and config changes, including before-and-after snapshots of settings changed outside a repository | anyone |
| `scripts/` | Helper scripts written while working the ticket | anyone |

Two rules about this folder:

- **`ticket.md` is regenerated** every time the ticket is fetched. Never write to it; anything added there is lost on the next fetch. To fetch or refresh the ticket, use the `ticket-workspace` skill (`/ticket-workspace <KEY>`), which rewrites `ticket.md` and leaves everything else alone.
- **Everything else belongs to the engineer.** They keep their own notes here. Add files and append to them, but do not overwrite, reorganise, or delete what is already there unless they ask.

Jira comments are in `ticket.md`. Slack and email are in `comms/comms.md`. Between them they are the record of what people have said about the ticket.

## Writing to the log

Use the scripts; they stamp the date and time, which you cannot know reliably on your own.

```bash
ticket-log "T2 done" <<'BODY'
- What changed, with paths or resource names
- How it was checked, with the command and its result
- Anything the reviewer should look at
BODY

ticket-log --status waiting "platform team to confirm the catalog name"
```

States are `new`, `planning`, `in-progress`, `review`, `waiting`, and `done`. Keep the state current when it changes; the standup and the other sessions read it.

Write log entries for a reader who was not there: a different session on a different model, or the engineer the next morning. Say what happened in full sentences or complete bullets, name the files and resources, and include the evidence. An entry that says only "done" is not usable.

