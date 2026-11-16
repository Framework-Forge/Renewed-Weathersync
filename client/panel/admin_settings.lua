local Admin = RenewedWeather.Admin
local function ctx(id, parent, title, options)
    pr_lib.registerContext({ id = id, menu = parent, title = Admin.t(title), options = options }); pr_lib.showContext(id)
end

function Admin.openScalableTime()
    local config = Admin.data.time
    local id = 'renewed_weather:scalable_time'
    local ignored = config.useRealTime
    ctx(id, 'renewed_weather:time', 'time.scalable_title', {
        { title = Admin.t(ignored and 'time.scalable_ignored' or 'time.scalable_status'), description = Admin.t(ignored and 'time.scalable_ignored_description' or 'time.scalable_status_description'), icon = ignored and 'triangle-exclamation' or 'circle-info', iconColor = ignored and '#f59e0b' or '#22c55e', readOnly = true },
        Admin.toggleOption('time.scalable', 'time.scalable_description', config.useScalableTime, function(value) config.useScalableTime = value; Admin.saveTime(Admin.openScalableTime) end),
        { title = Admin.t('time.day_scale'), description = Admin.t('time.scale_seconds_description', { value = config.daySecondsPerMinute }), icon = 'sun', onSelect = function()
            local result = Admin.numberDialog('time.day_scale', { { label = 'inputs.seconds_per_minute', value = config.daySecondsPerMinute, min = 1, max = 600, precision = 2 } })
            if result then config.daySecondsPerMinute = result[1]; Admin.saveTime(Admin.openScalableTime) end
        end },
        { title = Admin.t('time.night_scale_value'), description = Admin.t('time.scale_seconds_description', { value = config.nightSecondsPerMinute }), icon = 'moon', onSelect = function()
            local result = Admin.numberDialog('time.night_scale_value', { { label = 'inputs.seconds_per_minute', value = config.nightSecondsPerMinute, min = 1, max = 600, precision = 2 } })
            if result then config.nightSecondsPerMinute = result[1]; Admin.saveTime(Admin.openScalableTime) end
        end },
        { title = Admin.t('time.night_window'), description = Admin.t('time.night_window_description', { beginning = config.nightTime.beginning, ending = config.nightTime.ending }), icon = 'clock', onSelect = function()
            local result = Admin.numberDialog('time.night_window', {
                { label = 'inputs.beginning_hour', value = config.nightTime.beginning, min = 0, max = 23 },
                { label = 'inputs.ending_hour', value = config.nightTime.ending, min = 0, max = 23 },
            })
            if result then config.nightTime = { beginning = result[1], ending = result[2] }; Admin.saveTime(Admin.openScalableTime) end
        end },
    })
end

function Admin.openTime()
    local config = Admin.data.time
    local runtime = Admin.data.runtime and Admin.data.runtime.time or config.startUpTime
    local real = config.useRealTime
    ctx('renewed_weather:time', 'renewed_weather:settings', 'time.title', {
        Admin.toggleOption('time.real_time', 'time.real_time_description', real, function(value) config.useRealTime = value; Admin.saveTime(Admin.openTime) end),
        { title = Admin.t('time.force'), description = real and Admin.t('time.force_real_disabled') or Admin.t('time.force_description', { hour = runtime.hour or 0, minute = runtime.minute or 0 }), icon = 'clock-rotate-left', disabled = real, onSelect = function()
            local result = pr_lib.inputDialog(Admin.t('time.force'), {
                { type = 'number', label = Admin.t('inputs.hour'), default = runtime.hour or 0, min = 0, max = 23, required = true },
                { type = 'number', label = Admin.t('inputs.minute'), default = runtime.minute or 0, min = 0, max = 59, required = true },
                { type = 'checkbox', label = Admin.t('time.freeze_with_force'), checked = config.freezeTime == true },
            })
            if result then
                local response = pr_lib.callback.await(RenewedWeather.Callbacks.forceTime, 10000, tonumber(result[1]), tonumber(result[2]), result[3] == true)
                if type(response) == 'table' and response.success then Admin.notify('notify.saved', 'success'); Admin.fetch()
                else Admin.notify(response and response.error == 'real_time_enabled' and 'notify.real_time_blocked' or 'notify.save_failed', 'error') end
            end
            Admin.openTime()
        end },
        Admin.toggleOption('time.freeze', real and 'time.freeze_real_description' or 'time.freeze_description', config.freezeTime, function(value) config.freezeTime = value; Admin.saveTime(Admin.openTime) end, real),
        { title = Admin.t('time.scalable_title'), description = Admin.t(real and 'time.scalable_ignored_description' or 'time.scalable_menu_description'), icon = 'stopwatch', arrow = true, onSelect = Admin.openScalableTime },
        { title = Admin.t('time.startup'), description = Admin.t('time.startup_description', { hour = config.startUpTime.hour, minute = config.startUpTime.minute }), icon = 'play', disabled = real, onSelect = function()
            local result = Admin.numberDialog('time.startup', {
                { label = 'inputs.hour', value = config.startUpTime.hour, min = 0, max = 23 },
                { label = 'inputs.minute', value = config.startUpTime.minute, min = 0, max = 59 },
            })
            if result then config.startUpTime = { hour = result[1], minute = result[2] }; Admin.saveTime(Admin.openTime) end
        end },
        { title = Admin.t('time.default_speed'), description = Admin.t('time.default_speed_description', { value = config.defaultSecondsPerMinute }), icon = 'gamepad', readOnly = true },
    })
