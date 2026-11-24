-- offline tests, run with ./test.sh
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local ADDON = "TheSummonersUnion"
local DIR = ""

-- load files in TOC order like the client does
local ns = {}
for line in io.lines(DIR .. ADDON .. ".toc") do
    local file = line:match("^([%w_]+%.lua)%s*$")
    if file then assert(loadfile(DIR .. file))(ADDON, ns) end
end
M.Fire("ADDON_LOADED", ADDON)
M.Fire("PLAYER_LOGIN")

local passed, failed = 0, 0
local function test(name, fn)
    M.Advance(120) -- let anything queued by the previous test finish first
    M.Reset()
    SummonersUnionDB = ns.ApplyDefaults({}, ns.DEFAULTS)
    ns.db = SummonersUnionDB
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("PASS  " .. name)
    else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, what)
    if a ~= b then error(("%s: expected %s, got %s"):format(what or "value", tostring(b), tostring(a)), 2) end
end
local function ok(v, what) if not v then error((what or "condition") .. " was false", 2) end end

local function joinBadGroup()
    M.SetGroup({ { name = "Badlead", guild = "Greedy Raiders", leader = true }, { name = "Tank" }, { name = "Healer", realm = "Faerlina" } })
    M.Fire("GROUP_JOINED")
    M.Fire("GROUP_ROSTER_UPDATE")
end
local function summon(target, guid)
    M.Fire("UNIT_SPELLCAST_SENT", "player", target, guid, 698)
    M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, 698)
end
local function getKicked()
    M.Fire("CHAT_MSG_SYSTEM", ERR_UNINVITE_YOU)
    M.SetGroup(nil)
    M.Fire("GROUP_ROSTER_UPDATE")
    M.Fire("GROUP_LEFT")
    M.Advance(3)
end

-- names and keys
test("player keys add the home realm and ignore case", function()
    eq(ns.PlayerKey("badlead"), "badlead-whitemane", "bare name")
    eq(ns.PlayerKey("Badlead-Whitemane"), "badlead-whitemane", "full name")
    eq(ns.PlayerKey("Badlead", "Area 52"), "badlead-area52", "realm with a space")
    local _, display = ns.PlayerKey("badlead")
    eq(display, "Badlead-Whitemane", "display name")
    eq(ns.GuildKey("Greedy Raiders"), "greedy raiders@whitemane", "guild key")
end)

