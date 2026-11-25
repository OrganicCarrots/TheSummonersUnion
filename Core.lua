-- core: saved vars, event dispatch, name helpers, settings and slash commands
local ADDON, ns = ...

ns.ADDON = ADDON
ns.TITLE = "The Summoners Union"
local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (getMeta and getMeta(ADDON, "Version")) or "dev"

ns.DEFAULTS = {
    schema = 1,
    players = {},                              -- [name-realm] = your flag on a player
    guilds = {},                               -- [guild@realm] = your flag on a guild
    community = { players = {}, guilds = {} }, -- [key] = { [reporter] = report from another union member }
    reporterCounts = {},                       -- [reporter] = reports stored from them (capped)
    relayCounts = {},                          -- [relayer] = reports they passed on to us (capped)
    distrust = {},                             -- [reporter] = true, or "auto" if they flooded us
    retracted = {},                            -- ["P|key|reporter"] = day the flag was withdrawn
    filed = {},                                -- ["reporter|day"] = new reports from them that day
    seen = {},                                 -- [name-realm] = last time we were grouped with them
    seenGuilds = {},                           -- [guild@realm] = last time we grouped with a member
    settings = {
        promptOnKick = true,        -- ask to flag when you are removed after summoning
        promptOnDisband = true,     -- ...or when the group is disbanded after summoning
        minSummons = 1,             -- summons you must have cast in that group
        summonWindowMinutes = 20,   -- removal must come this soon after your last summon
        warnOnInvite = true,
        warnInGroup = true,
        autoDecline = false,        -- decline invites from flagged players outright
        communityThreshold = 2,     -- people you know who must report someone before you're warned
        strangerThreshold = 4,      -- ...or this many people in all, counting ones you don't know
        countStrangers = true,      -- off: only people you know can get someone flagged for you
        trustGuildmates = true,     -- one report from a guildmate is enough
        shareGuild = true,
        shareGroup = true,
        shareChannel = false,       -- opt-in public channel shared by all union members
        acceptRelays = true,        -- count reports other members pass on, not just first hand ones
        forwardReports = true,      -- pass new reports on to your other channels as soon as you get them
        channelName = "SummonersUnion",
        channelSuggested = false,   -- we've asked once whether to join the channel
        communityExpiryDays = 180,  -- other members' reports stop counting after this (0 = never)
        flagExpiryDays = 0,         -- forget your own flags after this, at login (0 = never)
        showMinimap = true,
        showReasons = true,         -- the reason you gave, next to your own flags in the list
        minimapAngle = 225,         -- degrees around the minimap, 0 = east
    },
}

ns.LIMITS = {
    countCap = 5,          -- most grievances one person can add against one target
    perReporter = 300,     -- reports kept from any one person
    perRelayer = 500,      -- reports any one person can pass on to us
    relaysPerTarget = 3,   -- reports about the same target one person can pass on
    dailyReports = 10,     -- new reports one person can file in a day before we ignore them
    groupedDays = 7,       -- your flag is only shared if you grouped with them this recently
    seenDays = 30,         -- how long we remember who we grouped with
    replyRecords = 120,    -- records sent when answering a query
    forwardPerMinute = 30, -- reports we pass on per minute, the rest wait for the next sync
    total = 5000,          -- community reports kept in all
}

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
ns.ApplyDefaults = applyDefaults

-- internal callbacks: FLAGS_CHANGED, FLAG_ADDED, FLAG_REMOVED, SETTING_CHANGED
local listeners = {}
function ns.Listen(name, fn)
    listeners[name] = listeners[name] or {}
    table.insert(listeners[name], fn)
end
function ns.Fire(name, ...)
    local list = listeners[name]
    if not list then return end
    for i = 1, #list do list[i](...) end
end

-- game events
local eventFrame = CreateFrame("Frame")
local handlers = {}
function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- not every event exists on every client and registering an unknown one errors
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    table.insert(handlers[event], fn)
end

-- retail 12 can give us "secret" values (names, chat text in some instances).
-- using them as strings errors so just treat them as unknown
function ns.IsSecret(v) return issecretvalue ~= nil and v ~= nil and issecretvalue(v) or false end
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end)

local readyFns = {}
function ns.OnReady(fn) table.insert(readyFns, fn) end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    SummonersUnionDB = applyDefaults(SummonersUnionDB or {}, ns.DEFAULTS)
    ns.db = SummonersUnionDB
end)