end

function Admin.openMode()
    local weather = Admin.data.weather
    local options = {}
    for _, name in ipairs({ 'daily_fixed', 'sequential', 'dynamic', 'unique' }) do
        local mode = name
        options[#options + 1] = { title = Admin.t('mode.' .. mode), description = Admin.t('mode_description.' .. mode),
            icon = weather.mode == mode and 'circle-check' or 'circle', iconColor = weather.mode == mode and '#22c55e' or '#6b7280',
            onSelect = function() weather.mode = mode; Admin.saveWeather(Admin.openSettings) end }
    end
    ctx('renewed_weather:mode', 'renewed_weather:settings', 'engine.mode', options)
end

function Admin.openUnique()
    local weather = Admin.data.weather
    local options = { { title = Admin.t('unique.explanation'), description = Admin.t('unique.explanation_description'), icon = 'circle-info', readOnly = true } }
    for index, event in ipairs(weather.events.items) do
        local item = event
        options[#options + 1] = { title = Admin.numberedSequence(item, index), description = Admin.t('unique.event_description', { count = #item.weathers }),
            icon = weather.uniqueEventId == item.id and 'circle-check' or 'circle', iconColor = weather.uniqueEventId == item.id and '#22c55e' or '#6b7280',
            onSelect = function() weather.uniqueEventId = item.id; Admin.saveWeather(Admin.openUnique) end }
    end
    ctx('renewed_weather:unique', 'renewed_weather:settings', 'unique.title', options)
end

function Admin.openSettings()
    local weather = Admin.data.weather
    ctx('renewed_weather:settings', Admin.root, 'menu.settings', {
        { title = Admin.t('engine.mode'), description = Admin.t('mode_description.' .. weather.mode), icon = 'shuffle', arrow = true, onSelect = Admin.openMode },
        Admin.toggleOption('engine.scheduled', 'engine.scheduled_description', weather.useScheduledWeather, function(value) weather.useScheduledWeather = value; Admin.saveWeather(Admin.openSettings) end),
        Admin.toggleOption('engine.december_snow', 'engine.december_snow_ground_description', weather.decemberSnow, function(value) weather.decemberSnow = value; Admin.saveWeather(Admin.openSettings) end),
        { title = Admin.t('menu.time'), description = Admin.t('menu.time_description'), icon = 'clock', arrow = true, onSelect = Admin.openTime },
        { title = Admin.t('unique.title'), description = Admin.t('unique.explanation_description'), icon = 'repeat', arrow = true, onSelect = Admin.openUnique },
        { title = Admin.t('profiles.title'), description = Admin.t('profiles.description', { profile = Admin.data.runtime.activeProfile or 'padrao' }), icon = 'folder-tree', arrow = true, onSelect = Admin.openProfiles },
    })
end