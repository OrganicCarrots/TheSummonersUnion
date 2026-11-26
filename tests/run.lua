package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")
local ADDON = "TheSummonersUnion"
local DIR = ""

local ns = {}
for line in io.lines(DIR .. ADDON .. ".toc") do
    local file = line:match("^([%w_]+%.lua)%s*$")
    if file then assert(loadfile(DIR .. file))(ADDON, ns) end
end
M.Fire("ADDON_LOADED", ADDON)
M.Fire("PLAYER_LOGIN")

local passed, failed = 0, 0
local function test(name, fn)
    M.Advance(120)
    M.Reset()
    ns.ResetSync()
    SummonersUnionDB = ns.ApplyDefaults({}, ns.DEFAULTS)
    SummonersUnionDB.settings.strangerThreshold = 2
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

test("player keys add the home realm and ignore case", function()
    eq(ns.PlayerKey("badlead"), "badlead-whitemane", "bare name")
    eq(ns.PlayerKey("Badlead-Whitemane"), "badlead-whitemane", "full name")
    eq(ns.PlayerKey("Badlead", "Area 52"), "badlead-area52", "realm with a space")
    local _, display = ns.PlayerKey("badlead")
    eq(display, "Badlead-Whitemane", "display name")
    eq(ns.GuildKey("Greedy Raiders"), "greedy raiders@whitemane", "guild key")
end)

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
    StaticPopupDialogs.SUMMONERSUNION_KICKED.OnAlt(nil, d)
    ok(ns.db.players["badlead-whitemane"], "player flagged")
    ok(ns.db.guilds["greedy raiders@whitemane"], "guild flagged")
    eq(ns.db.players["badlead-whitemane"].source, "you", "source")
    eq(ns.db.players["badlead-whitemane"].private, nil, "shared, you were grouped with them")
    eq(ns.db.guilds["greedy raiders@whitemane"].private, nil, "guild shared too")
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

test("your flags remember which of your characters made them", function()
    ok(ns.playerKey, "player key")
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", source = "you" }, true)
    eq(ns.db.players["badlead-whitemane"].by, ns.playerKey, "flagged by")
    ns.FlagGuild("greedy raiders@whitemane", { name = "Greedy Raiders", kind = "kick", source = "you" }, true)
    eq(ns.db.guilds["greedy raiders@whitemane"].by, ns.playerKey, "guild flagged by")
    ns.FlagPlayer("other-whitemane", { name = "Other-Whitemane", kind = "manual", source = "import" }, true)
    eq(ns.db.players["other-whitemane"].by, nil, "imported flag")
end)

test("a flagged guild member in your group is warned once", function()
    ns.FlagGuild("greedy raiders@whitemane", { name = "Greedy Raiders", kind = "kick", source = "you" }, true)
    joinBadGroup()
    M.Fire("GROUP_ROSTER_UPDATE")
    eq(#M.alerts, 1, "alerts")
    ok(M.alerts[1]:find("(group leader)", 1, true), "mentions leader")
end)

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
    ns.NoteGrouped("badlead-whitemane")
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
    eq(fresh.players["badlead-whitemane"].class, "WARLOCK", "class kept")
    local _, again = ns.ImportText(text)
    eq(again.skipped, 2, "re-import skips existing")
end)

