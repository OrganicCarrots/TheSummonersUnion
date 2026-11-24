# Changelog

## v1.0.0

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
