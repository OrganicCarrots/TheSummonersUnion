-- options panel (Options > AddOns). plain frames so the same code works on classic and retail
local _, ns = ...

local COL_W = 280
local LEFT_X, RIGHT_X = 16, 316

local panel, category
local controls = {}

local function tooltipFor(frame, title, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function header(x, y, text)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function checkbox(x, y, field, label, tip)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    -- own label, the template's text region is named differently between clients
    cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb.label:SetText(label)
    cb:SetScript("OnClick", function(self) ns.SetSetting(field, self:GetChecked() and true or false) end)
    tooltipFor(cb, label, tip)
    cb.Refresh = function(self) self:SetChecked(ns.db.settings[field] and true or false) end
    controls[field] = cb
    return cb
end

-- label with -/+ buttons that step through a list of values.
-- zeroIsNever: 0 means never and sorts last
local function stepper(x, y, field, label, values, format, tip, zeroIsNever)
    local function rank(v)
        if zeroIsNever and v == 0 then return math.huge end
        return v
    end
    local f = CreateFrame("Frame", nil, panel)
    f:SetSize(COL_W, 24)
    f:SetPoint("TOPLEFT", x, y)
    f:EnableMouse(true)
    f.label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.label:SetPoint("LEFT", 4, 0)
    f.label:SetText(label)
    f.plus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.plus:SetSize(24, 20)
    f.plus:SetPoint("RIGHT", 0, 0)
    f.plus:SetText("+")
    f.value = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.value:SetPoint("RIGHT", f.plus, "LEFT", -4, 0)
    f.value:SetWidth(66)
    f.value:SetJustifyH("CENTER")
    f.minus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.minus:SetSize(24, 20)
    f.minus:SetPoint("RIGHT", f.value, "LEFT", -4, 0)
    f.minus:SetText("-")

    -- step from the current value so custom values from /su set still work
    function f.Step(dir)
        local cur = rank(ns.db.settings[field] or 0)
        local pick
        if dir > 0 then
            for i = 1, #values do
                if rank(values[i]) > cur then pick = values[i]; break end
            end
        else
            for i = #values, 1, -1 do
                if rank(values[i]) < cur then pick = values[i]; break end
            end
        end
        if pick then ns.SetSetting(field, pick) end
    end
    f.minus:SetScript("OnClick", function() f.Step(-1) end)
    f.plus:SetScript("OnClick", function() f.Step(1) end)
    tooltipFor(f, label, tip)
    f.Refresh = function()
        local cur = ns.db.settings[field] or 0
        f.value:SetText(format(cur))
        f.minus:SetEnabled(rank(cur) > rank(values[1]))
        f.plus:SetEnabled(rank(cur) < rank(values[#values]))
    end
    controls[field] = f
    return f
end

local function button(text, width, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function refresh()
    if not ns.db then return end
    for _, c in pairs(controls) do c:Refresh() end
end

StaticPopupDialogs["SUMMONERSUNION_RESET"] = {
    text = "Put all The Summoners Union options back to their defaults? Your flags and reports are kept.",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function()
        ns.ResetSettings()
        ns.Print("Options are back to their defaults.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function minutes(v) return v .. " min" end
local function plain(v) return tostring(v) end
local function days(v) return v == 0 and "Never" or (v .. " days") end

local function build()
    panel = CreateFrame("Frame", "SummonersUnionOptions")
    panel.name = ns.TITLE

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", LEFT_X, -16)
    title:SetText(ns.TITLE)
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(580)
    sub:SetJustifyH("LEFT")
    sub:SetText(("Version %s. Changes apply right away. Hover over an option for details; /su help lists the commands."):format(ns.VERSION))

    -- left column
    header(LEFT_X, -70, "Summon-kick detection (warlocks)")
    checkbox(LEFT_X, -90, "promptOnKick", "Ask to flag after a summon-kick",
        "If you're removed from a group soon after summoning for it, ask whether to flag the leader. Nothing is flagged unless you click.")
    checkbox(LEFT_X, -116, "promptOnDisband", "Ask after a disband, too",
        "Also ask when the group is disbanded (or you're dropped with no message) soon after you summoned.")
    stepper(LEFT_X, -146, "summonWindowMinutes", "Kick must come within", { 5, 10, 15, 20, 25, 30, 45, 60, 90, 120 }, minutes,
        "How soon after your last summon a kick or disband counts.")
    stepper(LEFT_X, -174, "minSummons", "Summons needed", { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, plain,
        "How many Rituals of Summoning you must have finished in that group before you're asked.")

    header(LEFT_X, -214, "Warnings")
    checkbox(LEFT_X, -234, "warnOnInvite", "Warn on invites from flagged players",
        "Show a raid warning when a flagged player, or a member of a flagged guild, invites you.")
    checkbox(LEFT_X, -260, "warnInGroup", "Warn when one is in your group",
        "Show a raid warning when a flagged player joins your group, or once per flagged guild.")
    checkbox(LEFT_X, -286, "autoDecline", "Decline their invites automatically",
        "Decline group invites from flagged players without asking. You still get the warning.")

    header(LEFT_X, -326, "Display")
    checkbox(LEFT_X, -346, "showMinimap", "Show the minimap button",
        "Left-click the button for the list, right-click for these options, drag it to move it. On Retail the addon is also in the AddOns menu by the minimap.")

    -- right column
    header(RIGHT_X, -70, "Sharing")
    checkbox(RIGHT_X, -90, "shareGuild", "Share your flags with your guild",
        "Send your new flags to guildmates who run the addon, and answer their requests for recent flags. Uses hidden addon messages, never chat.")
    checkbox(RIGHT_X, -116, "shareGroup", "Share your flags with your group",
        "Send your new flags to party, raid or dungeon-finder group members who run the addon.")
    checkbox(RIGHT_X, -142, "shareChannel", "Join the union channel (recommended)",
        "For best results, turn this on: reports then reach every union member on your realm, not just your guild and groups. It's a hidden channel, nothing shows in your chat, and it stays off unless you turn it on.")
    checkbox(RIGHT_X, -168, "forwardReports", "Pass on reports from others",
        "When you get a report you haven't seen, pass it on to your other channels a few seconds later, so new reports reach everyone online quickly.")

    header(RIGHT_X, -208, "Community reports")
    stepper(RIGHT_X, -228, "communityThreshold", "Reporters needed", { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, plain,
        "How many different union members must report the same player before you're warned about them. Everything one person passes on counts as one.")
    checkbox(RIGHT_X, -256, "trustGuildmates", "One guildmate's report is enough",
        "Count a report from your own guild as enough on its own, whatever the number above.")
    checkbox(RIGHT_X, -282, "acceptRelays", "Count reports passed on by others",
        "Members pass on reports they got from other members, so the list fills in on its own. These can't be checked, so everything one person passes on counts as one toward the number above, and /su distrust drops everything they filed or passed on.")
    stepper(RIGHT_X, -312, "communityExpiryDays", "Forget reports after", { 30, 60, 90, 180, 365, 0 }, days,
        "Reports from other members stop counting once they're this old, and are cleared out when you log in.", true)

    header(RIGHT_X, -352, "Your flags")
    stepper(RIGHT_X, -372, "flagExpiryDays", "Forget your flags after", { 90, 180, 365, 730, 0 }, days,
        "Forget your own (and imported) flags once they're this old. Checked when you log in or /reload, so you can change your mind first.", true)

    -- not every client shows the settings window's own defaults button
    panel.resetButton = button("Reset to defaults", 130, function() StaticPopup_Show("SUMMONERSUNION_RESET") end)
    panel.resetButton:SetPoint("TOPLEFT", LEFT_X, -406)

    local list = button("Open the list", 110, function() ns.ToggleWindow() end)
    list:SetPoint("TOPLEFT", RIGHT_X, -406)
    local export = button("Export", 80, function() ns.ShowExport() end)
    export:SetPoint("LEFT", list, "RIGHT", 6, 0)
    local import = button("Import", 80, function() ns.ShowImport() end)
    import:SetPoint("LEFT", export, "RIGHT", 6, 0)

    panel:SetScript("OnShow", refresh)
    -- settings apply right away so commit/cancel do nothing, defaults resets ours
    panel.OnCommit = function() end
    panel.OnDefault = function() ns.ResetSettings() end
    panel.OnRefresh = refresh
    panel.okay, panel.cancel, panel.default, panel.refresh = panel.OnCommit, panel.OnCommit, panel.OnDefault, refresh

    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
    ns.Listen("SETTING_CHANGED", function() if panel:IsShown() then refresh() end end)
end

function ns.OpenOptions()
    if not panel then build() end
    if InCombatLockdown and InCombatLockdown() then
        ns.Print("The options can't open during combat. Try again after the fight.")
        return
    end
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- old clients need two calls to actually land on the page
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

ns.OnReady(function() if not panel then build() end end)

-- used by the tests
function ns.OptionControls() return controls, panel, category end
