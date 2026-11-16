local ConfigService = RenewedWeather.ConfigService

local globalState = RenewedWeather.State

local function exportHandler(exportName, func)
    AddEventHandler(('__cfx_export_qb-weathersync_%s'):format(exportName), function(setCB)
        setCB(func)
    end)
end

exportHandler('nextWeatherStage', function()
    return print("RENEWED WEATHERSYNC - THIS EXPORT IS NOT SUPPORTED")
end)

exportHandler('setDynamicWeather', function()
    return print("RENEWED WEATHERSYNC - THIS EXPORT IS NOT SUPPORTED")
end)


exportHandler('setWeather', function(weather)
    return RenewedWeather.WeatherService.force(weather)
end)

exportHandler('setTime', function(hour, minute)
    return RenewedWeather.TimeService.set(hour,minute,true,true)
end)

exportHandler('setBlackout', function(state)
    globalState.blackOut = state
end)

exportHandler('setTimeFreeze', function(state)
    return RenewedWeather.TimeService.freeze(state)
end)

exportHandler('getBlackoutState', function()
    return globalState.blackOut
end)

exportHandler('getTimeFreezeState', function()
    return globalState.freezeTime
end)

exportHandler('getWeatherState', function()
    local current = globalState.weather
    return current and current.weather or nil
end)

exportHandler('getDynamicWeather', function()
    return ConfigService.getWeather().mode ~= 'daily_fixed'
end)

exportHandler('getTime', function()
    local currentTime = globalState.currentTime

    return currentTime.hour, currentTime.minute
end)

RegisterNetEvent('qb-weathersync:server:setWeather', function(weather)
    if not IsPlayerAceAllowed(source, 'command.weather') then
        return
    end
    return RenewedWeather.WeatherService.force(weather)
end)

RegisterNetEvent('qb-weathersync:server:setTime', function(hour, minute)
    if not IsPlayerAceAllowed(source, 'command.time') then
        return
    end
    return RenewedWeather.TimeService.set(hour,minute,true,true)
end)
