RenewedWeather = RenewedWeather or {}
local RW = RenewedWeather
RW.Lang = pr_lib.locale()
function RW.t(key, params)
    local translator = RW.Lang
    if type(translator) == 'table' and type(translator.t) == 'function' then return translator:t(key, params) end
    return key
end
RW.WeatherTypes = { 'BLIZZARD','CLEAR','CLEARING','CLOUDS','EXTRASUNNY','FOGGY','NEUTRAL','OVERCAST','RAIN','SMOG','SNOW','SNOWLIGHT','THUNDER','XMAS' }
RW.WeatherTypeSet = {}
for index = 1, #RW.WeatherTypes do RW.WeatherTypeSet[RW.WeatherTypes[index]] = true end
RW.Modes = { daily_fixed = true, sequential = true, dynamic = true, unique = true }
RW.Callbacks = {
    getAdminData='Renewed-Weathersync:server:getAdminData', saveTime='Renewed-Weathersync:server:saveTimeConfig',
    saveWeather='Renewed-Weathersync:server:saveWeatherConfig', rebuild='Renewed-Weathersync:server:rebuildForecast',
    setWeatherType='Renewed-Weathersync:server:setWeatherType', setEventTime='Renewed-Weathersync:server:setEventTime',
    removeEvent='Renewed-Weathersync:server:removeEvent', forceEvent='Renewed-Weathersync:server:forceEvent',
    forceTime='Renewed-Weathersync:server:forceTime', profileList='Renewed-Weathersync:server:profileList',
    profileCreate='Renewed-Weathersync:server:profileCreate', profileActivate='Renewed-Weathersync:server:profileActivate',
    profileRename='Renewed-Weathersync:server:profileRename', profileDuplicate='Renewed-Weathersync:server:profileDuplicate',
    profileDelete='Renewed-Weathersync:server:profileDelete', profileExport='Renewed-Weathersync:server:profileExport',
    profileImport='Renewed-Weathersync:server:profileImport', profileOverwrite='Renewed-Weathersync:server:profileOverwrite',
}