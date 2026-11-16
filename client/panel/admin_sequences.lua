local Admin = RenewedWeather.Admin
local function show(id, parent, title, options)
    pr_lib.registerContext({ id = id, menu = parent, title = Admin.t(title), options = options }); pr_lib.showContext(id)
end
local function move(list, index, delta)
    local target = index + delta
    if target < 1 or target > #list then return index end
    list[index], list[target] = list[target], list[index]
    return target
end
local function sequenceAt(index) return Admin.data.weather.events.items[index] end

function Admin.openMonth(index)
    local sequence = sequenceAt(index)
    local parent, options = 'renewed_weather:sequence:' .. index, {}
    for month = 0, 12 do
        local value = month
        options[#options + 1] = { title = value == 0 and Admin.t('common.any') or Admin.t('months.' .. value),
            icon = sequence.month == value and 'circle-check' or 'circle', iconColor = sequence.month == value and '#22c55e' or '#6b7280',
            onSelect = function() sequence.month = value; Admin.saveWeather(function() Admin.openSequence(index) end) end }
    end
    show('renewed_weather:months', parent, 'sequence.month', options)
end

function Admin.openEvent(sequenceIndex, eventIndex)
    local sequence = sequenceAt(sequenceIndex)
    local event = sequence and sequence.weathers[eventIndex]
    if not event then return Admin.openSequence(sequenceIndex) end
    local id = ('renewed_weather:event:%s:%s'):format(sequenceIndex, eventIndex)
    local parent = 'renewed_weather:sequence:' .. sequenceIndex
    local options = {
        { title = Admin.weatherLabel(event.weather), description = Admin.t('event.weather_description'), icon = 'cloud', arrow = true, onSelect = function()
            Admin.pickWeather(id, event.weather, function(value)
                event.weather = value
                event.hasSnow = value == 'SNOW' or value == 'SNOWLIGHT' or value == 'BLIZZARD' or value == 'XMAS'
                Admin.saveWeather(function() Admin.openEvent(sequenceIndex, eventIndex) end)
            end)
        end },
        { title = Admin.t('event.duration'), description = Admin.t('event.duration_description', { minimum = event.time.min, maximum = event.time.max }), icon = 'clock', onSelect = function()
            local result = Admin.numberDialog('event.duration', {
                { label = 'inputs.minimum_minutes', value = event.time.min, min = 1, max = 1440 },
                { label = 'inputs.maximum_minutes', value = event.time.max, min = 1, max = 1440 },
            })
            if result then event.time = { min = math.min(result[1], result[2]), max = math.max(result[1], result[2]) }; Admin.saveWeather(function() Admin.openEvent(sequenceIndex, eventIndex) end) end
        end },
        { title = Admin.t('event.wind'), description = Admin.t('event.wind_description', { speed = event.windSpeed, direction = event.windDirection }), icon = 'wind', onSelect = function()
            local result = Admin.numberDialog('event.wind', {
                { label = 'inputs.wind_speed', value = event.windSpeed, min = 0, max = 20, precision = 2 },
                { label = 'inputs.degrees', value = event.windDirection, min = 0, max = 360, precision = 1 },
            })
            if result then event.windSpeed, event.windDirection = result[1], result[2]; Admin.saveWeather(function() Admin.openEvent(sequenceIndex, eventIndex) end) end
        end },
        Admin.toggleOption('event.snow', 'event.snow_description', event.hasSnow, function(value) event.hasSnow = value; Admin.saveWeather(function() Admin.openEvent(sequenceIndex, eventIndex) end) end),
        { title = Admin.t('common.move_up'), icon = 'arrow-up', disabled = eventIndex == 1, onSelect = function() local nextIndex = move(sequence.weathers, eventIndex, -1); Admin.saveWeather(function() Admin.openEvent(sequenceIndex, nextIndex) end) end },
        { title = Admin.t('common.move_down'), icon = 'arrow-down', disabled = eventIndex == #sequence.weathers, onSelect = function() local nextIndex = move(sequence.weathers, eventIndex, 1); Admin.saveWeather(function() Admin.openEvent(sequenceIndex, nextIndex) end) end },
        { title = Admin.t('event.duplicate'), description = Admin.t('event.duplicate_description'), icon = 'copy', onSelect = function() table.insert(sequence.weathers, eventIndex + 1, Admin.copy(event)); Admin.saveWeather(function() Admin.openEvent(sequenceIndex, eventIndex + 1) end) end },
        { title = Admin.t('event.delete'), description = Admin.t('event.delete_description'), icon = 'trash', iconColor = '#ef4444', disabled = #sequence.weathers <= 1, onSelect = function()
            if Admin.confirm('event.delete', 'event.delete_confirm') then table.remove(sequence.weathers, eventIndex); Admin.saveWeather(function() Admin.openSequence(sequenceIndex) end)
            else Admin.openEvent(sequenceIndex, eventIndex) end
        end },
    }
    show(id, parent, 'event.title', options)
end

function Admin.openSequence(index)
    local sequence = sequenceAt(index)
    if not sequence then return Admin.openSequences() end
    local id = 'renewed_weather:sequence:' .. index
    local options = {
        { title = Admin.numberedSequence(sequence, index), description = Admin.t('sequence.builder_help'), icon = 'diagram-project', readOnly = true },
        { title = Admin.t('sequence.rename'), description = Admin.t('sequence.rename_description'), icon = 'pen', onSelect = function()
            local name = Admin.textDialog('sequence.rename', 'sequence.name', Admin.sequenceLabel(sequence))
            if name and name ~= '' then sequence.name, sequence.nameKey = name, nil; Admin.saveWeather(function() Admin.openSequence(index) end)
            else Admin.openSequence(index) end
        end },
        { title = Admin.t('sequence.force'), description = Admin.t('sequence.force_description'), icon = 'forward-step', iconColor = '#22c55e', onSelect = function()
            local result = pr_lib.callback.await(RenewedWeather.Callbacks.forceEvent, 10000, sequence.id)
            Admin.notify(result and 'notify.forced' or 'notify.force_failed', result and 'success' or 'error')
            Admin.fetch(); Admin.openSequence(index)
        end },
        Admin.toggleOption('sequence.enabled', 'sequence.enabled_description', sequence.enabled, function(value) sequence.enabled = value; Admin.saveWeather(function() Admin.openSequence(index) end) end),
        Admin.toggleOption('sequence.split_regions', 'sequence.split_regions_description', sequence.splitRegions == true, function(value) sequence.splitRegions = value; Admin.saveWeather(function() Admin.openSequence(index) end) end),
        { title = Admin.t('sequence.probability'), description = Admin.t('sequence.probability_description', { chance = Admin.percent(sequence.probability) }), icon = 'dice', onSelect = function()
            local result = Admin.numberDialog('sequence.probability', { { label = 'inputs.probability_percent', value = sequence.probability * 100, min = 0, max = 100 } })
            if result then sequence.probability = result[1] / 100; Admin.saveWeather(function() Admin.openSequence(index) end) end
        end },
        { title = Admin.t('sequence.month'), description = sequence.month == 0 and Admin.t('common.any') or Admin.t('months.' .. sequence.month), icon = 'calendar', arrow = true, onSelect = function() Admin.openMonth(index) end },
        { title = Admin.t('sequence.wind_direction'), description = Admin.t('sequence.wind_direction_description', { direction = sequence.windDirection }), icon = 'compass', onSelect = function()
            local result = Admin.numberDialog('sequence.wind_direction', { { label = 'inputs.degrees', value = sequence.windDirection, min = 0, max = 360, precision = 1 } })
            if result then sequence.windDirection = result[1]; Admin.saveWeather(function() Admin.openSequence(index) end) end
        end },
        { title = Admin.t('sequence.add_event'), description = Admin.t('sequence.add_event_description'), icon = 'circle-plus', iconColor = '#22c55e', onSelect = function()
            sequence.weathers[#sequence.weathers + 1] = { weather = 'EXTRASUNNY', time = { min = 5, max = 10 }, windSpeed = 0, windDirection = sequence.windDirection, hasSnow = false }
            local nextIndex = #sequence.weathers; Admin.saveWeather(function() Admin.openEvent(index, nextIndex) end)
        end },
    }
    for eventIndex, event in ipairs(sequence.weathers) do
        local weatherIndex = eventIndex
        options[#options + 1] = { title = ('%s. %s'):format(weatherIndex, Admin.weatherLabel(event.weather)), description = Admin.t('event.list_description', { minimum = event.time.min, maximum = event.time.max, speed = event.windSpeed }), icon = 'cloud-arrow-right', arrow = true, onSelect = function() Admin.openEvent(index, weatherIndex) end }
    end
    options[#options + 1] = { title = Admin.t('common.move_up'), icon = 'arrow-up', disabled = index == 1, onSelect = function() local nextIndex = move(Admin.data.weather.events.items, index, -1); Admin.saveWeather(function() Admin.openSequence(nextIndex) end) end }
    options[#options + 1] = { title = Admin.t('common.move_down'), icon = 'arrow-down', disabled = index == #Admin.data.weather.events.items, onSelect = function() local nextIndex = move(Admin.data.weather.events.items, index, 1); Admin.saveWeather(function() Admin.openSequence(nextIndex) end) end }
    options[#options + 1] = { title = Admin.t('sequence.delete'), description = Admin.t('sequence.delete_description'), icon = 'trash', iconColor = '#ef4444', onSelect = function()
        if Admin.confirm('sequence.delete', 'sequence.delete_confirm') then table.remove(Admin.data.weather.events.items, index); Admin.saveWeather(Admin.openSequences)
        else Admin.openSequence(index) end
    end }
    show(id, 'renewed_weather:sequences', 'sequence.title', options)
end

function Admin.openSequences()
    local group = Admin.data.weather.events
    local options = {
        Admin.toggleOption('sequence.system_enabled', 'sequence.system_enabled_description', group.enabled, function(value) group.enabled = value; Admin.saveWeather(Admin.openSequences) end),
        { title = Admin.t('sequence.create'), description = Admin.t('sequence.create_description'), icon = 'circle-plus', iconColor = '#22c55e', onSelect = function()
            local name = Admin.textDialog('sequence.create', 'sequence.name', Admin.t('sequence.custom_name', { index = #group.items + 1 }))
            if not name or name == '' then return Admin.openSequences() end
            local index = #group.items + 1
            group.items[index] = { id = ('custom_%s_%s'):format(GetGameTimer(), index), name = name, enabled = true, splitRegions = false, probability = 1, month = 0, windDirection = 0,
                weathers = { { weather = 'EXTRASUNNY', time = { min = 5, max = 10 }, windSpeed = 0, windDirection = 0, hasSnow = false } } }
            Admin.saveWeather(function() Admin.openSequence(index) end)
        end },
    }
    for index, sequence in ipairs(group.items) do
        local eventIndex = index
        options[#options + 1] = { title = Admin.numberedSequence(sequence, index), description = Admin.t('sequence.list_description', { count = #sequence.weathers, chance = Admin.percent(sequence.probability), month = sequence.month == 0 and Admin.t('common.any') or Admin.t('months.' .. sequence.month) }),
            icon = sequence.enabled and 'route' or 'ban', iconColor = sequence.enabled and '#22c55e' or '#6b7280', arrow = true, onSelect = function() Admin.openSequence(eventIndex) end }
    end
    show('renewed_weather:sequences', Admin.root, 'sequence.list_title', options)
end