local RW = RenewedWeather
local Admin = { data = nil, root = 'renewed_weather:admin' }
RenewedWeather.Admin = Admin

function Admin.t(key, params) return RW.t(key, params) end
function Admin.copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}; for key, child in pairs(value) do result[Admin.copy(key)] = Admin.copy(child) end
    return result
end
function Admin.notify(key, kind, params)
    pr_lib.notify({ title = Admin.t('menu.title'), description = Admin.t(key, params), type = kind or 'inform' })
end
function Admin.icon(enabled) return enabled and 'toggle-on' or 'toggle-off' end
function Admin.color(enabled) return enabled and '#22c55e' or '#6b7280' end
function Admin.percent(value) return ('%.0f%%'):format((tonumber(value) or 0) * 100) end
function Admin.weatherLabel(value) return Admin.t('weather.' .. tostring(value):lower()) end
function Admin.sequenceLabel(sequence)
    if sequence and sequence.name and sequence.name ~= '' then return sequence.name end
    if sequence and sequence.nameKey then return Admin.t(sequence.nameKey) end
    return sequence and sequence.id or '-'
end
function Admin.numberedSequence(sequence, index) return ('%d - %s'):format(index, Admin.sequenceLabel(sequence)) end
function Admin.forecastSteps()
    local forecast = Admin.data and Admin.data.forecast
    if type(forecast) ~= 'table' then return {} end
    return type(forecast.steps) == 'table' and forecast.steps or forecast
end
function Admin.fetch()
    local result = pr_lib.callback.await(RW.Callbacks.getAdminData, 10000)
    if type(result) ~= 'table' then Admin.notify('notify.load_failed', 'error'); return false end
    Admin.data = result
    return true
end
function Admin.saveTime(returnTo)
    local result = pr_lib.callback.await(RW.Callbacks.saveTime, 10000, Admin.data.time)
    if type(result) ~= 'table' or not result.success then Admin.notify('notify.save_failed', 'error'); return false end
    Admin.data.time = result.config; Admin.notify('notify.saved', 'success')
    if returnTo then returnTo() end
    return true
end
function Admin.saveWeather(returnTo)
    local group = Admin.data.weather and Admin.data.weather.events
    if group and group.items then for index, event in ipairs(group.items) do event.order = index end end
    local result = pr_lib.callback.await(RW.Callbacks.saveWeather, 10000, Admin.data.weather)
    if type(result) ~= 'table' or not result.success then Admin.notify('notify.save_failed', 'error'); return false end
    Admin.data.weather, Admin.data.forecast = result.config, result.forecast or Admin.data.forecast
    Admin.notify('notify.saved', 'success')
    if returnTo then returnTo() end
    return true
end
function Admin.numberDialog(title, fields)
    local rows = {}
    for index, field in ipairs(fields) do
        rows[index] = { type = 'number', label = Admin.t(field.label), description = field.description and Admin.t(field.description) or nil,
            default = field.value, min = field.min, max = field.max, precision = field.precision, required = field.required ~= false }
    end
    local result = pr_lib.inputDialog(Admin.t(title), rows)
    if not result then return nil end
    local output = {}; for index = 1, #result do output[index] = tonumber(result[index]) end
    return output
end
function Admin.textDialog(title, label, value, multiline)
    local result = pr_lib.inputDialog(Admin.t(title), { { type = multiline and 'textarea' or 'input', label = Admin.t(label), default = value or '', required = true } })
    return result and tostring(result[1] or '') or nil
end
function Admin.confirm(title, description)
    return pr_lib.alertDialog({ header = Admin.t(title), content = Admin.t(description), centered = true, cancel = true }) == 'confirm'
end
function Admin.pickWeather(parent, selected, callback)
    local options = {}
    for _, weather in ipairs(RW.WeatherTypes) do
        options[#options + 1] = { title = Admin.weatherLabel(weather), description = Admin.t('weather_description.' .. weather:lower()),
            icon = selected == weather and 'circle-check' or 'cloud', iconColor = selected == weather and '#22c55e' or '#6b7280',
            onSelect = function() callback(weather) end }
    end
    pr_lib.registerContext({ id = 'renewed_weather:weather_picker', menu = parent, title = Admin.t('picker.weather'), searchPlaceholder = Admin.t('picker.search'), options = options })
    pr_lib.showContext('renewed_weather:weather_picker')
end
function Admin.toggleOption(title, description, value, callback, disabled)
    return { title = Admin.t(title), description = Admin.t(description), icon = Admin.icon(value), iconColor = Admin.color(value), disabled = disabled == true,
        onSelect = function() callback(not value) end }
end