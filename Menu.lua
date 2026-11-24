-- right-click menu on players: flag or unflag them and their guild.
-- needs the Menu api, older clients just don't get the entry (hooking their dropdowns taints)
local _, ns = ...

local MENUS = { "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_FRIEND" }

local function who(context)
    local unit = context and context.unit
    if unit and UnitExists(unit) then
        if not UnitIsPlayer(unit) then return end
        local key, display = ns.UnitKey(unit)
        local gk, gn = ns.UnitGuild(unit)
        return key, display, gk, gn
    end
    local name = context and context.name
    if not name or ns.IsSecret(name) or ns.IsSecret(context.server) then return end
    local key, display = ns.PlayerKey(name, context.server)
    local rec = key and ns.db.players[key]
    return key, display, rec and rec.guildKey, rec and rec.guild
end

local function addEntries(_, root, context)
    if not ns.db then return end
    local key, display, gk, gn = who(context)
    if not key or key == ns.playerKey then return end
    local short = display:match("^[^%-]+") or display
    root:CreateDivider()
    local sub = root:CreateButton(ns.TITLE)
    if ns.db.players[key] then
        sub:CreateButton("Unflag " .. short, function()
            if ns.UnflagPlayer(key) then ns.Print("Removed your flag on " .. display .. ".") end
        end)
    else
        sub:CreateButton("Flag " .. short, function() ns.FlagByHand(key, display, gk, gn) end)
    end
    if gk and gn then
        if ns.db.guilds[gk] then
            sub:CreateButton("Unflag guild <" .. gn .. ">", function()
                if ns.UnflagGuild(gk) then ns.Print("Removed your flag on <" .. gn .. ">.") end
            end)
        else
            sub:CreateButton("Flag guild <" .. gn .. ">", function() ns.FlagGuildByHand(gk, gn) end)
        end
    end
end

if Menu and Menu.ModifyMenu then
    for _, tag in ipairs(MENUS) do Menu.ModifyMenu(tag, addEntries) end
end
