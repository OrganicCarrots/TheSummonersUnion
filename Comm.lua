-- comm: share flags with other users over addon messages (never visible chat)
--
-- live messages, sent as they happen:
--   1~F~P~Name-Realm~Guild@Realm~summons~day~reason~count   sender flagged a player
--   1~F~G~Guild@Realm~~summons~day~reason~count              sender flagged a guild
--   1~X~P|G~Name-Realm|Guild@Realm~day                       sender withdrew their flag
--   1~Q~sinceDay                                             send me what you have since then
--
-- answers to Q pack several records into one message, separated by ^
--   1~B~record^record^...
-- records are F and X as above (without the leading 1~) plus relayed ones:
--   R~P|G~who~guild~summons~day~reason~count~reporter        someone else's flag, passed on
--   Y~P|G~who~reporter~day                                   someone else's retraction, passed on
--
-- one entry per reporter per key so nobody can stack votes. relayed entries remember who
-- passed them on, and nobody can fill more than a set number of slots either way.
-- 1.0 clients ignore B, R and Y and the trailing count field
local _, ns = ...

local PREFIX = "SUMUNION"
local SEP, RSEP = "~", "^"
local PROTO = "1"
local MAX_LEN = 255
local REPLY_COOLDOWN = 600
local SEND_INTERVAL = 1.2
local MAX_QUEUE = 200

ns.COMM_PREFIX = PREFIX
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end

local function clean(s, maxLen)
    s = tostring(s or ""):gsub("[~|^\r\n]", " ")
    return s:sub(1, maxLen or 48)
end

