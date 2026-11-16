local RW = RenewedWeather
local ConfigService = RW.ConfigService
local Runtime = RW.Runtime
local Config = ConfigService.getWeather()
local state = Runtime.getWeather()
local overrideWeather = false

math.randomseed(os.time() + GetGameTimer())

local function clone(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, child in pairs(value) do out[key] = clone(child) end
    return out
end

local function events()
    local cfg = (ConfigService and ConfigService.getWeather and ConfigService.getWeather()) or Config
    return (cfg and cfg.events and cfg.events.items) or (Config.events and Config.events.items) or {}
end
local function monthAllowed(event)
    local month = tonumber(event.month) or 0
    return month == 0 or month == (tonumber(os.date('%m')) or 1)
end
local function available()
    local out = {}
    if Config.events and Config.events.enabled == false then return out end
    for index, event in ipairs(events()) do
        if event.enabled ~= false and monthAllowed(event) then out[#out + 1] = index end
    end
    return out
end
local function eventIndexById(id)
    for index, event in ipairs(events()) do if event.id == id then return index end end
end
local function validEventIndex(index)
    index = tonumber(index)
    local event = index and events()[index]
    return event and event.enabled ~= false and monthAllowed(event) and index or nil
end
local function duration(step)
    local range = type(step.time) == 'table' and step.time or { min = step.time, max = step.time }
    local minimum = math.max(1, math.floor(tonumber(range.min) or 5))
    local maximum = math.max(minimum, math.floor(tonumber(range.max) or minimum))
    return math.random(minimum, maximum)
end
local function currentEvent()
    local index = eventIndexById(state.eventId) or validEventIndex(state.eventIndex)
    return index, index and events()[index] or nil
end
local function effectiveSnow(configured)
    return configured == true or (Config.decemberSnow == true and tonumber(os.date('%m')) == 12)
end

local function nextSequential(index)
    local list = available()
    if #list == 0 then return nil end
    for position, value in ipairs(list) do if value == index then return list[position % #list + 1] end end
    return list[1]
end

local function chooseDynamic(index)
    local list = available()
    if #list == 0 then return nil end
    local total = 0
    for _, eventIndex in ipairs(list) do total = total + math.max(0, tonumber(events()[eventIndex].probability) or 0) end
    if total <= 0 then return nextSequential(index) end
    local roll, cursor = math.random() * total, 0
    for _, eventIndex in ipairs(list) do
        cursor = cursor + math.max(0, tonumber(events()[eventIndex].probability) or 0)
        if roll <= cursor then return eventIndex end
    end
    return list[#list]
end

local function selectedUnique() return eventIndexById(Config.uniqueEventId) or available()[1] end

local function getNextEventIndex(eventIndex)
    if state.mode == 'unique' then
        return selectedUnique()
    elseif state.mode == 'dynamic' then
        return state.nextEventId and eventIndexById(state.nextEventId) or chooseDynamic(eventIndex)
    else
        return nextSequential(eventIndex)
    end
end

local function getStepArea2(event, eventIndex, currentIndex)
    local weathers = event.weathers or {}
    if weathers[currentIndex + 1] then
        return weathers[currentIndex + 1], event.windDirection
    end
    local nextIndex = getNextEventIndex(eventIndex)
    local nextEv = nextIndex and events()[nextIndex]
    if nextEv and nextEv.weathers and nextEv.weathers[1] then
        return nextEv.weathers[1], nextEv.windDirection
    end
    return weathers[currentIndex] or weathers[1], event.windDirection
end

local function publish(flush)
    if state.current then
        local global = clone(state.current)
        global.hasSnow = effectiveSnow(global.hasSnow)
        global.isRain = global.weather == 'RAIN' or global.weather == 'THUNDER'

        local eventIndex, event = currentEvent()
        local isSplit = event and event.splitRegions == true
        global.splitRegions = isSplit
        global.instant = flush == true
        global.eventId = event and event.id
        global.eventIndex = eventIndex
        global.eventName = event and event.name

        if isSplit and event then
            local step2, defaultWindDir2 = getStepArea2(event, eventIndex, state.weatherIndex or 1)
            local weather2 = tostring(step2 and step2.weather or global.weather):upper()
            local snow2 = effectiveSnow(step2 and step2.hasSnow)
            local windSpeed2 = tonumber(step2 and step2.windSpeed) or 0
            local windDir2 = tonumber(step2 and step2.windDirection) or tonumber(defaultWindDir2) or 0

            global.regions = {
                [1] = {
                    weather = global.weather,
                    windSpeed = global.windSpeed,
                    windDirection = global.windDirection,
                    hasSnow = global.hasSnow,
                    isRain = global.isRain,
                },
                [2] = {
                    weather = weather2,
                    windSpeed = windSpeed2,
                    windDirection = windDir2,
                    hasSnow = snow2,
                    isRain = weather2 == 'RAIN' or weather2 == 'THUNDER',
                }
            }
        else
            global.regions = nil
        end

        RenewedWeather.State.weather = global
    end
    Runtime.setWeather(state, flush == true)
end

local setStep
local function prepareDynamicNext(eventIndex, event)
    if state.mode ~= 'dynamic' or state.weatherIndex ~= #(event.weathers or {}) then
        state.nextEventId = nil
        return
    end
    local savedIndex = state.nextEventId and eventIndexById(state.nextEventId)
    if not savedIndex or not validEventIndex(savedIndex) then
        local nextIndex = chooseDynamic(eventIndex)
        state.nextEventId = nextIndex and events()[nextIndex].id or nil
    end
end

setStep = function(eventIndex, weatherIndex, remaining, flush, weatherOverride)
    local event = events()[eventIndex]
    local step = event and (event.weathers or {})[weatherIndex]
    if not step then return false end
    local sampled = math.max(1, math.floor(tonumber(remaining) or duration(step)))
    state.eventId, state.eventIndex, state.weatherIndex = event.id, eventIndex, weatherIndex
    state.sampledDuration, state.remainingMinutes = sampled, sampled
    state.current = {
        weather = tostring(weatherOverride or step.weather):upper(),
        time = sampled,
        windSpeed = tonumber(step.windSpeed) or 0,
        windDirection = tonumber(step.windDirection) or tonumber(event.windDirection) or 0,
        hasSnow = step.hasSnow == true,
        eventId = event.id,
        eventOrder = event.order,
        weatherIndex = weatherIndex,
        splitRegions = event.splitRegions == true,
    }
    prepareDynamicNext(eventIndex, event)
    publish(flush)
    return clone(state.current)
end

local updateDaily
local function continueTimed(flush)
    local eventIndex, event = currentEvent()
    if not event then
        local first = state.mode == 'unique' and selectedUnique() or available()[1]
        return first and setStep(first, 1, nil, flush) or false
    end
    local nextWeather = (state.weatherIndex or 1) + 1
    if (event.weathers or {})[nextWeather] then return setStep(eventIndex, nextWeather, nil, flush) end
    local nextEvent = getNextEventIndex(eventIndex)
    state.nextEventId = nil
    return nextEvent and setStep(nextEvent, 1, nil, flush) or false
end

local function activatePending(flush, gameMinute)
    if not state.pendingMode then return false end
    state.mode = RW.Modes[state.pendingMode] and state.pendingMode or Config.mode
    state.pendingMode, state.nextEventId = nil, nil
    if state.mode == 'unique' then
        local index = selectedUnique()
        return index and setStep(index, 1, nil, flush) or false
    end
    if state.mode == 'daily_fixed' then return updateDaily(gameMinute, flush, true) end
    return continueTimed(flush)
end

updateDaily = function(gameMinute, flush, entering)
    gameMinute = math.max(0, math.min(1439, math.floor(tonumber(gameMinute) or 0)))
    local eventIndex, event = currentEvent()
    if not event then eventIndex = available()[1]; event = eventIndex and events()[eventIndex] end
    if not event then state.current = nil; publish(flush); return false end

    local previous = tonumber(state.lastGameMinute) or gameMinute
    local rolled = not entering and gameMinute < previous
    local count = math.max(1, #(event.weathers or {}))
    local segment = 1440 / count
    local targetWeather = math.min(count, math.floor(gameMinute / segment) + 1)
    local boundary = rolled or targetWeather ~= state.weatherIndex

    if boundary and state.pendingMode then
        state.lastGameMinute = gameMinute
        return activatePending(flush, gameMinute)
    end

    if rolled then
        eventIndex = nextSequential(eventIndex) or eventIndex
        event = events()[eventIndex]
        count = math.max(1, #(event.weathers or {}))
        segment = 1440 / count
        targetWeather = math.min(count, math.floor(gameMinute / segment) + 1)
        state.cycleNumber = (state.cycleNumber or 0) + 1
    end

    state.lastGameMinute = gameMinute
    local remaining = math.max(1, math.ceil(targetWeather * segment - gameMinute))
    if state.eventId ~= event.id or state.weatherIndex ~= targetWeather or not state.current then
        return setStep(eventIndex, targetWeather, remaining, flush)
    end
    state.remainingMinutes = remaining
    state.current.time = remaining
    publish(flush)
    return clone(state.current)
end

local function boundary(flush)
    local time = RenewedWeather.State.currentTime or Runtime.getTime()
    local gameMinute = (tonumber(time.hour) or 0) * 60 + (tonumber(time.minute) or 0)
    if state.pendingMode then return activatePending(flush, gameMinute) end
    if state.mode == 'daily_fixed' then return updateDaily(gameMinute, flush, false) end
    return continueTimed(flush)
end

local function rebuild(flush)
    state.mode = Config.mode
    state.pendingMode, state.nextEventId = nil, nil
    state.eventId, state.eventIndex, state.weatherIndex = '', 1, 1
    state.remainingMinutes, state.sampledDuration, state.cycleNumber = 0, 0, 0
    local index = state.mode == 'unique' and selectedUnique() or available()[1]
    if not index then state.current = nil; publish(flush); return false end
    if state.mode == 'daily_fixed' then
        local time = RenewedWeather.State.currentTime or Runtime.getTime()
        return updateDaily((tonumber(time.hour) or 0) * 60 + (tonumber(time.minute) or 0), flush, true)
    end
    return setStep(index, 1, nil, flush)
end

local function forecast()
    local eventIndex, event = currentEvent()
    local result = {
        steps = {},
        currentEventId = event and event.id or nil,
        currentEventOrder = event and event.order or nil,
        nextEventId = state.nextEventId,
        mode = state.mode,
        pendingMode = state.pendingMode,
        splitRegions = event and event.splitRegions == true or false,
    }
    if not event then return result end
    for index, step in ipairs(event.weathers or {}) do
        result.steps[#result.steps + 1] = {
            weather = step.weather,
            time = index == state.weatherIndex and state.remainingMinutes or ((step.time.min == step.time.max) and step.time.min or step.time.max),
            timeRange = clone(step.time),
            windSpeed = step.windSpeed,
            windDirection = step.windDirection,
            hasSnow = effectiveSnow(step.hasSnow),
            eventId = event.id,
            eventIndex = eventIndex,
            weatherIndex = index,
            current = index == state.weatherIndex,
            splitRegions = event.splitRegions == true,
        }
    end
    return result
end

local function forceEvent(id)
    local index = eventIndexById(id) or validEventIndex(id)
    if not index then return false end
    state.pendingMode, state.nextEventId = nil, nil
    state.mode = Config.mode
    if state.mode == 'daily_fixed' then
        state.eventId, state.eventIndex = events()[index].id, index
        local time = RenewedWeather.State.currentTime or Runtime.getTime()
        return updateDaily((time.hour or 0) * 60 + (time.minute or 0), true, true)
    end
    return setStep(index, 1, nil, true)
end

local function forceWeather(value, weatherIndex)
    value = tostring(value or ''):upper()
    if not RW.WeatherTypeSet[value] then return false end
    local eventIndex, event = currentEvent()
    if not event then return false end
    weatherIndex = tonumber(weatherIndex) or state.weatherIndex
    if not (event.weathers or {})[weatherIndex] then weatherIndex = state.weatherIndex end
    local remaining = weatherIndex == state.weatherIndex and state.remainingMinutes or duration(event.weathers[weatherIndex])
    return setStep(eventIndex, weatherIndex, remaining, true, value)
end

local function forceRemaining(value)
    value = math.max(1, math.floor(tonumber(value) or 1))
    state.remainingMinutes, state.sampledDuration = value, value
    if state.current then state.current.time = value end
    publish(true)
    return value
end

local function validateCurrent()
    local eventIndex, event = currentEvent()
    if not event then return false end
    local step = (event.weathers or {})[state.weatherIndex]
    if not step or not state.current then return false end
    state.eventIndex = eventIndex
    state.current.eventId, state.current.eventOrder, state.current.weatherIndex = event.id, event.order, state.weatherIndex
    return true
end

ConfigService.setProvider({ get = forecast, rebuild = function() return rebuild(true) end })

if validateCurrent() then
    if not RW.Modes[state.mode] then state.mode = Config.mode end
    if state.pendingMode and not RW.Modes[state.pendingMode] then state.pendingMode = nil end
    publish(false)
else
    rebuild(false)
end

CreateThread(function()
    while true do
        Wait(60000)
        if not overrideWeather and state.mode ~= 'daily_fixed' then
            state.remainingMinutes = math.max(0, (state.remainingMinutes or 0) - 1)
            if state.current then state.current.time = state.remainingMinutes end
            if state.remainingMinutes <= 0 then boundary(true) else publish(false) end
        end
    end
end)

RenewedWeather.onStateChange('currentTime', 'global', function(_, _, value)
    if not RW.profileTimeChanging and state.mode == 'daily_fixed' and type(value) == 'table' then
        updateDaily((tonumber(value.hour) or 0) * 60 + (tonumber(value.minute) or 0), false, false)
    end
end)

AddEventHandler('Renewed-Weathersync:server:configChanged', function(section, value)
    if section ~= 'weather' then return end
    local selectedMode = value.mode
    Config = value
    overrideWeather = false
    if selectedMode ~= state.mode then state.pendingMode = selectedMode
    elseif state.pendingMode == selectedMode then state.pendingMode = nil end
    if not validateCurrent() then return rebuild(true) end
    publish(true)
end)

AddEventHandler('Renewed-Weathersync:server:profileChanged', function(_, weatherConfig, restart)
    Config = weatherConfig
    state = Runtime.getWeather()
    overrideWeather = false
    if restart or not validateCurrent() then rebuild(true) else publish(true) end
end)

RW.WeatherService = {
    force = forceWeather,
    prepareTimeForce = function(gameMinute)
        state.lastGameMinute = math.max(0, math.min(1439, math.floor(tonumber(gameMinute) or 0)))
        Runtime.setWeather(state, true)
        return true
    end,
}

pr_lib.callback.register(RW.Callbacks.setWeatherType, function(source, index, value)
    if IsPlayerAceAllowed(source, 'command.weather') then return forceWeather(value, index) end
    return false
end)
pr_lib.callback.register(RW.Callbacks.setEventTime, function(source, index, value)
    if not IsPlayerAceAllowed(source, 'command.weather') then return false end
    local eventIndex, event = currentEvent()
    index = tonumber(index) or state.weatherIndex
    if event and (event.weathers or {})[index] and index ~= state.weatherIndex then return setStep(eventIndex, index, value, true) end
    return forceRemaining(value)
end)
pr_lib.callback.register(RW.Callbacks.removeEvent, function() return false end)
pr_lib.callback.register(RW.Callbacks.forceEvent, function(source, id)
    if IsPlayerAceAllowed(source, 'command.weather') then return forceEvent(id) end
    return false
end)

local function addWeatherEvent(weatherTypeValue, minutes, index)
    weatherTypeValue = tostring(weatherTypeValue or ''):upper()
    if not RW.WeatherTypeSet[weatherTypeValue] then return false end
    local eventIndex, event = currentEvent(); if not event then return false end
    local config = ConfigService.getWeather(); local target = config.events.items[eventIndex]; if not target then return false end
    local position = math.max(1, math.min(#target.weathers + 1, math.floor(tonumber(index) or (#target.weathers + 1))))
    local value = math.max(1, math.min(1440, math.floor(tonumber(minutes) or 10)))
    table.insert(target.weathers, position, { weather = weatherTypeValue, time = { min = value, max = value }, windSpeed = 0, windDirection = target.windDirection or 0, hasSnow = weatherTypeValue == 'SNOW' or weatherTypeValue == 'SNOWLIGHT' or weatherTypeValue == 'BLIZZARD' or weatherTypeValue == 'XMAS' })
    return ConfigService.saveWeather(config)
end

local function removeWeatherEvent(index)
    local eventIndex, event = currentEvent(); if not event then return false end
    local config = ConfigService.getWeather(); local target = config.events.items[eventIndex]
    if not target or #target.weathers <= 1 then return false end
    index = math.floor(tonumber(index) or 0); if index < 1 or index > #target.weathers then return false end
    table.remove(target.weathers, index)
    return ConfigService.saveWeather(config)
end

exports('GetWeatherList', function() return forecast().steps end)
exports('SetWeatherType', function(_, value) return forceWeather(value) end)
exports('SetEventTime', function(index, value)
    local eventIndex, event = currentEvent(); index = tonumber(index) or state.weatherIndex
    if event and (event.weathers or {})[index] and index ~= state.weatherIndex then return setStep(eventIndex, index, value, true) end
    return forceRemaining(value)
end)
exports('RebuildWeatherList', function() return rebuild(true) end)
exports('ForceWeatherEvent', forceEvent)
exports('AddWeatherEvent', addWeatherEvent)
exports('RemoveWeatherEvent', removeWeatherEvent)
exports('GetRegionalWeather', function(regionId)
    local cur = RenewedWeather.State.weather
    if not cur then return nil end
    if not cur.splitRegions or not cur.regions then return cur end
    regionId = tonumber(regionId) or 1
    return cur.regions[regionId] or cur.regions[1]
end)

local WEATHER_INFO = {
    EXTRASUNNY = { label = 'Muito Ensolarado', icon = 'sun', baseMin = 22, baseMax = 33, rain = false, snow = false },
    CLEAR = { label = 'Céu Limpo', icon = 'sun', baseMin = 19, baseMax = 28, rain = false, snow = false },
    CLEARING = { label = 'Limpando', icon = 'cloud-sun', baseMin = 18, baseMax = 26, rain = false, snow = false },
    CLOUDS = { label = 'Nublado', icon = 'clouds', baseMin = 17, baseMax = 23, rain = false, snow = false },
    OVERCAST = { label = 'Encoberto', icon = 'cloud', baseMin = 16, baseMax = 21, rain = false, snow = false },
    SMOG = { label = 'Neblina Seca', icon = 'smog', baseMin = 19, baseMax = 27, rain = false, snow = false },
    FOGGY = { label = 'Nevoeiro', icon = 'fog', baseMin = 14, baseMax = 19, rain = false, snow = false },
    RAIN = { label = 'Chuva', icon = 'cloud-rain', baseMin = 15, baseMax = 20, rain = true, snow = false },
    THUNDER = { label = 'Tempestade', icon = 'cloud-bolt', baseMin = 14, baseMax = 18, rain = true, snow = false },
    SNOW = { label = 'Neve', icon = 'snowflake', baseMin = -4, baseMax = 2, rain = false, snow = true },
    BLIZZARD = { label = 'Nevasca', icon = 'snowflake', baseMin = -8, baseMax = -1, rain = false, snow = true },
    SNOWLIGHT = { label = 'Neve Fraca', icon = 'snowflake', baseMin = -2, baseMax = 4, rain = false, snow = true },
    XMAS = { label = 'Natalício', icon = 'snowflake', baseMin = -3, baseMax = 3, rain = false, snow = true },
    HALLOWEEN = { label = 'Halloween', icon = 'cloud-bolt', baseMin = 13, baseMax = 17, rain = false, snow = false },
    NEUTRAL = { label = 'Neutro', icon = 'cloud-sun', baseMin = 18, baseMax = 25, rain = false, snow = false },
}

local function forecastDayLabel(index)
    if index == 1 then return RW.t('forecast.today') end
    if index == 2 then return RW.t('forecast.tomorrow') end
    if index == 3 then return RW.t('forecast.day_after_tomorrow') end
    return RW.t('forecast.in_days', { days = index - 1 })
end

local function toFahrenheit(celsius)
    return math.floor(celsius * 1.8 + 32 + 0.5)
end

local function computeRegionTemps(weatherType, regionId)
    local info = WEATHER_INFO[weatherType] or WEATHER_INFO['CLEAR']
    local minC = info.baseMin
    local maxC = info.baseMax

    if regionId == 2 then
        if weatherType == 'EXTRASUNNY' or weatherType == 'CLEAR' then
            maxC = maxC + 4
            minC = minC - 1
        elseif info.snow then
            minC = minC - 3
            maxC = maxC - 2
        else
            minC = minC - 1
            maxC = maxC + 1
        end
    end

    return {
        label = info.label,
        icon = info.icon,
        hasRain = info.rain,
        hasSnow = info.snow,
        minC = minC,
        maxC = maxC,
        minF = toFahrenheit(minC),
        maxF = toFahrenheit(maxC),
    }
end

local function getWeeklyForecast()
    local curWeather = RenewedWeather.State.weather or {}
    local curTime = RenewedWeather.State.currentTime or { hour = 12, minute = 0 }
    local isSplit = curWeather.splitRegions == true and curWeather.regions ~= nil

    local currentSouthWeather = isSplit and curWeather.regions[1].weather or (curWeather.weather or 'CLEAR')
    local currentNorthWeather = isSplit and curWeather.regions[2].weather or (curWeather.weather or 'CLEAR')

    local southInfo = computeRegionTemps(currentSouthWeather, 1)
    local northInfo = computeRegionTemps(currentNorthWeather, 2)

    local hour = tonumber(curTime.hour) or 12
    local dayFactor = (hour >= 6 and hour <= 18) and math.sin(math.rad((hour - 6) / 12 * 180)) or 0
    local curTempSouthC = math.floor(southInfo.minC + (southInfo.maxC - southInfo.minC) * dayFactor)
    local curTempNorthC = math.floor(northInfo.minC + (northInfo.maxC - northInfo.minC) * dayFactor)

    local now = os.time()

    local avail = available()
    local curEvIndex = currentEvent()
    local availPosition = 1
    if curEvIndex and #avail > 0 then
        for pos, evIdx in ipairs(avail) do
            if evIdx == curEvIndex then
                availPosition = pos
                break
            end
        end
    end

    local days = {}

    for i = 1, 7 do
        local offsetSeconds = (i - 1) * 86400
        local dayDate = os.date('*t', now + offsetSeconds)
        local dateFormatted = ('%02d/%02d'):format(dayDate.day, dayDate.month)

        local dayWeatherSouth = currentSouthWeather
        local dayWeatherNorth = currentNorthWeather
        local dayIsSplit = isSplit
        local dayEventName = nil

        local curEvent = events()[curEvIndex]
        if i == 1 and curEvent then
            dayEventName = curEvent.name
        end

        if i > 1 and #avail > 0 then
            local projectedAvailPos = ((availPosition + i - 2) % #avail) + 1
            local projectedEvIndex = avail[projectedAvailPos]
            local projectedEvent = events()[projectedEvIndex]

            if projectedEvent then
                dayEventName = projectedEvent.name
                if projectedEvent.weathers and #projectedEvent.weathers > 0 then
                    dayIsSplit = projectedEvent.splitRegions == true
                    local w1 = projectedEvent.weathers[1].weather or 'CLEAR'
                    local w2 = (projectedEvent.weathers[2] and projectedEvent.weathers[2].weather) or w1
                    dayWeatherSouth = w1
                    dayWeatherNorth = dayIsSplit and w2 or w1
                end
            end
        end

        local daySouthTemps = computeRegionTemps(dayWeatherSouth, 1)
        local dayNorthTemps = computeRegionTemps(dayWeatherNorth, 2)

        days[#days + 1] = {
            index = i,
            day = forecastDayLabel(i),
            dayShort = forecastDayLabel(i),
            eventName = dayEventName,
            date = dateFormatted,
            isToday = i == 1,
            splitRegions = dayIsSplit,
            south = {
                weather = dayWeatherSouth,
                label = daySouthTemps.label,
                icon = daySouthTemps.icon,
                minC = daySouthTemps.minC,
                maxC = daySouthTemps.maxC,
                minF = daySouthTemps.minF,
                maxF = daySouthTemps.maxF,
                hasRain = daySouthTemps.hasRain,
                hasSnow = daySouthTemps.hasSnow,
                windSpeed = (isSplit and curWeather.regions[1].windSpeed) or curWeather.windSpeed or 1.0,
            },
            north = {
                weather = dayWeatherNorth,
                label = dayNorthTemps.label,
                icon = dayNorthTemps.icon,
                minC = dayNorthTemps.minC,
                maxC = dayNorthTemps.maxC,
                minF = dayNorthTemps.minF,
                maxF = dayNorthTemps.maxF,
                hasRain = dayNorthTemps.hasRain,
                hasSnow = dayNorthTemps.hasSnow,
                windSpeed = (isSplit and curWeather.regions[2].windSpeed) or curWeather.windSpeed or 1.5,
            },
        }
    end

    return {
        splitRegions = isSplit,
        currentTime = curTime,
        currentDay = forecastDayLabel(1),
        current = {
            south = {
                weather = currentSouthWeather,
                label = southInfo.label,
                icon = southInfo.icon,
                tempC = curTempSouthC,
                tempF = toFahrenheit(curTempSouthC),
                minC = southInfo.minC,
                maxC = southInfo.maxC,
                minF = southInfo.minF,
                maxF = southInfo.maxF,
                hasRain = southInfo.hasRain,
                hasSnow = southInfo.hasSnow,
                windSpeed = (isSplit and curWeather.regions[1].windSpeed) or curWeather.windSpeed or 1.0,
                windDirection = (isSplit and curWeather.regions[1].windDirection) or curWeather.windDirection or 0,
            },
            north = {
                weather = currentNorthWeather,
                label = northInfo.label,
                icon = northInfo.icon,
                tempC = curTempNorthC,
                tempF = toFahrenheit(curTempNorthC),
                minC = northInfo.minC,
                maxC = northInfo.maxC,
                minF = northInfo.minF,
                maxF = northInfo.maxF,
                hasRain = northInfo.hasRain,
                hasSnow = northInfo.hasSnow,
                windSpeed = (isSplit and curWeather.regions[2].windSpeed) or curWeather.windSpeed or 1.5,
                windDirection = (isSplit and curWeather.regions[2].windDirection) or curWeather.windDirection or 0,
            },
        },
        days = days,
    }
end

exports('GetWeeklyForecast', getWeeklyForecast)

pr_lib.addCommand('weather', { help = RW.t('commands.weather'), restricted = 'group.admin' }, function(source)
    TriggerClientEvent('Renewed-Weather:client:openAdmin', source)
end)
pr_lib.addCommand('blackout', { help = RW.t('commands.blackout'), restricted = 'group.admin', params = {
    { name = 'target', type = 'playerId', help = RW.t('commands.blackout_target'), optional = true },
} }, function(_, args)
    if not args.target then RenewedWeather.State.blackOut = not RenewedWeather.State.blackOut; return end
    RW.setPlayerBlackout(args.target)
end)

AddEventHandler('txAdmin:events:scheduledRestart', function(data)
    if not Config.useScheduledWeather then return end
    local seconds = data.secondsRemaining
    local weather = seconds == 900 and 'OVERCAST' or seconds == 600 and 'RAIN' or seconds == 300 and 'THUNDER'
    if weather then
        overrideWeather = true
        RenewedWeather.State.weather = { weather = weather, time = 9000000, windSpeed = weather == 'THUNDER' and 8 or 2, windDirection = 0, hasSnow = effectiveSnow(false), isRain = weather == 'RAIN' or weather == 'THUNDER' }
    end
end)
