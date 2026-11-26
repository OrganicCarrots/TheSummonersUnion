# Changelog

## v1.0.0-beta2.4.1

- Sync catches up on older reports even when there are more than 120.
- New flags and withdrawals go out before background sync.
- Late messages from updated clients respect newer flags and withdrawals.

## v1.0.0-beta2.4

- Anyone sending more than 60 addon messages a minute gets ignored automatically (the addon
  itself never sends more than 50). Every player's addon checks this on its own end, so a
  modified copy can't get around it. `/su trust <name>` undoes it

## v1.0.0-beta2.3

- WoW Forever fixes. It has no realms, which the addon wasn't expecting:
  - names without a last name don't show with a stray "-" anymore
  - a guild gets one key for all its members. Before, each member's last name ended up in
    it, so a guild flagged through one member didn't match the others. Guild flags from
    older versions get merged when you log in
  - flags on those names and guilds get shared properly now, and survive export/import
  - names in messages from other players ("First Last") now match the same people seen in
    groups or targeted (First-Last). Before, your own messages bounced back looking like
    they came from a guildmate
- Harder to mess with the shared list:
  - `/su purge` and a Clear community reports button in the options throw away reports
    from other people (all of them, only the union channel, only passed-on ones, or only
    the last few hours) and keep your own flags
  - everything one person passes on counts as one source now, whoever it says it's from
  - a passed-on withdrawal only counts if it comes from whoever passed you that report
  - reports remember when and where they arrived
  - reports from strangers need more people now: you're warned once 2 people you know
    (your guild, your group, anyone you've grouped with in the last 30 days) report
    someone, or 4 people in all. Nobody can check who really grouped with whom, so this
    keeps a few made-up characters on the channel from getting someone flagged. Change it
    in the options or with `/su set threshold` and `/su set strangers`, or ignore strangers
    completely with `/su set strangers off`
- The reason you give when flagging someone (or who you summoned, from the kick popup) shows
  next to your flags in the list, with the full text on hover. Turn it off in the options
  or with `/su set reasons off`. `/su check` shows it too

## v1.0.0-beta2.2

- Undid the names-with-a-space change in `/su flag`, `/su check` and `/su unflag`, it made
  things worse. The name is one word again, so type two part names as `First-Last`, the
  same way they show up when you flag your target
- Right-click menu shows the full name
- Took the Paste and Copy buttons back out, addons can't actually use the clipboard. The
  bigger clickable box stays

## v1.0.0-beta2.1

- Right-click a player's portrait or party/raid frame for a Summoners Union entry to flag
  or unflag them and their guild
- Reports show what class the reporter was playing (older versions don't send it, so
  their reports show without one)
- Names with a space in them work in `/su flag`, `/su check` and `/su unflag`. If one gets
  split wrong, put it in quotes: `/su flag "First Last" reason`
- `/su unflag` and `/su unflagguild` by name now find flags you made from a target on
  another realm
- Import/export box has a border and the whole box is clickable. Added Paste and Copy
  buttons (you still press Ctrl+V / Ctrl+C, addons can't use the clipboard)
- Reset to defaults button in the options, some clients don't show one
- New All tab in the list, it's what the list opens on now
- Minimap tooltip says "Flagged by other members: 2 players, 1 guild" instead of the
  confusing union reports line

## v1.0.0-beta2

- Added WoW Forever. It showed up as incompatible there before

## v1.0.0-beta1

First release.

- Warlocks: your Ritual of Summoning casts in a group are counted. If you get kicked (or
  the group disbands) within 20 minutes of your last summon, you're asked whether to flag
  the leader, or the leader and their guild. Leaving on your own never triggers it
- Warnings when a flagged player invites you or joins your group, with how many times
  they've been flagged and by how many members. Optional auto-decline
- Red tooltip line on flagged players
- Flag players and guilds by hand with `/su flag` and `/su flagguild`
- Flags are shared with other users in your guild and group (dungeon finder too) and on
  the opt-in union channel. New reports are passed on as they happen, and users swap their
  lists when they meet, so everyone's list fills in on its own
- Spam protection: flags are only shared if you grouped with that player in the last 7
  days, anyone filing more than 10 reports a day is ignored, reports need 2 sources before
  they warn you, made-up reporters count once, and `/su distrust` drops everything from one
  person
- Reports expire after 180 days, and withdrawn flags are withdrawn for everyone
- Export/import your list as text
- Options panel (`/su options`) and a minimap button
