# gathr

One cockpit over every org's conversations. The daemon syncs and stores in the
background; `gathr` on its own attaches the TUI. Source lives in its own repo
(`github.com/sebastianstupak/gathr`) and arrives as a flake input; the module is
`modules/home/gathr.nix`.

This doc is the workflow. Why the module looks the way it does is in its header
comment; why the daemon is built the way it is, is in the project's README.

## Daily use

```bash
gathr                     # attach the TUI
gathr api snapshot | jq   # per-org unread counts — what the bar reads
systemctl --user status gathr
journalctl --user -u gathr -f
```

TUI keys: `tab`/`shift-tab` move between panes, `j`/`k` navigate, `d` requests a
draft, `r` marks read, `o` opens the newest link in the transcript (a meeting
lands in the right org's browser profile), `R` refreshes, `?` lists keys, `q`
quits.

Three panes at 110+ columns: chats grouped by org on the left, transcript in the
middle, assistant on the right. Narrower, the assistant drops out — focus it with
`tab` and it swaps into the transcript's place.

## Adding a real Slack account

Everything below is per client, and each step is deliberate: from the moment an
account exists, this machine stores that client's messages.

### 1. Get a user token

Ask the client to install a small app in their workspace, or create one yourself
at <https://api.slack.com/apps> if you have the rights:

- **OAuth & Permissions → User Token Scopes**, add: `channels:history`,
  `groups:history`, `im:history`, `mpim:history`, `channels:read`, `groups:read`,
  `users:read`.
- Install to the workspace. Copy the **User** OAuth token (`xoxp-…`), not the bot
  one — the bot only sees channels it was invited to.

Browser session tokens (`xoxc`/`xoxd`) work against the same endpoints and need
no install. Prefer not to: pulling a client's history through undisclosed scraped
credentials reads badly in a security review, and it is their workspace. Ask.

### 2. Store the token

```bash
sops secrets/secrets.yaml      # add: gathr-datadir: xoxp-...
```

Then declare it wherever the other secrets are declared, and reference
`config.sops.secrets."gathr-datadir".path` below. Never the token itself: the
generated config is world-readable in the Nix store.

### 3. Collect channel ids

In Slack, open the channel → **Copy link** → take the trailing segment
(`C01ABCDEF`). Use the id, not the name: names are renameable, ids are not.

Only the channels you list are ever fetched. This is an allowlist, not a display
filter — an unlisted conversation leaves nothing on disk at all.

### 4. Declare the account

In `home/<user>/default.nix`:

```nix
my.gathr.accounts.datadir = {
  org = "datadir";                                    # must exist in my.orgs
  tokenFile = config.sops.secrets."gathr-datadir".path;
  chats = [
    { remoteId = "C01ABCDEF"; name = "platform-eng"; language = "en"; }
    { remoteId = "D02GHIJKL"; name = "Kata M."; kind = "dm"; language = "sk"; }
  ];
};
```

`language` is per chat, not per org: the same client can have an English
engineering channel and a Slovak DM. An account naming an org that is not in
`my.orgs` fails at build time, with the valid names listed.

Orgs that gain a real account stop getting fixture traffic automatically, so real
and invented conversations are never mixed in one list.

### 5. Apply and check

```bash
nixos-rebuild build --flake .#workstation    # verify first
sudo nixos-rebuild switch --flake .#workstation
systemctl --user restart gathr
journalctl --user -u gathr -n 20
```

A bad token shows up as `invalid_auth` in the journal. The daemon keeps serving
the API and the other orgs keep syncing — one broken account does not stop the
rest.

## When a contract ends

Deleting the account from `my.gathr.accounts` stops the syncing. It does **not**
delete what was already stored. That is a separate, deliberate act:

```bash
gathr api snapshot            # confirm which org you mean
# stop the daemon first: it is the only writer
systemctl --user stop gathr
# then purge; rows cascade from the org
sqlite3 ~/.local/share/gathr/gathr.db "DELETE FROM orgs WHERE id = 'datadir';"
systemctl --user start gathr
```

Worth knowing what this implies: running gathr makes you the operator of a
database holding clients' messages. The disk is encrypted, the socket is `0600`,
and per-org deletion works — but if a client asks how their data is stored, the
answer involves this machine.

## Why nothing can post

No provider implements the write interface. `canPost` on a chat records intent
and shows in the assistant pane; it grants nothing. Drafts live in their own
table and reach Slack only by you copying them.

That is structural rather than configured, and it is the property that makes
running an agent against three clients' conversations defensible.

## Fixtures

`my.gathr.fixtures` (default true) gives every org **without** a real account a
fake one, so a fresh install does not open on an empty database that looks like a
misconfiguration. For development against fixtures only:

```bash
cd ~/dev/personal/gathr && tools/dev.sh
```

That runs a daemon on a throwaway data directory and socket, safe to use while
the real service is up.
