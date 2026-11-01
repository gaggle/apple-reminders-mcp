# apple-reminders-mcp

An MCP server that lets Claude, or any MCP client, read and manage your Apple Reminders on macOS: lists, list sections, due dates, notes, flags and completion. It comes with `reminders-bridge`, a command-line tool over the same library.

Both are built on `RemindersCore`: EventKit for reminders and lists, and ReminderKit, the private framework the Reminders app itself uses, for list sections and flags, which EventKit doesn't expose.

Requires macOS 14 or later and Swift 6.

## The MCP server

```bash
scripts/install.sh
claude mcp add --scope user reminders -- "$HOME/Library/Application Support/apple-reminders-mcp/Reminders MCP"
```

Tools: `list_lists`, `list_reminders`, `create_reminder`, `update_reminder`, `delete_reminder`. Only `delete_reminder` is marked destructive; Reminders has no trash, so it's the one worth leaving on "ask".

Every reminder is addressed within its list, so a reminder id from one list can't touch another. Due dates are local wall-clock time: `YYYY-MM-DD` for an all-day due date, `YYYY-MM-DDTHH:MM` for a specific time.

### Reminders access

macOS grants Reminders access to a process's *responsible* app — for an MCP server, the client that launched it, which doesn't declare Reminders usage, so the request is denied without a prompt. The server relaunches itself with responsibility disclaimed, making itself the one asking. macOS names it by its file name, so it's installed as "Reminders MCP", with the reason coming from the Info.plist embedded in the binary. The first run asks for access.

`install.sh` signs with a valid Apple Development identity if there is one, so the permission survives reinstalls; otherwise ad-hoc, and each rebuild asks again. `APPLE_REMINDERS_MCP_SIGN_IDENTITY` overrides the choice (`-` for ad-hoc).

## reminders-bridge

```bash
swift build -c release --product reminders-bridge
reminders-bridge get-lists
reminders-bridge get-reminders --list Chores
```

Commands: `get-lists`, `get-reminders`, `create-reminder`, `set-body`, `set-name`, `complete`, `uncomplete`, `set-due`, `set-section`, `set-flagged`, `alert`, `delete`. JSON out; every id-based command is scoped to `--list`.

## Sections and flags use a private framework

Sections and flags go through ReminderKit, which Apple doesn't document and can change with any macOS update. Every class and selector is checked before use, so if it changes, anything touching them exits instead of half-working. Everything else uses EventKit.

## Tests

```bash
scripts/test.sh
```

End-to-end, against real Reminders: a test process can't get Reminders access itself, so the tests drive the server, installed as "Reminders MCP Tests" (the first run asks for access). They work in an existing list, "Sync Test" unless `REMINDERS_MCP_TEST_LIST` names another, touching only reminders they create and delete. Runs with Xcode's toolchain, for Swift Testing.

## License

Apache License 2.0; see [LICENSE](LICENSE) and [NOTICE](NOTICE).
