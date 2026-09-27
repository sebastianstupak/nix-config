# Orgs

This machine is used for several organisations. An **org** is the unit that
holds that together: a name, a directory, a commit identity, an assistant
account, a pair of workspaces, and a terminal session that survives being
closed.

The list lives in `home/sebastianstupak/default.nix` under `my.orgs`. Everything
below is derived from it — there is no second place to update.

## The one idea

**The boundary is a directory.** Not a mode you switch into, not a profile you
remember to select. Anything under `~/dev/<org>/` belongs to that org, and every
tool works it out from the path on its own.

Mode-switching fails the same way every time: you forget which mode you are in,
and find out after pushing a commit authored by the wrong identity. A path
cannot be forgotten.

## What an org gets

| | Derived from | Module |
|---|---|---|
| Commit identity | `email` → `includeIf gitdir:` + `allowed_signers` | `modules/home/git.nix` |
| Assistant account, MCP servers | a profile named after the org, rooted at its directory | `modules/home/claude-code-profiles.nix` |
| Two workspaces, a glyph, a colour | `workspaces`, `icon`, `color` | `modules/home/org.nix`, `modules/home/waybar.nix` |
| A persistent terminal session | a herdr session named after the org | `modules/home/herdr.nix` |

## Daily use

```bash
org                 # pick an org from a menu ($mod+O does the same)
org datadir         # the org's home screen, with its terminal
org datadir 2       # the org's second screen
org --list          # the known org names
```

`org <name>` switches to the org's home workspace and, unless one of its
terminals is already sitting there, opens one in the org's directory attached to
the org's herdr session. Run it again and it is purely "take me there" — it will
not pile up a second terminal.

The **second screen** is deliberately bare. It exists so one org's work can
spread across two screens; what belongs there is yours to decide, and `org
<name> 2` just takes you to it. `$mod+1`..`$mod+9` still work as normal.

Nothing about this is mandatory. Starting a terminal any other way and `cd`-ing
into an org's directory gets you the same identity, the same assistant account
and the same session — the launcher is a shortcut, not the mechanism.

### Closing things

Closing an org's window does **not** end its session. herdr keeps a server
running with the panes in it; the next `org <name>` reattaches to exactly what
was there, agents included. That is why org windows close without the usual
"all terminal sessions will be terminated" prompt: in an org window that warning
is untrue.

A reboot does end the processes, but the layout and each pane's working
directory are restored from herdr's `session.json` when you attach again.

To end one deliberately:

```bash
herdr session list              # what exists, and whether it is running
herdr session stop datadir      # end it, panes and all
herdr session delete datadir    # and forget it entirely
```

`stop` ends the panes but leaves the session listed as `stopped`, which is what
you want if you mean to come back to a clean one under the same name. `delete`
is what removes the entry.

## Reading the bar

The centre of the bar is one glyph per workspace, grouped by org:

```
󰋜 󰋜 󰋜   󰆼 󰆼   󰒋 󰒋   󰤇 󰤇
personal  datadir nettify bunny
```

Each org wears one glyph in one colour across all of its workspaces. A dimmed
glyph means that workspace is empty; the underline is where you are.

**personal owns 1-3**, and owning workspace 1 is deliberate: that is where you
land at login, so the machine's resting state belongs to an org rather than to
a no-man's-land that everything unfiled drifts into. It has three screens
because it is also where the odd jobs go — a scratch shell, this config, a
browser opened to look one thing up. Work orgs follow behind it.

A workspace shows a number instead of a glyph until the next login if it
already existed when the rules changed. Hyprland applies a workspace's name
only when the workspace is *created*, so renumbering the orgs takes effect at
the next login rather than at the next rebuild. Not a bug, and it clears
itself.

## Adding an org

One entry in `my.orgs` in `home/sebastianstupak/default.nix`:

```nix
acme = {
  email = "me@acme.example";       # omit to keep the global identity
  workspaces = [ 10 11 ];          # must not collide with another org
  icon = "󰀄";                      # must exist in the bar's font
  color = "base0C";                # a base16 key, not a hex value
};
```

1-9 are all spoken for, and those are the numbers `$mod+1`..`$mod+9` binds. A
fifth org means either taking screens from an existing one — most likely one of
personal's three — or living with workspaces only the launcher can reach.

Then rebuild. The directory, the git rule, the assistant profile, the workspace
rules, the bar glyph and the herdr session all follow.

Two things the build will stop you on, because both fail silently otherwise:

- **two orgs claiming the same workspace** — `org` would take you to someone
  else's screen
- **an org with workspaces but no icon** — an empty glyph is a chip you can
  click and cannot see

Check a glyph exists before using it, and look at it — several plausible
codepoints are not what their name suggests:

```bash
fc-list ':charset=f0907' family      # is it in the font at all
```

`base08` is deliberately unused by any org: the bar spends it on critical
states, and an org permanently wearing the alarm colour stops the alarm meaning
anything.

## On a new machine

Everything except the secrets is reproduced by a rebuild. What is not:

1. **The assistant account per org.** Each profile has its own login. Run
   `claude` once inside each org's directory and sign in. Until you do, any
   account is accepted there — there is nothing to compare against before a
   first login.
2. **`account` pinning.** After that first login, put the address `/status`
   reports into `my.claude.profiles.<org>.account`. From then on `claude`
   refuses to start in that tree signed in as anyone else, which is what keeps
   work off a personal subscription.
3. **MCP authorisation.** Remote servers need an interactive OAuth handshake;
   run `/mcp` once inside the profile.
4. **herdr sessions.** These are live state, not configuration. A new machine
   starts with none, and the first `org <name>` creates one.
5. **An ssh key, before the identity is verifiable.** `allowed_signers` is
   written during activation from the key's contents, so activating before
   `~/.ssh/id_ed25519` exists skips it — and git then calls your own commits
   unknown-signer. Make the key, then rebuild once more. See step 9 of
   [INSTALL.md](./INSTALL.md).

Everything else — directories, git rules, profile directories with their MCP
servers, workspace rules, bar glyphs — is there after the first rebuild.
Verified by running the activation against an empty home: 35 checks, including
that a second activation preserves a hand-edited `CLAUDE.md`, an existing login
and a hand-added MCP server.

## Rough edges

- **Session names are org names.** Renaming an org in `my.orgs` orphans its
  herdr session rather than renaming it: the old name keeps its panes and the
  new one starts empty. `herdr session list` shows both; `herdr session stop
  <old>` then `herdr session delete <old>` clears it out. Checked, including
  that a stopped session stays listed until it is deleted.
- **One identity for every org right now.** All four use the same address, so
  the per-org git rules are in place but currently resolve to the same answer.
  If an org ever needs its own — a GitHub org enforcing a verified domain, a CLA
  checking the author — it is one line, and nothing else moves.
- **herdr is pinned to a release tag**, not a branch, unlike every other flake
  input. It owns live session state, and an input bump that silently moved it
  would restart the server under whatever was running. Bumping it is a
  deliberate edit of the tag in `flake.nix`.
