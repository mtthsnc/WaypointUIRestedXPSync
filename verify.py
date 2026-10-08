"""Lua 5.1 behavior checks with mocked WoW and addon APIs."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

lua = LuaRuntime()
lua.execute('''
SlashCmdList = {}
function print() end
function CreateFrame()
    testFrame = { RegisterEvent = function() end }
    function testFrame:SetScript(name, fn) self[name] = fn end
    return testFrame
end
shown = true
rxp = {currentGuide = {}, arrowFrame = {IsShown = function() return shown end}}
ace = {GetAddon = function() return rxp end}
hbd = {GetZoneCoordinatesFromWorldInstance = function(_, wx, wy, instance, map)
    if instance == 1 and map == 10 then return wx / 100, wy / 100 end
end}
function LibStub(name) if name == "AceAddon-3.0" then return ace else return hbd end end
C_Map = {
    CanSetUserWaypointOnMap = function(map) return map == 10 end,
    GetBestMapForUnit = function() return 10 end,
    GetUserWaypoint = function() return native end,
}
clock = 0
function GetTime() return clock end
C_SuperTrack = {
    IsSuperTrackingUserWaypoint = function() return tracked end,
    SetSuperTrackedUserWaypoint = function(value) tracked = value end,
}
calls, clears = 0, 0
nav = {
    IsUserNavigationFlagged = function(flag) return current and current.flags == flag end,
    GetUserNavigation = function() return current end,
    ClearUserNavigation = function(preserve, suppress)
        assert(preserve == false and suppress == true)
        current, native = nil, nil
        clears = clears + 1
    end,
    NewUserNavigation = function(options)
        assert(options.suppressAudio)
        calls = calls + 1
        current = {name = options.name, flags = options.flags, mapID = options.mapID,
                   x = options.x / 100, y = options.y / 100,
                   iconTexture = options.iconTexture, iconType = options.iconType,
                   requestRecolor = options.requestRecolor}
        native = {uiMapID = options.mapID, position = {x = current.x, y = current.y}}
        tracked = true
        return current
    end,
}
WaypointUIAPI = {Navigation = nav}
function tick() clock = clock + 0.25; testFrame.OnUpdate(testFrame, 0.25) end
''')
lua.execute(Path(__file__).with_name('Sync.lua').read_text(encoding='utf-8'))
lua.execute('''
rxp.arrowFrame.element = {zone = 10, x = 25, y = 70, step = {active = true, index = 1}}
WaypointDB_Global = {WaypointUseWorldScale = true}
testFrame.OnEvent()
assert(WaypointDB_Global.WaypointUseWorldScale == false)
assert(calls == 1 and current.x == 0.25 and current.y == 0.7)
tick(); tick(); assert(calls == 1)
rxp.arrowFrame.element.x = 40; tick(); assert(calls == 2 and current.x == 0.4)
tracked = false; tick(); assert(calls == 2 and tracked)
current = {flags = 'manual'}; shown = false
rxp.arrowFrame.element.step.active = false; tick(); assert(clears == 0)
shown = true; rxp.arrowFrame.element.step.active = true; tick(); assert(calls == 3)
shown = false; tick(); assert(clears == 0 and current ~= nil)
rxp.arrowFrame.element.step.active = false; tick(); assert(clears == 1 and current == nil)
shown = true
rxp.arrowFrame.element = {zone = 10, zx = 0.2, zy = 0.3, step = {active = true}}
tick(); assert(current.x == 0.2 and current.y == 0.3)
rxp.arrowFrame.element = {wx = 30, wy = 40, instance = 1, title = 'Corpse'}
tick(); assert(current.name == 'Corpse' and current.x == 0.3 and current.y == 0.4)
SlashCmdList.WAYPOINTUIRESTEDXPSYNC('off'); assert(current == nil)
local count = calls; tick(); assert(calls == count)
SlashCmdList.WAYPOINTUIRESTEDXPSYNC('on'); assert(current ~= nil)
rxp.arrowFrame.element = {zone = 99, x = 50, y = 50}; tick(); assert(current == nil)
rxp.arrowFrame.element = {zone = 10, x = 120, y = 50}; tick(); assert(current == nil)
rxp.arrowFrame.element = {zone = 10, x = 50, y = 50, step = {active = false}}
tick(); assert(current == nil)
rxp.arrowFrame.element.step.active = true; rxp.currentGuide = nil
tick(); assert(current == nil)
rxp.currentGuide = {}; tick()
local count = calls
current.x = current.x + 0.00001
native.position.x = native.position.x + 0.00001
for i = 1, 240 do tick() end
assert(calls == count, 'unchanged target recreated during one minute of polling')
tracked = false; tick(); assert(calls == count)
rxp.arrowFrame.element = {zone = 10, x = 60, y = 50,
    parent = {text = '|Ticon:16|t|cffffffffTurn in: |Hquest:1|hA Threat Within|h|r'},
    step = {active = true, index = 16}}
tick(); assert(current.name == 'Turn in: A Threat Within')
local count = calls
for i = 1, 20 do tick() end
assert(calls == count)
rxp.arrowFrame.element.parent = {frame = {text = {GetText = function()
    return 'Collect Linen Cloth: 4/8' end}}}
rxp.arrowFrame.element.parent.frame.element = rxp.arrowFrame.element.parent
for i = 1, 4 do tick() end
assert(current.name == 'Collect Linen Cloth: 4/8')
rxp.arrowFrame.element.parent = nil
rxp.arrowFrame.element.step.elements = {
    {tag = 'accept', completed = true, text = 'Old quest'},
    {tag = 'turnin', text = 'Turn in: New quest'},
}
for i = 1, 4 do tick() end
assert(current.name == 'Turn in: New quest')
rxp.arrowFrame.element.step.elements = nil
for i = 1, 4 do tick() end
assert(current.name == 'RestedXP')
rxp.arrowFrame.element.tag = 'accept'
for i = 1, 4 do tick() end
assert(current.iconTexture:find('AvailableQuest', 1, true) and current.requestRecolor)
rxp.arrowFrame.element.tag = 'turnin'
for i = 1, 4 do tick() end
assert(current.iconTexture:find('CompleteQuest', 1, true))
rxp.arrowFrame.element.parent = {tag = 'collect', text = 'Collect: 4/8'}
for i = 1, 4 do tick() end
assert(current.iconTexture:find('IncompleteQuest', 1, true) and current.requestRecolor)
local icon = current.iconTexture
rxp.arrowFrame.element.parent.text = 'Collect: 5/8'
for i = 1, 4 do tick() end
assert(current.iconTexture == icon and current.name == 'Collect: 5/8')
rxp.arrowFrame.element.parent = {tag = 'combat', text = 'Defeat enemies'}
for i = 1, 4 do tick() end
assert(current.iconTexture:find('IncompleteQuest', 1, true))
rxp.arrowFrame.element.parent.icon = '|AQuestNormal:16:16|a'
for i = 1, 4 do tick() end
assert(current.iconTexture:find('IncompleteQuest', 1, true) and current.iconType == 'TEXTURE')
rxp.arrowFrame.element.parent = nil
rxp.arrowFrame.element.tag = 'goto'
for i = 1, 4 do tick() end
assert(current.iconTexture:find('Navigation', 1, true))
local count = calls
for i = 1, 240 do tick() end
assert(calls == count, 'unchanged icon recreated')
shown = false
rxp.arrowFrame.element = {zone = 10, x = 72, y = 35, text = 'Hidden arrow new objective',
    step = {active = true, index = 149}}
tick(); assert(current.x == 0.72 and current.y == 0.35 and current.name == 'Hidden arrow new objective')
rxp.arrowFrame.element.frame = {element = {}, text = {GetText = function() return 'Old pooled objective' end}}
for i=1,4 do tick() end
assert(current.name == 'Hidden arrow new objective')
rxp.ReplaceNpcIds = function(text, element) assert(element == nil); return text end
rxp.arrowFrame.element.text = 'Next step objective'; rxp.arrowFrame.element.x = 73
tick(); assert(current.name == 'Next step objective' and current.x == 0.73)
rxp.arrowFrame.element.parent = {text = 'Talk to the Captured Scarlet Zealot and the Captured Mountaineer downstairs in the back of the building'}
for i = 1, 4 do tick() end
assert(#current.name <= 66 and not current.name:find('downstairs', 1, true))
rxp.arrowFrame.element.parent.text = 'Collect the extremely long named supplies from the enemies in the clearing: 4/8'
for i = 1, 4 do tick() end
assert(current.name:find('4/8', 1, true) and #current.name <= 66)
WaypointDB_Global.WaypointUseWorldScale = true
rxp.arrowFrame.element = {zone = 10, x = 75, y = 35,
    step = {active = true, {tag = 'use', text = "Use Executor's Motivator on Deathguards"}}}
tick(); assert(current.name == "Use Executor's Motivator on Deathguards")
rxp.arrowFrame.element.step = {active = true, {tag = 'vendor', text = 'Talk to Oliver'}}
for i=1,4 do tick() end
assert(current.name == 'Talk to Oliver')
rxp.arrowFrame.element.step = {active = true}
RXPFrame = {CurrentStepFrame = {framePool = {{step = rxp.arrowFrame.element.step,
    elements = {{IsShown = function() return true end,
        text = {GetText = function() return '|cffffffffTalk to Oliver|r' end}}}}}}}
for i=1,4 do tick() end
assert(current.name == 'Talk to Oliver')
testFrame.OnEvent()
assert(WaypointDB_Global.WaypointUseWorldScale == true, 'one-time preference overwrote subsequent user choice')
pins, pinCalls, removed = {manual = {flags = 'manual'}}, 0, 0
nav.GetAllPins = function() return pins end
nav.NewPin = function(options)
    pinCalls = pinCalls + 1
    assert(options.suppressAudio)
    local pin = {name=options.name, mapID=options.mapID, x=options.x/100, y=options.y/100,
        flags=options.flags, iconTexture=options.iconTexture, iconType=options.iconType,
        requestRecolor=options.requestRecolor}
    pins[options.id] = pin
    return pin
end
nav.ClearPin = function(id) pins[id] = nil; removed = removed + 1 end
local first = {index=13,active=true}
local second = {index=14,active=true}
local one = {zone=10,x=20,y=30,text='First active task',step=first}
local two = {zone=10,x=60,y=70,text='Second active task',step=second}
first.elements = {one}; second.elements = {two}
rxp.RXPFrame = {activeSteps = {second, first}}
rxp.activeWaypoints = {two,one}
rxp.arrowFrame.element = two
tick()
assert(current.name == 'First active task' and current.x == 0.2)
assert(pins['WaypointUIRestedXPSync:13'] and pins['WaypointUIRestedXPSync:14'])
local count, primaryCalls = pinCalls, calls
-- RXP can leave a completed flag on coordinate elements; its map code does
-- not exclude them solely for that flag. Generated center pins may lack .step.
one.completed = true
tick(); assert(current.name == 'First active task')
first.elements = {}
first.centerPins = {{zone=10,x=20,y=30,text='First active task'}}
rxp.activeWaypoints = {two}
tick(); assert(current.name == 'First active task')
for i=1,240 do tick() end
assert(pinCalls == count and calls == primaryCalls, 'multi-pin refresh spam')
first.active = false
tick()
assert(current.name == 'Second active task' and not pins['WaypointUIRestedXPSync:13'])
assert(pins.manual, 'removed an unrelated pin')
local noDestination = {index=12,active=true,elements={{tag='use',text='No coordinates'}}}
rxp.RXPFrame.activeSteps = {noDestination,second}
tick(); assert(current.name == 'Second active task' and pinCalls == count)
SlashCmdList.WAYPOINTUIRESTEDXPSYNC('off')
assert(pins.manual and not pins['WaypointUIRestedXPSync:14'] and current == nil)
-- Reproduce a stale step-13 arrow/active flag while Compact shows step 24.
local stale = {index=13,active=true,elements={}}
local live = {index=24,active=true,elements={}}
local old = {zone=10,x=15,y=25,text='Use Motivator',step=stale}
local fresh = {zone=10,x=45,y=55,text='Talk to Deathguard Kristof',step=live}
stale.elements={old}; live.elements={fresh}
rxp.currentGuide.steps = {stale,live}
rxp.RXPFrame = {activeSteps={stale,live}, CurrentStepFrame={framePool={
    {step=stale,IsShown=function() return false end},
    {step=live,IsShown=function() return true end},
}}}
rxp.arrowFrame.element=old; rxp.activeWaypoints={old,fresh}
SlashCmdList.WAYPOINTUIRESTEDXPSYNC('on')
assert(current.name == 'Talk to Deathguard Kristof')
assert(pins['WaypointUIRestedXPSync:24'] and not pins['WaypointUIRestedXPSync:13'])
local nextStep={index=25,active=true}
local nextPin={zone=10,x=65,y=75,text='Talk to next NPC',step=nextStep}
nextStep.elements={nextPin}
live.completed=true
rxp.RXPFrame.activeSteps={live,nextStep}
rxp.RXPFrame.CurrentStepFrame.framePool={{step=nextStep,IsShown=function() return true end}}
rxp.activeWaypoints={fresh,nextPin}
tick(); assert(current.name == 'Talk to next NPC' and not pins['WaypointUIRestedXPSync:24'])
nextPin.tag = 'goto'
nextStep.elements = {nextPin, {tag='complete',text='Darkhound Blood',step=nextStep}}
for i=1,4 do tick() end
assert(current.iconTexture:find('IncompleteQuest',1,true))
assert(pins['WaypointUIRestedXPSync:25'].iconTexture:find('IncompleteQuest',1,true))
nextStep.elements = {nextPin}
nextPin.text = '5/5 Darkhound Blood'
for i=1,4 do tick() end
assert(current.iconTexture:find('IncompleteQuest',1,true))
nextPin.text = 'Travel to Brill'
for i=1,4 do tick() end
assert(current.iconTexture:find('Navigation',1,true))
nextPin.tag = 'accept'
nextStep.elements = {nextPin, {tag='complete',step=nextStep}}
for i=1,4 do tick() end
assert(current.iconTexture:find('AvailableQuest',1,true))
-- A live collection field must beat both static tooltip text and a stale widget.
nextPin.tag = 'goto'; nextPin.text = 'Travel to the field'
local collect = {tag='collect',step=nextStep,text='Blood: 1/5',tooltipText='Collect Blood'}
collect.frame = {element=collect,text={GetText=function() return 'Blood: 0/5' end}}
local other = {tag='complete',step=nextStep,text='Bones: 0/3'}
nextStep.elements = {nextPin,collect,other}
tick(); assert(current.name == 'Blood: 1/5')
assert(pins['WaypointUIRestedXPSync:25'].name == current.name)
collect.text = 'Blood: 2/5'
tick(); assert(current.name == 'Blood: 2/5', 'same-location progress did not refresh')
collect.completed = true
tick(); assert(current.name == 'Bones: 0/3', 'completed objective still selected')
assert(pins['WaypointUIRestedXPSync:25'].name == current.name)
-- Remove one of two active steps without changing the destination coordinates.
local concurrent = {index=26,active=true}
local concurrentPin = {tag='goto',step=concurrent,zone=10,x=65,y=75}
concurrent.elements={concurrentPin,{tag='complete',step=concurrent,text='Claws: 1/4'}}
rxp.RXPFrame = {activeSteps={nextStep,concurrent}}
rxp.activeWaypoints={nextPin,concurrentPin}
tick(); assert(pins['WaypointUIRestedXPSync:26'].name == 'Claws: 1/4')
nextStep.completed = true
tick(); assert(current.name == 'Claws: 1/4' and not pins['WaypointUIRestedXPSync:25'])
-- An arrow from an old guide with the same step number must not supply metadata.
local staleOwner={index=26,active=true}
rxp.arrowFrame.element={step=staleOwner,zone=10,x=1,y=1,text='Old guide task'}
tick(); assert(current.name == 'Claws: 1/4' and current.x == 0.65)
local stableCalls, stablePins = calls, pinCalls
for i=1,240 do tick() end
assert(calls == stableCalls and pinCalls == stablePins, 'metadata refresh spam')
''')
print('PASS: Lua 5.1 syntax, target changes, coordinate formats, priority, ownership cleanup, enable/disable and invalid destinations')
