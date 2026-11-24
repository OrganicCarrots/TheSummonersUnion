-- fake WoW API, just enough to load the addon in plain lua 5.1 and fire events at it.
-- widgets accept any method and do nothing
local M = { clock = 1800000000, timers = {}, sent = {}, chat = {}, alerts = {}, popups = {}, declined = 0, tooltip = {} }

-- clock and timers
function time() return M.clock end
date = os.date
function M.Advance(sec)
    -- run timers in order so ones created along the way also fire
    local target = M.clock + sec
    while true do
        local nextT, idx
        for i, t in ipairs(M.timers) do
            if not t.cancelled and t.due <= target and (not nextT or t.due < nextT.due) then nextT, idx = t, i end
        end
        if not nextT then break end
        M.clock = math.max(M.clock, nextT.due)
        if nextT.every then nextT.due = nextT.due + nextT.every else table.remove(M.timers, idx) end
        nextT.fn(nextT)
    end
    for i = #M.timers, 1, -1 do if M.timers[i].cancelled then table.remove(M.timers, i) end end
    M.clock = target
end
C_Timer = {
    After = function(delay, fn) table.insert(M.timers, { due = M.clock + delay, fn = function() fn() end }) end,
    NewTicker = function(every, fn)
        local t = { due = M.clock + every, every = every }
        t.fn = function() fn(t) end
        function t:Cancel() self.cancelled = true end
        table.insert(M.timers, t)
        return t
    end,
}

-- widgets: unknown methods are no-ops that return the widget
local frames = {}
local widgetMeta = { __index = function(t, k) return function() return t end end }
function CreateFrame(kind, name, parent, template)
    local f = setmetatable({ events = {}, scripts = {} }, widgetMeta)
    f.RegisterEvent = function(self, e) self.events[e] = true end
    f.UnregisterEvent = function(self, e) self.events[e] = nil end
    f.SetScript = function(self, k, fn) self.scripts[k] = fn end
    f.HookScript = function(self, k, fn) self.scripts[k] = fn end
    f.GetScript = function(self, k) return self.scripts[k] end
    f.IsShown = function(self) return self.shown end
    f.Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    f.Hide = function(self) self.shown = false end
    f.SetText = function(self, s) self.text = s end
    f.GetText = function(self) return self.text or "" end
    f.CreateFontString = function(self) return CreateFrame("FontString") end
    f.CreateTexture = function(self) return CreateFrame("Texture") end
    f.SetPoint = function(self, ...) self.point = { ... } end
    f.SetChecked = function(self, v) self.checked = v and true or false end
    f.GetChecked = function(self) return self.checked or false end
    f.SetEnabled = function(self, v) self.enabled = v and true or false end
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
function M.Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end
UIParent = CreateFrame("Frame", "UIParent")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
GameTooltip.AddLine = function(_, text) table.insert(M.tooltip, text) end
Minimap = CreateFrame("Minimap", "Minimap")
Minimap.GetWidth = function() return 140 end
Minimap.GetHeight = function() return 140 end
Minimap.GetCenter = function() return 500, 400 end
Minimap.GetEffectiveScale = function() return 1 end
M.cursor = { 0, 0 }
GetCursorPosition = function() return M.cursor[1], M.cursor[2] end
-- new style settings window (retail and current classic)
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        M.category = { frame = frame, name = name, GetID = function() return 4242 end }
        return M.category
    end,
    RegisterAddOnCategory = function(category) M.addonCategory = category end,
    OpenToCategory = function(id) M.openedCategory = id end,
}
UISpecialFrames = {}
ChatFontNormal = {}
FauxScrollFrame_Update = function() end
FauxScrollFrame_GetOffset = function() return 0 end
FauxScrollFrame_SetOffset = function() end
FauxScrollFrame_OnVerticalScroll = function() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(M.chat, msg) end }
RaidWarningFrame = {}
ChatTypeInfo = { RAID_WARNING = {} }
RaidNotice_AddMessage = function(_, msg) table.insert(M.alerts, msg) end
SOUNDKIT = { RAID_WARNING = 8959 }
PlaySound = function() end
StaticPopupDialogs = {}
StaticPopup_Show = function(which, a1, a2, data) table.insert(M.popups, { which = which, text = a1, data = data }); return {} end
StaticPopup_Hide = function() end
SlashCmdList = {}
UNKNOWNOBJECT = "Unknown"
tinsert = table.insert
geterrorhandler = function() return function(err) error(err, 0) end end
hooksecurefunc = function(a, b, c)
    local tbl, name, fn = _G, a, b
    if type(a) == "table" then tbl, name, fn = a, b, c end
    local orig = tbl[name]
    tbl[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
C_AddOns = { GetAddOnMetadata = function() return "test" end }
GetSpellInfo = function(id) if id == 698 then return "Ritual of Summoning" end return "Shadow Bolt" end

-- chat
ERR_UNINVITE_YOU = "You have been removed from the group."
ERR_GROUP_DISBANDED = "Your group has been disbanded."
ERR_LEFT_GROUP_YOU = "You leave the group."
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, chatType, target)
        table.insert(M.sent, { prefix = prefix, text = text, chatType = chatType, target = target })
    end,
}
GetChannelName = function(name) if M.channels[name] then return M.channels[name] end return 0 end
JoinChannelByName = function(name) M.channels[name] = 5 end
LeaveChannelByName = function(name) M.channels[name] = nil; table.insert(M.leftChannels, name) end
IsInGuild = function() return true end

-- the world: you are Mylock-Whitemane, a warlock in <The Union>
M.realm = "Whitemane"
M.units = {}      -- unit token -> { name, realm, guild, leader }
M.inGroup, M.raid = false, false
GetNormalizedRealmName = function() return M.realm end
GetRealZoneText = function() return "Molten Core" end
UnitClass = function() return "Warlock", "WARLOCK", 9 end
UnitExists = function(u) return M.units[u] ~= nil end
UnitIsPlayer = function(u) return M.units[u] ~= nil end
UnitName = function(u) local x = M.units[u]; if x then return x.name, x.realm end end
GetGuildInfo = function(u) local x = M.units[u]; if x and x.guild then return x.guild, "Member", 1, nil end end
UnitIsGroupLeader = function(u) local x = M.units[u]; return x and x.leader or false end
UnitIsGroupAssistant = function() return false end
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
IsInGroup = function(category)
    if category == LE_PARTY_CATEGORY_INSTANCE then return M.inGroup and M.instance end
    if category == LE_PARTY_CATEGORY_HOME then return M.inGroup and not M.instance end
    return M.inGroup
end
IsInRaid = function() return M.raid end
GetNumGroupMembers = function()
    local n = 0
    for u in pairs(M.units) do if u ~= "target" then n = n + 1 end end
    return M.inGroup and n or 0
end
DeclineGroup = function() M.declined = M.declined + 1 end
LeaveParty = function() M.SetGroup(nil) end

function M.SetGroup(members)
    local me = M.units.player
    M.units = { player = me }
    if not members then
        M.inGroup = false
        return
    end
    M.inGroup = true
    for i, m in ipairs(members) do M.units["party" .. i] = m end
end

function M.Reset()
    -- keep timers, the send queue might still be waiting on one from the last test
    M.sent, M.chat, M.alerts, M.popups, M.declined, M.tooltip = {}, {}, {}, {}, 0, {}
    M.units = { player = { name = "Mylock", guild = "The Union" } }
    M.inGroup, M.raid, M.instance = false, false, false
    M.channels, M.leftChannels, M.openedCategory = {}, {}, nil
end
M.Reset()

return M
