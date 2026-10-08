local _, ns = ...
local A = {}
ns.RestedXP = A

local function CleanText(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
    text = text:gsub("|cRXP_[%w_]+", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("%s+", " "):match("^%s*(.-)%s*$")
    if text == "" or text:find("%*quest%*") or text:find("%*npc%*") then return end
    return text
end

local function ElementText(rxp, element)
    if not element then return end
    -- RXP updates .text with objective counts; tooltipText can deliberately
    -- contain only the static instruction. Pooled widgets can lag behind both.
    for _, key in ipairs({"text", "tooltipText", "rawtext"}) do
        local text = element[key]
        if type(text) == "string" and rxp.ReplaceNpcIds then text = rxp.ReplaceNpcIds(text) end
        text = CleanText(text)
        if text then return text end
    end
    local holder = element.frame
    local widget = holder and holder.element == element and holder.text
    local rendered = widget and widget.GetText and CleanText(widget:GetText())
    if rendered then return rendered end
end

local function DestinationLabel(rxp, element)
    local step = element.step
    local original = element.original or element
    local function Active(obj)
        return obj and not obj.completed and not obj.skip and not obj.hidden
            and (not obj.step or obj.step == step)
            and obj.tag ~= "goto" and obj.tag ~= "target" and obj.tag ~= "mob"
    end
    local source, reason
    if Active(original.parent) then source, reason = original.parent, "linked objective"
    elseif Active(original) then source, reason = original, "coordinate objective" end
    -- Only infer a step-wide objective when it is unambiguous. Multiple
    -- unrelated tasks at distinct locations must never borrow each other's text.
    if not source and step then
        local only, count = nil, 0
        for _, obj in ipairs(step.elements or step) do
            if Active(obj) and ElementText(rxp, obj) then only, count = obj, count + 1 end
        end
        if count == 1 then source, reason = only, "sole unfinished objective" end
    end
    source, reason = source or original, reason or "destination instruction"
    local text = ElementText(rxp, source) or CleanText(original.title) or "RestedXP"
    local progress = text:match("%d+%s*/%s*%d+")
    if #text > 72 then
        local suffix = progress and (" · " .. progress) or ""
        local cut = 69 - #suffix
        while cut > 0 and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do cut = cut - 1 end
        local prefix = text:sub(1, cut):gsub("%s+$", "")
        text = prefix .. "..." .. suffix
    end
    return text, source, reason, progress
end

local function DestinationIcon(rxp, source, element)
    local tag = source and source.tag or element.tag
    local root = "Interface\\AddOns\\WaypointUI\\Art\\Icons\\"
    -- Use Waypoint UI's own artwork for the familiar quest symbols.
    if tag == "accept" or tag == "acceptmultiple" or tag == "daily" then
        return root .. "AvailableQuest", "TEXTURE", true
    elseif tag == "turnin" or tag == "turninmultiple" or tag == "dailyturnin" then
        return root .. "CompleteQuest", "TEXTURE", true
    end
    if tag == "complete" or tag == "collect" or tag == "collectmultiple"
        or tag == "combat" or tag == "kill" or tag == "use" or tag == "vendor" then
        return root .. "IncompleteQuest", "TEXTURE", true
    end
    -- Rendered counters may have no objective tag (for example "5/5 Blood").
    local text = ElementText(rxp, source) or ElementText(rxp, element)
    if text and text:find("%d+%s*/%s*%d+") then
        return root .. "IncompleteQuest", "TEXTURE", true
    end
    return root .. "Navigation", "TEXTURE", true
end

function A.GetRXP()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    return ace and ace:GetAddon("RXPGuides", true)
end

local function Valid(map, x, y)
    return type(map) == "number" and type(x) == "number" and type(y) == "number"
        and x >= 0 and x <= 1 and y >= 0 and y <= 1
        and x == x and y == y and C_Map.CanSetUserWaypointOnMap(map)
end

local function Coordinates(element)
    local map = element.zone or element.mapID
    local hbd = LibStub and LibStub("HereBeDragons-2.0", true)
    -- RXP uses world coordinates for generated destinations such as corpses.
    if hbd and element.wx and element.wy then
        local candidates = { map, C_Map.GetBestMapForUnit("player") }
        for i = 1, 2 do
            local candidate = candidates[i]
            if type(candidate) == "number" then
                local x, y
                if element.instance and hbd.GetZoneCoordinatesFromWorldInstance then
                    x, y = hbd:GetZoneCoordinatesFromWorldInstance(
                        element.wx, element.wy, element.instance, candidate)
                else
                    x, y = hbd:GetZoneCoordinatesFromWorld(element.wx, element.wy, candidate)
                end
                if Valid(candidate, x, y) then return candidate, x, y end
            end
        end
    end
    if Valid(map, element.zx, element.zy) then return map, element.zx, element.zy end
    local x = type(element.x) == "number" and element.x / 100
    local y = type(element.y) == "number" and element.y / 100
    if Valid(map, x, y) then return map, x, y end
end

local function Destinations(rxp, rejected)
    local steps, seen = {}, {}
    local function Add(step)
        if step and step.active and not step.completed and not seen[step] then
            seen[step] = true; steps[#steps + 1] = step
        end
    end
    local window = rxp.RXPFrame or _G.RXPFrame
    local authoritative = window and type(window.activeSteps) == "table"
    if authoritative then
        for _, step in pairs(window.activeSteps) do Add(step) end
    else
        local visible = window and window.CurrentStepFrame and window.CurrentStepFrame.framePool
        for _, holder in pairs(visible or {}) do
            if holder.IsShown and holder:IsShown() then Add(holder.step) end
        end
        authoritative = #steps > 0
    end
    if not authoritative then
        for _, step in ipairs(rxp.currentGuide and rxp.currentGuide.steps or {}) do Add(step) end
    end
    local arrow = rxp.arrowFrame and rxp.arrowFrame.element
    if #steps == 0 and not authoritative and arrow and not arrow.hidden
        and (not arrow.step or (arrow.step.active and not arrow.step.completed)) then
        return {arrow}
    end
    table.sort(steps, function(a,b) return (a.index or math.huge) < (b.index or math.huge) end)
    local result = {}
    for _, step in ipairs(steps) do
        local candidates, used = {}, {}
        local function Candidate(element, belongs)
            local owner = element and element.step
            local sameStep = owner == step
            if element and not used[element] and (belongs or sameStep) and not element.hidden
                and not element.skip
                and not (element.completed and element.tag and element.tag ~= "goto")
                and not (element.parent and (element.parent.completed or element.parent.skip)) then
                used[element] = true
                if belongs then
                    -- Attach context without modifying RXP's generated data.
                    element = setmetatable({step = step, original = element}, {__index = element})
                end
                candidates[#candidates + 1] = element
            end
        end
        -- Keep RXP's current choice within this step, then its ordered pins.
        Candidate(arrow)
        for _, element in ipairs(rxp.activeWaypoints or {}) do Candidate(element) end
        for _, element in ipairs(step.centerPins or {}) do Candidate(element, true) end
        for _, element in ipairs(step.elements or step) do Candidate(element, true) end
        local found
        for _, element in ipairs(candidates) do
            if Coordinates(element) then result[#result + 1] = element; found = true; break end
        end
        if not found and rejected then rejected[#rejected+1] = "Step " .. tostring(step.index) .. ": no usable unfinished destination" end
    end
    -- RXP's chosen arrow is authoritative even when its generated waypoint
    -- is absent from the active-step element arrays. Keep the working primary
    -- destination rather than clearing it when no secondary pins can be found.
    if #result == 0 and arrow and not arrow.hidden
        and ((not authoritative and not arrow.step) or seen[arrow.step])
        and Coordinates(arrow) then result[1] = arrow end
    return result
end


function A.Snapshot()
    local rxp = A.GetRXP()
    local snapshot = {pins = {}, rejected = {}}
    if not rxp or not rxp.currentGuide then return snapshot end
    local guide = rxp.currentGuide
    snapshot.guide = tostring(guide.group or "") .. ":" .. tostring(guide.name or "")
    for order, destination in ipairs(Destinations(rxp, snapshot.rejected)) do
        local map, x, y = Coordinates(destination)
        if map then
            local name, source, reason, progress = DestinationLabel(rxp, destination)
            local icon, kind, recolor = DestinationIcon(rxp, source, destination)
            local step = destination.step and destination.step.index or order
            snapshot.pins[#snapshot.pins + 1] = {id = snapshot.guide .. ":" .. step,
                step = step, mapID = map, x = x, y = y, name = name,
                iconTexture = icon, iconType = kind, requestRecolor = recolor,
                source = reason, coordinates = destination.wx and "world" or destination.zx and "normalized" or "percentage",
                tag = source and source.tag or "instruction", progress = progress}
        end
    end
    if #snapshot.pins == 0 then snapshot.rejected[1] = "No active step has a usable coordinate destination" end
    return snapshot
end

local hooked = {}
function A.Observe(changed)
    local rxp = A.GetRXP()
    if not rxp or not hooksecurefunc then return end
    for _, name in ipairs({"SetStep", "UpdateMap", "UpdateStepText"}) do
        if type(rxp[name]) == "function" and not hooked[name] then
            hooksecurefunc(rxp, name, changed)
            hooked[name] = true
        end
    end
end
