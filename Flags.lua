-- flags: your flags, community reports, warnings and the flag/unflag commands
local _, ns = ...

ns.REASONS = {
    kick = "summon-kicked",
    disband = "disbanded after summons",
    manual = "flagged by hand",
}

local function upsert(store, key, rec)
    local old = store[key]
    if old then
        old.times = (old.times or 1) + 1
        old.when = rec.when or time()
        old.summons = (old.summons or 0) + (rec.summons or 0)
        for _, f in ipairs({ "name", "guild", "guildKey", "zone", "kind", "reason", "note", "source", "class" }) do
            if rec[f] ~= nil and rec[f] ~= "" then old[f] = rec[f] end
        end
        old.private = (old.private and rec.private) or nil -- once shared, stays shared
        return old
    end
    rec.times = 1
    rec.when = rec.when or time()
    store[key] = rec
    return rec
end

-- who we've actually been in a group with, so flags can't be shared about random people
function ns.NoteGrouped(key, guildKey)
    local now = time()
    if key then ns.db.seen[key] = now end
    if guildKey then ns.db.seenGuilds[guildKey] = now end
end

function ns.GroupedRecently(key, isGuild)
    local t = key and (isGuild and ns.db.seenGuilds or ns.db.seen)[key]
    return t ~= nil and time() - t <= ns.LIMITS.groupedDays * 86400
end

local PRIVATE_NOTE = " Only you will see it: you haven't been in a group with %s in the last %d days, so it isn't shared."

function ns.FlagPlayer(key, rec, quiet)
    if not key then return end
    if rec.source == "you" then
        rec.private = not ns.GroupedRecently(key) or nil
        rec.class = rec.class or ns.playerClass
    end
    local r = upsert(ns.db.players, key, rec)
    ns.Fire("FLAGS_CHANGED")
    if rec.source == "you" then ns.Fire("FLAG_ADDED", "P", key, r) end
    if not quiet then
        local msg = ("Flagged %s%s."):format(r.name or key, r.guild and (" <" .. r.guild .. ">") or "")
        if r.private then msg = msg .. PRIVATE_NOTE:format("them", ns.LIMITS.groupedDays) end
        ns.Print(msg)
    end
    return r
end

function ns.FlagGuild(key, rec, quiet)
    if not key then return end
    if rec.source == "you" then
        rec.private = not ns.GroupedRecently(key, true) or nil
        rec.class = rec.class or ns.playerClass
    end
    local r = upsert(ns.db.guilds, key, rec)
    ns.Fire("FLAGS_CHANGED")
    if rec.source == "you" then ns.Fire("FLAG_ADDED", "G", key, r) end
    if not quiet then
        local msg = ("Flagged guild <%s>."):format(r.name or key)
        if r.private then msg = msg .. PRIVATE_NOTE:format("a member", ns.LIMITS.groupedDays) end
        ns.Print(msg)
    end
    return r
end

local function unflag(store, kind, key)
    local old = key and store[key]
    if not old then return false end
    store[key] = nil
    ns.Fire("FLAGS_CHANGED")
    if old.source == "you" then ns.Fire("FLAG_REMOVED", kind, key, old) end
    return true
end
function ns.UnflagPlayer(key) return unflag(ns.db.players, "P", key) end
function ns.UnflagGuild(key) return unflag(ns.db.guilds, "G", key) end

-- reports older than communityExpiryDays don't count (0 = never expire)
function ns.ReportExpired(day)
    local days = ns.db.settings.communityExpiryDays or 0
    return days > 0 and (tonumber(day) or 0) < ns.Today() - days
end

function ns.ReportUsable(reporter, r)
    local db = ns.db
    if db.distrust[reporter] or ns.ReportExpired(r.d) then return false end
    if r.rl and (not db.settings.acceptRelays or db.distrust[r.rl]) then return false end
    return true
end

