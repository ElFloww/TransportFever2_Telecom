-- Prototype – ajustez si votre version TPF2 a une API légèrement différente.
local api = api -- fourni par le jeu


-- CONFIG
local EPOCH_BONUS = {
    WIRE = { base = 0.05, yearFrom = 1850 },
    MOBILE_1990={ base = 0.10, yearFrom = 1990 },
    FIBER_2020 ={ base = 0.20, yearFrom = 2020 },
    MOBILE_2030={ base = 0.15, yearFrom = 2030 }, -- s'additionne au 1990 si plus récent
}


-- Bonus max cumulé par ville (sécurité)
local MAX_CITY_BONUS = 0.60


-- Densité -> facteur de portée (zones denses = portée effective plus petite)
local function densityFactor(popPerKm2)
    if popPerKm2 >= 10000 then return 0.6
    elseif popPerKm2 >= 6000 then return 0.75
    elseif popPerKm2 >= 3000 then return 0.9
    else return 1.0 end
end


-- État sérialisé
local state = { lastTick = 0 }


local function isTelecomConstruction(eId)
    local ent = api.engine.getComponent(eId, api.type.ComponentType.ENTITY_PTR)
    if not ent then return false end
        local con = api.engine.getComponent(eId, api.type.ComponentType.CONSTRUCTION)
    if not con or not con.metadata or not con.metadata.telecom then return false end
    return true
end


local function getTelecomNodes()
local nodes = {}
for _, id in ipairs(api.engine.getEntities({ })) do -- TODO: filtrer si disponible (category=CONSTRUCTION)
    local con = api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
    if con and con.metadata and con.metadata.telecom then
        local pos = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
        table.insert(nodes, { id=id, kind=con.metadata.telecom.kind, radius=con.metadata.telecom.radius, pos=pos and pos.transf or nil })
    end
end
return nodes
end


-- Récupère bâtiments de ville et population (approximée)
local function getTownBuildings(townId)
    local buildings = {}
end