local FLAG = "WaypointUIRestedXPSync"
local LEGACY_FLAG = "WaypointRestedXPBridge"
local frame = CreateFrame("Frame")
local elapsed = 0
local status = "Waiting for addons"
local lastTrackingRepair = -math.huge

local function CleanText(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
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
    local function IsObjective(objective)
        return objective and not objective.completed and not objective.skip and not objective.hidden
            and (not objective.step or objective.step == step)
            and objective.tag ~= "goto" and objective.tag ~= "target" and objective.tag ~= "mob"
    end
    local source = IsObjective(element.parent) and element.parent or nil
    local text = ElementText(rxp, source)
    -- Generated map points may link to a static instruction rather than the
    -- quest objective. Prefer that step's live progress over the static note.
    if step and (not source or not source.tag or source.tag == "goto") then
        for _, objective in ipairs(step.elements or step) do
            if IsObjective(objective) and (objective.tag == "complete" or objective.tag == "collect"
                or objective.tag == "collectmultiple" or objective.tag == "kill") then
                local liveText = ElementText(rxp, objective)
                if liveText then text = liveText; source = objective; break end
            end
        end
    end
    if not text and IsObjective(element) then source = element; text = ElementText(rxp, source) end
    if not text and step then
        -- Only use unfinished objectives from the selected destination's step.
        -- Guide data may store objectives directly in the step array. Include
        -- use/vendor/gossip and instruction notes, not only quest-log tags.
        for _, objective in ipairs(step.elements or step) do
            if IsObjective(objective) then
                text = ElementText(rxp, objective)
                if text then source = objective; break end
            end
        end
    end
    if not text and step then
        -- Read processed UI instructions from this destination's step only;
        -- concurrent sticky objectives can belong to a different location.
        local window = rxp.RXPFrame or _G.RXPFrame
        for _, holder in pairs(window and window.CurrentStepFrame and window.CurrentStepFrame.framePool or {}) do
            if holder.step == step and (not holder.IsShown or holder:IsShown()) then
                for _, row in ipairs(holder.elements or {}) do
                    local data = row.element
                    if row:IsShown() and (not data or IsObjective(data)) then
                        local widget = row.text
                        text = widget and widget.GetText and CleanText(widget:GetText())
                        if text then source = data or element; break end
                    end
                end
            end
            if text then break end
        end
    end
    -- Coordinate elements remain usable after their arrival flag is set, but
    -- their travel text must not hide an unfinished objective at that location.
    if not text then source = element; text = ElementText(rxp, source) end
    text = text or CleanText(element.title) or "RestedXP"
    -- Location details belong in the guide window, not the world marker.
    -- Keep the action/name first and preserve a trailing objective count.
    local progress = text:match("(%d+%s*/%s*%d+)%s*$")
    local shortened = text:match("^(.-)%s+[Dd]ownstairs")
        or text:match("^(.-)%s+[Uu]pstairs")
        or text:match("^(.-)%s+[Ii]nside the ")
    if shortened and #shortened >= 15 then text = shortened end
    -- Keep the world marker compact; do not split a UTF-8 character.
    if #text > 52 then
        local cut = progress and 38 or 49
        while cut > 0 and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do
            cut = cut - 1
        end
        local prefix = text:sub(1, cut)
        local boundary = prefix:match("^(.*)%s+%S*$")
        if boundary and #boundary >= 20 then prefix = boundary end
        text = prefix:gsub("%s+$", "") .. "..."
        if progress then text = text .. " " .. progress end
    end

    return text, source
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
    -- A .goto or plain instruction can carry the label while a separate
    -- .complete/.collect element describes the task at that location.
    -- Resolve the icon from this pin's step, never another active step.
    local step = element.step or (source and source.step)
    for _, objective in ipairs(step and (step.elements or step) or {}) do
        local action = objective.tag
        if not objective.skip and not objective.hidden
            and (action == "complete" or action == "collect" or action == "collectmultiple"
                or action == "combat" or action == "kill") then
            return root .. "IncompleteQuest", "TEXTURE", true
        end
    end
    -- Rendered counters may have no objective tag (for example "5/5 Blood").
    local text = ElementText(rxp, source) or ElementText(rxp, element)
    if text and text:find("%d+%s*/%s*%d+") then
        return root .. "IncompleteQuest", "TEXTURE", true
    end
    return root .. "Navigation", "TEXTURE", true
end

local function Navigation()
    return WaypointUIAPI and WaypointUIAPI.Navigation
end

local function ClearOwned()
    local nav = Navigation()
    if nav and (nav.IsUserNavigationFlagged(FLAG) or nav.IsUserNavigationFlagged(LEGACY_FLAG)
        or nav.IsUserNavigationFlagged("WaypointRXPBridge")) then
        -- Do not advance Waypoint UI's queued pins when our guide target ends.
        nav.ClearUserNavigation(false, true)
    end
    if nav and nav.GetAllPins and nav.ClearPin then
        local ids = {}
        for id, pin in pairs(nav.GetAllPins() or {}) do
            if pin.flags == FLAG then ids[#ids + 1] = id end
        end
        for _, id in ipairs(ids) do nav.ClearPin(id) end
    end
end

local function GetRXP()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    return ace and ace:GetAddon("RXPGuides", true)
end

local function Valid(map, x, y)
    return type(map) == "number" and type(x) == "number" and type(y) == "number"
        and x >= 0 and x <= 1 and y >= 0 and y <= 1
        and C_Map.CanSetUserWaypointOnMap(map)
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

local function Same(a, b)
    -- Match Waypoint UI's tolerance for native waypoint precision.
    return type(a) == "number" and math.abs(a - b) < 0.0005
end

local function Destinations(rxp)
    local steps, seen = {}, {}
    local function Add(step)
        if step and step.active and not step.completed and not seen[step] then
            seen[step] = true; steps[#steps + 1] = step
        end
    end
    local window = rxp.RXPFrame or _G.RXPFrame
    -- Use the same live step frames as Compact. Old guide entries can retain
    -- active flags and sticky objectives after disappearing from the display.
    local visible = window and window.CurrentStepFrame and window.CurrentStepFrame.framePool
    for _, holder in pairs(visible or {}) do
        if holder.IsShown and holder:IsShown() then Add(holder.step) end
    end
    local authoritative = #steps > 0
    if not authoritative and window and window.activeSteps then
        for _, step in pairs(window.activeSteps) do Add(step) end
        authoritative = true
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
                and not (element.parent and (element.parent.completed or element.parent.skip)) then
                used[element] = true
                if belongs then
                    -- Attach context without modifying RXP's generated data.
                    element = setmetatable({step = step}, {__index = element})
                end
                candidates[#candidates + 1] = element
            end
        end
        -- Keep RXP's current choice within this step, then its ordered pins.
        Candidate(arrow)
        for _, element in ipairs(rxp.activeWaypoints or {}) do Candidate(element) end
        for _, element in ipairs(step.centerPins or {}) do Candidate(element, true) end
        for _, element in ipairs(step.elements or step) do Candidate(element, true) end
        for _, element in ipairs(candidates) do
            if Coordinates(element) then result[#result + 1] = element; break end
        end
    end
    -- RXP's chosen arrow is authoritative even when its generated waypoint
    -- is absent from the active-step element arrays. Keep the working primary
    -- destination rather than clearing it when no secondary pins can be found.
    if #result == 0 and arrow and not arrow.hidden
        and ((not authoritative and not arrow.step) or seen[arrow.step])
        and Coordinates(arrow) then result[1] = arrow end
    return result
end

local function SyncPins(nav, destinations)
    if not nav.GetAllPins or not nav.NewPin or not nav.ClearPin then return end
    local existing, wanted = nav.GetAllPins() or {}, {}
    for order, element in ipairs(destinations) do
        local map,x,y = Coordinates(element)
        if map then
            local id = FLAG .. ":" .. tostring(element.step and element.step.index or order)
            wanted[id] = true
            local name = element.name
            local icon, kind, recolor = element.icon, element.iconType, element.recolor
            local old = existing[id]
            local moved = not old or old.mapID ~= map or not Same(old.x,x) or not Same(old.y,y)
            local changed = moved or old.name ~= name or old.iconTexture ~= icon or old.iconType ~= kind
                or old.requestRecolor ~= recolor
            if changed then
                local pin = nav.NewPin({id = id, name = name, mapID = map, x = x*100, y = y*100,
                    flags = FLAG, iconTexture = icon, iconType = kind, requestRecolor = recolor,
                    suppressAudio = true})
            end
        end
    end
    local remove = {}
    for id,pin in pairs(existing) do
        if pin.flags == FLAG and not wanted[id] then remove[#remove + 1] = id end
    end
    for _,id in ipairs(remove) do nav.ClearPin(id) end
end

local function Sync()
    if not WaypointUIRestedXPSyncDB or not WaypointUIRestedXPSyncDB.enabled then
        ClearOwned()
        status = "Disabled"
        return
    end
    local nav, rxp = Navigation(), GetRXP()
    if not nav or not rxp then status = "Waiting for addons"; return end
    local destinations = Destinations(rxp)
    if not rxp.currentGuide then destinations = {} end
    -- Resolve once before emitting Waypoint UI callbacks, so the stored pins
    -- and world marker receive the same objective/coordinate snapshot.
    for i, destination in ipairs(destinations) do
        local map, x, y = Coordinates(destination)
        local name, source = DestinationLabel(rxp, destination)
        local icon, kind, recolor = DestinationIcon(rxp, source, destination)
        destinations[i] = {step = destination.step, zone = map, zx = x, zy = y,
            name = name, icon = icon, iconType = kind, recolor = recolor}
    end
    SyncPins(nav, destinations)
    local element = destinations[1]
    if not rxp.currentGuide or not element
        or element.hidden or (element.step and not element.step.active) then
        ClearOwned()
        status = "No active RestedXP destination with coordinates"
        return
    end
    local map, x, y = Coordinates(element)
    if not map then
        ClearOwned()
        status = "RestedXP destination cannot be displayed on this map"
        return
    end
    local name = element.name
    local icon, iconType, recolor = element.icon, element.iconType, element.recolor
    local current = nav.GetUserNavigation()
    local owned = nav.IsUserNavigationFlagged(FLAG)
    local native = C_Map.GetUserWaypoint()
    if owned and current and current.mapID == map and Same(current.x, x)
        and Same(current.y, y) and native
        and native.uiMapID == map and native.position
        and Same(native.position.x, x) and Same(native.position.y, y) then
        -- RXP can supertrack a quest independently. Restore tracking without
        -- emitting another NewUserNavigation event and rebuilding the marker.
        if not C_SuperTrack.IsSuperTrackingUserWaypoint()
            and GetTime() - lastTrackingRepair >= 1 then
            lastTrackingRepair = GetTime()
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        if (current.name == name and current.iconTexture == icon
            and current.iconType == iconType and current.requestRecolor == recolor) then
            status = "Following " .. name
            return
        end
    end
    local result = nav.NewUserNavigation({
        -- NewUserNavigation takes 0..100 input and returns 0..1 session data.
        name = name, mapID = map, x = x * 100, y = y * 100, flags = FLAG,
        suppressAudio = true, iconTexture = icon, iconType = iconType,
        requestRecolor = recolor,
    })
    status = result and ("Following " .. name) or "Waypoint UI could not create the destination"
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    if type(WaypointUIRestedXPSyncDB) ~= "table" and type(WaypointRXPBridgeDB) == "table" then
        WaypointUIRestedXPSyncDB = WaypointRXPBridgeDB
    end
    WaypointRXPBridgeDB = nil
    if type(WaypointUIRestedXPSyncDB) ~= "table" and type(WaypointRestedXPBridgeDB) == "table" then
        WaypointUIRestedXPSyncDB = WaypointRestedXPBridgeDB
    end
    WaypointRestedXPBridgeDB = nil
    if type(WaypointUIRestedXPSyncDB) ~= "table" then WaypointUIRestedXPSyncDB = {} end
    if WaypointUIRestedXPSyncDB.enabled == nil then WaypointUIRestedXPSyncDB.enabled = true end
    -- One-time user-requested setting; later adjustments in /wp remain yours.
    if not WaypointUIRestedXPSyncDB.fixedScaleApplied and type(WaypointDB_Global) == "table" then
        WaypointDB_Global.WaypointUseWorldScale = false
        WaypointUIRestedXPSyncDB.fixedScaleApplied = true
    end
    if not WaypointUIRestedXPSyncDB.multiPinsApplied and type(WaypointDB_Global) == "table" then
        WaypointDB_Global.CustomMapPinsEnabled = true
        WaypointUIRestedXPSyncDB.multiPinsApplied = true
    end
    Sync()
end)
frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.25 then return end
    elapsed = 0
    Sync()
end)

SLASH_WAYPOINTUIRESTEDXPSYNC1 = "/wrxs"
SlashCmdList.WAYPOINTUIRESTEDXPSYNC = function(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "on" or command == "off" then
        WaypointUIRestedXPSyncDB = WaypointUIRestedXPSyncDB or {}
        WaypointUIRestedXPSyncDB.enabled = command == "on"
        Sync()
    elseif command ~= "" and command ~= "status" then
        print("WaypointUIRestedXPSync: /wrxs on | off | status")
        return
    end
    local rxp = GetRXP()
    local destinations = rxp and Destinations(rxp) or {}
    local element = destinations[1]
    local step = element and element.step and element.step.index
    print("WaypointUIRestedXPSync: " .. status .. (step and (" (primary step " .. step .. ")") or "")
        .. " — " .. #destinations .. " active destinations")
end
