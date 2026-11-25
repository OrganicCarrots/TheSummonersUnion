-- ui: kick prompt, list window, export/import box
local _, ns = ...

-- prompt
local function flagFromPrompt(d, withGuild)
    if d.test then
        ns.Print("That was a preview; nothing was flagged.")
        return
    end
    local note = (#(d.targets or {}) > 0) and ("summoned " .. table.concat(d.targets, ", ")) or nil
    ns.FlagPlayer(d.key, { name = d.name, guildKey = d.guildKey, guild = d.guild, summons = d.summons,
        zone = d.zone, kind = d.kind, note = note, source = "you" })
    if withGuild and d.guildKey then
        ns.FlagGuild(d.guildKey, { name = d.guild, summons = d.summons, zone = d.zone, kind = d.kind,
            note = "leader " .. (d.name or d.key), source = "you" })
    end
end

-- one time suggestion to join the union channel, it stays opt-in
StaticPopupDialogs["SUMMONERSUNION_CHANNEL"] = {
    text = "The Summoners Union works best when you join the union channel: reports then reach every union member on your realm, not just your guild and groups.\n\nIt's a hidden channel, nothing shows in your chat. Join it now? You can change this any time in the options.",
    button1 = "Join channel",
    button2 = "Not now",
    OnAccept = function() ns.Slash("share channel on") end,
    OnCancel = function() ns.Print("No problem. If you change your mind: /su share channel on, or the options panel.") end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns.SuggestChannel()
    local st = ns.db.settings
    if st.shareChannel or st.channelSuggested then return end
    st.channelSuggested = true
    StaticPopup_Show("SUMMONERSUNION_CHANNEL")
end
ns.OnReady(function() C_Timer.After(20, ns.SuggestChannel) end)

StaticPopupDialogs["SUMMONERSUNION_KICKED"] = {
    text = "%s",
    button1 = "Flag player",
    button2 = "Not now",
    button3 = "Player + guild",
    OnAccept = function(_, data) flagFromPrompt(data, false) end,
    OnAlt = function(_, data) flagFromPrompt(data, true) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}

function ns.ShowKickPrompt(d)
    StaticPopupDialogs.SUMMONERSUNION_KICKED.button3 = d.guildKey and "Player + guild" or nil
    local mins = math.max(0, math.floor((time() - (d.lastSummon or time())) / 60))
    local how = d.kind == "kick" and "removed you from the group" or "disbanded the group"
    local text = ("%s%s %s%s %s after your last summon.\n\nYou cast %d summon%s for them. Flag them as a summon-kicker?"):format(
        d.name, d.guild and (" <" .. d.guild .. ">") or "", how,
        (d.zone and d.zone ~= "") and (" in " .. d.zone) or "",
        mins < 1 and "less than a minute" or (mins .. " minute" .. (mins == 1 and "" or "s")),
        d.summons or 0, (d.summons or 0) == 1 and "" or "s")
    StaticPopup_Show("SUMMONERSUNION_KICKED", text, nil, d)
end

-- list window
local ROWS, ROW_H = 14, 20
local frame, rows, tabButtons, tab, items, offset = nil, {}, {}, "all", {}, 0

local function collect()
    local out = {}
    if tab == "all" or tab == "community" then
        for _, bucket in ipairs({ "players", "guilds" }) do
            for key in pairs(ns.db.community[bucket]) do
                local n, shown, latest, total = ns.Community(bucket, key)
                if n > 0 then
                    out[#out + 1] = { list = "community", key = key, bucket = bucket, n = n, total = total, shown = shown,
                                      latest = latest or {}, when = ((latest and latest.d) or 0) * 86400 }
                end
            end
        end
    end
    for _, list in ipairs({ "players", "guilds" }) do
        if tab == "all" or tab == list then
            for key, rec in pairs(ns.db[list]) do out[#out + 1] = { list = list, key = key, rec = rec, when = rec.when or 0 } end
        end
    end
    table.sort(out, function(a, b) return a.when > b.when end)
    return out
end

local function rowText(it)
    if it.list == "community" then
        local l = it.latest
        local name = (it.bucket == "guilds" and ("<" .. (l.n or it.key) .. ">")) or (l.n or it.key)
        if it.bucket == "players" and l.gn then name = name .. " |cffaaaaaa<" .. l.gn .. ">|r" end
        local state = it.shown and "|cffff5050warning|r" or "|cff999999below threshold|r"
        local classes = ns.ReporterClasses(it.bucket, it.key)
        return name, ("%dx by %s%s, %s"):format(it.total or it.n, ns.Plural(it.n, "member"),
            classes and (" (" .. classes .. ")") or "", state), ns.DayText(l.d)
    end
    local r = it.rec
    local name = r.name or it.key
    if it.list == "guilds" then name = "<" .. name .. ">" elseif r.guild then name = name .. " |cffaaaaaa<" .. r.guild .. ">|r" end
    local what = ns.REASONS[r.kind] or r.kind or ""
    if r.class then what = what .. " as " .. ns.ClassName(r.class) end
    if (r.summons or 0) > 0 then what = what .. ", " .. r.summons .. " summons" end
    if (r.times or 1) > 1 then what = what .. ", x" .. r.times end
    if r.source == "import" then what = what .. " (imported)" end
    if r.private then what = what .. " (private)" end
    local why = r.reason or r.note
    if why and ns.db.settings.showReasons then what = what .. ' |cffaaaaaa"' .. why:gsub("|", "||") .. '"|r' end
    return name, what, ns.TimeText(r.when)
end

local function refresh()
    if not frame or not frame:IsShown() then return end
    items = collect()
    offset = math.max(0, math.min(offset, #items - ROWS))
    for i = 1, ROWS do
        local row, it = rows[i], items[offset + i]
        row.item = it
        if it then
            local a, b, c = rowText(it)
            row.name:SetText(a)
            row.what:SetText(b)
            row.date:SetText(c)
            if it.list == "community" then row.remove:Hide() else row.remove:Show() end
            row:Show()
        else
            row:Hide()
        end
    end
    local communityN = ns.Count(ns.db.community.players) + ns.Count(ns.db.community.guilds)
    frame.summary:SetText(("Your flags: %d players, %d guilds   Community reports: %d"):format(
        ns.Count(ns.db.players), ns.Count(ns.db.guilds), communityN))
    frame.page:SetText(#items > ROWS and ("%d-%d of %d, scroll for more"):format(offset + 1, math.min(offset + ROWS, #items), #items)
        or (#items == 0 and "Nothing here yet." or ""))
end

local function button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function makeMovable(f, globalName)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, globalName) -- close with Escape
end

local function build()
    frame = CreateFrame("Frame", "SummonersUnionFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(640, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    makeMovable(frame, "SummonersUnionFrame")
    frame:SetScript("OnShow", refresh)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -6)
    title:SetText(ns.TITLE)

    local tabs = { { "all", "All" }, { "players", "Players" }, { "guilds", "Guilds" }, { "community", "Community" } }
    for i, t in ipairs(tabs) do
        local b = button(frame, t[2], 100, function()
            tab, offset = t[1], 0
            refresh()
        end)
        b:SetPoint("TOPLEFT", 14 + (i - 1) * 104, -30)
        tabButtons[t[1]] = b
    end

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        refresh()
    end)
    frame.page = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.page:SetPoint("TOPRIGHT", -16, -36)

    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(604, ROW_H)
        row:SetPoint("TOPLEFT", 18, -60 - (i - 1) * ROW_H)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 0, 0)
        row.name:SetWidth(190)
        row.name:SetJustifyH("LEFT")
        row.what = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.what:SetPoint("LEFT", 195, 0)
        row.what:SetWidth(285)
        row.what:SetJustifyH("LEFT")
        row.what:SetWordWrap(false)
        row.date = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.date:SetPoint("LEFT", 484, 0)
        row.date:SetWidth(62)
        row.date:SetJustifyH("LEFT")
        row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.remove:SetSize(54, 18)
        row.remove:SetPoint("RIGHT", 0, 0)
        row.remove:SetText("Remove")
        row.remove:SetScript("OnClick", function()
            local it = row.item
            if not it then return end
            if it.list == "players" then ns.UnflagPlayer(it.key) elseif it.list == "guilds" then ns.UnflagGuild(it.key) end
        end)
        -- long reasons get cut off in the row, the full text is on hover
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local why = self.item and self.item.rec and (self.item.rec.reason or self.item.rec.note)
            if not why then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.name:GetText(), 1, 1, 1)
            GameTooltip:AddLine((why:gsub("|", "||")), nil, nil, nil, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = row
    end

    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.summary:SetPoint("BOTTOMLEFT", 16, 18)
    button(frame, "Import", 80, function() ns.ShowImport() end):SetPoint("BOTTOMRIGHT", -14, 12)
    button(frame, "Export", 80, function() ns.ShowExport() end):SetPoint("BOTTOMRIGHT", -98, 12)
    button(frame, "Options", 80, function()
        frame:Hide() -- otherwise it covers the settings window
        ns.OpenOptions()
    end):SetPoint("BOTTOMRIGHT", -182, 12)

    ns.Listen("FLAGS_CHANGED", refresh)
end

function ns.ToggleWindow()
    if not frame then build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- used by the tests
function ns.ListWindow() return frame, rows, tabButtons end

-- export / import box
local box

local function buildBox()
    box = CreateFrame("Frame", "SummonersUnionIO", UIParent, "BasicFrameTemplateWithInset")
    box:SetSize(520, 340)
    box:SetPoint("CENTER", 0, 30)
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:Hide()
    makeMovable(box, "SummonersUnionIO")
    box.title = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.title:SetPoint("TOP", 0, -6)
    box.help = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    box.help:SetPoint("TOPLEFT", 16, -30)
    box.help:SetWidth(488)
    box.help:SetJustifyH("LEFT")

    -- bordered so it's clear where the text goes, and a click anywhere in it puts the cursor in the box
    local area = CreateFrame("Frame", nil, box, BackdropTemplateMixin and "BackdropTemplate" or nil)
    area:SetPoint("TOPLEFT", 12, -62)
    area:SetPoint("BOTTOMRIGHT", -12, 42)
    if area.SetBackdrop then
        area:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        area:SetBackdropColor(0, 0, 0, 0.8)
        area:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    area:EnableMouse(true)

    local sf = CreateFrame("ScrollFrame", "SummonersUnionIOScroll", area, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)
    sf:EnableMouse(true)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(450)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(eb)
    box.edit = eb

    box.hint = area:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    box.hint:SetPoint("CENTER")
    box.hint:SetText("Click here, then press Ctrl+V to paste")
    local function updateHint()
        if eb:GetText() == "" then box.hint:Show() else box.hint:Hide() end
    end
    box.updateHint = updateHint
    eb:SetScript("OnTextChanged", updateHint)
    local function focus() eb:SetFocus() end
    area:SetScript("OnMouseDown", focus)
    sf:SetScript("OnMouseDown", focus)

    box.action = button(box, "Close", 100, function() box:Hide() end)
    box.action:SetPoint("BOTTOMRIGHT", -14, 12)
end

function ns.ShowExport()
    if not box then buildBox() end
    box.title:SetText("Export your flags")
    box.help:SetText("Press Ctrl+C to copy, then share it. Others paste it into /su import. Imported flags stay theirs to remove.")
    box.edit:SetText(ns.Export(ns.db))
    box.updateHint()
    box.action:SetText("Close")
    box.action:SetScript("OnClick", function() box:Hide() end)
    box:Show()
    box.edit:SetFocus()
    box.edit:HighlightText()
end

function ns.ShowImport()
    if not box then buildBox() end
    box.title:SetText("Import flags")
    box.help:SetText("Paste a Summoners Union export below (Ctrl+V), then press Import. Flags you already have are kept as they are.")
    box.edit:SetText("")
    box.updateHint()
    box.action:SetText("Import")
    box.action:SetScript("OnClick", function()
        local ok, res = ns.ImportText(box.edit:GetText())
        if ok then
            ns.Print(("Imported %d player and %d guild flag(s); %d you already had."):format(res.players, res.guilds, res.skipped))
            box:Hide()
        else
            ns.Print("|cffff5050Import failed:|r " .. tostring(res) .. ".")
        end
    end)
    box:Show()
    box.edit:SetFocus()
end