local function split(s)
    local out = {}
    for v in (s .. SEP):gmatch("(.-)" .. SEP) do out[#out + 1] = v end
    return out
end

local function dayOf(t) return math.floor((t or time()) / 86400) end
local function countOf(n) return math.max(1, math.min(math.floor(tonumber(n) or 1), ns.LIMITS.countCap)) end
local function bucketOf(kind) return kind == "P" and "players" or "guilds" end
function ns.RecordId(kind, key, reporter) return kind .. "|" .. key .. "|" .. reporter end

local function guildField(guildKey, guild)
    if not guildKey then return "" end
    local name, realm = guildKey:match("^(.-)@(.+)$")
    if not name then return "" end
    return clean((guild or name) .. "@" .. realm, 64)
end

local function who(kind, key, name)
    if kind == "P" then
        return clean((name and name:find("-", 1, true)) and name or key, 64)
    end
    local g, realm = key:match("^(.-)@(.+)$")
    return clean((name or g or "") .. "@" .. (realm or ""), 64)
end

-- your own flag, as a record without the 1~ in front
local function ownRecord(kind, key, rec)
    return table.concat({
        "F", kind, who(kind, key, rec.name), kind == "P" and guildField(rec.guildKey, rec.guild) or "",
        tostring(math.min(tonumber(rec.summons) or 0, 99)), tostring(dayOf(rec.when)),
        clean(rec.kind or "manual", 10), tostring(countOf(rec.times)),
    }, SEP)
end

local function relayRecord(kind, key, reporter, r)
    return table.concat({
        "R", kind, who(kind, key, r.n), kind == "P" and guildField(r.g, r.gn) or "",
        tostring(math.min(tonumber(r.s) or 0, 99)), tostring(r.d or ns.Today()),
        clean(r.r or "manual", 10), tostring(countOf(r.c)), clean(reporter, 64),
    }, SEP)
end

function ns.EncodeFlag(kind, key, rec) return PROTO .. SEP .. ownRecord(kind, key, rec) end

function ns.EncodeRetract(kind, key, rec, day)
    return table.concat({ PROTO, "X", kind, who(kind, key, rec and rec.name), tostring(day or ns.Today()) }, SEP)
end

function ns.EncodeQuery(sinceDay)
    return table.concat({ PROTO, "Q", tostring(sinceDay or 0) }, SEP)
end

local function reporterKey(s)
    if not s or not s:find("^[^%-]+%-[^%-]+$") then return nil end
    return (ns.PlayerKey(s))
end

local function decodeRecord(f)
    local t = f[1]
    if t == "Q" then return { type = "Q", since = tonumber(f[2]) or 0 } end
    if t ~= "F" and t ~= "X" and t ~= "R" and t ~= "Y" then return nil end
    local kind, id = f[2], f[3] or ""
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
    local today = ns.Today()
    local day
    if t == "F" or t == "R" then
        local g, realm = (f[4] or ""):match("^(.-)@(.+)$")
        if g and g ~= "" then m.guildKey, m.guild = ns.GuildKey(g, realm) end
        m.summons = math.max(0, math.min(tonumber(f[5]) or 0, 99))
        day = f[6]
        m.reason = (f[7] ~= nil and f[7] ~= "") and f[7] or "manual"
        m.count = countOf(f[8])
        if t == "R" then
            m.reporter = reporterKey(f[9])
            if not m.reporter then return nil end
        end
    elseif t == "X" then
        day = f[4]
    else
        m.reporter = reporterKey(f[4])
        if not m.reporter then return nil end
        day = f[5]
    end
    m.day = math.floor(tonumber(day) or today)
    if m.day > today + 1 or m.day < today - 3650 then return nil end
    return m
end

-- every record in a message (batches hold several), or nil if it isn't ours
function ns.DecodeMessages(text)
    text = text or ""
    if text:sub(1, #PROTO + 1) ~= PROTO .. SEP then return nil end
    local body, list = text:sub(#PROTO + 2), {}
    if body:sub(1, 2) == "B" .. SEP then
        for rec in (body:sub(3) .. RSEP):gmatch("(.-)%^") do
            local m = decodeRecord(split(rec))
            if m and m.type ~= "Q" then list[#list + 1] = m end
        end
    else
        list[1] = decodeRecord(split(body))
    end
    return list
end

function ns.DecodeMessage(text)
    local list = ns.DecodeMessages(text)
    return list and list[1]
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
    if #queue >= MAX_QUEUE or #text > MAX_LEN then return end
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

local function sharingOn(chatType)
    local st = ns.db.settings
    if chatType == "GUILD" then return st.shareGuild end
    if chatType == "CHANNEL" then return st.shareChannel end
    return st.shareGroup
end

local function scopes()
    local out = {}
    if sharingOn("GUILD") and IsInGuild() then out[#out + 1] = { "GUILD" } end
    if IsInGroup() and sharingOn("PARTY") then out[#out + 1] = { ns.GroupChannel() } end
    if sharingOn("CHANNEL") then
        local id = channelId()
        if id then out[#out + 1] = { "CHANNEL", id } end
    end
    return out
end

local function broadcast(text)
    for _, s in ipairs(scopes()) do ns.Send(text, s[1], s[2]) end
end

-- private flags (you hadn't grouped with them) never leave your client
ns.Listen("FLAG_ADDED", function(kind, key, rec)
    if rec.private then return end
    ns.db.retracted[ns.RecordId(kind, key, ns.playerKey)] = nil
    broadcast(ns.EncodeFlag(kind, key, rec))
end)
ns.Listen("FLAG_REMOVED", function(kind, key, rec)
    if rec.private then return end
    ns.db.retracted[ns.RecordId(kind, key, ns.playerKey)] = ns.Today() -- so we keep passing the retraction on
    broadcast(ns.EncodeRetract(kind, key, rec))
end)

-- receiving
local function dropReport(bucket, key, reporter)
    local db = ns.db
    local all = db.community[bucket]
    local r = all[key] and all[key][reporter]
    if not r then return false end
    all[key][reporter] = nil
    if next(all[key]) == nil then all[key] = nil end
    db.reporterCounts[reporter] = math.max(0, (db.reporterCounts[reporter] or 1) - 1)
    if r.rl then db.relayCounts[r.rl] = math.max(0, (db.relayCounts[r.rl] or 1) - 1) end
    return true
end

-- someone filing a pile of new reports in one day is spamming, ignore them until you /su trust them
local function flooded(reporter, day)
    local db = ns.db
    local k = reporter .. "|" .. day
    db.filed[k] = (db.filed[k] or 0) + 1
    if db.filed[k] <= ns.LIMITS.dailyReports then return false end
    if not db.distrust[reporter] then
        db.distrust[reporter] = "auto"
        local display = ns.DisplayName(reporter)
        ns.Print(("Ignoring reports from %s: they filed more than %d in one day. /su trust %s counts them again."):format(
            display, ns.LIMITS.dailyReports, display))
    end
    return true
end

local function putReport(bucket, m, reporter, via, relayer)
    local db, limits = ns.db, ns.LIMITS
    local all = db.community[bucket]
    local old = all[m.key] and all[m.key][reporter]
    local newRelayer = relayer and (not old or old.rl ~= relayer)
    -- check the caps before touching anything
    if not old and (db.reporterCounts[reporter] or 0) >= limits.perReporter then return false end
    if newRelayer then
        if (db.relayCounts[relayer] or 0) >= limits.perRelayer then return false end
        local here = 0
        for _, r in pairs(all[m.key] or {}) do
            if r.rl == relayer then here = here + 1 end
        end
        if here >= limits.relaysPerTarget then return false end
    end
    if not old and flooded(reporter, m.day) then return false end
    if not old then db.reporterCounts[reporter] = (db.reporterCounts[reporter] or 0) + 1 end
    if old and old.rl and old.rl ~= relayer then db.relayCounts[old.rl] = math.max(0, (db.relayCounts[old.rl] or 1) - 1) end
    if newRelayer then db.relayCounts[relayer] = (db.relayCounts[relayer] or 0) + 1 end
    all[m.key] = all[m.key] or {}
    all[m.key][reporter] = { n = m.name, g = m.guildKey, gn = m.guild, s = m.summons, d = m.day, r = m.reason,
                             c = m.count or 1, via = via, rl = relayer }
    return true
end

-- returns true if anything changed
local function handle(sender, via, m)
    local db = ns.db
    local bucket = bucketOf(m.kind)
    local reporter = m.reporter or sender
    if reporter == sender then
        -- straight from the person who filed it, this always wins over anything relayed
        local id = ns.RecordId(m.kind, m.key, sender)
        if m.type == "F" or m.type == "R" then
            if ns.ReportExpired(m.day) then return false end
            db.retracted[id] = nil
            return putReport(bucket, m, sender, via, nil)
        end
        if (db.retracted[id] or -1) < m.day then db.retracted[id] = m.day end
        return dropReport(bucket, m.key, sender)
    end

    if not db.settings.acceptRelays or reporter == ns.playerKey or db.distrust[reporter] then return false end
    local id = ns.RecordId(m.kind, m.key, reporter)
    local existing = db.community[bucket][m.key] and db.community[bucket][m.key][reporter]
    if existing and not existing.rl then return false end -- we heard this one first hand
    if m.type == "R" then
        if ns.ReportExpired(m.day) or (db.retracted[id] or -1) >= m.day then return false end
        if existing and ((existing.d or 0) > m.day or ((existing.d or 0) == m.day and (existing.c or 1) >= m.count)) then
            return false
        end
        return putReport(bucket, m, reporter, "RELAY", sender)
    end
    if (db.retracted[id] or -1) < m.day then db.retracted[id] = m.day end
    return dropReport(bucket, m.key, reporter)
end

-- everything we know since a day, newest first, as records ready to pack
local function syncRecords(since, skip, querier)
    local db, me, items = ns.db, ns.playerKey, {}
    local function add(day, rec, id, reporter)
        if (day or 0) >= since and not skip[id] and reporter ~= querier then items[#items + 1] = { day or 0, rec } end
    end
    for _, kind in ipairs({ "P", "G" }) do
        for key, rec in pairs(kind == "P" and db.players or db.guilds) do
            if rec.source == "you" and not rec.private then
                add(dayOf(rec.when), ownRecord(kind, key, rec), ns.RecordId(kind, key, me), me)
            end
        end
        for key, reports in pairs(db.community[bucketOf(kind)]) do
            for reporter, r in pairs(reports) do
                if ns.ReportUsable(reporter, r) then
                    add(r.d, relayRecord(kind, key, reporter, r), ns.RecordId(kind, key, reporter), reporter)
                end
            end
        end
    end
    for id, day in pairs(db.retracted) do
        local kind, key, reporter = id:match("^(%a)|(.-)|(.+)$")
        if kind then
            local target = who(kind, key, nil)
            if reporter == me then
                add(day, table.concat({ "X", kind, target, tostring(day) }, SEP), id, reporter)
            else
                add(day, table.concat({ "Y", kind, target, reporter, tostring(day) }, SEP), id, reporter)
            end
        end
    end
    table.sort(items, function(a, b) return a[1] > b[1] end)
    local out = {}
    for i = 1, math.min(#items, ns.LIMITS.replyRecords) do out[i] = items[i][2] end
    return out
end

-- as few messages as possible, each under the 255 byte limit
local function pack(records)
    local msgs, cur = {}, nil
    local head = PROTO .. SEP .. "B" .. SEP
    for _, rec in ipairs(records) do
        if cur and #cur + #RSEP + #rec <= MAX_LEN then
            cur = cur .. RSEP .. rec
        else
            if cur then msgs[#msgs + 1] = cur end
            cur = head .. rec
            if #cur > MAX_LEN then cur = nil end
        end
    end
    if cur then msgs[#msgs + 1] = cur end
    return msgs
end

function ns.SyncMessages(since, skip, querier) return pack(syncRecords(since or 0, skip or {}, querier)) end

-- while we wait to answer a query, remember what others already sent so we don't repeat it
local pending, lastReply = {}, {}
local function slotOf(chatType, target) return chatType .. tostring(target or "") end

function ns.ResetSync() pending, lastReply = {}, {} end -- used by the tests

local function onQuery(channel, sender, since)
    local target
    if channel == "CHANNEL" then
        target = channelId()
        if not target then return end
    elseif channel ~= "GUILD" and channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then
        return
    end
    if not sharingOn(channel) then return end
    local slot = slotOf(channel, target)
    if pending[slot] or (lastReply[slot] and time() - lastReply[slot] < REPLY_COOLDOWN) then return end
    pending[slot] = { seen = {} }
    -- random delay so the whole guild doesn't answer at once
    C_Timer.After(3 + math.random() * 12, function()
        local p = pending[slot]
        pending[slot] = nil
        lastReply[slot] = time()
        for _, text in ipairs(ns.SyncMessages(since, p and p.seen, sender)) do ns.Send(text, channel, target) end
    end)
end

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if ns.IsSecret(prefix) or ns.IsSecret(text) or ns.IsSecret(sender) then return end
    if prefix ~= PREFIX or not text or not sender or not ns.db then return end
    local senderKey = ns.PlayerKey(sender)
    if not senderKey or senderKey == ns.playerKey or ns.db.distrust[senderKey] then return end
    local list = ns.DecodeMessages(text)
    if not list then return end
    local p = pending[slotOf(channel, channel == "CHANNEL" and channelId() or nil)]
    local changed = false
    for _, m in ipairs(list) do
        if m.type == "Q" then
            onQuery(channel, senderKey, m.since)
        else
            if p then p.seen[ns.RecordId(m.kind, m.key, m.reporter or senderKey)] = true end
            if handle(senderKey, channel, m) then changed = true end
        end
    end
    if changed then ns.Fire("FLAGS_CHANGED") end
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
        if sharingOn("GUILD") and IsInGuild() then ns.Send(ns.EncodeQuery(querySince(180)), "GUILD") end
    end)
end)

-- swap lists with whoever else in a new group runs the addon
ns.On("GROUP_JOINED", function()
    C_Timer.After(8, function()
        if IsInGroup() and sharingOn("PARTY") then ns.Send(ns.EncodeQuery(querySince(180)), ns.GroupChannel()) end
    end)
end)

ns.Listen("SETTING_CHANGED", function(field, value)
    if field ~= "shareChannel" then return end
    if value then ns.JoinUnionChannel() else ns.LeaveUnionChannel() end
end)