-- returns: members who reported it, whether that's enough to warn, newest report,
-- total grievances, and how many of the reports were relayed.
-- the threshold counts sources, not reports. a passed-on report only counts as its own
-- source if the reporter has messaged us directly at some point (so they're a real user),
-- otherwise everything one person passes on counts once. making up names doesn't help
function ns.Community(bucket, key)
    local reports = key and ns.db.community[bucket][key]
    local n, total, relayed, trusted, latest = 0, 0, 0, false, nil
    local sources, nSources = {}, 0
    if reports then
        local cap = ns.LIMITS.countCap
        for reporter, r in pairs(reports) do
            if ns.ReportUsable(reporter, r) then
                n = n + 1
                total = total + math.min(r.c or 1, cap)
                if r.rl then relayed = relayed + 1 end
                local src = (r.rl and not ns.db.known[reporter]) and r.rl or reporter
                if not sources[src] then sources[src], nSources = true, nSources + 1 end
                if r.via == "GUILD" and not r.rl and ns.db.settings.trustGuildmates then trusted = true end
                if not latest or (r.d or 0) > (latest.d or 0) then latest = r end
            end
        end
    end
    local shown = n > 0 and (nSources >= ns.db.settings.communityThreshold or trusted)
    return n, shown, latest, total, relayed
end

function ns.Status(playerKey, guildKey)
    local s = {}
    if playerKey then
        s.player = ns.db.players[playerKey]
        s.cPlayer, s.cPlayerShown, s.cPlayerLatest, s.cPlayerTotal, s.cPlayerRelayed = ns.Community("players", playerKey)
        if not guildKey then
            -- no guild info before you're grouped (invites), use the last one we saw
            guildKey = (s.player and s.player.guildKey) or (s.cPlayerLatest and s.cPlayerLatest.g) or nil
        end
    end
    if guildKey then
        s.guildKey = guildKey
        s.guild = ns.db.guilds[guildKey]
        s.cGuild, s.cGuildShown, s.cGuildLatest, s.cGuildTotal = ns.Community("guilds", guildKey)
    end
    s.flagged = (s.player or s.guild or s.cPlayerShown or s.cGuildShown) and true or false
    return s
end

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end
ns.Plural = plural

function ns.ClassName(token)
    local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] or token
    return tostring(name or "?"):lower()
end

