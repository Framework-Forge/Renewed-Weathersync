local RW = RenewedWeather
local ConfigService = RW.ConfigService
local Runtime = RW.Runtime
local Config = ConfigService.getTime()
local globalState = RenewedWeather.State
local saved = Runtime.getTime()
local hour, minute = saved.hour, saved.minute
local currentScale = 2000
local freezeTime = false
local lastTick = GetGameTimer()

local function isNight(value)
    local beginning, ending = Config.nightTime.beginning, Config.nightTime.ending
    if beginning == ending then return true end
    if beginning < ending then return value >= beginning and value < ending end
    return value >= beginning or value < ending
end

local function effectiveScale(value)
    if Config.useRealTime then return 60000 end
    if Config.useScalableTime then
        local seconds = isNight(value) and Config.nightSecondsPerMinute or Config.daySecondsPerMinute
        return math.floor(math.max(1, seconds) * 1000)
    end
    return math.floor(math.max(1, Config.defaultSecondsPerMinute or 2) * 1000)
end

local function effectiveFreeze() return Config.useRealTime ~= true and Config.freezeTime == true end

local function publish(flush, profileChange)
    freezeTime = effectiveFreeze()
    currentScale = effectiveScale(hour)
    -- Profile runtime is already activated; the old weather observer must not
    -- write its previous event into that profile before the weather hook runs.
    RW.profileTimeChanging = profileChange == true
    RW.setWorld({currentTime={hour=hour,minute=minute},isNight=isNight(hour),timeScale=currentScale,freezeTime=freezeTime})
    RW.profileTimeChanging = false
    Runtime.setTime({ hour = hour, minute = minute }, flush == true)
end

local function setTime(nextHour, nextMinute, flush, manual)
    if manual and Config.useRealTime then return false, 'real_time_enabled' end
    hour = math.max(0, math.min(23, math.floor(tonumber(nextHour) or 0)))
    minute = math.max(0, math.min(59, math.floor(tonumber(nextMinute) or 0)))
    if manual and RW.WeatherService and RW.WeatherService.prepareTimeForce then RW.WeatherService.prepareTimeForce(hour * 60 + minute) end
    publish(flush)
    lastTick = GetGameTimer()
    return { hour = hour, minute = minute }
end

local function apply(nextConfig, profileChange)
    Config = nextConfig
    if profileChange then
        local runtimeTime = Runtime.getTime()
        hour, minute = runtimeTime.hour, runtimeTime.minute
    elseif Config.useRealTime then
        hour, minute = tonumber(os.date('%H')), tonumber(os.date('%M'))
    end
    publish(true, profileChange)
    lastTick = GetGameTimer()
end

if Config.useRealTime then hour, minute = tonumber(os.date('%H')), tonumber(os.date('%M')) end
publish(false)

CreateThread(function()
    while true do
        Wait(250)
        if Config.useRealTime then
            local realHour, realMinute = tonumber(os.date('%H')), tonumber(os.date('%M'))
            if realHour ~= hour or realMinute ~= minute then hour, minute = realHour, realMinute; publish(false) end
            lastTick = GetGameTimer()
        elseif effectiveFreeze() then
            lastTick = GetGameTimer()
        else
            local now = GetGameTimer()
            local elapsed = now - lastTick
            local scale = effectiveScale(hour)
            if elapsed >= scale then
                local steps = math.min(60, math.floor(elapsed / scale))
                lastTick = lastTick + steps * scale
                local total = (hour * 60 + minute + steps) % 1440
                hour, minute = math.floor(total / 60), total % 60
                publish(false)
            elseif currentScale ~= scale then
                currentScale = scale
                globalState.timeScale = scale
            end
        end
    end
end)

AddEventHandler('Renewed-Weathersync:server:configChanged', function(section, value)
    if section == 'time' then apply(value, false) end
end)

AddEventHandler('Renewed-Weathersync:server:profileChanged', function(timeConfig)
    apply(timeConfig, true)
end)

