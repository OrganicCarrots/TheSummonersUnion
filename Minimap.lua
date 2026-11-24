-- minimap button and the retail addon compartment entry.
-- left click opens the list, right click opens options
local _, ns = ...

local ICON = "Interface\\Icons\\Spell_Shadow_Twilight"
local EDGE = 5 -- px outside the minimap edge
local RETAIL = WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local button

-- used by both the minimap button and the compartment
function ns.FillTooltip(tt, draggable)
    tt:AddLine(ns.TITLE)
    local warnings = 0
    for _, bucket in ipairs({ "players", "guilds" }) do
        for key in pairs(ns.db.community[bucket]) do
            local _, shown = ns.Community(bucket, key)
            if shown then warnings = warnings + 1 end
        end
    end
    tt:AddLine(("Your flags: %d players, %d guilds"):format(ns.Count(ns.db.players), ns.Count(ns.db.guilds)), 1, 1, 1)
    tt:AddLine(("Union reports you're warned about: %d"):format(warnings), 1, 1, 1)
    tt:AddLine(" ")
    tt:AddLine("Left-click: open the list", 0.7, 0.7, 0.7)
    tt:AddLine("Right-click: options", 0.7, 0.7, 0.7)
    if draggable then tt:AddLine("Drag: move this button", 0.7, 0.7, 0.7) end
    if not ns.db.settings.shareChannel then
        tt:AddLine(" ")
        tt:AddLine("Tip: join the union channel (/su share channel on) so reports reach every union member on your realm.", 1, 0.82, 0, true)
    end
end

local function onClick(mouseButton)
    if mouseButton == "RightButton" then ns.OpenOptions() else ns.ToggleWindow() end
end

-- minimap button
local function position()
    local angle = math.rad(ns.db.settings.minimapAngle or 225)
    local x, y = math.cos(angle), math.sin(angle)
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        -- square minimaps: push it out to the edge
        local d = math.max(math.abs(x), math.abs(y))
        x, y = x / d, y / d
    end
    local w = Minimap:GetWidth() / 2 + EDGE
    local h = Minimap:GetHeight() / 2 + EDGE
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function followCursor()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    -- set directly, SetSetting would refresh the UI every frame while dragging
    ns.db.settings.minimapAngle = math.floor(math.deg(math.atan2(py - my, px - mx)) % 360 + 0.5)
    position()
end

local function create()
    button = CreateFrame("Button", "SummonersUnionMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(31, 31)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- standard minimap button border so it matches everyone else's
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    if RETAIL then
        overlay:SetSize(50, 50)
        background:SetSize(24, 24)
        background:SetPoint("CENTER")
        icon:SetSize(18, 18)
        icon:SetPoint("CENTER")
    else
        overlay:SetSize(53, 53)
        background:SetSize(20, 20)
        background:SetPoint("TOPLEFT", 7, -5)
        icon:SetSize(17, 17)
        icon:SetPoint("TOPLEFT", 7, -6)
    end

    button:SetScript("OnClick", function(_, mouseButton) onClick(mouseButton) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        ns.FillTooltip(GameTooltip, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:LockHighlight()
        self:SetScript("OnUpdate", followCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)
end

function ns.UpdateMinimapButton()
    if not ns.db.settings.showMinimap then
        if button then button:Hide() end
        return
    end
    if not Minimap then return end
    if not button then create() end
    position()
    button:Show()
end

ns.OnReady(ns.UpdateMinimapButton)
ns.Listen("SETTING_CHANGED", function(field)
    if field == "showMinimap" then ns.UpdateMinimapButton() end
end)

-- addon compartment (Retail)
-- hooked up in the TOC (AddonCompartmentFunc), ignored on clients without it.
-- newer clients pass a table instead of the button name
function SummonersUnion_OnAddonCompartmentClick(_, mouseButton)
    if type(mouseButton) == "table" then mouseButton = mouseButton.buttonName end
    onClick(mouseButton)
end

function SummonersUnion_OnAddonCompartmentEnter(_, menuButton)
    local owner = (type(menuButton) == "table" and menuButton.GetObjectType) and menuButton or AddonCompartmentFrame or UIParent
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    ns.FillTooltip(GameTooltip, false)
    GameTooltip:Show()
end

function SummonersUnion_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

-- used by the tests
function ns.MinimapButton() return button end
