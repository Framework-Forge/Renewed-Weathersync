local Admin = RenewedWeather.Admin
local function show(id, parent, title, options)
    pr_lib.registerContext({ id = id, menu = parent, title = Admin.t(title), options = options }); pr_lib.showContext(id)
end
local function responseOk(result)
    if type(result) == 'table' and result.success then Admin.notify('notify.profile_saved', 'success'); return true end
    Admin.notify('notify.profile_failed', 'error', { error = type(result) == 'table' and result.error or 'unknown' })
    return false
end

local function createProfile(clean)
    local name = Admin.textDialog('profiles.create_title', 'profiles.name', '')
    if not name or name == '' then return Admin.openProfiles() end
    local result = pr_lib.callback.await(RenewedWeather.Callbacks.profileCreate, 10000, name, clean == true)
    if responseOk(result) then Admin.fetch() end
    Admin.openProfiles()
end

function Admin.openProfile(slug)
    local profile
    for _, item in ipairs(Admin.data.profiles or {}) do if item.slug == slug then profile = item break end end
    if not profile then return Admin.openProfiles() end
    local id = 'renewed_weather:profile:' .. slug
    local options = {
        { title = profile.name, description = Admin.t('profiles.summary', { mode = Admin.t('mode.' .. profile.mode), events = profile.events, slug = profile.slug }), icon = profile.active and 'folder-open' or 'folder', iconColor = profile.active and '#22c55e' or nil, readOnly = true },
        { title = Admin.t('profiles.activate_continue'), description = Admin.t('profiles.activate_continue_description'), icon = 'play', disabled = profile.active, onSelect = function()
            local result = pr_lib.callback.await(RenewedWeather.Callbacks.profileActivate, 10000, slug, false)
            if responseOk(result) then Admin.data = result.data end
            Admin.openProfiles()
        end },
        { title = Admin.t('profiles.activate_restart'), description = Admin.t('profiles.activate_restart_description'), icon = 'rotate-left', onSelect = function()
            if not Admin.confirm('profiles.activate_restart', 'profiles.activate_restart_confirm') then return Admin.openProfile(slug) end
            local result = pr_lib.callback.await(RenewedWeather.Callbacks.profileActivate, 10000, slug, true)
            if responseOk(result) then Admin.data = result.data end
            Admin.openProfiles()
        end },
        { title = Admin.t('profiles.rename'), description = Admin.t('profiles.rename_description'), icon = 'pen', onSelect = function()
            local name = Admin.textDialog('profiles.rename', 'profiles.name', profile.name)
            if name and name ~= '' then
                local result = pr_lib.callback.await(RenewedWeather.Callbacks.profileRename, 10000, slug, name)
                if responseOk(result) then Admin.fetch(); return Admin.openProfile(result.slug) end
            end
            Admin.openProfile(slug)
        end },
        { title = Admin.t('profiles.duplicate'), description = Admin.t('profiles.duplicate_description'), icon = 'copy', onSelect = function()
            local name = Admin.textDialog('profiles.duplicate', 'profiles.name', profile.name .. ' - cópia')
            if name and name ~= '' then
                local result = pr_lib.callback.await(RenewedWeather.Callbacks.profileDuplicate, 10000, slug, name)
                if responseOk(result) then Admin.fetch() end
            end
            Admin.openProfiles()
        end },
        { title = Admin.t('profiles.export'), description = Admin.t('profiles.export_description'), icon = 'clipboard', onSelect = function()
            local result = pr_lib.callback.await(RenewedWeather.Callbacks.profileExport, 10000, slug)
            if type(result) == 'table' and result.success and result.bundle then
                pr_lib.setClipboard(json.encode(result.bundle))
                Admin.notify('notify.profile_exported', 'success')
            else Admin.notify('notify.profile_failed', 'error', { error = 'export' }) end
            Admin.openProfile(slug)
        end },
        { title = Admin.t('profiles.overwrite'), description = Admin.t('profiles.overwrite_description'), icon = 'floppy-disk', disabled = profile.active, onSelect = function()
            if Admin.confirm('profiles.overwrite', 'profiles.overwrite_confirm') then
                responseOk(pr_lib.callback.await(RenewedWeather.Callbacks.profileOverwrite, 10000, slug)); Admin.fetch()
            end
            Admin.openProfile(slug)
        end },
        { title = Admin.t('profiles.delete'), description = Admin.t(profile.active and 'profiles.delete_active_description' or 'profiles.delete_description'), icon = 'trash', iconColor = '#ef4444', disabled = profile.active, onSelect = function()
            if Admin.confirm('profiles.delete', 'profiles.delete_confirm') then
                responseOk(pr_lib.callback.await(RenewedWeather.Callbacks.profileDelete, 10000, slug)); Admin.fetch()
            end
            Admin.openProfiles()
        end },
    }
    show(id, 'renewed_weather:profiles', 'profiles.profile_title', options)
end

function Admin.openProfiles()
    local options = {
        { title = Admin.t('profiles.active'), description = Admin.t('profiles.active_description', { profile = Admin.data.runtime.activeProfile or 'padrao' }), icon = 'circle-info', readOnly = true },
        { title = Admin.t('profiles.create_current'), description = Admin.t('profiles.create_current_description'), icon = 'folder-plus', iconColor = '#22c55e', onSelect = function() createProfile(false) end },
        { title = Admin.t('profiles.create_clean'), description = Admin.t('profiles.create_clean_description'), icon = 'file-circle-plus', onSelect = function() createProfile(true) end },
        { title = Admin.t('profiles.import'), description = Admin.t('profiles.import_description'), icon = 'file-import', onSelect = function()
            local result = pr_lib.inputDialog(Admin.t('profiles.import'), {
                { type = 'input', label = Admin.t('profiles.name'), required = true },
                { type = 'textarea', label = Admin.t('profiles.json_bundle'), required = true },
            })
            if result then
                local response = pr_lib.callback.await(RenewedWeather.Callbacks.profileImport, 10000, result[1], result[2])
                if responseOk(response) then Admin.fetch() end
            end
            Admin.openProfiles()
        end },
    }
    for _, profile in ipairs(Admin.data.profiles or {}) do
        local slug = profile.slug
        options[#options + 1] = { title = profile.name, description = Admin.t('profiles.list_description', { mode = Admin.t('mode.' .. profile.mode), events = profile.events, slug = profile.slug }),
            icon = profile.active and 'folder-open' or 'folder', iconColor = profile.active and '#22c55e' or nil, arrow = true,
            onSelect = function() Admin.openProfile(slug) end }
    end
    show('renewed_weather:profiles', 'renewed_weather:settings', 'profiles.title', options)
end