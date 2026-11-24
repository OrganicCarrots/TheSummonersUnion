-- detect: spot the summon-then-kick pattern and offer to flag the leader
--
-- While you are in a group we keep a "session": who leads it, everyone's guild, and how
-- many Ritual of Summoning casts you finished in it. When the session ends, we decide how:
--   * "You leave the group." or a LeaveParty() call -> you left. Nothing happens.
--   * "You have been removed from the group."      -> kicked.
--   * "Your group has been disbanded." or a silent drop -> disbanded.
-- If you were kicked or disbanded within the window after your last summon, you're asked
-- whether to flag the leader (and their guild). Nothing is flagged without that click.
local _, ns = ...

local RITUAL_IDS = { [698] = true } -- Ritual of Summoning
local ritualName
local session            -- the group you're in now
local removal            -- what the last system message said happened
local leftAt = 0         -- when you chose to leave
local pendingTargets = {}
local EVAL_DELAY = 2     -- the system message and the roster event arrive in either order

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function isRitual(spellID)
    if RITUAL_IDS[spellID] then return true end
    ritualName = ritualName or spellName(698)
    return ritualName ~= nil and spellID ~= nil and spellName(spellID) == ritualName
end

local function newSession()
    return { started = time(), summons = 0, lastSummon = 0, targets = {}, members = {},
             zone = GetRealZoneText and GetRealZoneText() or "" }
end

local function scanRoster()
    if not IsInGroup() then return end
    session = session or newSession()
    session.raid = IsInRaid()
    for _, unit in ipairs(ns.GroupUnits()) do
        local key, display = ns.UnitKey(unit)
        if key then
            local gkey, gname = ns.UnitGuild(unit)
            local m = session.members[key] or {}
            m.name, m.guildKey, m.guild = display, gkey or m.guildKey, gname or m.guild
            session.members[key] = m
            if UnitIsGroupLeader(unit) then session.leader = key end
        end
    end
end

local function evaluate()
    if IsInGroup() or not session then return end
    local s, kind = session, removal
    session, removal = nil, nil
    if not kind then
        if time() - leftAt <= 10 then return end -- you left on your own
        kind = "disband"                          -- dropped with no message: treat like a disband
    end
    if kind == "left" then return end
    ns.ConsiderKick(s, kind)
end

local function later() C_Timer.After(EVAL_DELAY, evaluate) end

function ns.ConsiderKick(s, kind)
    local st = ns.db.settings
    if kind == "kick" and not st.promptOnKick then return end
    if kind == "disband" and not st.promptOnDisband then return end
    if (s.summons or 0) < st.minSummons then return end
    if time() - (s.lastSummon or 0) > st.summonWindowMinutes * 60 then return end
    if not s.leader or s.leader == ns.playerKey then return end -- you led the group yourself
    local leader = s.members[s.leader] or {}
    ns.ShowKickPrompt({
        key = s.leader, name = leader.name or s.leader, guildKey = leader.guildKey, guild = leader.guild,
        summons = s.summons, zone = s.zone, kind = kind, lastSummon = s.lastSummon, targets = s.targets,
    })
end

-- group lifecycle
ns.On("GROUP_JOINED", function()
    session, removal = newSession(), nil
    scanRoster()
end)
ns.On("GROUP_ROSTER_UPDATE", function()
    if IsInGroup() then scanRoster() elseif session then later() end
end)
ns.On("PARTY_LEADER_CHANGED", scanRoster)
ns.On("GROUP_LEFT", function() if session then later() end end)

ns.On("CHAT_MSG_SYSTEM", function(msg)
    if not msg or ns.IsSecret(msg) then return end
    if msg == ERR_UNINVITE_YOU then
        removal = "kick"
    elseif msg == ERR_GROUP_DISBANDED then
        removal = removal or "disband"
    elseif msg == ERR_LEFT_GROUP_YOU or (ERR_RAID_YOU_LEFT and msg == ERR_RAID_YOU_LEFT) then
        removal = "left"
    else
        return
    end
    if session then later() end
end)

local function markLeave() leftAt = time() end

ns.OnReady(function()
    if type(LeaveParty) == "function" then hooksecurefunc("LeaveParty", markLeave) end
    if C_PartyInfo and type(C_PartyInfo.LeaveParty) == "function" then hooksecurefunc(C_PartyInfo, "LeaveParty", markLeave) end
    if IsInGroup() then scanRoster() end -- logged in (or /reload) while grouped
end)

-- summons
ns.On("UNIT_SPELLCAST_SENT", function(unit, target, castGUID, spellID)
    if unit ~= "player" or not ns.isWarlock or not castGUID then return end
    if isRitual(spellID) then pendingTargets[castGUID] = target end
end)

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
    if unit ~= "player" or not ns.isWarlock or not isRitual(spellID) or not IsInGroup() then return end
    scanRoster()
    session.summons = session.summons + 1
    session.lastSummon = time()
    session.zone = (GetRealZoneText and GetRealZoneText()) or session.zone
    local t = castGUID and pendingTargets[castGUID]
    if castGUID then pendingTargets[castGUID] = nil end
    if t and t ~= "" then table.insert(session.targets, t) end
end)

-- used by the tests
function ns.CurrentSession() return session end
