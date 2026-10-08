local _, ns = ...
local A = ns.RestedXP
local FLAG = "WaypointUIRestedXPSync"
local frame = CreateFrame("Frame")
local db, timer, queued, applying, paused, lastError
local snapshot = {pins = {}, rejected = {}}
local status = "Waiting for login"
local Run, Queue
local function Say(text) print(FLAG .. ": " .. text) end
local function Nav() return WaypointUIAPI and WaypointUIAPI.Navigation end
local function Same(a,b) return type(a) == "number" and type(b) == "number" and math.abs(a-b) < 0.0005 end
local function Position(a,b) return a and b and a.mapID == b.mapID and Same(a.x,b.x) and Same(a.y,b.y) end
local function Equal(a,b)
    return Position(a,b) and a.name == b.name and a.iconTexture == b.iconTexture
        and a.iconType == b.iconType and a.requestRecolor == b.requestRecolor
end
local function Owned(pin)
    return pin and (pin.flags == FLAG or pin.flags == "WaypointRXPBridge" or pin.flags == "WaypointRestedXPBridge")
end
local function Clear(preserveManual)
    local nav = Nav()
    if not nav then return end
    if nav.GetUserNavigation and nav.ClearUserNavigation and Owned(nav.GetUserNavigation()) then
        nav.ClearUserNavigation(preserveManual == true, true)
    end
    if nav.GetAllPins and nav.ClearPin then
        local remove = {}
        for id,pin in pairs(nav.GetAllPins() or {}) do if Owned(pin) then remove[#remove+1] = id end end
        for _,id in ipairs(remove) do nav.ClearPin(id) end
    end
end
local function Compatible(nav)
    for _,name in ipairs({"GetUserNavigation", "NewUserNavigation", "ClearUserNavigation", "IsPathStepWaypointTracked"}) do
        if type(nav[name]) ~= "function" then return false, "Waypoint UI API unavailable: " .. name end
    end
    if not C_Map or not C_Map.GetUserWaypoint or not C_Map.CanSetUserWaypointOnMap
        or not C_SuperTrack or not C_SuperTrack.SetSuperTrackedUserWaypoint
        or not C_SuperTrack.IsSuperTrackingUserWaypoint then
        return false, "This client lacks required waypoint APIs"
    end
    return true
end
local function Options(pin)
    return {name=pin.name, mapID=pin.mapID, x=pin.x*100, y=pin.y*100,
        flags=FLAG, iconTexture=pin.iconTexture, iconType=pin.iconType,
        requestRecolor=pin.requestRecolor, suppressAudio=true}
end
local function Sync()
    if not db or not db.enabled then return end
    local nav = Nav()
    if not nav then status = "Waiting for Waypoint UI"; return end
    local ok, reason = Compatible(nav)
    if not ok then status = reason; if lastError ~= reason then Say(reason); lastError=reason end; return end
    A.Observe(Queue)
    if paused then status = "Paused for manual navigation; /wrxs resume"; return end
    local current = nav.GetUserNavigation()
    local native = C_Map.GetUserWaypoint()
    local route = Owned(current) and nav.IsPathStepWaypointTracked()
    local nativeMatches = native and native.position and current and native.uiMapID == current.mapID
        and Same(native.position.x,current.x) and Same(native.position.y,current.y)
    if db.mode == "manual" and ((current and not Owned(current)) or (native and not route and not nativeMatches)) then
        paused = true; Clear(true); status = "Paused for manual navigation; /wrxs resume"; return
    end
    snapshot = A.Snapshot()
    local pins = snapshot.pins
    local existing = nav.GetAllPins and nav.GetAllPins() or {}
    local wanted = {}
    if db.multiPins and nav.NewPin and nav.ClearPin then
        for _,pin in ipairs(pins) do
            local id = FLAG .. ":" .. pin.id
            wanted[id] = true
            if not Equal(existing[id],pin) then
                local options = Options(pin); options.id = id
                nav.NewPin(options)
            end
        end
    end
    if nav.ClearPin then
        local remove = {}
        for id,pin in pairs(existing or {}) do if Owned(pin) and not wanted[id] then remove[#remove+1] = id end end
        for _,id in ipairs(remove) do nav.ClearPin(id) end
    end
    local primary = pins[1]
    if not primary then Clear(false); status = "No active destination"; return end
    if Owned(current) and Equal(current,primary) and (route or nativeMatches) then
        if not route and not C_SuperTrack.IsSuperTrackingUserWaypoint() then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        status = "Following " .. primary.name
        return
    end
    local result = nav.NewUserNavigation(Options(primary))
    status = result and ("Following " .. primary.name) or "Waypoint UI rejected the destination"
end
Run = function()
    queued = false
    if applying or not db or not db.enabled then return end
    applying = true
    local ok, err = pcall(Sync)
    applying = false
    if not ok then
        status = "Sync error; /wrxs debug"
        if lastError ~= tostring(err) then lastError=tostring(err); Say(lastError) end
    end
end
Queue = function()
    if not db or not db.enabled or applying or queued then return end
    queued = true
    C_Timer.After(0.1, Run)
end
local function Start()
    if timer then timer:Cancel(); timer=nil end
    if db.enabled then timer=C_Timer.NewTicker(1, Queue); Queue() end
end
local function Version(name)
    return C_AddOns and C_AddOns.GetAddOnMetadata(name,"Version") or "unknown"
end
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("USER_WAYPOINT_UPDATED")
frame:SetScript("OnEvent", function(_,event)
    if event ~= "PLAYER_LOGIN" then Queue(); return end
    WaypointUIRestedXPSyncDB = type(WaypointUIRestedXPSyncDB) == "table" and WaypointUIRestedXPSyncDB
        or type(WaypointRXPBridgeDB) == "table" and WaypointRXPBridgeDB
        or type(WaypointRestedXPBridgeDB) == "table" and WaypointRestedXPBridgeDB or {}
    WaypointRXPBridgeDB, WaypointRestedXPBridgeDB = nil,nil
    db = WaypointUIRestedXPSyncDB
    if db.enabled == nil then db.enabled=true end
    if db.mode ~= "manual" then db.mode="always" end
    if db.multiPins == nil then db.multiPins=db.multiPinsApplied == true end
    db.schema = 2
    -- Existing Waypoint UI preferences are preserved; fresh installs opt in.
    A.Observe(Queue)
    Start()
end)
SLASH_WAYPOINTUIRESTEDXPSYNC1 = "/wrxs"
SlashCmdList.WAYPOINTUIRESTEDXPSYNC = function(message)
    if not db then Say("Waiting for login"); return end
    local command,arg = (message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "on" or command == "off" then
        db.enabled = command == "on"; paused=false
        if not db.enabled then applying=true; Clear(false); applying=false; snapshot={pins={},rejected={}}; status="Disabled" end
        Start()
    elseif command == "resume" then
        paused=false; db.enabled=true
        -- Resume explicitly takes ownership once even in manual-pause mode.
        local mode=db.mode; db.mode="always"; Run(); db.mode=mode; Start()
    elseif command == "mode" and (arg == "always" or arg == "manual") then
        db.mode=arg; paused=false; Queue()
    elseif command == "pins" and (arg == "on" or arg == "off") then
        db.multiPins=arg == "on"
        if db.multiPins and WaypointDB_Global then WaypointDB_Global.CustomMapPinsEnabled=true end
        Queue()
    elseif command == "scale" and (arg == "fixed" or arg == "distance") then
        if WaypointDB_Global then WaypointDB_Global.WaypointUseWorldScale=arg == "distance" end
        Say("Waypoint UI scale set to " .. arg)
    elseif command == "debug" then
        local version,build,_,interface = GetBuildInfo()
        Say("addon=" .. Version(FLAG) .. " client=" .. tostring(version) .. "/" .. tostring(build)
            .. " interface=" .. tostring(interface) .. " RXP=" .. Version("RXPGuides") .. " WUI=" .. Version("WaypointUI"))
        Say("mode=" .. db.mode .. " pins=" .. tostring(db.multiPins) .. " guide=" .. tostring(snapshot.guide))
        for _,pin in ipairs(snapshot.pins) do
            Say("step=" .. pin.step .. " source=" .. pin.source .. " tag=" .. pin.tag
                .. " coordinates=" .. pin.coordinates .. " map=" .. pin.mapID .. " x=" .. pin.x .. " y=" .. pin.y .. " label=" .. pin.name)
        end
        for _,reason in ipairs(snapshot.rejected) do Say(reason) end
        if lastError then Say("Last error: " .. lastError) end
    elseif command ~= "" and command ~= "status" then
        Say("on | off | resume | status | debug | mode always/manual | pins on/off | scale fixed/distance")
        return
    end
    Say(status .. " — " .. #snapshot.pins .. " destinations")
end
