-- comm: share flags with other users over addon messages (never visible chat)
--
--   1~F~P~Name-Realm~Guild@Realm~summons~day~reason   a member flagged a player
--   1~F~G~Guild@Realm~~summons~day~reason              a member flagged a guild
--   1~X~P|G~Name-Realm|Guild@Realm                     a member withdrew their flag
--   1~Q~sinceDay                                       "send me your recent flags"
--
-- one entry per reporter per key in db.community so nobody can stack votes,
-- and at most MAX_PER_SENDER reports are kept from any one person
local _, ns = ...

local PREFIX = "SUMUNION"
local SEP = "~"
local PROTO = "1"
local MAX_PER_SENDER = 300
local REPLY_LIMIT = 30
local REPLY_COOLDOWN = 600
local SEND_INTERVAL = 1.2
local MAX_QUEUE = 200

ns.COMM_PREFIX = PREFIX
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end

local function clean(s, maxLen)
    s = tostring(s or ""):gsub("[~|\r\n]", " ")
    return s:sub(1, maxLen or 48)
end

local function split(s)
    local out = {}
    for v in (s .. SEP):gmatch("(.-)" .. SEP) do out[#out + 1] = v end
    return out
end

local function guildField(rec)
    if not rec.guildKey then return "" end
    local name, realm = rec.guildKey:match("^(.-)@(.+)$")
    if not name then return "" end
    return clean((rec.guild or name) .. "@" .. realm, 64)
end

local function who(kind, key, rec)
    if kind == "P" then
        return clean((rec.name and rec.name:find("-", 1, true)) and rec.name or key, 64)
    end
    local name, realm = key:match("^(.-)@(.+)$")
    return clean((rec.name or name or "") .. "@" .. (realm or ""), 64)
end

function ns.EncodeFlag(kind, key, rec)
    return table.concat({
        PROTO, "F", kind, who(kind, key, rec), kind == "P" and guildField(rec) or "",
        tostring(math.min(tonumber(rec.summons) or 0, 99)), tostring(math.floor((rec.when or time()) / 86400)),
        clean(rec.kind or "manual", 10),
    }, SEP)
end

function ns.EncodeRetract(kind, key, rec)
    return table.concat({ PROTO, "X", kind, who(kind, key, rec) }, SEP)
end

function ns.EncodeQuery(sinceDay)
    return table.concat({ PROTO, "Q", tostring(sinceDay or 0) }, SEP)
end

function ns.DecodeMessage(text)
    local f = split(text or "")
    if f[1] ~= PROTO then return nil end
    local t = f[2]
    if t == "Q" then return { type = "Q", since = tonumber(f[3]) or 0 } end
    if t ~= "F" and t ~= "X" then return nil end
    local kind, id = f[3], f[4] or ""
    local m = { type = t, kind = kind }
    if kind == "P" then
        if not id:find("^[^%-]+%-[^%-]+$") then return nil end
        m.key, m.name = ns.PlayerKey(id)
    elseif kind == "G" then
        local g, realm = id:match("^(.-)@(.+)$")
        if not g or g == "" then return nil end
        m.key, m.name = ns.GuildKey(g, realm)
    else
        return nil
    end
    if t == "F" then
        local g, realm = (f[5] or ""):match("^(.-)@(.+)$")
        if g and g ~= "" then m.guildKey, m.guild = ns.GuildKey(g, realm) end
        m.summons = math.max(0, math.min(tonumber(f[6]) or 0, 99))
        m.day = tonumber(f[7]) or ns.Today()
        if m.day > ns.Today() + 1 or m.day < ns.Today() - 3650 then return nil end
        m.reason = (f[8] ~= nil and f[8] ~= "") and f[8] or "manual"
    end
    return m
end

-- throttled queue, the server drops addon messages sent in bursts
local queue, ticker = {}, nil
local function pump()
    local item = table.remove(queue, 1)
    if not item then
        if ticker then ticker:Cancel() end
        ticker = nil
        return
    end
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.text, item.chatType, item.target)
end

