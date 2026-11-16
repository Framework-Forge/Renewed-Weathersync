local Runtime = { path = 'data/runtime.json', dirty = false }

local function clone(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, child in pairs(value) do out[clone(key)] = clone(child) end
    return out
end

local function clampInteger(value, minimum, maximum, fallback)
    value = math.floor(tonumber(value) or fallback or minimum)
    return math.max(minimum, math.min(maximum, value))
end

local function normalizeTime(value)
    value = type(value) == 'table' and value or {}
    return { hour = clampInteger(value.hour, 0, 23, 12), minute = clampInteger(value.minute, 0, 59, 0) }
end

local function normalizeWeather(value)
    value = type(value) == 'table' and value or {}
    return {
        mode = tostring(value.mode or 'dynamic'),
        pendingMode = type(value.pendingMode) == 'string' and value.pendingMode or nil,
        eventId = tostring(value.eventId or ''),
        eventIndex = math.max(1, math.floor(tonumber(value.eventIndex) or 1)),
        weatherIndex = math.max(1, math.floor(tonumber(value.weatherIndex) or 1)),
        remainingMinutes = math.max(0, math.floor(tonumber(value.remainingMinutes) or 0)),
        sampledDuration = math.max(0, math.floor(tonumber(value.sampledDuration) or 0)),
        lastGameMinute = clampInteger(value.lastGameMinute, 0, 1439, 720),
        cycleNumber = math.max(0, math.floor(tonumber(value.cycleNumber) or 0)),
        nextEventId = type(value.nextEventId) == 'string' and value.nextEventId or nil,
        current = type(value.current) == 'table' and clone(value.current) or nil,
        updatedAt = math.floor(tonumber(value.updatedAt) or 0),
    }
end

local function normalizeProfile(value)
    value = type(value) == 'table' and value or {}
    return { time = normalizeTime(value.time), weather = normalizeWeather(value.weather) }
end

local function normalize(value)
    value = type(value) == 'table' and value or {}
    local active = tostring(value.activeProfile or 'padrao')
    local profiles = {}
    if type(value.profiles) == 'table' then
        for slug, profile in pairs(value.profiles) do
            if type(slug) == 'string' and slug ~= '' then profiles[slug] = normalizeProfile(profile) end
        end
    end
    if not next(profiles) then
        profiles.padrao = normalizeProfile({ time = value.time, weather = value.weather })
        active = 'padrao'
    end
    if not profiles[active] then active = profiles.padrao and 'padrao' or next(profiles) end
    return { schemaVersion = 2, activeProfile = active, profiles = profiles }
end

local ok, loaded = pcall(pr_lib.loadJson, Runtime.path, true)
Runtime.data = normalize(ok and loaded or nil)

local function current()
    local slug = Runtime.data.activeProfile
    Runtime.data.profiles[slug] = Runtime.data.profiles[slug] or normalizeProfile()
    return Runtime.data.profiles[slug]
end

function Runtime.get()
    local profile = current()
    return { schemaVersion = 2, activeProfile = Runtime.data.activeProfile, time = clone(profile.time), weather = clone(profile.weather) }
end
function Runtime.getRaw() return clone(Runtime.data) end
function Runtime.getActiveProfile() return Runtime.data.activeProfile end
function Runtime.getTime() return clone(current().time) end
function Runtime.getWeather() return clone(current().weather) end
function Runtime.getProfile(slug) local value = Runtime.data.profiles[tostring(slug or '')]; return value and clone(value) or nil end

function Runtime.ensureProfile(slug, initial)
    slug = tostring(slug or '')
    if slug == '' then return false end
    if not Runtime.data.profiles[slug] then Runtime.data.profiles[slug] = normalizeProfile(initial); Runtime.dirty = true end
    return true
end

function Runtime.setTime(value, flush)
    current().time = normalizeTime(value); Runtime.dirty = true
    if flush then return Runtime.flush() end
end

function Runtime.setWeather(value, flush)
    current().weather = normalizeWeather(value); current().weather.updatedAt = os.time(); Runtime.dirty = true
    if flush then return Runtime.flush() end
end

function Runtime.activateProfile(slug, reset, initial)
    slug = tostring(slug or '')
    if slug == '' then return false, 'invalid_profile' end
    Runtime.ensureProfile(slug, initial)
    Runtime.data.activeProfile = slug
    if reset then Runtime.data.profiles[slug] = normalizeProfile(initial) end
    Runtime.dirty = true
    return Runtime.flush()
end

function Runtime.renameProfile(fromSlug, toSlug)
    if fromSlug == toSlug or not Runtime.data.profiles[fromSlug] or Runtime.data.profiles[toSlug] then return false end
    Runtime.data.profiles[toSlug] = Runtime.data.profiles[fromSlug]; Runtime.data.profiles[fromSlug] = nil
    if Runtime.data.activeProfile == fromSlug then Runtime.data.activeProfile = toSlug end
    Runtime.dirty = true
    return Runtime.flush()
end

function Runtime.deleteProfile(slug)
    if Runtime.data.activeProfile == slug or not Runtime.data.profiles[slug] then return false end
    Runtime.data.profiles[slug] = nil; Runtime.dirty = true
    return Runtime.flush()
end

function Runtime.flush()
    if not Runtime.dirty then return true end
    local saved, result = pr_lib.saveJson(Runtime.path, Runtime.data)
    if saved then Runtime.dirty = false end
    return saved, result
end

CreateThread(function() while true do Wait(30000); Runtime.flush() end end)
AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then Runtime.flush() end end)
RenewedWeather.Runtime = Runtime
