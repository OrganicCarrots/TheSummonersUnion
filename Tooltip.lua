-- tooltip: red line on flagged players
local _, ns = ...

local function addLines(tooltip, unit)
    if not ns.db or not unit or not UnitIsPlayer(unit) then return end
    local key = ns.UnitKey(unit)
    if not key or key == ns.playerKey then return end
    local s = ns.Status(key, ns.UnitGuild(unit))
    if not s.flagged then return end
    tooltip:AddLine("Summoners Union: " .. ns.Describe(s), 1, 0.3, 0.3, true)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        local _, unit = tooltip:GetUnit()
        addLines(tooltip, unit)
    end)
elseif GameTooltip then
    GameTooltip:HookScript("OnTooltipSetUnit", function(self)
        local _, unit = self:GetUnit()
        addLines(self, unit)
    end)
end
