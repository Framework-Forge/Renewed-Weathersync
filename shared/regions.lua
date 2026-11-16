RenewedWeather = RenewedWeather or {}
local RW = RenewedWeather

RW.Regions = {
    count = 2,
    list = {
        [1] = {
            id = 1,
            key = 'south',
            label = 'Sul (Los Santos)',
        },
        [2] = {
            id = 2,
            key = 'north',
            label = 'Norte (Blaine County & Paleto)',
        }
    },
    -- Divisória de latitude Y no mapa de San Andreas:
    -- Y < 850.0  -> Área 1 (Los Santos / Cidade)
    -- Y >= 850.0 -> Área 2 (Blaine County / Sandy Shores / Paleto Bay)
    boundaryY = 850.0,

    -- Zonas customizadas adicionais (se definidas)
    customZones = {}
}

---Determina o ID da região meteorológica (1 ou 2) para uma dada coordenada
---@param coords vector3|table
---@return number regionId
function RW.GetRegionFromCoords(coords)
    if not coords then return 1 end
    local y = coords.y or coords[2] or 0.0

    if RW.Regions.customZones and #RW.Regions.customZones > 0 then
        for i = 1, #RW.Regions.customZones do
            local zone = RW.Regions.customZones[i]
            if zone and zone.regionId and type(zone.check) == 'function' then
                if zone.check(coords) then
                    return zone.regionId
                end
            end
        end
    end

    if y >= RW.Regions.boundaryY then
        return 2
    end

    return 1
end

---Retorna os metadados da região indicada
---@param regionId number
---@return table
function RW.GetRegionData(regionId)
    return RW.Regions.list[regionId] or RW.Regions.list[1]
end
