local Admin = RenewedWeather.Admin

local function currentEvent()
    local runtime = Admin.data.runtime and Admin.data.runtime.weather or {}
    for index, event in ipairs((Admin.data.weather.events and Admin.data.weather.events.items) or {}) do
        if event.id == runtime.eventId then return Admin.numberedSequence(event, index) end
    end
    return runtime.eventId ~= '' and runtime.eventId or '-'
end

function Admin.openSummary()
    local runtime = Admin.data.runtime and Admin.data.runtime.weather or {}
    local time = Admin.data.runtime and Admin.data.runtime.time or {}
    local selected = Admin.data.weather.mode
    local active = runtime.mode or selected
    local options = {
        { title = Admin.t('summary.profile'), description = tostring(Admin.data.runtime.activeProfile or 'padrao'), icon = 'folder-open', readOnly = true },
        { title = Admin.t('summary.clock'), description = Admin.t('summary.clock_description', { hour = time.hour or 0, minute = time.minute or 0 }), icon = 'clock', readOnly = true },
        { title = Admin.t('summary.mode'), description = Admin.t('summary.mode_description', { active = Admin.t('mode.' .. active), selected = Admin.t('mode.' .. selected) }), icon = 'gears', readOnly = true },
        { title = Admin.t('summary.event'), description = currentEvent(), icon = 'flag', readOnly = true },
        { title = Admin.t('summary.weather'), description = runtime.current and Admin.weatherLabel(runtime.current.weather) or '-', icon = 'cloud-sun', readOnly = true },
        { title = Admin.t('summary.remaining'), description = Admin.t('summary.remaining_description', { minutes = runtime.remainingMinutes or 0 }), icon = 'hourglass-half', readOnly = true },
    }
    if runtime.pendingMode then
        options[#options + 1] = { title = Admin.t('summary.pending_mode'), description = Admin.t('mode.' .. runtime.pendingMode), icon = 'clock-rotate-left', iconColor = '#f59e0b', readOnly = true }
    end
    pr_lib.registerContext({ id = 'renewed_weather:summary', menu = Admin.root, title = Admin.t('menu.status'), options = options })
    pr_lib.showContext('renewed_weather:summary')
end

function Admin.openMain(refresh, parentMenu, parentResource)
    if parentMenu ~= nil then Admin.parentMenu, Admin.parentResource = parentMenu, parentResource end
    if refresh ~= false and not Admin.fetch() then return end
    pr_lib.registerContext({ id = Admin.root, title = Admin.t('menu.title'), menu = Admin.parentMenu, menuResource = Admin.parentResource, options = {
        { title = Admin.t('menu.status'), description = Admin.t('menu.status_open'), icon = 'circle-info', arrow = true, onSelect = Admin.openSummary },
        { title = Admin.t('menu.forecast'), description = Admin.t('menu.forecast_description'), icon = 'list-ol', arrow = true, onSelect = Admin.openForecast },
        { title = Admin.t('menu.sequences'), description = Admin.t('menu.sequences_description'), icon = 'route', arrow = true, onSelect = Admin.openSequences },
        { title = Admin.t('menu.settings'), description = Admin.t('menu.settings_description'), icon = 'gears', arrow = true, onSelect = Admin.openSettings },
        { title = Admin.t('menu.rebuild'), description = Admin.t('menu.rebuild_description'), icon = 'arrows-rotate', iconColor = '#22c55e', onSelect = function()
            if not Admin.confirm('menu.rebuild', 'menu.rebuild_confirm') then return Admin.openMain(false) end
            local result = pr_lib.callback.await(RenewedWeather.Callbacks.rebuild, 10000)
            if type(result) == 'table' and result.success then
                Admin.data.forecast, Admin.data.runtime = result.forecast, result.runtime or Admin.data.runtime
                Admin.notify('notify.rebuilt', 'success')
            else Admin.notify('notify.rebuild_failed', 'error') end
            Admin.openMain(true)
        end },
    } })
    pr_lib.showContext(Admin.root)
end

RegisterNetEvent('Renewed-Weather:client:openAdmin', function(parentMenu, parentResource)
    if parentMenu == nil then Admin.parentMenu, Admin.parentResource = nil, nil end
    Admin.openMain(true, parentMenu, parentResource)
end)
RegisterNetEvent('Renewed-Weather:client:timeRejected', function() Admin.notify('notify.real_time_blocked', 'error') end)
exports('OpenWeatherAdmin', function(parentMenu, parentResource)
    if parentMenu == nil then Admin.parentMenu, Admin.parentResource = nil, nil end
    Admin.openMain(true, parentMenu, parentResource)
    return true
end)