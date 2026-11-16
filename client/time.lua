local timeScale = RenewedWeather.State.timeScale
local currentTime = RenewedWeather.State.currentTime
local timeFrozen = RenewedWeather.State.freezeTime
local playerState = RenewedWeather.PlayerState

RenewedWeather.onStateChange('currentTime', 'global', function(_, _, value)
    if value and next(value) then

        if playerState.syncWeather then
            NetworkOverrideClockTime(value.hour, value.minute, 0)
        end

        currentTime = value
    end
end)

RenewedWeather.onStateChange('timeScale', 'global', function(_, _, value)
    if value and type(value) == 'number' then

        if playerState.syncWeather then
            NetworkOverrideClockMillisecondsPerGameMinute(RenewedWeather.State.freezeTime and 99999999 or value)
        end

        timeScale = value
    end
end)

RenewedWeather.onStateChange('freezeTime', 'global', function(_, _, value)
    if playerState.syncWeather then
        NetworkOverrideClockMillisecondsPerGameMinute(value and 99999999 or RenewedWeather.State.timeScale)
    end

    timeFrozen = value
end)

NetworkOverrideClockMillisecondsPerGameMinute(timeFrozen and 99999999 or timeScale)
NetworkOverrideClockTime(currentTime.hour,currentTime.minute,0)

RenewedWeather.onStateChange('syncWeather', ('player:%s'):format(pr_lib.cache.serverId), function(_, _, value)
    if value then
        NetworkOverrideClockTime(currentTime.hour, currentTime.minute, 0)
        NetworkOverrideClockMillisecondsPerGameMinute(timeFrozen and 99999999 or timeScale)
    else
        NetworkOverrideClockMillisecondsPerGameMinute(99999999)
        NetworkOverrideClockTime(0, 0, 0)
    end
end)
