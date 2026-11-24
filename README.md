# The Summoners Union

A WoW addon for warlocks who are tired of getting invited to "help out", spending ten minutes
summoning the whole group, and then getting kicked the second the last person is through the
portal.

It remembers who did it, warns you the next time they invite you or show up in your group, and
shares flags with other people running the addon.

## Features

- Counts your Ritual of Summoning casts while you're in a group. If you get kicked (or the
  group disbands) within 20 minutes of your last summon, a popup asks if you want to flag the
  leader, or the leader and their guild. Leaving on your own doesn't trigger it, and nothing
  gets flagged unless you click.
- Raid warning when a flagged player invites you or joins your group, same for members of a
  flagged guild. It tells you how many times they've been flagged and by how many people,
  e.g. "flagged 6 times by 4 union members". Optional auto-decline (off by default).
- Red line on flagged players' tooltips.
- `/su flag` and `/su flagguild` to flag someone by hand. Works on any class.
- Flags get shared with other users in your guild and group through hidden addon messages,
  dungeon finder groups included. There's an opt-in public channel too. Whenever users meet
  (guild at login, a group when you join it, the channel) they swap their whole lists,
  including reports they got from other people, so everyone's list fills in on its own.
- Export/import your list as text to pass it to friends or your guild.
- Options panel under Options > AddOns (or `/su options`) and a minimap button. Left click
  opens the list, right click opens the options.

## Commands

| Command | What it does |
|---|---|
| `/su` | Open the list (your players, your guilds, community reports) |
| `/su options` | Open the options panel |
| `/su flag [name] [reason]` | Flag a player (your target if you don't give a name) |
| `/su flagguild [guild]` | Flag a guild (your target's guild if you don't give one) |
| `/su unflag <name>`, `/su unflagguild <guild>` | Remove your flag |
| `/su check [name]` | Look someone up |
| `/su list` | Print your flags to chat |
| `/su export`, `/su import` | Share your list as text |
| `/su share guild\|group\|channel on\|off` | Where your flags get shared |
| `/su distrust <name>`, `/su trust <name>` | Ignore (or stop ignoring) everything from one person |
| `/su set window <minutes>` | How soon after your last summon a kick counts (default 20) |
| `/su set minsummons <n>` | Summons needed before a kick counts (default 1) |
| `/su set threshold <n>` | How many people need to report someone before you see it (default 2) |
| `/su set autodecline on\|off` | Decline invites from flagged players |
| `/su set relays on\|off` | Count reports other people pass on, not just first hand ones (default on) |
| `/su set expiry <days>` | Ignore other people's reports after this long (default 180, 0 = never) |
| `/su set flagexpiry <days>` | Forget your own flags after this long, checked at login (default 0 = never) |
| `/su minimap` | Show/hide the minimap button |
| `/su test` | Show the kick popup without flagging anything |

## Abuse and false reports

A shared list is only useful if people can't spam it, so:

- You can only share a flag on someone you've been in a group with in the last 7 days (or
  a member of that guild). Flags from the kick popup always qualify. Anything else stays
  private: it still warns you, but nobody else sees it.
- Anyone who files more than 10 new reports in one day gets ignored automatically. You get
  a message, and `/su trust <name>` undoes it.
- Someone else's report only warns you once 2 different sources have reported the same
  player (`/su set threshold`). Everyone who reported directly is one source, and
  everything one person passes on counts as one, so making up reporters doesn't help. One
  first hand report from a guildmate is enough, unless you `/su set trustguild off`.
- One person counts once per player. Their count of grievances is capped at 5, one person
  can pass on at most 3 reports about the same player, and at most 300 reports are stored
  from anyone.
- `/su distrust <name>` drops everything that person reported or passed on.
  `/su set relays off` ignores passed-on reports altogether.
- Removing a flag sends a retraction that spreads like the reports do, and old copies
  can't bring it back.
- Reports expire after 180 days. Your own flags stay until you remove them, unless you set
  `/su set flagexpiry`.
- Nothing is ever posted in chat, flagged players are never messaged, and nobody gets told
  they were flagged. The addon never kicks or reports anyone. Warnings only show for you.

The addon is open source, so someone could change their copy to skip the checks on their
own flags. That's why the checks that matter (thresholds, caps, flood detection) happen on
the receiving end.

## Game versions

Classic Era (incl. Hardcore and SoD), TBC Anniversary, MoP Classic and Retail. Summon kicking
is mostly a Classic thing but it runs everywhere.

## Development

- `./test.sh` runs the tests under Lua 5.1 against a mocked WoW API. Uses Docker if you don't
  have lua5.1 installed.
- `./build.sh [version]` builds a zip in `dist/` if you want to install it by hand.
- Pushing a `v*` tag runs the tests and uploads to CurseForge with the
  [BigWigs packager](https://github.com/BigWigsMods/packager). Needs the `CF_API_KEY` secret
  and `## X-Curse-Project-ID:` in the TOC.

MIT licensed. Not affiliated with Blizzard.
