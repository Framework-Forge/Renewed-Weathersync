local serverWeather = RenewedWeather.State.weather
local hadSnow = false
local playerState = RenewedWeather.PlayerState
local currentRegionId = nil
local lastAppliedWeather = nil
local RW = RenewedWeather

local function resetWeatherParticles()
    if hadSnow then
        SetForceVehicleTrails(false)
        SetForcePedFootstepsTracks(false)
        ReleaseNamedScriptAudioBank('ICE_FOOTSTEPS')
        ReleaseNamedScriptAudioBank('SNOW_FOOTSTEPS')
        ForceSnowPass(false)
        WaterOverrideSetStrength(0.5)
        RemoveNamedPtfxAsset('core_snow')

        if IsIplActive('alamo_ice') then
            RemoveIpl('alamo_ice')
        end

        hadSnow = false
    end
end

local function setWeatherParticles()
    if not hadSnow then
        pr_lib.requestNamedPtfxAsset('core_snow', 1000)
        UseParticleFxAsset('core_snow')

        ForceSnowPass(true)
        SetForceVehicleTrails(true)
        SetForcePedFootstepsTracks(true)
        RequestScriptAudioBank('ICE_FOOTSTEPS', false)
        RequestScriptAudioBank('SNOW_FOOTSTEPS', false)
        WaterOverrideSetStrength(0.9)

        if GetResourceState('nve_iced_alamo') ~= 'missing' then
            RequestIpl('alamo_ice')
        end

        hadSnow = true
    end
end

local function updateCurrentRegion()
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        currentRegionId = RW.GetRegionFromCoords(GetEntityCoords(ped))
    end
    return currentRegionId or 1
end

local function getTargetWeatherData()
    if not serverWeather then return nil end
    if serverWeather.splitRegions and serverWeather.regions then
        local regionId = currentRegionId or updateCurrentRegion()
        local regionData = serverWeather.regions[regionId]
        if regionData then
            return regionData
        end
    end
    return serverWeather
end

local function setWeather(forceSwap, overrideDuration)
    local target = getTargetWeatherData()
    if not target or not target.weather then return end

    SetRainLevel(-1.0)

    if forceSwap then
        ClearWeatherTypePersist()
        SetWeatherTypePersist(target.weather)
        SetWeatherTypeNow(target.weather)
        SetWeatherTypeNowPersist(target.weather)
        lastAppliedWeather = target.weather
    else
        local duration = overrideDuration or 15.0
        SetWeatherTypeOvertimePersist(target.weather, duration)
        lastAppliedWeather = target.weather
    end

    if target.windDirection then
        SetWindDirection(math.rad(target.windDirection))
    end

    if target.windSpeed then
        SetWind(target.windSpeed / 2)
    end

    if target.hasSnow then
        setWeatherParticles()
    elseif hadSnow then
        resetWeatherParticles()
    end
end

RenewedWeather.onStateChange('weather', 'global', function(_, _, value)
    if value then
        serverWeather = value

        if playerState.syncWeather then
            updateCurrentRegion()
            setWeather(value.instant == true)
        end
    end
end)

local function applyBlackout()
    SetArtificialLightsState(RW.State.blackOut == true or playerState.playerBlackOut == true)
    SetArtificialLightsStateAffectsVehicles(false)
end
RenewedWeather.onStateChange('blackOut','global',applyBlackout)
RenewedWeather.onStateChange('playerBlackOut','player',applyBlackout)

-- Monitoramento leve de transição entre regiões geográficas --
CreateThread(function()
    while true do
        Wait(1500)
        if playerState.syncWeather and serverWeather and serverWeather.splitRegions then
            local ped = PlayerPedId()
            if DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                local newRegionId = RW.GetRegionFromCoords(coords)
                if newRegionId ~= currentRegionId then
                    currentRegionId = newRegionId
                    local target = getTargetWeatherData()
                    if target and target.weather ~= lastAppliedWeather then
                        setWeather(false, 15.0)
                    end
                end
            end
        end
    end
end)

-- Inicialização do cliente --
CreateThread(function ()
    SetWind(0.1)
    WaterOverrideSetStrength(0.5)

    updateCurrentRegion()
    setWeather(true)

    playerState.syncWeather = true
    applyBlackout()
end)

RenewedWeather.onStateChange('syncWeather', ('player:%s'):format(pr_lib.cache.serverId), function(_, _, value)
    if not value then
        SetTimeout(0, function()
            resetWeatherParticles()
            while not playerState.syncWeather do
                SetRainLevel(0.0)
                SetWeatherTypePersist('EXTRASUNNY')
                SetWeatherTypeNow('EXTRASUNNY')
                SetWeatherTypeNowPersist('EXTRASUNNY')
                Wait(2500)
            end
        end)
    else
        updateCurrentRegion()
        setWeather(true)
    end
end)

exports('GetCurrentRegion', function()
    return currentRegionId or updateCurrentRegion()
end)

exports('GetCurrentRegionWeather', function()
    return getTargetWeatherData()
end)