-- who's behind the reports on someone, "2 warlocks, 1 priest", warlocks first
function ns.ReporterClasses(bucket, key)
    local counts, order = {}, {}
    for reporter, r in pairs(key and ns.db.community[bucket][key] or {}) do
        if r.cl and ns.ReportUsable(reporter, r) then
            if not counts[r.cl] then counts[r.cl], order[#order + 1] = 0, r.cl end
            counts[r.cl] = counts[r.cl] + 1
        end
    end
    if #order == 0 then return nil end
    table.sort(order, function(a, b)
        if (a == "WARLOCK") ~= (b == "WARLOCK") then return a == "WARLOCK" end
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end
        return a < b
    end)
    local parts = {}
    for i, cl in ipairs(order) do parts[i] = plural(counts[cl], ns.ClassName(cl)) end
    return table.concat(parts, ", ")
end

-- "flagged 6 times by 4 union members, including you"
local function tally(total, members, mine)
    local by = plural(members, "union member") .. (mine and ", including you" or "")
    if mine and members == 1 then by = "you" end
    return ("flagged %s by %s"):format(plural(total, "time"), by)
end

local function yours(p)
    local times = p.times or 1
    return ("you flagged them %s (%s%s)"):format(
        times > 1 and (times .. " times, last on " .. ns.TimeText(p.when)) or ("on " .. ns.TimeText(p.when)),
        ns.REASONS[p.kind] or p.kind or "flagged", (p.summons or 0) > 0 and (", " .. p.summons .. " summons") or "")
end

function ns.Describe(s)
    local parts, cap = {}, ns.LIMITS.countCap
    local p, g = s.player, s.guild
    if s.cPlayerShown then
        local total, members = s.cPlayerTotal or s.cPlayer, s.cPlayer
        if p then total, members = total + math.min(p.times or 1, cap), members + 1 end
        parts[#parts + 1] = tally(total, members, p ~= nil)
    end
    if p then parts[#parts + 1] = yours(p) end
    if g or s.cGuildShown then
        local total, members = 0, 0
        if s.cGuildShown then total, members = s.cGuildTotal or s.cGuild, s.cGuild end
        if g then total, members = total + math.min(g.times or 1, cap), members + 1 end
        local name = (g and g.name) or (s.cGuildLatest and s.cGuildLatest.n) or s.guildKey
        parts[#parts + 1] = ("their guild <%s> has been %s"):format(name, tally(total, members, g ~= nil))
    end
    return table.concat(parts, "; ")
end

function ns.Alert(msg)
    ns.Print("|cffff5050" .. msg .. "|r")
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
        RaidNotice_AddMessage(RaidWarningFrame, "Summoners Union: " .. msg, ChatTypeInfo.RAID_WARNING)
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

-- warnings
ns.On("PARTY_INVITE_REQUEST", function(inviter)
    if not ns.db.settings.warnOnInvite or not inviter or ns.IsSecret(inviter) then return end
    local key, display = ns.PlayerKey(inviter)
    local s = ns.Status(key)
    if not s.flagged then return end
    ns.Alert(("%s invited you to a group: %s."):format(display, ns.Describe(s)))
    if ns.db.settings.autoDecline then
        DeclineGroup()
        if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
        ns.Print("Invite declined automatically (/su set autodecline off to stop this).")
    end
end)

local warnedPlayers, warnedGuilds = {}, {}
local function scanGroup()
    if not IsInGroup() then
        warnedPlayers, warnedGuilds = {}, {}
        return
    end
    if not ns.db.settings.warnInGroup then return end
    for _, unit in ipairs(ns.GroupUnits()) do
        local key, display = ns.UnitKey(unit)
        if key and key ~= ns.playerKey and not warnedPlayers[key] then
            local gkey = ns.UnitGuild(unit)
            local s = ns.Status(key, gkey)
            local personal = s.player or s.cPlayerShown
            local guildOnly = not personal and (s.guild or s.cGuildShown)
            if personal or (guildOnly and not warnedGuilds[gkey]) then
                warnedPlayers[key] = true
                if gkey then warnedGuilds[gkey] = true end
                local lead = UnitIsGroupLeader(unit) and " (group leader)" or ""
                ns.Alert(("%s%s is in your group: %s."):format(display, lead, ns.Describe(s)))
            end
        end
    end
end
ns.On("GROUP_ROSTER_UPDATE", scanGroup)
ns.OnReady(scanGroup)

-- aging
-- clears out expired reports, and your own old flags if flagExpiryDays is set.
-- only runs at login so changing the setting never deletes anything mid-session.
-- forgotten flags aren't retracted, other people's copies expire on their own
function ns.Prune()
    local db = ns.db
    local reportsRemoved, flagsRemoved = 0, 0
    local kept = {}
    for _, bucket in ipairs({ "players", "guilds" }) do
        local all = db.community[bucket]
        for key, reports in pairs(all) do
            for reporter, r in pairs(reports) do
                if ns.ReportExpired(r.d) then
                    reports[reporter] = nil
                    reportsRemoved = reportsRemoved + 1
                else
                    kept[#kept + 1] = { all, key, reporter, r }
                end
            end
            if next(reports) == nil then all[key] = nil end
        end
    end
    -- over the total cap: drop relayed reports first, oldest first
    if #kept > ns.LIMITS.total then
        table.sort(kept, function(a, b)
            if (a[4].rl ~= nil) ~= (b[4].rl ~= nil) then return a[4].rl ~= nil end
            return (a[4].d or 0) < (b[4].d or 0)
        end)
        while #kept > ns.LIMITS.total do
            local k = table.remove(kept, 1)
            k[1][k[2]][k[3]] = nil
            if next(k[1][k[2]]) == nil then k[1][k[2]] = nil end
            reportsRemoved = reportsRemoved + 1
        end
    end
    -- recount from scratch so the caps can't drift
    local counts, relays = {}, {}
    for _, k in ipairs(kept) do
        counts[k[3]] = (counts[k[3]] or 0) + 1
        if k[4].rl then relays[k[4].rl] = (relays[k[4].rl] or 0) + 1 end
    end
    db.reporterCounts, db.relayCounts = counts, relays

    for id, day in pairs(db.retracted) do
        if ns.ReportExpired(day) then db.retracted[id] = nil end
    end
    local today = ns.Today()
    for k in pairs(db.filed) do
        local day = tonumber(k:match("|(%d+)$"))
        if not day or day < today - 1 then db.filed[k] = nil end
    end
    local cutoff = time() - ns.LIMITS.seenDays * 86400
    for _, seen in ipairs({ db.seen, db.seenGuilds }) do
        for k, t in pairs(seen) do
            if t < cutoff then seen[k] = nil end
        end
    end
    cutoff = time() - ns.LIMITS.knownDays * 86400
    for k, t in pairs(db.known) do
        if t < cutoff then db.known[k] = nil end
    end

    local days = db.settings.flagExpiryDays or 0
    if days > 0 then
        local cutoff = time() - days * 86400
        for _, store in ipairs({ db.players, db.guilds }) do
            for key, r in pairs(store) do
                if (r.when or 0) < cutoff then
                    store[key] = nil
                    flagsRemoved = flagsRemoved + 1
                end
            end
        end
        if flagsRemoved > 0 then
            ns.Print(("Forgot %d flag(s) older than %d days (/su set flagexpiry 0 keeps them forever)."):format(flagsRemoved, days))
        end
    end
    if reportsRemoved > 0 or flagsRemoved > 0 then ns.Fire("FLAGS_CHANGED") end
    return reportsRemoved, flagsRemoved
end
ns.OnReady(ns.Prune)

-- commands
-- "/su flag Name-Realm some reason" or a bare "/su flag" for your target.
-- two part names are typed First-Last, same as they come from the target
local function resolvePlayer(rest)
    local name, reason = ns.Trim(rest):match("^(%S+)%s*(.-)$")
    if name then
        local key, display = ns.PlayerKey(name)
        for _, unit in ipairs(ns.GroupUnits()) do
            if ns.UnitKey(unit) == key then
                local gk, gn = ns.UnitGuild(unit)
                return key, display, gk, gn, reason
            end
        end
        if UnitExists("target") and ns.UnitKey("target") == key then
            local gk, gn = ns.UnitGuild("target")
            return key, display, gk, gn, reason
        end
        return key, display, nil, nil, reason
    end
    if UnitExists("target") and UnitIsPlayer("target") then
        local key, display = ns.UnitKey("target")
        local gk, gn = ns.UnitGuild("target")
        return key, display, gk, gn, ""
    end
end

local function resolveGuild(rest)
    rest = ns.Trim(rest)
    if rest ~= "" then
        local g, realm = rest:match("^(.-)@(.+)$")
        return ns.GuildKey(g or rest, realm)
    end
    if UnitExists("target") then return ns.UnitGuild("target") end
end

-- also used by the right-click menu
function ns.FlagByHand(key, display, gk, gn, reason)
    return ns.FlagPlayer(key, {
        name = display, guildKey = gk, guild = gn, kind = "manual", summons = 0, source = "you",
        reason = (reason and reason ~= "" and reason) or nil, zone = GetRealZoneText and GetRealZoneText() or nil,
    })
end

function ns.FlagGuildByHand(gk, gn)
    return ns.FlagGuild(gk, { name = gn, kind = "manual", summons = 0, source = "you" })
end

-- a guild typed without a realm still finds the flag if it's on another realm (targets can
-- be from connected realms). nil plus true if it's on more than one, they need to say which
local function guildOnAnyRealm(key)
    local store = ns.db.guilds
    if store[key] then return key end
    local want, found = key:match("^(.-)@"), nil
    for k in pairs(store) do
        if k:match("^(.-)@") == want then
            if found then return nil, true end
            found = k
        end
    end
    return found
end

function ns.SlashFlag(rest)
    local key, display, gk, gn, reason = resolvePlayer(rest)
    if not key then
        ns.Print("Usage: /su flag <name> [reason], or target the player first. Two part names go as First-Last.")
        return
    end
    ns.FlagByHand(key, display, gk, gn, reason)
end

function ns.SlashFlagGuild(rest)
    local gk, gn = resolveGuild(rest)
    if not gk then
        ns.Print("Usage: /su flagguild <guild name>, or target a member of the guild.")
        return
    end
    ns.FlagGuildByHand(gk, gn)
end

function ns.SlashUnflag(rest)
    local key, display = resolvePlayer(rest)
    if key and ns.UnflagPlayer(key) then
        ns.Print("Removed your flag on " .. display .. ".")
    else
        ns.Print("You haven't flagged that player.")
    end
end

function ns.SlashUnflagGuild(rest)
    local gk, gn = resolveGuild(rest)
    local many
    if gk and not rest:find("@", 1, true) then gk, many = guildOnAnyRealm(gk) end
    local rec = gk and ns.db.guilds[gk]
    if rec and ns.UnflagGuild(gk) then
        ns.Print("Removed your flag on <" .. (rec.name or gn) .. ">.")
    elseif many then
        ns.Print("You flagged that guild name on more than one realm. Add the realm: /su unflagguild Guild@Realm")
    else
        ns.Print("You haven't flagged that guild.")
    end
end

function ns.SlashCheck(rest)
    local key, display, gk = resolvePlayer(rest)
    if not key then
        ns.Print("Usage: /su check <name>, or target the player first.")
        return
    end
    local s = ns.Status(key, gk)
    if s.flagged then
        ns.Print(display .. ": " .. ns.Describe(s) .. ".")
        local classes = ns.ReporterClasses("players", key)
        if classes then ns.Print("  Reported by: " .. classes .. ".") end
        if (s.cPlayerRelayed or 0) > 0 then
            ns.Print(("  %d of the union reports were passed on by other members rather than sent by the reporter."):format(s.cPlayerRelayed))
        end
        if s.player and s.player.private then ns.Print("  Your flag on them is private (you hadn't grouped with them).") end
    elseif (s.cPlayer or 0) > 0 or (s.cGuild or 0) > 0 then
        ns.Print(("%s: %d report(s) on them and %d on their guild, below your threshold of %d."):format(
            display, s.cPlayer or 0, s.cGuild or 0, ns.db.settings.communityThreshold))
    else
        ns.Print(display .. " isn't flagged.")
    end
end

function ns.SlashList()
    local list = {}
    for key, r in pairs(ns.db.players) do list[#list + 1] = { r.when or 0, ("%s%s - %s, %s"):format(r.name or key,
        r.guild and (" <" .. r.guild .. ">") or "", ns.REASONS[r.kind] or r.kind or "", ns.TimeText(r.when)) } end
    for key, r in pairs(ns.db.guilds) do list[#list + 1] = { r.when or 0, ("guild <%s> - %s, %s"):format(r.name or key,
        ns.REASONS[r.kind] or r.kind or "", ns.TimeText(r.when)) } end
    table.sort(list, function(a, b) return a[1] > b[1] end)
    if #list == 0 then
        ns.Print("You haven't flagged anyone yet.")
        return
    end
    ns.Print(("%d flag(s), newest first:"):format(#list))
    for i = 1, math.min(#list, 15) do ns.Print("  " .. list[i][2]) end
    if #list > 15 then ns.Print("  ...open /su for the full list.") end
end

-- imported flags are stored like yours (source "import") but never re-broadcast
function ns.ImportText(text)
    local list, err = ns.ParseExport(text)
    if not list then return false, err end
    local res = { players = 0, guilds = 0, skipped = 0 }
    for _, e in ipairs(list) do
        local store = e.kind == "P" and ns.db.players or ns.db.guilds
        if store[e.key] then
            res.skipped = res.skipped + 1
        else
            e.rec.source, e.rec.times = "import", 1
            store[e.key] = e.rec
            if e.kind == "P" then res.players = res.players + 1 else res.guilds = res.guilds + 1 end
        end
    end
    ns.Fire("FLAGS_CHANGED")
    return true, res
end
