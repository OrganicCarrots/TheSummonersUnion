-- export/import as plain text. no game API in here so the tests cover all of it
local _, ns = ...

local HEADER = "SummonersUnion:1"
local SEP = "~"

local function clean(s) return (tostring(s or ""):gsub("[~|\r\n]", " ")) end

-- adler-32 style checksum, stays exact with lua 5.1 numbers
local function checksum(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%04x%04x", b, a)
end
ns.Checksum = checksum

local function line(kind, key, r)
    return table.concat({
        kind, clean(key), clean(r.name), clean(r.guildKey), clean(r.guild),
        tostring(tonumber(r.summons) or 0), tostring(math.floor((r.when or 0) / 86400)), clean(r.kind or "manual"),
        clean(r.class),
    }, SEP)
end

function ns.Export(db)
    local lines = {}
    for key, r in pairs(db.players or {}) do lines[#lines + 1] = line("P", key, r) end
    for key, r in pairs(db.guilds or {}) do lines[#lines + 1] = line("G", key, r) end
    table.sort(lines)
    local body = table.concat(lines, "\n")
    return HEADER .. "\n" .. body .. "\n#" .. checksum(body)
end

local function field(v) if v ~= nil and v ~= "" then return v end end

-- returns a list of { kind = "P"|"G", key, rec }, or nil + reason
function ns.ParseExport(text)
    text = tostring(text or ""):gsub("\r", "")
    local header, body, sum = text:match("^%s*(SummonersUnion:%d+)\n(.*)\n#(%x+)%s*$")
    if not header then return nil, "that isn't a Summoners Union export" end
    if header ~= HEADER then return nil, "it was made by a newer version of the addon" end
    if checksum(body) ~= sum:lower() then return nil, "the text was changed or cut off (checksum mismatch)" end
    local out = {}
    for ln in (body .. "\n"):gmatch("(.-)\n") do
        if ln ~= "" then
            local f = {}
            for v in (ln .. SEP):gmatch("(.-)" .. SEP) do f[#f + 1] = v end
            local kind, key = f[1], (f[2] or ""):lower()
            -- the realm part can be empty, wow forever has no realms
            local valid = (kind == "P" and key:find("^[^%-]+%-[^%-]*$")) or (kind == "G" and key:find("^.+@.*$"))
            if valid then
                out[#out + 1] = { kind = kind, key = key, rec = {
                    name = field(f[3]), guildKey = field(f[4]) and f[4]:lower(), guild = field(f[5]),
                    summons = math.max(0, math.min(tonumber(f[6]) or 0, 999)),
                    when = (tonumber(f[7]) or 0) * 86400 + 43200, kind = field(f[8]) or "manual",
                    class = f[9] and f[9]:find("^%u+$") and #f[9] <= 12 and f[9] or nil,
                } }
            end
        end
    end
    return out
end
