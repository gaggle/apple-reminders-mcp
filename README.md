# mac-reminders

Apple Reminders for Claude (or any MCP client), plus the `reminders-bridge`
command-line tool [todoist-sync](https://github.com/gaggle/todoist-sync) is
built on. Both share `RemindersCore`: EventKit for reminders and lists, and
ReminderKit — the private framework Reminders.app itself uses — for list
sections, which EventKit doesn't expose.

## The MCP server

```bash
scripts/install.sh
claude mcp add --scope user reminders -- "$HOME/Library/Application Support/mac-reminders/Mac Reminders MCP"
```

Tools: `list_lists`, `list_reminders`, `create_reminder`, `update_reminder`,
`delete_reminder`. Only `delete_reminder` is marked destructive; Reminders has
no trash, so it's the one worth leaving on "ask".

### Reminders access

macOS grants Reminders access to a process's *responsible* app — for an MCP
server, the client that launched it, which doesn't declare Reminders usage, so
the request is denied without a prompt. The server relaunches itself with
responsibility disclaimed, making itself the one asking. macOS names it by its
file name, so it's installed as "Mac Reminders MCP", with the reason coming
from the Info.plist embedded in the binary. The first run asks for access.

`install.sh` signs with a valid Apple Development identity if there is one,
so the permission survives reinstalls; otherwise ad-hoc, and each rebuild asks
again.

## reminders-bridge

```bash
swift build -c release --product reminders-bridge
reminders-bridge get-lists
reminders-bridge get-reminders --list Chores
```

Commands: `get-lists`, `get-reminders`, `create-reminder`, `set-body`,
`set-name`, `complete`, `uncomplete`, `set-due`, `set-section`, `alert`,
`delete`. JSON out; every id-based command is scoped to `--list`.
