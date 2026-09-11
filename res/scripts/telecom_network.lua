-- Pure snapshot calculation; only collect() reads the TF2 engine.
local network = {}

network.techs = {
    { year = 1992, radius = 2000, bonus = 0.02, name = "2G",  key = "tech_2g" },
    { year = 2004, radius = 1500, bonus = 0.03, name = "3G",  key = "tech_3g" },
    { year = 2006, radius = 1500, bonus = 0.04, name = "3G+", key = "tech_3gp" },
    { year = 2012, radius = 1200, bonus = 0.05, name = "4G",  key = "tech_4g" },
    { year = 2014, radius = 1200, bonus = 0.06, name = "4G+", key = "tech_4gp" },
    { year = 2020, radius = 800,  bonus = 0.08, name = "5G",  key = "tech_5g" },
    { year = 2023, radius = 500,  bonus = 0.10, name = "5G+", key = "tech_5gp" },
}

local fixed = {
    NRA = { key = "NRA", name = "NRA", year = 1974, radius = 1500, bonus = 0.03 },
    NRO = { key = "NRO", name = "NRO", year = 2007, radius = 3000, bonus = 0.08 },
}

local constructionKinds = {
    ["telecom/nra.con"] = "NRA",
    ["telecom/nro.con"] = "NRO",
    ["telecom/antenna.con"] = "ANTENNA",
}

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function checkYear(year)
    assert(finite(year) and year > 0 and year == math.floor(year), "Annee du jeu indisponible ou invalide")
    return year
end

local function position(pos, label)
    assert(pos, "Position manquante: " .. label)
    local x, y, z = pos.x or pos[1], pos.y or pos[2], pos.z or pos[3] or 0
    assert(finite(x) and finite(y) and finite(z), "Position invalide: " .. label)
    return x, y, z
end

-- Input: {id, kind, name?, x, y, z?, params?}. Named combo indices only.
function network.makeNode(raw, year)
    checkYear(year)
    assert(fixed[raw.kind] or raw.kind == "ANTENNA", "Type telecom inconnu")
    local x, y, z = position(raw, "noeud " .. tostring(raw.id))
    local node = {
        id = raw.id, kind = raw.kind, name = raw.name or raw.kind,
        x = x, y = y, z = z, services = {},
    }
    local catalogue = raw.kind == "ANTENNA" and network.techs or { fixed[raw.kind] }
    for _, tech in ipairs(catalogue) do
        local configured = raw.kind ~= "ANTENNA" or (raw.params or {})[tech.key] == 1
        node.services[#node.services + 1] = {
            key = tech.key, name = tech.name, radius = tech.radius, bonus = tech.bonus,
            year = tech.year, configured = configured,
            active = configured and year >= tech.year, townIds = {},
        }
    end
    return node
end

-- TERRAIN.size counts 256 m tiles, centred on the world origin.
-- Without terrain dimensions include every service disc, even inactive ones.
function network.computeBounds(nodes, towns, terrainSize)
    if terrainSize and finite(terrainSize.x) and finite(terrainSize.y)
        and terrainSize.x > 0 and terrainSize.y > 0 then
        local halfX, halfY = terrainSize.x * 128, terrainSize.y * 128
        return { minX = -halfX, maxX = halfX, minY = -halfY, maxY = halfY }, false
    end
    local bounds = { minX = math.huge, maxX = -math.huge, minY = math.huge, maxY = -math.huge }
    local function include(x, y, radius)
        bounds.minX = math.min(bounds.minX, x - radius)
        bounds.maxX = math.max(bounds.maxX, x + radius)
        bounds.minY = math.min(bounds.minY, y - radius)
        bounds.maxY = math.max(bounds.maxY, y + radius)
    end
    for _, town in ipairs(towns) do include(town.x, town.y, 0) end
    for _, node in ipairs(nodes) do
        local radius = 0
        for _, service in ipairs(node.services) do radius = math.max(radius, service.radius) end
        include(node.x, node.y, radius)
    end
    if bounds.minX == math.huge then include(0, 0, 128) end
    if bounds.minX == bounds.maxX then
        bounds.minX, bounds.maxX = bounds.minX - 128, bounds.maxX + 128
    end
    if bounds.minY == bounds.maxY then
        bounds.minY, bounds.maxY = bounds.minY - 128, bounds.maxY + 128
    end
    return bounds, true
end

