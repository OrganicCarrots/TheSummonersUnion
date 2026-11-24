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
        for _, f in ipairs({ "name", "guild", "guildKey", "zone", "kind", "reason", "note", "source" }) do
            if rec[f] ~= nil and rec[f] ~= "" then old[f] = rec[f] end
        end
        return old
    end
    rec.times = 1
    rec.when = rec.when or time()
    store[key] = rec
    return rec
end

function ns.FlagPlayer(key, rec, quiet)
    if not key then return end
    local r = upsert(ns.db.players, key, rec)
    ns.Fire("FLAGS_CHANGED")
    if rec.source == "you" then ns.Fire("FLAG_ADDED", "P", key, r) end
    if not quiet then
        ns.Print(("Flagged %s%s."):format(r.name or key, r.guild and (" <" .. r.guild .. ">") or ""))
    end
    return r
end

function ns.FlagGuild(key, rec, quiet)
    if not key then return end
    local r = upsert(ns.db.guilds, key, rec)
    ns.Fire("FLAGS_CHANGED")
    if rec.source == "you" then ns.Fire("FLAG_ADDED", "G", key, r) end
    if not quiet then ns.Print(("Flagged guild <%s>."):format(r.name or key)) end
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

-- returns: number of (trusted) reporters, whether that's enough to show, newest report
function ns.Community(bucket, key)
    local reports = key and ns.db.community[bucket][key]
    local n, trusted, latest = 0, false, nil
    if reports then
        for reporter, r in pairs(reports) do
            if not ns.db.distrust[reporter] and not ns.ReportExpired(r.d) then
                n = n + 1
                if r.via == "GUILD" and ns.db.settings.trustGuildmates then trusted = true end
                if not latest or (r.d or 0) > (latest.d or 0) then latest = r end
            end
        end
    end
    local shown = n > 0 and (n >= ns.db.settings.communityThreshold or trusted)
    return n, shown, latest
end

function ns.Status(playerKey, guildKey)
    local s = {}
    if playerKey then
        s.player = ns.db.players[playerKey]
        s.cPlayer, s.cPlayerShown, s.cPlayerLatest = ns.Community("players", playerKey)
        if not guildKey then
            -- no guild info before you're grouped (invites), use the last one we saw
            guildKey = (s.player and s.player.guildKey) or (s.cPlayerLatest and s.cPlayerLatest.g) or nil
        end
    end
    if guildKey then
        s.guildKey = guildKey
        s.guild = ns.db.guilds[guildKey]
        s.cGuild, s.cGuildShown = ns.Community("guilds", guildKey)
    end
    s.flagged = (s.player or s.guild or s.cPlayerShown or s.cGuildShown) and true or false
    return s
end

function ns.Describe(s)
    local parts = {}
    if s.player then
        local p = s.player
        parts[#parts + 1] = ("you flagged them %s (%s%s)"):format(ns.TimeText(p.when), ns.REASONS[p.kind] or p.kind or "flagged",
            (p.summons or 0) > 0 and (", " .. p.summons .. " summons") or "")
    end
    if s.guild then parts[#parts + 1] = ("their guild <%s> is flagged"):format(s.guild.name or s.guildKey) end
    if s.cPlayerShown then parts[#parts + 1] = ("%d union member%s reported them"):format(s.cPlayer, s.cPlayer == 1 and "" or "s") end
    if s.cGuildShown then parts[#parts + 1] = ("%d union member%s reported their guild"):format(s.cGuild, s.cGuild == 1 and "" or "s") end
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
    local counts = {}
    for _, bucket in ipairs({ "players", "guilds" }) do
        local all = db.community[bucket]
        for key, reports in pairs(all) do
            for reporter, r in pairs(reports) do
                if ns.ReportExpired(r.d) then
                    reports[reporter] = nil
                    reportsRemoved = reportsRemoved + 1
                else
                    counts[reporter] = (counts[reporter] or 0) + 1
                end
            end
            if next(reports) == nil then all[key] = nil end
        end
    end
    db.reporterCounts = counts -- recount from scratch so the cap can't drift

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

function ns.SlashFlag(rest)
    local key, display, gk, gn, reason = resolvePlayer(rest)
    if not key then
        ns.Print("Usage: /su flag <name> [reason], or target the player first.")
        return
    end
    ns.FlagPlayer(key, {
        name = display, guildKey = gk, guild = gn, kind = "manual", summons = 0, source = "you",
        reason = (reason ~= "" and reason) or nil, zone = GetRealZoneText and GetRealZoneText() or nil,
    })
end

function ns.SlashFlagGuild(rest)
    local gk, gn = resolveGuild(rest)
    if not gk then
        ns.Print("Usage: /su flagguild <guild name>, or target a member of the guild.")
        return
    end
    ns.FlagGuild(gk, { name = gn, kind = "manual", summons = 0, source = "you" })
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
    if gk and ns.UnflagGuild(gk) then
        ns.Print("Removed your flag on <" .. gn .. ">.")
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
