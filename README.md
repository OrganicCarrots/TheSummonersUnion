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
  flagged guild. Optional auto-decline for their invites (off by default).
- Red line on flagged players' tooltips.
- `/su flag` and `/su flagguild` to flag someone by hand. Works on any class.
- Flags get shared with other users in your guild and group through hidden addon messages,
  dungeon finder groups included. There's an opt-in public channel too. When you log in,
  guildmates send you their recent flags.
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
| `/su set expiry <days>` | Ignore other people's reports after this long (default 180, 0 = never) |
| `/su set flagexpiry <days>` | Forget your own flags after this long, checked at login (default 0 = never) |
| `/su minimap` | Show/hide the minimap button |
| `/su test` | Show the kick popup without flagging anything |

## False reports

Anyone can flag anyone, so other people's reports are treated carefully:

- Your own flags always count. Someone else's report only shows up once 2 different people
  have reported the same player (`/su set threshold`). One report from a guildmate is enough,
  unless you turn that off with `/su set trustguild off`.
- Each person counts once per player however many times they send it, and at most 300
  reports are stored from any one person.
- `/su distrust <name>` drops everything from that person. Removing a flag sends a
  retraction, so it goes away for everyone else too.
- Reports expire after 180 days. Your own flags stay until you remove them, unless you set
  `/su set flagexpiry`.
- Nothing is ever posted in chat, flagged players are never messaged, and nobody gets told
  they were flagged. The addon never kicks or reports anyone. Warnings only show for you.

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