function ns.Send(text, chatType, target)
    if #queue >= MAX_QUEUE or #text > 255 then return end
    queue[#queue + 1] = { text = text, chatType = chatType, target = target }
    if not ticker then ticker = C_Timer.NewTicker(SEND_INTERVAL, pump) end
end

local function channelId()
    local id = GetChannelName(ns.db.settings.channelName)
    if id and id > 0 then return id end
end

-- LFG/LFR/BG groups only get INSTANCE_CHAT, PARTY and RAID messages are dropped there
function ns.GroupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    return IsInRaid() and "RAID" or "PARTY"
end

local function scopes()
    local st, out = ns.db.settings, {}
    if st.shareGuild and IsInGuild() then out[#out + 1] = { "GUILD" } end
    if st.shareGroup and IsInGroup() then out[#out + 1] = { ns.GroupChannel() } end
    if st.shareChannel then
        local id = channelId()
        if id then out[#out + 1] = { "CHANNEL", id } end
    end
    return out
end

local function broadcast(text)
    for _, s in ipairs(scopes()) do ns.Send(text, s[1], s[2]) end
end

ns.Listen("FLAG_ADDED", function(kind, key, rec) broadcast(ns.EncodeFlag(kind, key, rec)) end)
ns.Listen("FLAG_REMOVED", function(kind, key, rec) broadcast(ns.EncodeRetract(kind, key, rec)) end)

-- receiving
local function store(sender, via, m)
    local reports = ns.db.community[m.kind == "P" and "players" or "guilds"]
    local counts = ns.db.reporterCounts
    if m.type == "X" then
        local r = reports[m.key]
        if r and r[sender] then
            r[sender] = nil
            if next(r) == nil then reports[m.key] = nil end
            counts[sender] = math.max(0, (counts[sender] or 1) - 1)
            ns.Fire("FLAGS_CHANGED")
        end
        return
    end
    if ns.ReportExpired(m.day) then return end -- too old to count anyway
    local r = reports[m.key] or {}
    local isNew = r[sender] == nil
    if isNew and (counts[sender] or 0) >= MAX_PER_SENDER then return end
    r[sender] = { n = m.name, g = m.guildKey, gn = m.guild, s = m.summons, d = m.day, r = m.reason, via = via }
    reports[m.key] = r
    if isNew then counts[sender] = (counts[sender] or 0) + 1 end
    ns.Fire("FLAGS_CHANGED")
end

local lastReply = {}
local function reply(chatType, target, since)
    local slot = chatType .. tostring(target or "")
    if lastReply[slot] and time() - lastReply[slot] < REPLY_COOLDOWN then return end
    lastReply[slot] = time()
    local items = {}
    for _, kind in ipairs({ "P", "G" }) do
        for key, rec in pairs(kind == "P" and ns.db.players or ns.db.guilds) do
            if rec.source == "you" and math.floor((rec.when or 0) / 86400) >= since then
                items[#items + 1] = { kind, key, rec }
            end
        end
    end
    table.sort(items, function(a, b) return (a[3].when or 0) > (b[3].when or 0) end)
    for i = 1, math.min(#items, REPLY_LIMIT) do
        ns.Send(ns.EncodeFlag(items[i][1], items[i][2], items[i][3]), chatType, target)
    end
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if ns.IsSecret(prefix) or ns.IsSecret(text) or ns.IsSecret(sender) then return end
    if prefix ~= PREFIX or not text or not sender or not ns.db then return end
    local senderKey = ns.PlayerKey(sender)
    if not senderKey or senderKey == ns.playerKey or ns.db.distrust[senderKey] then return end
    local m = ns.DecodeMessage(text)
    if not m then return end
    if m.type == "Q" then
        local target
        if channel == "CHANNEL" then
            target = channelId()
            if not target then return end
        elseif channel ~= "GUILD" and channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then
            return
        end
        -- random delay so the whole guild doesn't answer at once
        C_Timer.After(3 + math.random() * 12, function() reply(channel, target, m.since) end)
    else
        store(senderKey, channel, m)
    end
end)

-- don't ask for anything older than we'd keep
local function querySince(maxDays)
    local expiry = ns.db.settings.communityExpiryDays or 0
    if expiry > 0 and expiry < maxDays then maxDays = expiry end
    return ns.Today() - maxDays
end

function ns.LeaveUnionChannel()
    if channelId() and LeaveChannelByName then LeaveChannelByName(ns.db.settings.channelName) end
end

function ns.JoinUnionChannel()
    local name = ns.db.settings.channelName
    if not channelId() and JoinChannelByName then JoinChannelByName(name) end
    C_Timer.After(5, function()
        local id = channelId()
        if not id then return end
        if ChatFrame_RemoveChannel and DEFAULT_CHAT_FRAME then ChatFrame_RemoveChannel(DEFAULT_CHAT_FRAME, name) end
        ns.Send(ns.EncodeQuery(querySince(30)), "CHANNEL", id)
    end)
end

ns.OnReady(function()
    if ns.db.settings.shareChannel then C_Timer.After(10, ns.JoinUnionChannel) end
    C_Timer.After(30, function()
        if ns.db.settings.shareGuild and IsInGuild() then ns.Send(ns.EncodeQuery(querySince(180)), "GUILD") end
    end)
end)

ns.Listen("SETTING_CHANGED", function(field, value)
    if field ~= "shareChannel" then return end
    if value then ns.JoinUnionChannel() else ns.LeaveUnionChannel() end
end)
