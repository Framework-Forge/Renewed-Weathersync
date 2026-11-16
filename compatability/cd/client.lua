if GetConvar('weather_disablecd', 'false') == 'true' then
    return
end

local cd_weather = {}

local playerState = RenewedWeather.PlayerState

RenewedWeather.onStateChange('weather', 'global', function(_, _, value)
    if value then
        cd_weather.weather = value.weather
    end
end)

RenewedWeather.onStateChange('blackOut', 'global', function(_, _, value)
    cd_weather.blackout = value
end)

RenewedWeather.onStateChange('freezeTime', 'global', function(_, _, value)
    cd_weather.freeze = value
end)

AddEventHandler('__cfx_export_cd_easytime_GetWeather', function(setCB)
    setCB(function()
        local snapshot=RenewedWeather.getSnapshot()
        return {weather=snapshot.weather and snapshot.weather.weather,blackout=snapshot.blackOut,freeze=snapshot.freezeTime}
    end)
end)

RegisterNetEvent('cd_easytime:PauseSync', function(toggle)
    playerState.syncWeather = not toggle
end)
