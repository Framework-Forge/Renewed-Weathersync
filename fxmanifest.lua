fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_fxv2_oal 'yes'

name 'Renewed Weather Sync'
author 'FjamZoo - Renewed Scripts / Forge Core JSON panel'
version '3.0.0'

shared_scripts {
    '@pr_bridge/init.lua',
    'shared/init.lua',
    'shared/regions.lua',
    'shared/cache.lua',
}

files {
    'data/*.json',
    'data/profiles/**/*.json',
    'locale/*.json',
}

client_scripts {
    'client/time.lua',
    'client/weather.lua',
    'client/panel/admin_core.lua',
    'client/panel/admin_settings.lua',
    'client/panel/admin_profiles.lua',
    'client/panel/admin_sequences.lua',
    'client/panel/admin_forecast.lua',
    'client/panel/admin_entry.lua',
    'compatability/**/client.lua',
}

server_scripts {
    'server/profiles_fs.js',
    'server/runtime.lua',
    'server/config.lua',
    'server/time_json.lua',
    'server/weather_json.lua',
    'compatability/**/server.lua',
}

provide 'qb-weathersync'
provide 'cd_easytime'

dependency 'pr_bridge'
