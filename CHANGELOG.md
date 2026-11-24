# Changelog

## v1.1.0

- Warnings say how many times a player or guild has been flagged and by how many members
- Users swap their whole lists when they meet (guild at login, groups when you join, the
  union channel), including reports passed on from others, so lists fill in on their own
- Your flags are only shared if you've grouped with them in the last 7 days, otherwise
  they stay private
- Anyone filing more than 10 new reports in a day gets ignored automatically (`/su trust`
  to undo)
- Everything one person passes on counts once toward the warning threshold, and they can
  pass on at most 3 reports about the same player
- New reports are passed on as they happen: when you get one you haven't seen, it goes to
  your other channels a few seconds later (`/su set forward off` to stop), capped at 30 a
  minute
- A passed-on report counts as its own source if the reporter has messaged you directly
  before, made-up names still count once per person passing them on
- A report passed on in your name that you never made gets withdrawn automatically
- Withdrawn flags spread to everyone and stay withdrawn
- `/su set relays off` ignores passed-on reports
- Asks once whether you want to join the union channel (still opt-in), and the options and
  tooltips point out it gives the best results
- Don't answer list requests on a scope you've turned sharing off for
- 1.0 ignores passed-on reports and the new count field, so mixed versions still work

## v1.0.0

- Options panel (Options > AddOns, or `/su options`)
- Minimap button, plus an entry in the retail addon compartment
- Flags are now shared in dungeon finder, LFR and battleground groups
- Community reports expire after 180 days (`/su set expiry`)
- Optional expiry for your own flags (`/su set flagexpiry`), checked at login
- Turning off the union channel now actually leaves it
- `/su set` values are clamped, e.g. threshold 0 becomes 1
- Options button on the list window

## v0.1.0

- First release: summon-kick detection and popup, warnings on invites and in groups,
  optional auto-decline, tooltip line, flagging by hand, sharing with guild/group/channel,
  export/import