test("slash commands flag, check and unflag", function()
    ns.Slash("flag Badlead stole the summons")
    ok(ns.db.players["badlead-whitemane"], "flagged")
    eq(ns.db.players["badlead-whitemane"].reason, "stole the summons", "reason")
    ns.Slash("flagguild Greedy Raiders")
    ok(ns.db.guilds["greedy raiders@whitemane"], "guild flagged")
    ns.Slash("check Badlead")
    ok(table.concat(M.chat, "\n"):find("Badlead-Whitemane: you flagged them on", 1, true), "check output")
    ok(M.chat[#M.chat]:find("private", 1, true), "says the flag is private")
    ns.Slash("unflag Badlead")
    eq(ns.db.players["badlead-whitemane"], nil, "unflagged")
    ns.Slash("set window 45")
    eq(ns.db.settings.summonWindowMinutes, 45, "setting changed")
    ns.Slash("share channel off")
    eq(ns.db.settings.shareChannel, false, "share setting")
end)

test("two part names are typed First-Last, same as a flag from the target", function()
    M.units.target = { name = "First", realm = "Last" }
    ns.Slash("flag")
    eq(ns.db.players["first-last"].name, "First-Last", "flag from the target")
    M.units.target = nil
    ns.Slash("unflag first-last")
    eq(ns.db.players["first-last"], nil, "typed the same way, it unflags")
    ns.Slash("flag first-last left right after")
    eq(ns.db.players["first-last"].name, "First-Last", "shows the same as the target flag")
    eq(ns.db.players["first-last"].reason, "left right after", "the rest is the reason")
    ns.Slash("check first-last")
    ok(table.concat(M.chat, "\n"):find("First-Last: you flagged them", 1, true), "check finds it")
    ns.Slash("flag Bob ran off")
    eq(ns.db.players["bob-whitemane"].reason, "ran off", "one word names get your realm")
end)

test("unflagguild by name finds a guild flagged from a target on another realm", function()
    M.units.target = { name = "Farlead", realm = "Faerlina", guild = "Far Guild" }
    ns.Slash("flagguild")
    ok(ns.db.guilds["far guild@faerlina"], "guild flagged from the target")
    M.units.target = nil
    ns.Slash("unflagguild Far Guild")
    eq(ns.db.guilds["far guild@faerlina"], nil, "guild unflagged by name")

    ns.FlagGuild("twins@faerlina", { name = "Twins", kind = "manual", source = "you" }, true)
    ns.FlagGuild("twins@mankrik", { name = "Twins", kind = "manual", source = "you" }, true)
    ns.Slash("unflagguild Twins")
    ok(ns.db.guilds["twins@faerlina"] and ns.db.guilds["twins@mankrik"], "nothing removed when it's on two realms")
    ok(M.chat[#M.chat]:find("more than one realm", 1, true), "asks for the realm")
    ns.Slash("unflagguild Twins@Mankrik")
    eq(ns.db.guilds["twins@mankrik"], nil, "the realm picks one")
end)

local function noRealms(fn)
    M.realm = ""
    local ok2, err = pcall(fn)
    M.realm = "Whitemane"
    if not ok2 then error(err, 0) end
end

test("with no realms, names have no stray hyphen and a guild has one key", function()
    noRealms(function()
        local key, display = ns.PlayerKey("bob")
        eq(key, "bob-", "key")
        eq(display, "Bob", "no stray hyphen")
        eq(select(2, ns.PlayerKey("Kyle", "Selten")), "Kyle-Selten", "last name in the realm slot")
        eq(ns.DisplayName("bob-"), "Bob", "display name from a key")
        eq(ns.PlayerKey("John Warcarft"), "john-warcarft", "message senders come as First Last")
        eq(select(2, ns.PlayerKey("John Warcarft")), "John-Warcarft", "shown the same as from a target")
        local me = ns.playerKey
        ns.playerKey = "john-warcarft"
        local ok3, err3 = pcall(M.Fire, "CHAT_MSG_ADDON", "SUMUNION",
            ns.EncodeFlag("P", "bob-", { name = "Bob", kind = "kick", when = time() }), "GUILD", "John Warcarft")
        ns.playerKey = me
        if not ok3 then error(err3, 0) end
        eq(ns.db.community.players["bob-"], nil, "your own message coming back is ignored")
        M.units.target = { name = "Kyle", realm = "Selten", guild = "Salty Tears" }
        M.units.party1 = { name = "Ann", realm = "Other", guild = "Salty Tears" }
        eq(ns.UnitGuild("target"), "salty tears@", "guild key ignores the last name")
        eq(ns.UnitGuild("party1"), "salty tears@", "same key for every member")
        ns.Slash("flagguild Salty Tears")
        ok(ns.db.guilds["salty tears@"], "a typed guild gets the same key")

        local m = ns.DecodeMessage(ns.EncodeFlag("P", "bob-", { name = "Bob", guildKey = "salty tears@", guild = "Salty Tears", kind = "kick", when = time() }))
        eq(m.key, "bob-", "player key survives sharing")
        eq(m.guildKey, "salty tears@", "their guild survives sharing")
        local g = ns.DecodeMessage(ns.EncodeFlag("G", "salty tears@", { name = "Salty Tears", kind = "kick", when = time() }))
        eq(g.key, "salty tears@", "guild flag survives sharing")
        ns.FlagPlayer("bob-", { name = "Bob", kind = "manual", source = "you" }, true)
        local list = assert(ns.ParseExport(ns.Export(ns.db)))
        eq(#list, 2, "export keeps both")
    end)
end)

test("with no realms, old per-member guild keys and stray hyphens get cleaned up", function()
    noRealms(function()
        ns.db.guilds["salty tears@selten"] = { name = "Salty Tears", when = 100, source = "you" }
        ns.db.guilds["salty tears@other"] = { name = "Salty Tears", when = 200, source = "you" }
        ns.db.players["kyle-selten"] = { name = "Kyle-Selten", guildKey = "salty tears@selten" }
        ns.db.players["bob-"] = { name = "Bob-" }
        ns.db.community.guilds["salty tears@selten"] = { ["ann-other"] = { d = 1 } }
        ns.db.community.players["bob-"] = { ["ann-other"] = { n = "Bob-", g = "salty tears@other", d = 1 },
            ["kyle selten-"] = { n = "Bob-", d = 2, rl = "evil doer-" } }
        ns.db.distrust["evil doer-"] = true
        ns.FixRealmless(ns.db)
        local moved = ns.db.community.players["bob-"]["kyle-selten"]
        ok(moved and not ns.db.community.players["bob-"]["kyle selten-"], "old First Last sender keys moved to First-Last")
        eq(moved.rl, "evil-doer", "who passed it on too")
        ok(ns.db.distrust["evil-doer"] and not ns.db.distrust["evil doer-"], "distrust follows them")
        ok(ns.db.guilds["salty tears@"] and not ns.db.guilds["salty tears@selten"], "folded into one key")
        eq(ns.db.guilds["salty tears@"].when, 200, "the newest one kept")
        eq(ns.db.players["kyle-selten"].guildKey, "salty tears@", "player's guild folded")
        eq(ns.db.players["kyle-selten"].name, "Kyle-Selten", "real last names left alone")
        eq(ns.db.players["bob-"].name, "Bob", "stray hyphen dropped")
        ok(ns.db.community.guilds["salty tears@"]["ann-other"], "reports folded")
        eq(ns.db.community.players["bob-"]["ann-other"].g, "salty tears@", "report's guild folded")
        eq(ns.db.community.players["bob-"]["ann-other"].n, "Bob", "report's name cleaned")
    end)
end)

test("reports say which class the reporter was", function()
    local function report(sender, class)
        local msg = ns.EncodeFlag("P", "badlead-whitemane", { name = "Badlead-Whitemane", kind = "manual", when = time(), class = class })
        M.Fire("CHAT_MSG_ADDON", "SUMUNION", msg, "CHANNEL", sender)
    end
    report("Lock-Faerlina", "WARLOCK")
    report("Oldversion-Mankrik", nil)
    report("Healer-Mankrik", "PRIEST")
    local reports = ns.db.community.players["badlead-whitemane"]
    eq(reports["lock-faerlina"].cl, "WARLOCK", "class stored")
    eq(reports["oldversion-mankrik"].cl, nil, "older versions send no class")
    eq(ns.ReporterClasses("players", "badlead-whitemane"), "1 warlock, 1 priest", "warlocks first")
    ns.Slash("check Badlead")
    ok(table.concat(M.chat, "\n"):find("Reported by: 1 warlock, 1 priest.", 1, true), "check lists the classes")

    local passed
    for _, text in ipairs(ns.SyncMessages(0, nil, "asker-whitemane")) do
        for _, m in ipairs(ns.DecodeMessages(text)) do
            if m.reporter == "lock-faerlina" then passed = m.class end
        end
    end
    eq(passed, "WARLOCK", "passed-on reports keep the class")
    ns.FlagPlayer("other-whitemane", { name = "Other-Whitemane", kind = "manual", source = "you" }, true)
    eq(ns.db.players["other-whitemane"].class, "WARLOCK", "your own flags remember your class")
end)

test("the reset button in the options asks first, then restores the defaults", function()
    local _, panel = ns.OptionControls()
    ns.Slash("set autodecline on")
    panel.resetButton.scripts.OnClick(panel.resetButton)
    eq(M.popups[#M.popups].which, "SUMMONERSUNION_RESET", "asks first")
    eq(ns.db.settings.autoDecline, true, "nothing changes before you confirm")
    StaticPopupDialogs.SUMMONERSUNION_RESET.OnAccept()
    eq(ns.db.settings.autoDecline, false, "defaults back")
end)

test("the import box shows a hint until there's text", function()
    ns.Slash("import")
    local box = _G.SummonersUnionIO
    ok(box.hint.shown, "hint while empty")
    box.edit:SetText("something")
    box.edit.scripts.OnTextChanged(box.edit)
    ok(not box.hint.shown, "hint goes once there's text")
    ns.Slash("export")
    ok(not box.hint.shown, "no hint over the export")
end)

test("the right-click menu flags and unflags a player and their guild", function()
    M.units.target = { name = "Badlead", guild = "Greedy Raiders" }
    local function entries()
        local root = M.OpenMenu("MENU_UNIT_PLAYER", { unit = "target" })
        local sub = root.items[#root.items]
        eq(sub.text, "The Summoners Union", "our submenu")
        local out = {}
        for _, e in ipairs(sub.items) do out[e.text] = e end
        return out
    end
    local e = entries()
    e["Flag Badlead-Whitemane"].fn()
    ok(ns.db.players["badlead-whitemane"], "player flagged")
    e["Flag guild <Greedy Raiders>"].fn()
    ok(ns.db.guilds["greedy raiders@whitemane"], "guild flagged")
    e = entries()
    e["Unflag Badlead-Whitemane"].fn()
    eq(ns.db.players["badlead-whitemane"], nil, "player unflagged")
    e["Unflag guild <Greedy Raiders>"].fn()
    eq(ns.db.guilds["greedy raiders@whitemane"], nil, "guild unflagged")
    eq(#M.OpenMenu("MENU_UNIT_PLAYER", { unit = "player" }).items, 0, "nothing on yourself")
    eq(#M.OpenMenu("MENU_UNIT_FRIEND", { name = "Chatter", server = "Faerlina" }).items[2].items, 1, "chat names get the player entry")
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

test("the minimap button shows, hides, drags and clicks", function()
    local b = ns.MinimapButton()
    ok(b and b.shown, "created and shown at login")
    ns.Slash("minimap")
    eq(b.shown, false, "hidden")
    ns.Slash("minimap")
    eq(b.shown, true, "shown again")

    M.cursor = { 600, 400 }
    b.scripts.OnDragStart(b)
    b.scripts.OnUpdate(b)
    eq(ns.db.settings.minimapAngle, 0, "angle east")
    eq(b.point[4], 75, "on the edge, x")
    eq(math.floor(b.point[5] + 0.5), 0, "on the edge, y")
    M.cursor = { 500, 300 }
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
    ns.db.community.players["grief-whitemane"] = { ["guildie-whitemane"] = { d = ns.Today(), via = "GUILD" } }
    b.scripts.OnEnter(b)
    local tip = table.concat(M.tooltip, "\n")
    ok(tip:find("Your flags: 1 player, 0 guilds", 1, true), "tooltip counts your flags")
    ok(tip:find("Flagged by other members: 1 player, 0 guilds", 1, true), "tooltip counts other members' flags")
end)

test("the list window's All tab shows your flags and community reports together", function()
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick" }, true)
    ns.FlagGuild("bad guild@whitemane", { name = "Bad Guild", kind = "kick" }, true)
    ns.db.community.players["grief-whitemane"] = { ["guildie-whitemane"] = { d = ns.Today(), n = "Grief-Whitemane", via = "GUILD" } }
    if not ns.ListWindow() then ns.ToggleWindow() end
    local frame, rows, tabs = ns.ListWindow()
    if not frame:IsShown() then frame:Show() end

    local function shownRows()
        local out = {}
        for _, row in ipairs(rows) do if row.shown then out[row.name.text] = row end end
        return out
    end
    tabs.all.scripts.OnClick(tabs.all)
    local all = shownRows()
    ok(all["Badlead-Whitemane"] and all["<Bad Guild>"] and all["Grief-Whitemane"], "player, guild and community rows")
    ok(all["Badlead-Whitemane"].remove.shown, "your flags can be removed")
    ok(not all["Grief-Whitemane"].remove.shown, "community reports can't")

    all["Badlead-Whitemane"].remove.scripts.OnClick(all["Badlead-Whitemane"].remove)
    eq(ns.db.players["badlead-whitemane"], nil, "remove works from the All tab")
    all = shownRows()
    ok(all["<Bad Guild>"] and all["Grief-Whitemane"] and not all["Badlead-Whitemane"], "row gone after removing")

    tabs.players.scripts.OnClick(tabs.players)
    eq(next(shownRows()), nil, "players tab is empty now")
    tabs.guilds.scripts.OnClick(tabs.guilds)
    ok(shownRows()["<Bad Guild>"], "guilds tab still has the guild")
end)

test("your reasons show in the list unless you turn them off", function()
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "manual", reason = "left after the summon", source = "you" }, true)
    if not ns.ListWindow() then ns.ToggleWindow() end
    local frame, rows, tabs = ns.ListWindow()
    if not frame:IsShown() then frame:Show() end
    tabs.players.scripts.OnClick(tabs.players)
    ok(rows[1].what.text:find("left after the summon", 1, true), "reason shown")
    rows[1].scripts.OnEnter(rows[1])
    ok(table.concat(M.tooltip, "\n"):find("left after the summon", 1, true), "full reason on hover")
    ns.Slash("set reasons off")
    ok(not rows[1].what.text:find("left after the summon", 1, true), "hidden when turned off")
    ns.Slash("check Badlead")
    ok(table.concat(M.chat, "\n"):find("Your reason: left after the summon", 1, true), "check shows it")
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

test("dungeon finder groups share over INSTANCE_CHAT", function()
    joinBadGroup()
    M.instance = true
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", source = "you" }, true)
    M.Advance(5)
    eq(#M.sent, 2, "messages sent")
    eq(M.sent[2].chatType, "INSTANCE_CHAT", "group scope")
end)

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

local function hear(text, channel, sender)
    M.Fire("CHAT_MSG_ADDON", "SUMUNION", text, channel or "CHANNEL", sender)
end
local function flagMsg(daysAgo, count)
    return ns.EncodeFlag("P", "badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick",
        when = time() - (daysAgo or 0) * 86400, times = count })
end
local function relayMsg(reporter, daysAgo, count, target)
    return ("1~R~P~%s~~0~%d~kick~%d~%s"):format(target or "Badlead-Whitemane", ns.Today() - (daysAgo or 0), count or 1, reporter)
end

test("warnings say how many times and by how many members", function()
    hear(flagMsg(0, 3), "CHANNEL", "Stranger-Faerlina")
    hear(flagMsg(0, 1), "CHANNEL", "Other-Mankrik")
    M.Fire("PARTY_INVITE_REQUEST", "Badlead")
    ok(M.alerts[1]:find("flagged 4 times by 2 union members", 1, true), "alert: " .. tostring(M.alerts[1]))
    ns.NoteGrouped("badlead-whitemane")
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", source = "you" }, true)
    local text = ns.Describe(ns.Status("badlead-whitemane"))
    ok(text:find("flagged 5 times by 3 union members, including you", 1, true), text)
    ok(text:find("you flagged them on", 1, true), text)
end)

test("one person's count is capped and flags without a count count once", function()
    hear(flagMsg(0, 99), "CHANNEL", "Stranger-Faerlina")
    hear("1~F~P~Badlead-Whitemane~~2~" .. ns.Today() .. "~kick", "CHANNEL", "Old-Mankrik")
    local n, _, _, total = ns.Community("players", "badlead-whitemane")
    eq(n, 2, "members")
    eq(total, ns.LIMITS.countCap + 1, "total")
end)

test("relayed reports count, but one relayer only counts once toward the threshold", function()
    hear(relayMsg("Ann-Faerlina"), "GUILD", "Relayer-Whitemane")
    hear(relayMsg("Bob-Faerlina"), "GUILD", "Relayer-Whitemane")
    local s = ns.Status("badlead-whitemane")
    eq(s.cPlayer, 2, "both stored")
    eq(s.cPlayerRelayed, 2, "both relayed")
    eq(s.flagged, false, "one relayer is one source, even over guild chat")
    hear(flagMsg(0), "CHANNEL", "Carl-Mankrik")
    s = ns.Status("badlead-whitemane")
    eq(s.flagged, true, "a second source makes it show")
    ok(ns.Describe(s):find("flagged 3 times by 3 union members", 1, true), ns.Describe(s))
    ns.Slash("distrust Relayer-Whitemane")
    eq(ns.Status("badlead-whitemane").cPlayer, 1, "distrusting the relayer drops what they passed on")
end)

test("a relayer can only pass on a few reports about one target", function()
    for i = 1, 6 do hear(relayMsg("Fake" .. string.char(96 + i) .. "-Faerlina"), "GUILD", "Liar-Whitemane") end
    eq(ns.Status("badlead-whitemane").cPlayer, ns.LIMITS.relaysPerTarget, "capped")
end)

test("relays can be switched off", function()
    ns.Slash("set relays off")
    hear(relayMsg("Ann-Faerlina"), "GUILD", "Relayer-Whitemane")
    eq(ns.Status("badlead-whitemane").cPlayer, 0, "ignored")
end)

test("a first hand report beats relayed news about it", function()
    hear(flagMsg(1, 1), "GUILD", "Ann-Faerlina")
    hear(relayMsg("Ann-Faerlina", 0, 5), "GUILD", "Relayer-Whitemane")
    local r = ns.db.community.players["badlead-whitemane"]["ann-faerlina"]
    eq(r.rl, nil, "still first hand")
    eq(r.c, 1, "count untouched")
    hear("1~B~Y~P~Badlead-Whitemane~ann-faerlina~" .. ns.Today(), "GUILD", "Relayer-Whitemane")
    ok(ns.db.community.players["badlead-whitemane"], "a relayed retraction can't remove a first hand report")
end)

test("retractions stick, so relays can't bring a report back", function()
    hear(flagMsg(2), "GUILD", "Ann-Faerlina")
    hear(ns.EncodeRetract("P", "badlead-whitemane", { name = "Badlead-Whitemane" }), "GUILD", "Ann-Faerlina")
    eq(ns.Status("badlead-whitemane").cPlayer, 0, "retracted")
    hear(relayMsg("Ann-Faerlina", 2), "GUILD", "Relayer-Whitemane")
    eq(ns.Status("badlead-whitemane").cPlayer, 0, "stale relay ignored")
    hear(flagMsg(0), "GUILD", "Ann-Faerlina")
    eq(ns.Status("badlead-whitemane").cPlayer, 1, "a new first hand report still counts")
    hear(relayMsg("Bob-Faerlina", 1), "GUILD", "Relayer-Whitemane")
    eq(ns.Status("badlead-whitemane").cPlayer, 2, "relayed copy stored")
    hear("1~B~Y~P~Badlead-Whitemane~bob-faerlina~" .. ns.Today(), "GUILD", "Other-Whitemane")
    eq(ns.Status("badlead-whitemane").cPlayer, 2, "someone else can't withdraw it")
    hear("1~B~Y~P~Badlead-Whitemane~bob-faerlina~" .. ns.Today(), "GUILD", "Relayer-Whitemane")
    eq(ns.Status("badlead-whitemane").cPlayer, 1, "whoever passed it on can")
end)

test("someone filing lots of reports in a day gets ignored", function()
    for i = 1, ns.LIMITS.dailyReports + 1 do
        local target = "Victim" .. string.char(96 + i) .. "-Whitemane"
        hear(ns.EncodeFlag("P", target:lower(), { name = target, kind = "kick" }), "GUILD", "Spammer-Whitemane")
    end
    eq(ns.db.distrust["spammer-whitemane"], "auto", "auto distrusted")
    ok(table.concat(M.chat, "\n"):find("Ignoring reports from Spammer-Whitemane", 1, true), "tells you")
    eq(ns.Status("victima-whitemane").cPlayer, 0, "their earlier reports stop counting too")
    ns.Slash("trust Spammer-Whitemane")
    eq(ns.Status("victima-whitemane").cPlayer, 1, "trusting them again restores them")
    hear(ns.EncodeFlag("P", "newvictim-whitemane", { name = "Newvictim-Whitemane", kind = "kick" }), "GUILD", "Spammer-Whitemane")
    eq(ns.Status("newvictim-whitemane").cPlayer, 1, "and their daily count starts over")
end)

test("flags on people you haven't grouped with stay private", function()
    ns.Slash("flag Stranger-Mankrik rude")
    local r = ns.db.players["stranger-mankrik"]
    eq(r.private, true, "private")
    ok(M.chat[#M.chat]:find("Only you will see it", 1, true), "says so")
    M.Advance(5)
    eq(#M.sent, 0, "nothing broadcast")
    eq(#ns.SyncMessages(0), 0, "not in sync answers either")
    eq(ns.Status("stranger-mankrik").flagged, true, "still warns you")
    ns.NoteGrouped("stranger-mankrik")
    ns.Slash("flag Stranger-Mankrik rude again")
    eq(ns.db.players["stranger-mankrik"].private, nil, "shared once you've grouped")
    M.Advance(5)
    eq(#M.sent, 1, "broadcast to guild")
end)

test("grouping with someone is remembered for a week", function()
    joinBadGroup()
    ok(ns.GroupedRecently("badlead-whitemane"), "leader")
    ok(ns.GroupedRecently("greedy raiders@whitemane", true), "their guild")
    M.SetGroup(nil)
    M.Advance(8 * 86400)
    eq(ns.GroupedRecently("badlead-whitemane"), false, "forgotten after a week")
end)

test("sync answers pack everything we know into a few messages", function()
    ns.NoteGrouped("badlead-whitemane")
    ns.FlagPlayer("badlead-whitemane", { name = "Badlead-Whitemane", kind = "kick", source = "you" }, true)
    ns.NoteGrouped("gone-whitemane")
    ns.FlagPlayer("gone-whitemane", { name = "Gone-Whitemane", kind = "kick", source = "you" }, true)
    ns.UnflagPlayer("gone-whitemane")
    for i = 1, 8 do hear(ns.EncodeFlag("P", ("target%d-mankrik"):format(i), { name = ("Target%d-Mankrik"):format(i), kind = "kick" }), "CHANNEL", "Ann-Faerlina") end
    hear(flagMsg(0), "CHANNEL", "Asker-Whitemane")
    M.Advance(10)
    M.sent = {}
    local msgs = ns.SyncMessages(0, nil, "asker-whitemane")
    local types, reporters = {}, {}
    for _, text in ipairs(msgs) do
        ok(#text <= 255, "fits in one addon message")
        for _, m in ipairs(ns.DecodeMessages(text)) do
            types[m.type] = (types[m.type] or 0) + 1
            if m.reporter then reporters[m.reporter] = true end
        end
    end
    eq(types.F, 1, "your shared flag")
    eq(types.X, 1, "your retraction")
    eq(types.R, 8, "reports you heard from others")
    eq(reporters["asker-whitemane"], nil, "the asker's own reports aren't sent back")
    ok(#msgs < 10, "batched (" .. #msgs .. " messages)")
end)

test("a query isn't answered with what someone else already sent", function()
    hear(flagMsg(0), "GUILD", "Ann-Faerlina")
    M.Advance(10)
    M.sent = {}
    hear(ns.EncodeQuery(0), "GUILD", "Asker-Whitemane")
    hear("1~B~" .. relayMsg("ann-faerlina"):sub(3), "GUILD", "Quick-Whitemane")
    M.Advance(20)
    eq(#M.sent, 0, "nothing left to add")
end)

test("no answers on a scope you don't share with", function()
    hear(flagMsg(0), "GUILD", "Ann-Faerlina")
    ns.Slash("share guild off")
    M.Advance(10)
    M.sent = {}
    hear(ns.EncodeQuery(0), "GUILD", "Asker-Whitemane")
    M.Advance(20)
    eq(#M.sent, 0, "stayed quiet")
end)

test("joining a group asks it for its lists", function()
    joinBadGroup()
    M.Advance(10)
    local asked = false
    for _, m in ipairs(M.sent) do
        local d = ns.DecodeMessage(m.text)
        if d and d.type == "Q" and m.chatType == "PARTY" then asked = true end
    end
    ok(asked, "query sent to the party")
end)

test("pruning keeps the report store bounded", function()
    local old = ns.LIMITS.total
    ns.LIMITS.total = 3
    hear(flagMsg(5), "GUILD", "Ann-Faerlina")
    hear(flagMsg(1), "GUILD", "Bob-Faerlina")
    hear(relayMsg("Cat-Faerlina", 0), "GUILD", "Relayer-Whitemane")
    hear(relayMsg("Dan-Faerlina", 0), "GUILD", "Relayer-Whitemane")
    ns.Prune()
    ns.LIMITS.total = old
    local reports = ns.db.community.players["badlead-whitemane"]
    local n = 0
    for _ in pairs(reports) do n = n + 1 end
    eq(n, 3, "capped")
    ok(reports["ann-faerlina"] and reports["bob-faerlina"], "first hand reports kept over relayed ones")
    eq(ns.db.relayCounts["relayer-whitemane"], 1, "relay counts recounted")
end)

local function sentRecords(kind)
    local out = {}
    for _, s in ipairs(M.sent) do
        for _, m in ipairs(ns.DecodeMessages(s.text) or {}) do
            if not kind or m.type == kind then out[#out + 1] = { chatType = s.chatType, m = m } end
        end
    end
    return out
end
local function onScope(list, chatType)
    local n = 0
    for _, x in ipairs(list) do if x.chatType == chatType then n = n + 1 end end
    return n
end

test("a new report is passed on to your other channels within seconds", function()
    joinBadGroup()
    ns.Slash("share channel on")
    M.Advance(10)
    M.sent = {}
    hear(flagMsg(0, 2), "GUILD", "Ann-Faerlina")
    M.Advance(12)
    local relays = sentRecords("R")
    eq(onScope(relays, "PARTY"), 1, "to the group")
    eq(onScope(relays, "CHANNEL"), 1, "to the union channel")
    eq(onScope(relays, "GUILD"), 0, "not back where it came from")
    eq(relays[1].m.reporter, "ann-faerlina", "keeps the original reporter")
    eq(relays[1].m.count, 2, "and their count")
    M.sent = {}
    hear(flagMsg(0, 2), "GUILD", "Ann-Faerlina")
    M.Advance(12)
    eq(#sentRecords("R"), 0, "only passed on the first time")
end)

test("reports aren't passed on where someone else already did", function()
    joinBadGroup()
    M.Advance(10)
    M.sent = {}
    hear(flagMsg(0), "GUILD", "Ann-Faerlina")
    hear(relayMsg("ann-faerlina"), "PARTY", "Quick-Whitemane")
    M.Advance(12)
    eq(#sentRecords("R"), 0, "nothing left to pass on")
end)

test("retractions are passed on too", function()
    joinBadGroup()
    hear(flagMsg(1), "GUILD", "Ann-Faerlina")
    M.Advance(20)
    M.sent = {}
    hear(ns.EncodeRetract("P", "badlead-whitemane", { name = "Badlead-Whitemane" }), "GUILD", "Ann-Faerlina")
    M.Advance(12)
    local y = sentRecords("Y")
    eq(#y, 1, "retraction passed on")
    eq(y[1].chatType, "PARTY", "to the group")
    eq(y[1].m.reporter, "ann-faerlina", "for the right reporter")
end)

test("passing on can be switched off and is rate limited", function()
    joinBadGroup()
    M.Advance(10)
    ns.Slash("set forward off")
    M.sent = {}
    hear(flagMsg(0), "GUILD", "Ann-Faerlina")
    M.Advance(12)
    eq(#sentRecords("R"), 0, "off")
    ns.Slash("set forward on")
    local old = ns.LIMITS.forwardPerMinute
    ns.LIMITS.forwardPerMinute = 2
    for i = 1, 4 do hear(flagMsg(0), "GUILD", ("Rep%s-Faerlina"):format(string.char(96 + i))) end
    M.Advance(12)
    ns.LIMITS.forwardPerMinute = old
    eq(#sentRecords("R"), 2, "capped per minute, the rest waits for the next sync")
end)

test("passed-on reports count as whoever passed them on, even under real people's names", function()
    hear(ns.EncodeQuery(0), "CHANNEL", "Ann-Faerlina")
    hear(ns.EncodeQuery(0), "CHANNEL", "Bob-Faerlina")
    hear(relayMsg("ann-faerlina"), "GUILD", "Liar-Whitemane")
    hear(relayMsg("bob-faerlina"), "GUILD", "Liar-Whitemane")
    hear(relayMsg("carl-faerlina"), "GUILD", "Liar-Whitemane")
    local s = ns.Status("badlead-whitemane")
    eq(s.cPlayer, 3, "all three stored")
    eq(s.flagged, false, "one person passing them on is one source, even with names we've heard from")
    hear(relayMsg("dana-faerlina"), "GUILD", "Relayer-Whitemane")
    eq(ns.Status("badlead-whitemane").flagged, true, "a second person passing one on makes two")
end)

test("anyone sending too many messages in a minute gets ignored", function()
    for i = 1, ns.LIMITS.floodPerMinute do hear(ns.EncodeQuery(0), "CHANNEL", "Flooder-Faerlina") end
    eq(ns.db.distrust["flooder-faerlina"], nil, "up to the limit is fine")
    hear(ns.EncodeQuery(0), "CHANNEL", "Flooder-Faerlina")
    eq(ns.db.distrust["flooder-faerlina"], "auto", "one more and they're ignored")
    ok(M.chat[#M.chat]:find("more than 60 messages in a minute", 1, true), "says why")
    hear(flagMsg(0), "CHANNEL", "Flooder-Faerlina")
    eq(ns.db.community.players["badlead-whitemane"], nil, "nothing from them counts after that")
    hear(flagMsg(0), "CHANNEL", "Honest-Faerlina")
    ok(ns.db.community.players["badlead-whitemane"]["honest-faerlina"], "other people are fine")
    M.Advance(61)
    for i = 1, 30 do hear(ns.EncodeQuery(0), "CHANNEL", "Busy-Faerlina") end
    M.Advance(61)
    for i = 1, 30 do hear(ns.EncodeQuery(0), "CHANNEL", "Busy-Faerlina") end
    eq(ns.db.distrust["busy-faerlina"], nil, "the count starts over every minute")
end)

test("strangers need more reporters than people you know", function()
    ns.db.settings.strangerThreshold = 4
    for i = 1, 3 do hear(flagMsg(0), "CHANNEL", ("Alt%s-Faerlina"):format(string.char(96 + i))) end
    eq(ns.Status("badlead-whitemane").flagged, false, "three strangers on the channel aren't enough")
    hear(flagMsg(0), "CHANNEL", "Altd-Faerlina")
    eq(ns.Status("badlead-whitemane").flagged, true, "four are")
    ns.Slash("set strangers off")
    eq(ns.db.settings.countStrangers, false, "/su set strangers off")
    eq(ns.Status("badlead-whitemane").flagged, false, "strangers turned off don't count at all")
    eq(ns.Status("badlead-whitemane").cPlayer, 4, "their reports are still kept")
    ns.Slash("set strangers on")
    eq(ns.Status("badlead-whitemane").flagged, true, "and count again when turned back on")
end)

test("two people you know are enough", function()
    ns.db.settings.strangerThreshold = 4
    ns.db.settings.trustGuildmates = false
    ns.NoteGrouped("friend-faerlina")
    hear(flagMsg(0), "CHANNEL", "Friend-Faerlina")
    hear(flagMsg(0), "CHANNEL", "Stranger-Faerlina")
    eq(ns.Status("badlead-whitemane").flagged, false, "one person you know and one stranger isn't enough")
    hear(flagMsg(0), "GUILD", "Guildie-Whitemane")
    eq(ns.Status("badlead-whitemane").flagged, true, "a second person you know is")
    ns.Slash("set strangers off")
    eq(ns.Status("badlead-whitemane").flagged, true, "people you know still count with strangers off")
    ns.Slash("set strangers 3")
    eq(ns.db.settings.strangerThreshold, 3, "/su set strangers <n> still sets the number")
    local controls = ns.OptionControls()
    ok(controls.strangerThreshold and controls.countStrangers, "both are in the options")
end)

test("purge clears other people's reports and keeps your own flags", function()
    ns.FlagPlayer("mine-whitemane", { name = "Mine-Whitemane", kind = "kick", source = "you" }, true)
    hear(flagMsg(0), "CHANNEL", "Chan-Faerlina")
    hear(flagMsg(0), "GUILD", "Guildie-Whitemane")
    hear(relayMsg("Ann-Faerlina"), "GUILD", "Relayer-Whitemane")
    local reports = ns.db.community.players["badlead-whitemane"]
    ok(reports["chan-faerlina"].at, "arrival time kept")
    eq(reports["ann-faerlina"].ch, "GUILD", "arrival channel kept for passed-on reports")

    ns.Slash("purge channel")
    eq(reports["chan-faerlina"], nil, "the channel report is gone")
    ok(reports["guildie-whitemane"] and reports["ann-faerlina"], "the rest stay")
    ns.Slash("purge relays")
    eq(reports["ann-faerlina"], nil, "the passed-on report is gone")
    ok(reports["guildie-whitemane"], "the first hand guild report stays")
    reports["guildie-whitemane"].at = time() - 7200
    ns.Slash("purge since 1")
    ok(reports["guildie-whitemane"], "anything older than the hour stays")
    ns.db.retracted[ns.RecordId("P", "x-whitemane", "someone-whitemane")] = ns.Today()
    ns.db.retracted[ns.RecordId("P", "y-whitemane", ns.playerKey)] = ns.Today()
    ns.Slash("purge all")
    eq(ns.db.community.players["badlead-whitemane"], nil, "everything from others is gone")
    ok(ns.db.players["mine-whitemane"], "your own flag is untouched")
    eq(ns.db.reporterCounts["guildie-whitemane"] or 0, 0, "counts kept in step")
    eq(ns.db.retracted[ns.RecordId("P", "x-whitemane", "someone-whitemane")], nil, "other people's withdrawals cleared")
    ok(ns.db.retracted[ns.RecordId("P", "y-whitemane", ns.playerKey)], "your own withdrawals kept")
    ns.Slash("purge")
    ok(M.chat[#M.chat]:find("Usage: /su purge", 1, true), "usage without a scope")
end)

test("the clear community reports button asks first", function()
    local _, panel = ns.OptionControls()
    hear(flagMsg(0), "GUILD", "Guildie-Whitemane")
    panel.purgeButton.scripts.OnClick(panel.purgeButton)
    eq(M.popups[#M.popups].which, "SUMMONERSUNION_PURGE", "asks first")
    ok(ns.db.community.players["badlead-whitemane"], "nothing cleared yet")
    StaticPopupDialogs.SUMMONERSUNION_PURGE.OnAccept()
    eq(ns.db.community.players["badlead-whitemane"], nil, "cleared")
end)

test("a forged report in your name gets withdrawn", function()
    M.Advance(10)
    M.sent = {}
    hear(relayMsg("mylock-whitemane"), "GUILD", "Liar-Whitemane")
    M.Advance(3)
    local x = sentRecords("X")
    eq(#x, 1, "withdrawal sent")
    eq(x[1].chatType, "GUILD", "where the forgery showed up")
    eq(ns.Status("badlead-whitemane").cPlayer, 0, "not stored")
    ok(ns.db.retracted[ns.RecordId("P", "badlead-whitemane", "mylock-whitemane")], "kept so syncs carry it")
    ns.NoteGrouped("realone-whitemane")
    ns.FlagPlayer("realone-whitemane", { name = "Realone-Whitemane", kind = "kick", source = "you" }, true)
    M.Advance(10)
    M.sent = {}
    hear(relayMsg("mylock-whitemane", 0, 1, "Realone-Whitemane"), "GUILD", "Friend-Whitemane")
    M.Advance(3)
    eq(#sentRecords("X"), 0, "nothing withdrawn")
end)

test("you're asked once to join the union channel, and it stays opt-in", function()
    eq(ns.db.settings.shareChannel, false, "off by default")
    ns.SuggestChannel()
    eq(#M.popups, 1, "asked")
    eq(M.popups[1].which, "SUMMONERSUNION_CHANNEL", "the channel prompt")
    ns.SuggestChannel()
    eq(#M.popups, 1, "only once")
    eq(ns.db.settings.shareChannel, false, "nothing joined without a click")
    StaticPopupDialogs.SUMMONERSUNION_CHANNEL.OnAccept()
    eq(ns.db.settings.shareChannel, true, "joined after clicking")
    eq(M.channels.SummonersUnion, 5, "in the channel")
    ok(M.chat[#M.chat]:find("every union member on your realm", 1, true), "says what it does")
    ns.ResetSettings()
    ns.SuggestChannel()
    eq(#M.popups, 1, "resetting the options doesn't ask again")
end)

test("people already in the channel aren't asked", function()
    ns.db.settings.shareChannel = true
    ns.SuggestChannel()
    eq(#M.popups, 0, "not asked")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