ns.On("PLAYER_LOGIN", function()
    ns.playerKey, ns.playerName = ns.UnitKey("player")
    local _, class = UnitClass("player")
    ns.playerClass = class
    ns.isWarlock = (class == "WARLOCK")
    for i = 1, #readyFns do
        local ok, err = pcall(readyFns[i])
        if not ok then geterrorhandler()(err) end
    end
end)

-- helpers
function ns.Print(msg)
    local cf = DEFAULT_CHAT_FRAME
    if cf then cf:AddMessage("|cff9b6fd8Summoners Union|r: " .. tostring(msg)) end
end

function ns.Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function ns.Today() return math.floor(time() / 86400) end
function ns.DayText(day) return date("%Y-%m-%d", (tonumber(day) or 0) * 86400 + 43200) end
function ns.TimeText(t) return date("%Y-%m-%d", t or 0) end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
ns.Trim = trim

local function normRealm(realm)
    if not realm or realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "Unknown"
    end
    return (realm:gsub("[%s%-']", ""))
end
ns.NormRealm = normRealm

-- empty on wow forever, which has no realms
function ns.HomeRealm() return normRealm(nil) end

-- "Name", "Name-Realm" or ("Name", "Realm") -> key "name-realm" plus display name "Name-Realm".
-- with no realm the key ends in "-" and the display name is just "Name"
function ns.PlayerKey(name, realm)
    name = trim(name)
    if name == "" then return nil end
    local n, r = name:match("^([^%-]+)%-(.*)$")
    if n then
        name, realm = n, r
    elseif (not realm or realm == "") and normRealm(nil) == "" then
        -- wow forever sends "First Last" in messages, unit names put the last name in the realm slot
        local first, last = name:match("^(%S+)%s+(.+)$")
        if first then name, realm = first, last end
    end
    name = name:gsub("^%l", string.upper)
    realm = normRealm(realm):gsub("^%l", string.upper)
    return (name .. "-" .. realm):lower(), realm == "" and name or (name .. "-" .. realm)
end

-- "name-realm" key back to something readable, "Name-Realm"
function ns.DisplayName(key)
    local n, r = tostring(key or ""):match("^([^%-]+)%-(.*)$")
    if not n then return key end
    n = n:gsub("^%l", string.upper)
    if r == "" then return n end
    return n .. "-" .. (r:gsub("^%l", string.upper))
end

-- guild names are unique per realm, key is "guild name@realm"
function ns.GuildKey(guild, realm)
    guild = trim(guild)
    if guild == "" then return nil end
    return (guild .. "@" .. normRealm(realm)):lower(), guild
end

