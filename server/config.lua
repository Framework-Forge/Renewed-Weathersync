local RW = RenewedWeather
local Runtime = RW.Runtime
local Service = { provider = nil }
local resourceName = GetCurrentResourceName()
local indexPath = 'data/profiles.json'

local function clone(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, child in pairs(value) do out[clone(key, seen)] = clone(child, seen) end
    return out
end
local function clamp(value, minimum, maximum, fallback)
    value = tonumber(value); if value == nil then value = fallback or minimum end
    return math.max(minimum, math.min(maximum, value))
end
local function boolean(value, fallback) if type(value) == 'boolean' then return value end; return fallback == true end
local function choose(value, fallback) if value ~= nil then return value end; return fallback end
local function weatherType(value, fallback)
    value = tostring(value or ''):upper()
    return RW.WeatherTypeSet[value] and value or fallback or 'EXTRASUNNY'
end
local function slugify(value)
    local slug = tostring(value or ''):lower():gsub('[^%w_%-]', '_'):gsub('_+', '_'):gsub('^_+', ''):gsub('_+$', '')
    return slug:sub(1, 64)
end
local function profilePath(slug, file) return ('data/profiles/%s/%s.json'):format(slug, file) end
local function ensureDirectory(slug)
    local ok, result = pcall(function() return exports[resourceName]:EnsureProfileDirectory(slug) end)
    return ok and result ~= false
end
local function loadJson(path)
    local ok, value = pcall(pr_lib.loadJson, path, true)
    if not ok then print(('^1[Renewed-Weathersync] JSON %s: %s^0'):format(path, tostring(value))); return nil end
    return value
end
local function saveJson(path, value)
    local ok, result = pr_lib.saveJson(path, value)
    return ok, result
end

local function normalizeTime(value)
    value = type(value) == 'table' and value or {}
    local night = type(value.nightTime) == 'table' and value.nightTime or {}
    local startup = type(value.startUpTime) == 'table' and value.startUpTime or {}
    local daySeconds = value.daySecondsPerMinute or value.secondsPerGameMinute or ((tonumber(value.timeScale) or 2000) / 1000)
    local nightSeconds = value.nightSecondsPerMinute or ((tonumber(value.timeScaleNight) or 8000) / 1000)
    local scalable = choose(value.useScalableTime, value.useNightScale)
    return {
        schemaVersion = 2,
        useRealTime = boolean(value.useRealTime, false),
        freezeTime = boolean(value.freezeTime, false),
        useScalableTime = boolean(scalable, false),
        daySecondsPerMinute = clamp(daySeconds, 1, 600, 2),
        nightSecondsPerMinute = clamp(nightSeconds, 1, 600, 8),
        defaultSecondsPerMinute = clamp(value.defaultSecondsPerMinute, 1, 60, 2),
        nightTime = {
            beginning = math.floor(clamp(night.beginning, 0, 23, 22)),
            ending = math.floor(clamp(night.ending, 0, 23, 6)),
        },
        startUpTime = {
            hour = math.floor(clamp(startup.hour, 0, 23, 12)),
            minute = math.floor(clamp(startup.minute, 0, 59, 0)),
        },
    }
end

local function normalizeRange(value)
    if type(value) == 'number' then local n = math.floor(clamp(value, 1, 1440, 5)); return { min = n, max = n } end
    value = type(value) == 'table' and value or {}
    local minimum = math.floor(clamp(value.min or value[1], 1, 1440, 5))
    local maximum = math.floor(clamp(value.max or value[2], 1, 1440, minimum))
    if minimum > maximum then minimum, maximum = maximum, minimum end
    return { min = minimum, max = maximum }
end

local function normalizeWeatherStep(value, eventDirection)
    value = type(value) == 'table' and value or {}
    local direction = choose(value.windDirection, eventDirection)
    return {
        weather = weatherType(value.weather),
        time = normalizeRange(value.time),
        windSpeed = clamp(value.windSpeed, 0, 20, 0),
        windDirection = clamp(direction, 0, 360, eventDirection or 0),
        hasSnow = boolean(choose(value.hasSnow, value.HasSnow), false),
    }
end

local function normalizeEvent(value, index)
    value = type(value) == 'table' and value or {}
    local direction = clamp(value.windDirection, 0, 360, 0)
    local input = type(value.weathers) == 'table' and value.weathers or type(value.events) == 'table' and value.events or {}
    local weathers = {}
    for i = 1, math.min(#input, 100) do weathers[#weathers + 1] = normalizeWeatherStep(input[i], direction) end
    if #weathers == 0 then weathers[1] = normalizeWeatherStep({}, direction) end
    local id = slugify(value.id or ('event_%s'):format(index)); if id == '' then id = ('event_%s'):format(index) end
    return {
        id = id,
        name = type(value.name) == 'string' and value.name:sub(1, 80) or ('Evento %s'):format(index),
        nameKey = type(value.nameKey) == 'string' and value.nameKey:sub(1, 100) or nil,
        enabled = boolean(value.enabled, true),
        splitRegions = boolean(value.splitRegions, false),
        order = math.max(1, math.floor(tonumber(value.order) or index)),
        probability = clamp(value.probability, 0, 1, 1),
        month = math.floor(clamp(value.month, 0, 12, 0)),
        windDirection = direction,
        weathers = weathers,
    }
end

local function defaultWeather()
    return {
        schemaVersion = 3,
        mode = 'dynamic',
        uniqueEventId = 'default',
        useScheduledWeather = true,
        decemberSnow = false,
        events = { enabled = true, items = {
            { id = 'default', name = 'Evento inicial', enabled = true, splitRegions = false, order = 1, probability = 1, month = 0, windDirection = 0,
                weathers = { { weather = 'EXTRASUNNY', time = { min = 30, max = 30 }, windSpeed = 0, windDirection = 0, hasSnow = false } } }
        } },
    }
end

local function normalizeWeather(value)
    value = type(value) == 'table' and value or defaultWeather()
    local group = type(value.events) == 'table' and value.events or type(value.sequences) == 'table' and value.sequences or {}
    local input = type(group.items) == 'table' and group.items or type(value.weatherSequences) == 'table' and value.weatherSequences or {}
    local items = {}
    for i = 1, math.min(#input, 100) do items[#items + 1] = normalizeEvent(input[i], i) end
    if #items == 0 then items[1] = normalizeEvent(defaultWeather().events.items[1], 1) end
    local usedIds = {}
    for _, event in ipairs(items) do
        local base, suffix = event.id, 1
        while usedIds[event.id] do suffix = suffix + 1; event.id = ('%s_%s'):format(base, suffix) end
        usedIds[event.id] = true
    end
    table.sort(items, function(a, b) if a.order == b.order then return a.id < b.id end; return a.order < b.order end)
    for i = 1, #items do items[i].order = i end
    local mode = tostring(value.mode or 'dynamic'):lower(); if mode == 'fixed' then mode = 'unique' end
    if not RW.Modes[mode] then mode = 'dynamic' end
    local unique = tostring(value.uniqueEventId or '')
    local found = false; for i = 1, #items do if items[i].id == unique then found = true break end end
    if not found then unique = items[1].id end
    return {
        schemaVersion = 3,
        mode = mode,
        uniqueEventId = unique,
        useScheduledWeather = boolean(value.useScheduledWeather, true),
        decemberSnow = boolean(value.decemberSnow, false),
        events = { enabled = boolean(choose(group.enabled, true), true), items = items },
    }
end

local function normalizeIndex(value)
    value = type(value) == 'table' and value or {}
    local items = type(value.items) == 'table' and value.items or {}
    local out = {}
    for slug, meta in pairs(items) do
        if type(slug) == 'string' and slugify(slug) == slug then
            meta = type(meta) == 'table' and meta or {}
            out[slug] = {
                name = tostring(meta.name or slug):sub(1, 80),
                createdAt = math.floor(tonumber(meta.createdAt) or os.time()),
                updatedAt = math.floor(tonumber(meta.updatedAt) or os.time()),
            }
        end
    end
    return { schemaVersion = 1, items = out }
end

Service.index = normalizeIndex(loadJson(indexPath))

local function metadata(slug, name)
    local current = Service.index.items[slug]
    if current then
        if name then current.name = tostring(name):sub(1, 80) end
        current.updatedAt = os.time()
        return current
    end
    current = { name = tostring(name or slug):sub(1, 80), createdAt = os.time(), updatedAt = os.time() }
    Service.index.items[slug] = current
    return current
end

local function saveIndex()
    local ok, result = saveJson(indexPath, Service.index)
    if ok then
        for slug, meta in pairs(Service.index.items) do
            if ensureDirectory(slug) then saveJson(profilePath(slug, 'profile'), { schemaVersion = 1, slug = slug, name = meta.name, createdAt = meta.createdAt, updatedAt = meta.updatedAt }) end
        end
    end
    return ok, result
end

local function saveProfileFiles(slug, timeConfig, weatherConfig, name)
    if not ensureDirectory(slug) then return false, 'directory_failed' end
    local okTime, errTime = saveJson(profilePath(slug, 'time'), normalizeTime(timeConfig))
    if not okTime then return false, errTime end
    local okWeather, errWeather = saveJson(profilePath(slug, 'weather'), normalizeWeather(weatherConfig))
    if not okWeather then return false, errWeather end
    metadata(slug, name)
    local okIndex, errIndex = saveIndex()
    if not okIndex then return false, errIndex end
    return true
end

local activeSlug = Runtime.getActiveProfile()
local rootTime = loadJson('data/time.json')
local rootWeather = loadJson('data/weather.json')
local activeTime = loadJson(profilePath(activeSlug, 'time'))
local activeWeather = loadJson(profilePath(activeSlug, 'weather'))
if not activeTime or not activeWeather then
    activeTime = activeTime or rootTime or normalizeTime({})
    activeWeather = activeWeather or rootWeather or defaultWeather()
    saveProfileFiles(activeSlug, activeTime, activeWeather, Service.index.items[activeSlug] and Service.index.items[activeSlug].name or 'Padrão')
end
Service.time = normalizeTime(activeTime)
Service.weather = normalizeWeather(activeWeather)
metadata(activeSlug, Service.index.items[activeSlug] and Service.index.items[activeSlug].name or 'Padrão')
saveProfileFiles(activeSlug, Service.time, Service.weather)
saveJson('data/time.json', Service.time)
saveJson('data/weather.json', Service.weather)

local function allowed(source) return source == 0 or IsPlayerAceAllowed(source, 'command.weather') end

local function save(section, value)
    local normalizer = section == 'time' and normalizeTime or normalizeWeather
    local normalized = normalizer(value)
    local path = profilePath(Runtime.getActiveProfile(), section)
    local ok, result = saveJson(path, normalized)
    if not ok then return false, result end
    saveJson(('data/%s.json'):format(section), normalized)
    Service[section] = normalized
    metadata(Runtime.getActiveProfile())
    saveIndex()
    TriggerEvent('Renewed-Weathersync:server:configChanged', section, clone(normalized))
    return true, clone(normalized)
end

local function profileInitial(timeConfig, weatherConfig)
    return {
        time = { hour = timeConfig.startUpTime.hour, minute = timeConfig.startUpTime.minute },
        weather = { mode = weatherConfig.mode, eventId = '', eventIndex = 1, weatherIndex = 1, remainingMinutes = 0, sampledDuration = 0, lastGameMinute = timeConfig.startUpTime.hour * 60 + timeConfig.startUpTime.minute, cycleNumber = 0 },
    }
end

function Service.getTime() return clone(Service.time) end
function Service.getWeather() return clone(Service.weather) end
function Service.saveTime(value) return save('time', value) end
function Service.saveWeather(value) return save('weather', value) end
function Service.setProvider(value) Service.provider = value end
function Service.getForecast() return Service.provider and Service.provider.get and Service.provider.get() or { steps = {} } end
function Service.rebuildForecast() return Service.provider and Service.provider.rebuild and Service.provider.rebuild() or false end

function Service.listProfiles()
    local out = {}
    local active = Runtime.getActiveProfile()
    for slug, meta in pairs(Service.index.items) do
        local weather = loadJson(profilePath(slug, 'weather'))
        out[#out + 1] = {
            slug = slug, name = meta.name, active = slug == active, createdAt = meta.createdAt, updatedAt = meta.updatedAt,
            mode = weather and normalizeWeather(weather).mode or 'dynamic',
            events = weather and #(normalizeWeather(weather).events.items) or 0,
        }
    end
    table.sort(out, function(a, b) if a.active ~= b.active then return a.active end; return a.name:lower() < b.name:lower() end)
    return out
end

function Service.createProfile(name, sourceSlug, clean)
    name = tostring(name or ''):sub(1, 80)
    local base = slugify(name); if base == '' then return false, 'invalid_name' end
    local slug, suffix = base, 1
    while Service.index.items[slug] do suffix = suffix + 1; slug = ('%s_%s'):format(base, suffix) end
    local timeConfig, weatherConfig
    if clean then timeConfig, weatherConfig = normalizeTime({}), defaultWeather()
    elseif sourceSlug then timeConfig, weatherConfig = loadJson(profilePath(sourceSlug, 'time')), loadJson(profilePath(sourceSlug, 'weather'))
    else timeConfig, weatherConfig = Service.getTime(), Service.getWeather() end
    if not timeConfig or not weatherConfig then return false, 'source_not_found' end
    local ok, err = saveProfileFiles(slug, timeConfig, weatherConfig, name)
    if not ok then return false, err end
    Runtime.ensureProfile(slug, profileInitial(normalizeTime(timeConfig), normalizeWeather(weatherConfig))); Runtime.flush()
    return true, slug
end

function Service.activateProfile(slug, restart)
    if not Service.index.items[slug] then return false, 'not_found' end
    local timeConfig = loadJson(profilePath(slug, 'time'))
    local weatherConfig = loadJson(profilePath(slug, 'weather'))
    if not timeConfig or not weatherConfig then return false, 'invalid_profile' end
    timeConfig, weatherConfig = normalizeTime(timeConfig), normalizeWeather(weatherConfig)
    local initial = profileInitial(timeConfig, weatherConfig)
    local ok, err = Runtime.activateProfile(slug, restart == true, initial)
    if not ok then return false, err end
    Service.time, Service.weather = timeConfig, weatherConfig
    saveJson('data/time.json', timeConfig); saveJson('data/weather.json', weatherConfig)
    TriggerEvent('Renewed-Weathersync:server:profileChanged', clone(timeConfig), clone(weatherConfig), restart == true)
    return true
end

function Service.renameProfile(slug, name)
    local meta = Service.index.items[slug]; if not meta then return false, 'not_found' end
    name = tostring(name or ''):sub(1, 80); if name == '' then return false, 'invalid_name' end
    local target = slugify(name)
    if target == '' then return false, 'invalid_name' end
    if target ~= slug and Service.index.items[target] then return false, 'already_exists' end
    if target ~= slug then
        local ok, renamed = pcall(function() return exports[resourceName]:RenameProfileDirectory(slug, target) end)
        if not ok or not renamed then return false, 'rename_failed' end
        Service.index.items[target] = meta; Service.index.items[slug] = nil
        if not Runtime.renameProfile(slug, target) then return false, 'runtime_rename_failed' end
        slug = target
    end
    metadata(slug, name); saveIndex()
    return true, slug
end

function Service.deleteProfile(slug)
    if slug == Runtime.getActiveProfile() then return false, 'active_profile' end
    if not Service.index.items[slug] then return false, 'not_found' end
    local ok, deleted = pcall(function() return exports[resourceName]:DeleteProfileDirectory(slug) end)
    if not ok or not deleted then return false, 'delete_failed' end
    Service.index.items[slug] = nil; Runtime.deleteProfile(slug); saveIndex()
    return true
end

function Service.exportProfile(slug)
    local meta = Service.index.items[slug]; if not meta then return nil end
    local timeConfig, weatherConfig = loadJson(profilePath(slug, 'time')), loadJson(profilePath(slug, 'weather'))
    if not timeConfig or not weatherConfig then return nil end
    return { schemaVersion = 1, name = meta.name, time = normalizeTime(timeConfig), weather = normalizeWeather(weatherConfig) }
end

function Service.importProfile(name, payload)
    local ok, bundle = pcall(json.decode, tostring(payload or ''))
    if not ok or type(bundle) ~= 'table' or type(bundle.time) ~= 'table' or type(bundle.weather) ~= 'table' then return false, 'invalid_json' end
    return Service.createProfile(name or bundle.name, nil, false, bundle)
end

local originalCreate = Service.createProfile
Service.createProfile = function(name, sourceSlug, clean, bundle)
    if bundle then
        local base = slugify(name or bundle.name); if base == '' then return false, 'invalid_name' end
        local slug, suffix = base, 1
        while Service.index.items[slug] do suffix = suffix + 1; slug = ('%s_%s'):format(base, suffix) end
        local ok, err = saveProfileFiles(slug, normalizeTime(bundle.time), normalizeWeather(bundle.weather), name or bundle.name)
        if not ok then return false, err end
        Runtime.ensureProfile(slug, profileInitial(normalizeTime(bundle.time), normalizeWeather(bundle.weather))); Runtime.flush()
        return true, slug
    end
    return originalCreate(name, sourceSlug, clean)
end

function Service.overwriteProfile(slug)
    if not Service.index.items[slug] then return false, 'not_found' end
    return saveProfileFiles(slug, Service.time, Service.weather, Service.index.items[slug].name)
end

local function adminData()
    return {
        time = Service.getTime(), weather = Service.getWeather(), forecast = Service.getForecast(),
        runtime = Runtime.get(), profiles = Service.listProfiles(),
    }
end

pr_lib.callback.register(RW.Callbacks.getAdminData, function(source) if not allowed(source) then return false end; return adminData() end)
pr_lib.callback.register(RW.Callbacks.saveTime, function(source, value) if not allowed(source) then return false end; local ok, result = Service.saveTime(value); return { success = ok, config = ok and result or nil, error = ok and nil or result } end)
pr_lib.callback.register(RW.Callbacks.saveWeather, function(source, value) if not allowed(source) then return false end; local ok, result = Service.saveWeather(value); return { success = ok, config = ok and result or nil, forecast = ok and Service.getForecast() or nil, error = ok and nil or result } end)
pr_lib.callback.register(RW.Callbacks.rebuild, function(source) if not allowed(source) then return false end; local result = Service.rebuildForecast(); return { success = result ~= false, forecast = Service.getForecast(), runtime = Runtime.get() } end)
pr_lib.callback.register(RW.Callbacks.profileList, function(source) if not allowed(source) then return false end; return { active = Runtime.getActiveProfile(), items = Service.listProfiles() } end)
pr_lib.callback.register(RW.Callbacks.profileCreate, function(source, name, clean) if not allowed(source) then return false end; local ok, result = Service.createProfile(name, nil, clean == true); return { success = ok, slug = ok and result or nil, error = ok and nil or result } end)
pr_lib.callback.register(RW.Callbacks.profileDuplicate, function(source, slug, name) if not allowed(source) then return false end; local ok, result = Service.createProfile(name, slug, false); return { success = ok, slug = ok and result or nil, error = ok and nil or result } end)
pr_lib.callback.register(RW.Callbacks.profileActivate, function(source, slug, restart) if not allowed(source) then return false end; local ok, err = Service.activateProfile(slug, restart == true); return { success = ok, error = err, data = ok and adminData() or nil } end)
pr_lib.callback.register(RW.Callbacks.profileRename, function(source, slug, name) if not allowed(source) then return false end; local ok, result = Service.renameProfile(slug, name); return { success = ok, slug = ok and result or nil, error = ok and nil or result } end)
pr_lib.callback.register(RW.Callbacks.profileDelete, function(source, slug) if not allowed(source) then return false end; local ok, err = Service.deleteProfile(slug); return { success = ok, error = err } end)
pr_lib.callback.register(RW.Callbacks.profileExport, function(source, slug) if not allowed(source) then return false end; local bundle = Service.exportProfile(slug); return bundle and { success = true, bundle = bundle } or { success = false, error = 'not_found' } end)
pr_lib.callback.register(RW.Callbacks.profileImport, function(source, name, payload) if not allowed(source) then return false end; local ok, result = Service.importProfile(name, payload); return { success = ok, slug = ok and result or nil, error = ok and nil or result } end)
pr_lib.callback.register(RW.Callbacks.profileOverwrite, function(source, slug) if not allowed(source) then return false end; local ok, err = Service.overwriteProfile(slug); return { success = ok, error = err } end)

exports('GetTimeConfig', Service.getTime)
exports('GetWeatherConfig', Service.getWeather)
exports('SaveTimeConfig', Service.saveTime)
exports('SaveWeatherConfig', Service.saveWeather)
exports('GetWeatherProfiles', Service.listProfiles)
exports('ActivateWeatherProfile', Service.activateProfile)
RenewedWeather.ConfigService = Service