RW.TimeService = {
    freeze = function(value)
        if Config.useRealTime then return false,'real_time_enabled' end
        local config=ConfigService.getTime();config.freezeTime=value==true
        return ConfigService.saveTime(config)
    end,
    set = function(nextHour, nextMinute, flush, manual)
        return setTime(nextHour, nextMinute, flush ~= false, manual == true)
    end,
    get = function() return { hour = hour, minute = minute, frozen = effectiveFreeze(), realTime = Config.useRealTime } end,
}

exports('SetTime', function(nextHour, nextMinute) return RW.TimeService.set(nextHour, nextMinute, true, true) end)
exports('SetTimeScale', function(value)
    local config = ConfigService.getTime()
    local milliseconds = math.max(1000, math.min(600000, math.floor(tonumber(value) or (config.daySecondsPerMinute * 1000))))
    config.daySecondsPerMinute = milliseconds / 1000
    config.useScalableTime = true
    local ok, savedConfig = ConfigService.saveTime(config)
    return ok and savedConfig.daySecondsPerMinute * 1000 or false
end)
exports('SetFreezeTime', function(value)
    if Config.useRealTime then return false, 'real_time_enabled' end
    local config = ConfigService.getTime(); config.freezeTime = value == true
    local ok, savedConfig = ConfigService.saveTime(config)
    return ok and savedConfig.freezeTime or false
end)

pr_lib.callback.register(RW.Callbacks.forceTime, function(source, nextHour, nextMinute, shouldFreeze)
    if not IsPlayerAceAllowed(source, 'command.weather') then return { success = false, error = 'forbidden' } end
    if Config.useRealTime then return { success = false, error = 'real_time_enabled' } end
    if type(shouldFreeze) == 'boolean' and shouldFreeze ~= Config.freezeTime then
        local config = ConfigService.getTime(); config.freezeTime = shouldFreeze
        local ok = ConfigService.saveTime(config)
        if not ok then return { success = false, error = 'save_failed' } end
    end
    local result, err = setTime(nextHour, nextMinute, true, true)
    return { success = result ~= false, time = result ~= false and result or nil, error = err }
end)

pr_lib.addCommand('time', { help = RW.t('commands.time'), restricted = 'group.admin', params = {
    { name = 'hour', type = 'number', help = RW.t('commands.hour') },
    { name = 'minute', type = 'number', help = RW.t('commands.minute'), optional = true },
} }, function(source, args)
    local result, err = setTime(args.hour, args.minute or 0, true, true)
    if not result and source > 0 then TriggerClientEvent('Renewed-Weather:client:timeRejected', source, err) end
end)

local presets = { noon = { 12, 0 }, morning = { 9, 0 }, evening = { 18, 0 }, night = { 23, 0 } }
for command, value in pairs(presets) do
    pr_lib.addCommand(command, { help = RW.t('commands.' .. command), restricted = 'group.admin' }, function(source)
        local result, err = setTime(value[1], value[2], true, true)
        if not result and source > 0 then TriggerClientEvent('Renewed-Weather:client:timeRejected', source, err) end
    end)
end

pr_lib.addCommand('timescale', { help = RW.t('commands.timescale'), restricted = 'group.admin', params = {
    { name = 'seconds', type = 'number', help = RW.t('commands.scale') },
} }, function(_, args)
    local config = ConfigService.getTime()
    config.daySecondsPerMinute = math.max(1, math.min(600, tonumber(args.seconds) or config.daySecondsPerMinute))
    config.useScalableTime = true
    ConfigService.saveTime(config)
end)

pr_lib.addCommand('freezetime', { help = RW.t('commands.freezetime'), restricted = 'group.admin', params = {
    { name = 'time', type = 'number', help = RW.t('commands.freeze_value') },
} }, function(_, args)
    if Config.useRealTime then return end
    local config = ConfigService.getTime(); config.freezeTime = tonumber(args.time) == 1
    ConfigService.saveTime(config)
end)