function ns.UnitKey(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    local name, realm = UnitName(unit)
    if ns.IsSecret(name) or ns.IsSecret(realm) then return nil end
    if not name or name == "" or name == UNKNOWNOBJECT then return nil end
    return ns.PlayerKey(name, realm)
end

function ns.UnitGuild(unit)
    if not unit or not UnitExists(unit) then return nil end
    local guild, _, _, guildRealm = GetGuildInfo(unit)
    if ns.IsSecret(guild) or ns.IsSecret(guildRealm) then return nil end
    if not guild or guild == "" then return nil end
    if ns.HomeRealm() == "" then
        guildRealm = nil -- wow forever has no realms, that slot holds the last name there
    elseif not guildRealm or guildRealm == "" then
        local _, unitRealm = UnitName(unit)
        guildRealm = unitRealm
    end
    return ns.GuildKey(guild, guildRealm)
end

-- older versions on wow forever put a member's last name in guild keys, so one guild had a
-- key per member, and names got a stray "-". fold those up
function ns.FixRealmless(db)
    local function fold(k) return k and (k:gsub("@.*$", "@")) end
    local function rekey(store, merge)
        local moves = {}
        for k in pairs(store) do
            if fold(k) ~= k then moves[#moves + 1] = k end
        end
        for _, k in ipairs(moves) do
            local nk, v = fold(k), store[k]
            store[k] = nil
            store[nk] = store[nk] and merge(store[nk], v) or v
        end
    end
    rekey(db.guilds, function(a, b) return (a.when or 0) >= (b.when or 0) and a or b end)
    rekey(db.seenGuilds, math.max)
    rekey(db.community.guilds, function(a, b)
        for who, r in pairs(b) do
            if not a[who] or (a[who].d or 0) < (r.d or 0) then a[who] = r end
        end
        return a
    end)
    for _, r in pairs(db.players) do
        r.guildKey = fold(r.guildKey)
        if r.name then r.name = (r.name:gsub("%-$", "")) end
    end
    for _, reports in pairs(db.community.players) do
        for _, r in pairs(reports) do
            r.g = fold(r.g)
            if r.n then r.n = (r.n:gsub("%-$", "")) end
        end
    end

    -- message senders used to be keyed "first last-", unit names give "first-last"
    local function person(k)
        local first, last = k:match("^(%S+) (.+)%-$")
        return first and (first .. "-" .. last:gsub("[%s%-']", "")) or k
    end
    for _, bucket in ipairs({ "players", "guilds" }) do
        for _, reports in pairs(db.community[bucket]) do
            local moves = {}
            for who in pairs(reports) do
                if person(who) ~= who then moves[#moves + 1] = who end
            end
            for _, who in ipairs(moves) do
                local nk, r = person(who), reports[who]
                reports[who] = nil
                if not reports[nk] or (reports[nk].d or 0) < (r.d or 0) then reports[nk] = r end
            end
            for _, r in pairs(reports) do
                if r.rl then r.rl = person(r.rl) end
            end
        end
    end
    local distrust = {}
    for who, v in pairs(db.distrust) do distrust[person(who)] = v end
    db.distrust = distrust
end
ns.OnReady(function() if ns.HomeRealm() == "" then ns.FixRealmless(ns.db) end end)

-- unit tokens for the whole group, including the player
function ns.GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        units[1] = "player"
        for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
    end
    return units
end

-- settings
-- all changes go through SetSetting so /su set and the options panel behave the same
local SETTINGS = {
    window = { "summonWindowMinutes", "number", 1, 240 },
    minsummons = { "minSummons", "number", 1, 40 },
    threshold = { "communityThreshold", "number", 1, 50 },
    strangers = { "strangerThreshold", "number", 1, 50 },
    expiry = { "communityExpiryDays", "number", 0, 3650 },
    flagexpiry = { "flagExpiryDays", "number", 0, 3650 },
    autodecline = { "autoDecline", "bool" },
    warninvite = { "warnOnInvite", "bool" },
    warngroup = { "warnInGroup", "bool" },
    promptkick = { "promptOnKick", "bool" },
    promptdisband = { "promptOnDisband", "bool" },
    trustguild = { "trustGuildmates", "bool" },
    relays = { "acceptRelays", "bool" },
    forward = { "forwardReports", "bool" },
    minimap = { "showMinimap", "bool" },
    reasons = { "showReasons", "bool" },
}
local SETTING_NAMES = {}
for name in pairs(SETTINGS) do SETTING_NAMES[#SETTING_NAMES + 1] = name end
table.sort(SETTING_NAMES)

function ns.SetSetting(field, value)
    local st = ns.db.settings
    if st[field] == value then return end
    st[field] = value
    ns.Fire("SETTING_CHANGED", field, value)
    ns.Fire("FLAGS_CHANGED")
end

-- reset everything except the minimap button position
function ns.ResetSettings()
    for field, value in pairs(ns.DEFAULTS.settings) do
        if field ~= "minimapAngle" and field ~= "channelSuggested" then ns.SetSetting(field, value) end
    end
end

-- slash commands
local HELP = {
    "/su - open the union list",
    "/su options - open the options panel",
    "/su flag [name] [reason] - flag a player (your target if no name)",
    "/su flagguild [guild] - flag a guild (your target's guild if none)",
    "/su unflag <name>  |  /su unflagguild <guild>",
    "/su check [name] - look a player up",
    "/su list - print your flags to chat",
    "/su export  |  /su import - share lists as text",
    "/su share guild|group|channel on|off - /su share channel on is recommended",
    "/su distrust <name>  |  /su trust <name> - ignore or restore a reporter",
    "/su purge all|channel|relays|since <hours> - clear other people's reports, yours stay",
    "/su set <option> <value> - type /su set to list the options",
    "/su minimap - show or hide the minimap button",
    "/su test - preview the prompt you get after a summon-kick",
}

local function onoff(v)
    v = (v or ""):lower()
    if v == "on" or v == "1" or v == "true" or v == "yes" then return true end
    if v == "off" or v == "0" or v == "false" or v == "no" then return false end
end
ns.OnOff = onoff

local function setCommand(rest)
    local opt, val = rest:lower():match("^(%S+)%s*(%S*)$")
    -- /su set strangers on|off, a number still sets how many
    if opt == "strangers" and onoff(val) ~= nil then
        ns.SetSetting("countStrangers", onoff(val))
        ns.Print(ns.db.settings.countStrangers and "Reports from strangers count again."
            or "Reports from strangers are ignored now. Only people you know can get someone flagged for you.")
        return
    end
    local def = SETTINGS[opt or ""]
    if not def then
        ns.Print("Options: " .. table.concat(SETTING_NAMES, ", ") .. ". Or use /su options.")
        return
    end
    local field, kind, lo, hi = def[1], def[2], def[3], def[4]
    local v
    if kind == "number" then
        v = tonumber(val)
        if v then v = math.max(lo, math.min(hi, math.floor(v))) end
    else
        v = onoff(val)
    end
    if v == nil then
        ns.Print(("%s is %s."):format(opt, tostring(ns.db.settings[field])))
        return
    end
    ns.SetSetting(field, v)
    ns.Print(("%s set to %s."):format(opt, tostring(v)))
    if field == "flagExpiryDays" and v > 0 then
        ns.Print(("Flags older than %d days will be forgotten the next time you log in or /reload."):format(v))
    end
end

function ns.Slash(msg)
    local cmd, rest = trim(msg):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""
    if cmd == "" or cmd == "show" then
        ns.ToggleWindow()
    elseif cmd == "help" then
        for _, line in ipairs(HELP) do ns.Print(line) end
    elseif cmd == "options" or cmd == "config" or cmd == "settings" then
        ns.OpenOptions()
    elseif cmd == "flag" then
        ns.SlashFlag(rest)
    elseif cmd == "flagguild" then
        ns.SlashFlagGuild(rest)
    elseif cmd == "unflag" then
        ns.SlashUnflag(rest)
    elseif cmd == "unflagguild" then
        ns.SlashUnflagGuild(rest)
    elseif cmd == "check" then
        ns.SlashCheck(rest)
    elseif cmd == "list" then
        ns.SlashList()
    elseif cmd == "export" then
        ns.ShowExport()
    elseif cmd == "import" then
        ns.ShowImport()
    elseif cmd == "share" then
        local scope, val = rest:lower():match("^(%S+)%s*(%S*)$")
        local field = ({ guild = "shareGuild", group = "shareGroup", channel = "shareChannel" })[scope or ""]
        local on = onoff(val)
        if not field or on == nil then
            ns.Print("Usage: /su share guild|group|channel on|off")
            return
        end
        ns.SetSetting(field, on)
        if field == "shareChannel" then
            ns.Print(on and "Joined the union channel. Reports now reach every union member on your realm, not just your guild and groups."
                or "Left the union channel. You'll only share with your guild and groups. /su share channel on to rejoin.")
        else
            ns.Print(("Sharing with %s is now %s."):format(scope, on and "on" or "off"))
        end
    elseif cmd == "distrust" or cmd == "trust" then
        local key, display = ns.PlayerKey(rest)
        if not key then
            ns.Print("Usage: /su " .. cmd .. " <name>")
            return
        end
        ns.db.distrust[key] = (cmd == "distrust") or nil
        if cmd == "trust" then
            -- start their daily count over, otherwise an old flood would trip it again
            for k in pairs(ns.db.filed) do
                if k:sub(1, #key + 1) == key .. "|" then ns.db.filed[k] = nil end
            end
        end
        ns.Fire("FLAGS_CHANGED")
        ns.Print(cmd == "distrust" and ("Ignoring everything %s reports or passes on."):format(display)
            or ("%s's reports count again."):format(display))
    elseif cmd == "purge" then
        ns.SlashPurge(rest)
    elseif cmd == "set" then
        setCommand(rest)
    elseif cmd == "minimap" then
        local on = onoff(rest)
        if on == nil then on = not ns.db.settings.showMinimap end
        ns.SetSetting("showMinimap", on)
        ns.Print(on and "Minimap button shown." or "Minimap button hidden. /su minimap brings it back.")
    elseif cmd == "test" then
        ns.ShowKickPrompt({
            key = "example-realm", name = "Example-Realm", guildKey = "example guild@realm", guild = "Example Guild",
            summons = 4, zone = GetRealZoneText and GetRealZoneText() or "", kind = "kick",
            lastSummon = time() - 120, targets = { "Someone", "Someoneelse" }, test = true,
        })
    else
        ns.Print("Unknown command. Type /su help.")
    end
end

SLASH_SUMMONERSUNION1 = "/su"
SLASH_SUMMONERSUNION2 = "/summonersunion"
SlashCmdList.SUMMONERSUNION = function(msg) ns.Slash(msg or "") end