-- Input: {year, nodes={raw nodes}, towns={id,name,x,y,z}, terrainSize?}.
-- Returns a new serializable snapshot, without mutating input or the catalogue.
function network.computeSnapshot(input, revision)
    local snapshot = {
        revision = revision or 1, year = checkYear(input.year), nodes = {}, towns = {},
        coverage = {}, globalBonus = 0, coveredTowns = 0, interval = 60,
    }
    for _, raw in ipairs(input.nodes) do
        snapshot.nodes[#snapshot.nodes + 1] = network.makeNode(raw, snapshot.year)
    end
    for _, raw in ipairs(input.towns) do
        local x, y, z = position(raw, "ville " .. tostring(raw.id))
        snapshot.towns[#snapshot.towns + 1] = { id = raw.id, name = raw.name or "", x = x, y = y, z = z }
    end
    local function byId(a, b) return a.id < b.id end
    table.sort(snapshot.nodes, byId)
    table.sort(snapshot.towns, byId)
    for _, town in ipairs(snapshot.towns) do
        snapshot.coverage[town.id] = {
            townName = town.name, hasFixed = false, hasMobile = false,
            fixedBonus = 0, mobileBonus = 0, bonus = 0,
        }
    end
    for _, node in ipairs(snapshot.nodes) do
        for _, service in ipairs(node.services) do
            if service.active then
                for _, town in ipairs(snapshot.towns) do
                    local dx, dy = town.x - node.x, town.y - node.y
                    if dx * dx + dy * dy <= service.radius * service.radius then
                        service.townIds[#service.townIds + 1] = town.id
                        local c = snapshot.coverage[town.id]
                        if node.kind == "ANTENNA" then
                            c.hasMobile = true
                            -- Preserve stacking across both technologies and antennas.
                            c.mobileBonus = c.mobileBonus + service.bonus
                        else
                            c.hasFixed = true
                            c.fixedBonus = math.max(c.fixedBonus, service.bonus)
                        end
                    end
                end
            end
        end
    end
    local totalBonus = 0
    for _, town in ipairs(snapshot.towns) do
        local c = snapshot.coverage[town.id]
        c.bonus = (c.fixedBonus + c.mobileBonus) * (c.hasFixed and c.hasMobile and 1.2 or 1)
        totalBonus = totalBonus + c.bonus
        if c.hasFixed or c.hasMobile then snapshot.coveredTowns = snapshot.coveredTowns + 1 end
    end
    if #snapshot.towns > 0 then snapshot.globalBonus = math.min(0.60, totalBonus / #snapshot.towns) end
    snapshot.interval = math.max(1, math.floor(60 * (1 - snapshot.globalBonus)))
    snapshot.bounds, snapshot.boundsEstimated = network.computeBounds(snapshot.nodes, snapshot.towns, input.terrainSize)
    return snapshot
end

-- TF2 API reference: api.engine.forEachEntityWithComponent(callback, type),
-- api.engine.util.getWorld(), Construction.transf:cols(3), Terrain.size.
-- The native binding uses "cols" (plural), with zero-based columns, unlike the wiki's "col".
-- GAME_TIME has gameTime/gameTime0/tickCount/updateCount, not time/date.
-- The legacy interface supplies the calendar date independently of simulation speed.
function network.collect(engineApi, interface)
    local clock = interface.getGameTime()
    local input = { year = checkYear(clock and clock.date and clock.date.year), nodes = {}, towns = {} }
    local engine, types = engineApi.engine, engineApi.type.ComponentType
    local world = engine.util.getWorld()
    assert(world ~= nil, "Entite monde indisponible")
    local terrain = engine.getComponent(world, types.TERRAIN)
    if terrain and terrain.size then
        input.terrainSize = { x = terrain.size.x, y = terrain.size.y }
    end
    engine.forEachEntityWithComponent(function(id)
        local con = assert(engine.getComponent(id, types.CONSTRUCTION), "Construction indisponible: " .. tostring(id))
        local kind = constructionKinds[con.fileName]
        if kind then
            assert(con.transf, "Transformation manquante: " .. tostring(id))
            local x, y, z = position(con.transf:cols(3), "construction " .. tostring(id))
            local params = {}
            if kind == "ANTENNA" then
                assert(con.params, "Parametres antenne indisponibles: " .. tostring(id))
                for _, tech in ipairs(network.techs) do params[tech.key] = con.params[tech.key] end
            end
            -- Copy construction data before another getComponent can reuse its userdata.
            local name = engine.getComponent(id, types.NAME)
            input.nodes[#input.nodes + 1] = {
                id = id, kind = kind, name = name and name.name or kind,
                x = x, y = y, z = z, params = params,
            }
        end
    end, types.CONSTRUCTION)
    local townIds = assert(interface.getTowns(), "Liste des villes indisponible")
    for _, id in ipairs(townIds) do
        local town = assert(interface.getEntity(id), "Ville indisponible: " .. tostring(id))
        local x, y, z = position(town.position, "ville " .. tostring(id))
        input.towns[#input.towns + 1] = { id = id, name = town.name or "", x = x, y = y, z = z }
    end
    return input
end

return network
