local RW, cache = RenewedWeather, pr_lib.cache
local server = IsDuplicityVersion()
local prefix = 'Renewed-Weathersync:'
local listeners = {}
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result={};for key,item in pairs(value) do result[key]=copy(item) end;return result
end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for key,value in pairs(a) do if not equal(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end
local function emit(key,value)
    for _,fn in ipairs(listeners[key] or {}) do
        local ok,err=pcall(fn,'cache',key,copy(value))
        if not ok then print('[Renewed-Weathersync] cache listener: '..tostring(err)) end
    end
    TriggerEvent('pr_bridge:weather:changed',key,copy(value))
end
function RW.onStateChange(key,_,fn)
    listeners[key]=listeners[key] or {};table.insert(listeners[key],fn)
end
local defaults={currentTime={hour=12,minute=0},timeScale=2000,freezeTime=false,isNight=false,blackOut=false}
local generation=cache.get(prefix..'generation') or 0
if server then
    generation=math.max(generation+1,os.time()+GetGameTimer()/1000);cache.set(prefix..'generation',generation)
    cache.set(prefix..'world',{generation=generation,revision=0,data=copy(defaults)})
end
local function record() return cache.get(prefix..'world') or {generation=0,revision=-1,data=copy(defaults)} end
function RW.setWorld(values)
    assert(server,'Only the weather server publishes world state')
    local nextRecord=copy(record());local changed={}
    for key,value in pairs(values) do
        if not equal(nextRecord.data[key],value) then nextRecord.data[key]=copy(value);changed[#changed+1]=key end
    end
    if #changed==0 then return end
    nextRecord.revision=nextRecord.revision+1
    cache.set(prefix..'world',nextRecord)
    -- Send before listeners: a daily weather update can publish recursively.
    TriggerClientEvent('Renewed-Weathersync:client:world',-1,copy(nextRecord))
    for _,key in ipairs(changed) do emit(key,nextRecord.data[key]) end
end
RW.State=setmetatable({}, {
    __index=function(_,key) return copy(record().data[key]) end,
    __newindex=function(_,key,value) RW.setWorld({[key]=value}) end,
})
local function localPlayer() return cache.get(prefix..'self') or {syncWeather=true,playerBlackOut=false} end
RW.PlayerState=setmetatable({}, {
    __index=function(_,key) return copy(localPlayer()[key]) end,
    __newindex=function(_,key,value)
        local nextPlayer=copy(localPlayer());if equal(nextPlayer[key],value) then return end
        nextPlayer[key]=copy(value);cache.set(prefix..'self',nextPlayer);emit(key,value)
    end,
})
function RW.getSnapshot() return copy(record().data) end
exports('GetSnapshot',RW.getSnapshot)
exports('GetRegionFromCoords',RW.GetRegionFromCoords)
if server then
    local function playerKey(src)
        local identifier=pr_lib.framework.GetIdentifier(tonumber(src))
        if not identifier then return nil end
        cache.set(prefix..'binding:'..src,identifier)
        return prefix..'player:'..identifier
    end
    function RW.setPlayerBlackout(src,value)
        local key=playerKey(src);if not key then return false end
        local state=cache.get(key) or {playerBlackOut=false}
        state.playerBlackOut=value==nil and not state.playerBlackOut or value==true
        cache.set(key,copy(state))
        TriggerClientEvent('Renewed-Weathersync:client:personal',tonumber(src),copy(state))
        return true
    end
    pr_lib.callback.register('Renewed-Weathersync:server:snapshot',function(src)
        local key=playerKey(src)
        return {world=copy(record()),player=key and copy(cache.get(key)) or {playerBlackOut=false}}
    end)
    local function clearPlayer(src)
        local identifier=cache.get(prefix..'binding:'..tostring(src))
        if identifier then cache.clear(prefix..'player:'..identifier) end
        cache.clear(prefix..'binding:'..tostring(src))
    end
    AddEventHandler('playerDropped',function() clearPlayer(source) end)
    AddEventHandler('pr_bridge:server:OnPlayerUnloaded',clearPlayer)
else
    local function applyWorld(packet)
        if type(packet)~='table' or type(packet.data)~='table' or type(packet.generation)~='number' or type(packet.revision)~='number' then return false end
        local old=record()
        if packet.generation<old.generation or (packet.generation==old.generation and packet.revision<=old.revision) then return false end
        cache.set(prefix..'world',copy(packet))
        for key,value in pairs(packet.data) do if not equal(value,old.data[key]) then emit(key,value) end end
        return true
    end
    RegisterNetEvent('Renewed-Weathersync:client:world',function(packet) if source==65535 then applyWorld(packet) end end)
    local personalRevision=0
    RegisterNetEvent('Renewed-Weathersync:client:personal',function(packet)
        if source==65535 and type(packet)=='table' then personalRevision=personalRevision+1;RW.PlayerState.playerBlackOut=packet.playerBlackOut==true end
    end)
    local lifecycle=0
    function RW.refreshCache()
        local expected=lifecycle
        local personalAtStart=personalRevision
        local ok,payload=pcall(pr_lib.callback.await,'Renewed-Weathersync:server:snapshot',5000)
        if not ok or type(payload)~='table' or expected~=lifecycle then return false end
        applyWorld(payload.world)
        if personalRevision==personalAtStart then
            RW.PlayerState.playerBlackOut=type(payload.player)=='table' and payload.player.playerBlackOut==true or false
        end
        -- A valid empty-weather snapshot is still hydrated (events may be disabled).
        -- Future weather arrives by push; do not poll every player indefinitely.
        return type(payload.world)=='table' and type(payload.world.data)=='table' and type(payload.world.generation)=='number' and type(payload.world.revision)=='number'
    end
    AddEventHandler('pr_bridge:client:OnPlayerLoaded',function() lifecycle=lifecycle+1;RW.PlayerState.syncWeather=true;RW.refreshCache() end)
    AddEventHandler('pr_bridge:client:OnPlayerUnloaded',function() lifecycle=lifecycle+1;RW.PlayerState.playerBlackOut=false end)
    CreateThread(function()
        while not RW.refreshCache() do Wait(1000) end
    end)
    exports('ToggleSync',function(enabled) RW.PlayerState.syncWeather=enabled==true;return true end)
end
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    cache.clear(prefix..'world');cache.clear(prefix..'self')
end)
