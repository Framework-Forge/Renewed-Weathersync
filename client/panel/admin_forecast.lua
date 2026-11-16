local Admin = RenewedWeather.Admin

local function eventById(id)
    for index, event in ipairs((Admin.data.weather.events and Admin.data.weather.events.items) or {}) do
        if event.id == id then return event, index end
    end
end

function Admin.openForecastEvent(index)
    local step = Admin.forecastSteps()[index]
    if not step then return Admin.openForecast() end
    local id = 'renewed_weather:forecast:' .. index
    pr_lib.registerContext({ id = id, menu = 'renewed_weather:forecast', title = Admin.weatherLabel(step.weather), options = {
        { title = Admin.t('forecast.force_weather'), description = Admin.t('forecast.force_weather_description'), icon = 'cloud-bolt', arrow = true, onSelect = function()
            Admin.pickWeather(id, step.weather, function(value)
                local result = pr_lib.callback.await(RenewedWeather.Callbacks.setWeatherType, 10000, step.weatherIndex or index, value)
                Admin.notify(result and 'notify.forced' or 'notify.force_failed', result and 'success' or 'error')
                Admin.fetch(); Admin.openForecast()
            end)
        end },
        { title = Admin.t('forecast.force_duration'), description = Admin.t('forecast.duration_description', { minutes = step.time }), icon = 'clock', onSelect = function()
            local result = Admin.numberDialog('forecast.force_duration', { { label = 'inputs.minutes', value = step.time, min = 1, max = 1440 } })
            if result then
                local changed = pr_lib.callback.await(RenewedWeather.Callbacks.setEventTime, 10000, step.weatherIndex or index, result[1])
                Admin.notify(changed and 'notify.forced' or 'notify.force_failed', changed and 'success' or 'error')
                Admin.fetch()
            end
            Admin.openForecast()
        end },
    } })
    pr_lib.showContext(id)
end

function Admin.openForecast()
    local forecast = Admin.data.forecast or {}
    local steps = Admin.forecastSteps()
    local currentEvent, currentIndex = eventById(forecast.currentEventId)
    local options = {
        { title = Admin.t('forecast.explanation'), description = Admin.t('forecast.explanation_description'), icon = 'circle-info', readOnly = true },
        { title = Admin.t('forecast.current_event'), description = currentEvent and Admin.numberedSequence(currentEvent, currentIndex) or '-', icon = 'flag', readOnly = true },
    }
    for index, step in ipairs(steps) do
        local eventIndex = index
        options[#options + 1] = {
            title = ('%s. %s%s'):format(index, Admin.weatherLabel(step.weather), step.current and (' — ' .. Admin.t('forecast.current')) or ''),
            description = Admin.t('forecast.list_description', { minutes = step.time, speed = step.windSpeed or 0, direction = step.windDirection or 0 }),
            icon = step.current and 'location-dot' or 'cloud-arrow-right', iconColor = step.current and '#22c55e' or nil, arrow = true,
            onSelect = function() Admin.openForecastEvent(eventIndex) end,
        }
    end
    local nextEvent, nextIndex = eventById(forecast.nextEventId)
    if nextEvent then
        options[#options + 1] = { title = Admin.t('forecast.next_event'), description = Admin.numberedSequence(nextEvent, nextIndex), icon = 'forward-step', iconColor = '#22c55e', readOnly = true }
    elseif forecast.mode == 'dynamic' then
        options[#options + 1] = { title = Admin.t('forecast.next_event'), description = Admin.t('forecast.dynamic_pending'), icon = 'dice', readOnly = true }
    elseif forecast.mode == 'unique' and currentEvent then
        options[#options + 1] = { title = Admin.t('forecast.next_event'), description = Admin.numberedSequence(currentEvent, currentIndex), icon = 'repeat', readOnly = true }
    end
    if #steps == 0 then options[#options + 1] = { title = Admin.t('forecast.empty'), icon = 'triangle-exclamation', readOnly = true } end
    pr_lib.registerContext({ id = 'renewed_weather:forecast', menu = Admin.root, title = Admin.t('forecast.title'), options = options })
    pr_lib.showContext('renewed_weather:forecast')
end