-- detection
test("summon then kick asks to flag the leader and their guild", function()
    joinBadGroup()
    summon("Tank", "c1"); summon("Healer", "c2"); summon("Dps", "c3")
    M.Advance(60)
    getKicked()
    eq(#M.popups, 1, "prompts shown")
    local d = M.popups[1].data
    eq(d.key, "badlead-whitemane", "flag target")
    eq(d.guild, "Greedy Raiders", "guild")
    eq(d.summons, 3, "summons counted")
    eq(d.kind, "kick", "kind")
    eq(table.concat(d.targets, ","), "Tank,Healer,Dps", "summon targets")
    ok(M.popups[1].text:find("removed you from the group", 1, true), "prompt wording")
    -- clicking "Player + guild"
    StaticPopupDialogs.SUMMONERSUNION_KICKED.OnAlt(nil, d)
    ok(ns.db.players["badlead-whitemane"], "player flagged")
    ok(ns.db.guilds["greedy raiders@whitemane"], "guild flagged")
    eq(ns.db.players["badlead-whitemane"].source, "you", "source")
end)

test("leaving on your own never prompts", function()
    joinBadGroup()
    summon("Tank", "c1")
    LeaveParty()
    M.Fire("CHAT_MSG_SYSTEM", ERR_LEFT_GROUP_YOU)
    M.Fire("GROUP_ROSTER_UPDATE")
    M.Fire("GROUP_LEFT")
    M.Advance(3)
    eq(#M.popups, 0, "prompts shown")
end)

test("a kick long after the last summon doesn't prompt", function()
    joinBadGroup()
    summon("Tank", "c1")
    M.Advance(30 * 60)
    getKicked()
    eq(#M.popups, 0, "prompts shown")
end)

test("a kick without any summons doesn't prompt", function()
    joinBadGroup()
    getKicked()
    eq(#M.popups, 0, "prompts shown")
end)

test("a disband after summons prompts with disband wording", function()
    joinBadGroup()
    summon("Tank", "c1")
    M.Fire("CHAT_MSG_SYSTEM", ERR_GROUP_DISBANDED)
    M.SetGroup(nil)
    M.Fire("GROUP_ROSTER_UPDATE")
    M.Advance(3)
    eq(#M.popups, 1, "prompts shown")
    eq(M.popups[1].data.kind, "disband", "kind")
    ok(M.popups[1].text:find("disbanded the group", 1, true), "prompt wording")
end)

test("the leader is whoever led at the moment of the kick", function()
    joinBadGroup()
    summon("Tank", "c1")
    M.units.party1.leader = false
    M.units.party2.leader = true
    M.Fire("PARTY_LEADER_CHANGED")
    getKicked()
    eq(M.popups[1].data.key, "tank-whitemane", "flag target")
end)

test("summons by a non-warlock are ignored", function()
    ns.isWarlock = false
    joinBadGroup()
    summon("Tank", "c1")
    getKicked()
    ns.isWarlock = true
    eq(#M.popups, 0, "prompts shown")
end)

-- warnings
test("an invite from a flagged player raises an alert", function()
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", summons = 3, source = "you" }, true)
    M.Fire("PARTY_INVITE_REQUEST", "Badlead")
    eq(#M.alerts, 1, "alerts")
    ok(M.alerts[1]:find("Badlead%-Whitemane invited you"), "alert text")
    eq(M.declined, 0, "declined")
end)

test("autodecline declines flagged invites only", function()
    ns.db.settings.autoDecline = true
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", source = "you" }, true)
    M.Fire("PARTY_INVITE_REQUEST", "Goodfriend")
    eq(M.declined, 0, "declined a clean invite")
    M.Fire("PARTY_INVITE_REQUEST", "Badlead-Whitemane")
    eq(M.declined, 1, "declined the flagged invite")
end)

test("a flagged guild member in your group is warned once", function()
    ns.FlagGuild("greedy raiders@whitemane", { name = "Greedy Raiders", kind = "kick", source = "you" }, true)
    joinBadGroup()
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(#M.alerts, 1, "alerts")
    ok(M.alerts[1]:find("(group leader)", 1, true), "mentions leader")
end)

-- sharing
test("a new flag is broadcast to guild and group, throttled", function()
    joinBadGroup()
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", guildKey = "greedy raiders@whitemane",
        guild = "Greedy Raiders", kind = "kick", summons = 3, source = "you" }, true)
    eq(#M.sent, 0, "nothing sent before the throttle tick")
    M.Advance(5)
    eq(#M.sent, 2, "messages sent")
    eq(M.sent[1].chatType, "GUILD", "first scope")
    eq(M.sent[2].chatType, "PARTY", "second scope")
    local m = ns.DecodeMessage(M.sent[1].text)
    eq(m.key, "badlead-whitemane", "decoded key")
    eq(m.guildKey, "greedy raiders@whitemane", "decoded guild")
    eq(m.summons, 3, "decoded summons")
end)

test("imported flags are not re-broadcast as your own", function()
    local ok2 = ns.ImportText(ns.Export({ players = { ["x-whitemane"] = { name = "X-Whitemane", when = time(), kind = "kick" } }, guilds = {} }))
    ok(ok2, "import worked")
    M.Advance(5)
    eq(#M.sent, 0, "messages sent")
end)

test("community reports need the threshold, one vote each", function()
    local msg = ns.EncodeFlag("P", "badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", summons = 2, when = time() })
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", msg, "CHANNEL", "Stranger-Faerlina")
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", msg, "CHANNEL", "Stranger-Faerlina")
    local s = ns.Status("badlead-whitemane")
    eq(s.cPlayer, 1, "one reporter counted once")
    eq(s.flagged, false, "not shown below threshold")
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", msg, "CHANNEL", "Other-Mankrik")
    s = ns.Status("badlead-whitemane")
    eq(s.cPlayer, 2, "two reporters")
    eq(s.flagged, true, "shown at threshold")
    ns.Slash("distrust Other-Mankrik")
    eq(ns.Status("badlead-whitemane").flagged, false, "distrusted reporter no longer counts")
end)

test("a single guildmate report is trusted", function()
    local msg = ns.EncodeFlag("P", "badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", when = time() })
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", msg, "GUILD", "Buddy-Whitemane")
    eq(ns.Status("badlead-whitemane").flagged, true, "shown")
end)

test("a retraction removes the reporter's report", function()
    local rec = { name = "Badlead-Whitemane", kind = "kick", when = time() }
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", ns.EncodeFlag("P", "badlead-whitemane", rec), "GUILD", "Buddy-Whitemane")
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", ns.EncodeRetract("P", "badlead-whitemane", rec), "GUILD", "Buddy-Whitemane")
    eq(ns.Status("badlead-whitemane").cPlayer, 0, "reports left")
end)

test("garbage and other addons' messages are ignored", function()
    M.Fire("CHAT_MSG_ADDON", "OTHERADDON", "1~F~P~X-Y~~1~1~kick", "GUILD", "A-B")
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", "nonsense", "GUILD", "A-B")
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", "1~F~P~nohyphen~~1~1~kick", "GUILD", "A-B")
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", "1~F~P~X-Y~~1~99999999~kick", "GUILD", "A-B")
    local n = 0
    for _ in pairs(ns.db.community.players) do n = n + 1 end
    eq(n, 0, "stored reports")
end)

test("a query is answered with your own recent flags after a delay", function()
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", source = "you" }, true)
    M.Advance(5)
    M.sent = {}
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", ns.EncodeQuery(ns.Today() - 30), "GUILD", "Buddy-Whitemane")
    M.Advance(20)
    eq(#M.sent, 1, "replies")
    eq(M.sent[1].chatType, "GUILD", "reply scope")
    M.sent = {}
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", ns.EncodeQuery(ns.Today() - 30), "GUILD", "Buddy-Whitemane")
    M.Advance(20)
    eq(#M.sent, 0, "second query within the cooldown is ignored")
end)

test("Retail secret values are skipped instead of erroring", function()
    issecretvalue = function(v) return v == "SECRET" end
    M.units.party1 = { name = "SECRET" }
    eq(ns.UnitKey("party1"), nil, "secret name ignored")
    M.Fire("CHAT_MSG_SYSTEM", "SECRET")
    M.Fire("PARTY_INVITE_REQUEST", "SECRET")
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", "SECRET", "GUILD", "A-B")
    issecretvalue = nil
end)

-- export / import
test("export round-trips and rejects tampering", function()
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", guildKey = "greedy raiders@whitemane",
        guild = "Greedy Raiders", kind = "kick", summons = 3, source = "you" }, true)
    ns.FlagGuild("greedy raiders@whitemane", { name = "Greedy Raiders", kind = "kick", source = "you" }, true)
    local text = ns.Export(ns.db)
    local list = assert(ns.ParseExport(text))
    eq(#list, 2, "entries")
    local bad, err = ns.ParseExport(text:gsub("Badlead", "Goodlead"))
    eq(bad, nil, "tampered parse")
    ok(err:find("checksum"), "tamper reason")
    eq((ns.ParseExport("hello")), nil, "non-export")
    local fresh = { players = {}, guilds = {}, community = { players = {}, guilds = {} }, distrust = {}, reporterCounts = {}, settings = ns.db.settings }
    ns.db = fresh
    local okImport, res = ns.ImportText(text)
    ok(okImport, "import")
    eq(res.players, 1, "players imported")
    eq(res.guilds, 1, "guilds imported")
    eq(fresh.players["badlead-whitemane"].summons, 3, "summons kept")
    eq(fresh.players["badlead-whitemane"].source, "import", "marked as imported")
    local _, again = ns.ImportText(text)
    eq(again.skipped, 2, "re-import skips existing")
end)

-- commands and UI smoke tests
test("slash commands flag, check and unflag", function()
    ns.Slash("flag Badlead stole the summons")
    ok(ns.db.players["badlead-whitemane"], "flagged")
    eq(ns.db.players["badlead-whitemane"].reason, "stole the summons", "reason")
    ns.Slash("flagguild Greedy Raiders")
    ok(ns.db.guilds["greedy raiders@whitemane"], "guild flagged")
    ns.Slash("check Badlead")
    ok(M.chat[#M.chat]:find("you flagged them", 1, true), "check output")
    ns.Slash("unflag Badlead")
    eq(ns.db.players["badlead-whitemane"], nil, "unflagged")
    ns.Slash("set window 45")
    eq(ns.db.settings.summonWindowMinutes, 45, "setting changed")
    ns.Slash("share channel off")
    eq(ns.db.settings.shareChannel, false, "share setting")
end)

test("windows build and refresh without errors", function()
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", source = "you" }, true)
    ns.Slash("")
    ns.Slash("export")
    ns.Slash("import")
    ns.Slash("test")
    ok(#M.popups == 1 and M.popups[1].data.test, "test prompt shown")
    StaticPopupDialogs.SUMMONERSUNION_KICKED.OnAccept(nil, M.popups[1].data)
    eq(ns.db.players["example-realm"], nil, "preview flags nothing")
end)

-- settings
test("slash settings are clamped to sensible ranges", function()
    ns.Slash("set threshold 0")
    eq(ns.db.settings.communityThreshold, 1, "threshold floor")
    ns.Slash("set window 9999")
    eq(ns.db.settings.summonWindowMinutes, 240, "window ceiling")
    ns.Slash("set expiry -5")
    eq(ns.db.settings.communityExpiryDays, 0, "expiry floor")
    ns.Slash("set minsummons 2.7")
    eq(ns.db.settings.minSummons, 2, "whole numbers")
    ns.Slash("set bogus 1")
    ok(M.chat[#M.chat]:find("Options:", 1, true), "lists the options")
end)

test("the options panel registers and its controls change settings", function()
    local controls, panel, category = ns.OptionControls()
    ok(category and M.addonCategory == category, "registered in the settings window")
    eq(category.name, "The Summoners Union", "category name")
    panel:Show()
    eq(controls.summonWindowMinutes.value.text, "20 min", "stepper shows the setting")
    eq(controls.autoDecline:GetChecked(), false, "checkbox shows the setting")

    controls.autoDecline:SetChecked(true)
    controls.autoDecline.scripts.OnClick(controls.autoDecline)
    eq(ns.db.settings.autoDecline, true, "checkbox writes the setting")

    controls.summonWindowMinutes.Step(1)
    eq(ns.db.settings.summonWindowMinutes, 25, "stepper up")
    eq(controls.summonWindowMinutes.value.text, "25 min", "open panel refreshes")
    ns.Slash("set window 37")
    controls.summonWindowMinutes.Step(1)
    eq(ns.db.settings.summonWindowMinutes, 45, "steps up from a custom value")
    ns.Slash("set window 37")
    controls.summonWindowMinutes.Step(-1)
    eq(ns.db.settings.summonWindowMinutes, 30, "steps down from a custom value")

    local expiry = controls.communityExpiryDays
    expiry.Step(1)
    eq(ns.db.settings.communityExpiryDays, 365, "180 -> 365")
    expiry.Step(1)
    eq(ns.db.settings.communityExpiryDays, 0, "365 -> never")
    eq(expiry.value.text, "Never", "never label")
    eq(expiry.plus.enabled, false, "can't go past never")
    expiry.Step(1)
    eq(ns.db.settings.communityExpiryDays, 0, "stays at never")
    expiry.Step(-1)
    eq(ns.db.settings.communityExpiryDays, 365, "never -> 365")

    panel.OnDefault()
    eq(ns.db.settings.autoDecline, false, "defaults restored")
    eq(ns.db.settings.summonWindowMinutes, 20, "defaults restored")
    panel:Hide()

    ns.Slash("options")
    eq(M.openedCategory, 4242, "/su options opens our page")
end)

test("turning the union channel on and off joins and leaves it", function()
    ns.Slash("share channel on")
    eq(M.channels.SummonersUnion, 5, "joined")
    M.Advance(8)
    local q = ns.DecodeMessage(M.sent[#M.sent].text)
    eq(q and q.type, "Q", "asks the channel for recent flags")
    eq(M.sent[#M.sent].chatType, "CHANNEL", "on the channel")
    ns.Slash("share channel off")
    eq(M.leftChannels[1], "SummonersUnion", "left")
end)

-- minimap and compartment
test("the minimap button shows, hides, drags and clicks", function()
    local b = ns.MinimapButton()
    ok(b and b.shown, "created and shown at login")
    ns.Slash("minimap")
    eq(b.shown, false, "hidden")
    ns.Slash("minimap")
    eq(b.shown, true, "shown again")

    M.cursor = { 600, 400 } -- straight east of the minimap's centre
    b.scripts.OnDragStart(b)
    b.scripts.OnUpdate(b)
    eq(ns.db.settings.minimapAngle, 0, "angle east")
    eq(b.point[4], 75, "on the edge, x")
    eq(math.floor(b.point[5] + 0.5), 0, "on the edge, y")
    M.cursor = { 500, 300 } -- straight south
    b.scripts.OnUpdate(b)
    eq(ns.db.settings.minimapAngle, 270, "angle south")
    eq(math.floor(b.point[5] + 0.5), -75, "on the edge, y")
    b.scripts.OnDragStop(b)
    eq(b.scripts.OnUpdate, nil, "stops following the cursor")

    local list = _G.SummonersUnionFrame
    local before = list and list.shown or false
    b.scripts.OnClick(b, "LeftButton")
    eq(_G.SummonersUnionFrame.shown, not before, "left-click toggles the list")
    b.scripts.OnClick(b, "RightButton")
    eq(M.openedCategory, 4242, "right-click opens the options")

    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick" }, true)
    b.scripts.OnEnter(b)
    ok(table.concat(M.tooltip, "\n"):find("Your flags: 1 players, 0 guilds", 1, true), "tooltip counts")
end)

test("the addon compartment entry opens the list and options", function()
    SummonersUnion_OnAddonCompartmentClick("TheSummonersUnion", "RightButton")
    eq(M.openedCategory, 4242, "right-click, older clients")
    M.openedCategory = nil
    SummonersUnion_OnAddonCompartmentClick("TheSummonersUnion", { buttonName = "RightButton" })
    eq(M.openedCategory, 4242, "right-click, newer clients")
    local before = _G.SummonersUnionFrame.shown
    SummonersUnion_OnAddonCompartmentClick("TheSummonersUnion", "LeftButton")
    eq(_G.SummonersUnionFrame.shown, not before, "left-click toggles the list")
    SummonersUnion_OnAddonCompartmentEnter("TheSummonersUnion", CreateFrame("Button"))
    ok(table.concat(M.tooltip, "\n"):find("Right-click: options", 1, true), "tooltip")
    SummonersUnion_OnAddonCompartmentLeave()
end)

-- dungeon finder groups
test("dungeon finder groups share over INSTANCE_CHAT", function()
    joinBadGroup()
    M.instance = true
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", source = "you" }, true)
    M.Advance(5)
    eq(#M.sent, 2, "messages sent")
    eq(M.sent[2].chatType, "INSTANCE_CHAT", "group scope")
end)

-- aging
local function report(sender, daysAgo, channel)
    local msg = ns.EncodeFlag("P", "badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", when = time() - daysAgo * 86400 })
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", msg, channel or "CHANNEL", sender)
end

test("old community reports stop counting and are pruned", function()
    report("Stale-Faerlina", 200)
    eq(ns.db.community.players["badlead-whitemane"], nil, "a report past the expiry isn't stored")
    report("Stranger-Faerlina", 100)
    report("Other-Mankrik", 100)
    eq(ns.Status("badlead-whitemane").flagged, true, "two recent reports count")
    ns.Slash("set expiry 90")
    eq(ns.Status("badlead-whitemane").flagged, false, "they stop counting once past the expiry")
    eq(ns.db.reporterCounts["stranger-faerlina"], 1, "still stored before pruning")
    local removed = ns.Prune()
    eq(removed, 2, "reports pruned")
    eq(ns.db.community.players["badlead-whitemane"], nil, "entry removed")
    eq(ns.db.reporterCounts["stranger-faerlina"], nil, "reporter counts recounted")
    ns.Slash("set expiry 0")
    report("Ancient-Faerlina", 2000)
    eq(ns.Status("badlead-whitemane").cPlayer, 1, "with expiry off, old reports are kept")
end)

test("your own flags are only forgotten at login, and only if you ask", function()
    ns.FlagPlayer("old-whitemane", { name = "Old-Whitemane", kind = "kick", when = time() - 400 * 86400 }, true)
    ns.FlagPlayer("new-whitemane", { name = "New-Whitemane", kind = "kick" }, true)
    local _, forgotten = ns.Prune()
    eq(forgotten, 0, "kept forever by default")
    ns.Slash("set flagexpiry 365")
    ok(ns.db.players["old-whitemane"], "changing the setting deletes nothing by itself")
    _, forgotten = ns.Prune()
    eq(forgotten, 1, "forgotten at the next prune")
    eq(ns.db.players["old-whitemane"], nil, "old flag gone")
    ok(ns.db.players["new-whitemane"], "recent flag kept")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
