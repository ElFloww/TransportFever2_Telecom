-- =============================================================================
-- telecom_growth.lua  —  Moteur de croissance télécom
-- Mod : Réseaux de Communication  |  Auteur : elfloww
-- =============================================================================
--
-- FONCTIONNEMENT :
--   Ce game_script est appelé par le moteur TF2 à chaque tick de simulation.
--   Toutes les TICK_INTERVAL secondes de jeu, il :
--     1. Scanne toutes les constructions pour trouver les nœuds télécoms
--     2. Scanne toutes les villes pour obtenir leur position
--     3. Calcule la couverture de chaque ville (WIRE et MOBILE séparément)
--     4. Détermine le bonus global de croissance à appliquer
--     5. Modifie game.config.townGrowthFactor dynamiquement
--
-- BONUS PAR ÉPOQUE (cumulatif, plafonné à MAX_BONUS) :
--   WIRE  1850 : +5%  par ville couverte
--   WIRE  2020 : +20% par ville couverte (remplace le 1850 si les deux existent)
--   MOBILE 1990 : +10% par ville couverte
--   MOBILE 2030 : +15% par ville couverte (remplace le 1990 si les deux existent)
--   Bonus combiné WIRE+MOBILE : multiplicateur x1.2 (synergie)
-- =============================================================================

local TICK_INTERVAL = 60   -- secondes de jeu entre deux recalculs
local BASE_GROWTH   = 1.0  -- valeur par défaut de townGrowthFactor
local MAX_BONUS     = 0.60 -- bonus maximal cumulable (+60% au-dessus du défaut)

-- Bonus de base par type et époque (la meilleure époque disponible est retenue)
local WIRE_BONUS = {
    [1850] = 0.05,
    [2020] = 0.20,  -- remplace 1850 si disponible dans la partie
}
local MOBILE_BONUS = {
    [1990] = 0.10,
    [2030] = 0.15,  -- remplace 1990 si disponible dans la partie
}

-- Multiplicateur si une ville a à la fois couverture WIRE et MOBILE
local SYNERGY_MULT = 1.2

-- =============================================================================
-- UTILITAIRES
-- =============================================================================

--- Distance euclidienne 2D entre deux positions (ignore Z)
local function dist2D(a, b)
    if not a or not b then return math.huge end
    local dx = (a[13] or a.x or 0) - (b[13] or b.x or 0)
    local dy = (a[14] or a.y or 0) - (b[14] or b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

--- Extrait la position XY depuis une matrice de transformation 4x4 (table de 16 valeurs)
local function posFromTransf(t)
    if not t then return nil end
    -- La matrice TF2 est column-major : [1..4]=col0, [5..8]=col1, [9..12]=col2, [13..16]=col3
    -- col3 = translation : indices 13, 14, 15
    return { x = t[13] or 0, y = t[14] or 0, z = t[15] or 0 }
end

-- =============================================================================
-- COLLECTE DES NOEUDS TELECOM
-- Cherche toutes les constructions ayant metadata.telecom dans leurs paramètres.
-- =============================================================================
local function collectTelecomNodes()
    local nodes = {}
    -- Itérer sur toutes les entités du monde
    local entityCount = 0
    -- api.engine.getEntitiesOfType n'existant pas toujours,
    -- on utilise la méthode universelle avec forEachEntity si disponible,
    -- sinon on itère sur une plage d'IDs (fallback).
    local ok, entities = pcall(function()
        return api.engine.getEntitiesOfType(api.type.EntityType.CONSTRUCTION)
    end)
    if not ok or not entities then
        -- Fallback : getEntities() sans filtre
        ok, entities = pcall(function()
            return api.engine.getEntities()
        end)
    end
    if not ok or not entities then return nodes end

    for _, id in ipairs(entities) do
        local con = api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
        if con then
            -- La metadata télécom est stockée dans con.params (sérialisé par le jeu)
            -- ou accessible via les paramètres de construction
            -- On cherche dans con.fileName pour identifier nos fichiers .con
            local fileName = con.fileName or ""
            local kind, radius, epoch

            if fileName:find("fixed_line_1850") then
                kind  = "WIRE"
                epoch = 1850
            elseif fileName:find("fiber_2020") then
                kind  = "WIRE"
                epoch = 2020
            elseif fileName:find("mobile_1990") then
                kind  = "MOBILE"
                epoch = 1990
            elseif fileName:find("mobile_2030") then
                kind  = "MOBILE"
                epoch = 2030
            end

            if kind then
                -- Récupérer la position
                local tf = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
                local pos = tf and posFromTransf(tf.transf) or nil

                -- Récupérer le rayon depuis les params de construction
                -- con.params[1] correspond au premier param (index 0-based interne → +1 en Lua)
                local r = 300 -- défaut
                if con.params and con.params[1] then
                    local pIdx = (con.params[1] or 0)
                    if kind == "WIRE" and epoch == 1850 then
                        local radii = { 100, 200, 300, 400, 500 }
                        r = radii[pIdx + 1] or 300
                    elseif kind == "WIRE" and epoch == 2020 then
                        local radii = { 300, 450, 600, 900, 1200 }
                        r = radii[pIdx + 1] or 600
                    elseif kind == "MOBILE" and epoch == 1990 then
                        local radii = { 400, 600, 800, 1000 }
                        r = radii[pIdx + 1] or 600
                    elseif kind == "MOBILE" and epoch == 2030 then
                        local radii = { 800, 1200, 1600, 2000 }
                        r = radii[pIdx + 1] or 1200
                    end
                end

                table.insert(nodes, {
                    id    = id,
                    kind  = kind,
                    epoch = epoch,
                    radius = r,
                    pos   = pos,
                })
                entityCount = entityCount + 1
            end
        end
    end
    return nodes
end

-- =============================================================================
-- COLLECTE DES VILLES
-- =============================================================================
local function collectTowns()
    local towns = {}
    local ok, townIds = pcall(function()
        return api.engine.getEntitiesOfType(api.type.EntityType.TOWN)
    end)
    if not ok or not townIds then
        -- Fallback via game.interface si disponible
        ok, townIds = pcall(function()
            return game.interface.getTowns()
        end)
    end
    if not ok or not townIds then return towns end

    for _, id in ipairs(townIds) do
        local tf  = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
        local pos = tf and posFromTransf(tf.transf) or nil
        if pos then
            table.insert(towns, { id = id, pos = pos })
        end
    end
    return towns
end

-- =============================================================================
-- CALCUL DE COUVERTURE
-- Retourne pour chaque ville son meilleur epoch WIRE et son meilleur epoch MOBILE
-- =============================================================================
local function computeCoverage(nodes, towns)
    -- coverage[townId] = { wireEpoch = nil|1850|2020, mobileEpoch = nil|1990|2030 }
    local coverage = {}
    for _, town in ipairs(towns) do
        coverage[town.id] = { wireEpoch = nil, mobileEpoch = nil }
    end

    for _, node in ipairs(nodes) do
        if node.pos then
            for _, town in ipairs(towns) do
                if dist2D(node.pos, town.pos) <= node.radius then
                    local c = coverage[town.id]
                    if node.kind == "WIRE" then
                        -- Garder l'époque la plus récente (meilleur bonus)
                        if not c.wireEpoch or node.epoch > c.wireEpoch then
                            c.wireEpoch = node.epoch
                        end
                    elseif node.kind == "MOBILE" then
                        if not c.mobileEpoch or node.epoch > c.mobileEpoch then
                            c.mobileEpoch = node.epoch
                        end
                    end
                end
            end
        end
    end
    return coverage
end

-- =============================================================================
-- CALCUL DU BONUS GLOBAL
-- Moyenne pondérée du bonus sur toutes les villes
-- =============================================================================
local function computeGlobalBonus(coverage, totalTowns)
    if totalTowns == 0 then return 0 end

    local totalBonus = 0
    local coveredTowns = 0

    for _, c in pairs(coverage) do
        local wireB   = 0
        local mobileB = 0

        if c.wireEpoch then
            wireB = WIRE_BONUS[c.wireEpoch] or 0
        end
        if c.mobileEpoch then
            mobileB = MOBILE_BONUS[c.mobileEpoch] or 0
        end

        if wireB > 0 or mobileB > 0 then
            local bonus = wireB + mobileB
            -- Synergie : bonus supplémentaire si les deux types sont couverts
            if wireB > 0 and mobileB > 0 then
                bonus = bonus * SYNERGY_MULT
            end
            totalBonus  = totalBonus + bonus
            coveredTowns = coveredTowns + 1
        end
    end

    -- Le bonus global = moyenne sur les villes couvertes × ratio de couverture
    -- (plus on couvre de villes, plus l'effet est fort)
    if coveredTowns == 0 then return 0 end

    local avgBonus    = totalBonus / coveredTowns
    local coverRatio  = coveredTowns / totalTowns
    local globalBonus = avgBonus * coverRatio

    -- Plafonner au maximum configuré
    return math.min(globalBonus, MAX_BONUS)
end

-- =============================================================================
-- APPLICATION DU BONUS
-- Modifie game.config.townGrowthFactor (valeur lue par le moteur de croissance)
-- =============================================================================
local function applyBonus(bonus)
    local newFactor = BASE_GROWTH + bonus
    -- Sécurité : ne jamais descendre en-dessous de 1.0 ni dépasser 1.0 + MAX_BONUS
    newFactor = math.max(BASE_GROWTH, math.min(BASE_GROWTH + MAX_BONUS, newFactor))
    if game and game.config then
        game.config.townGrowthFactor = newFactor
    end
end

-- =============================================================================
-- POINT D'ENTRÉE DU GAME SCRIPT
-- =============================================================================
function data()
    return {
        -- Initialise l'état persistant de la sauvegarde
        init = function(state)
            state.tick      = 0
            state.nodes     = {}
            state.coverage  = {}
            state.lastBonus = 0
        end,

        -- Appelé à chaque tick de simulation
        update = function(state)
            state.tick = (state.tick or 0) + 1

            -- Ne recalculer que toutes les TICK_INTERVAL secondes
            if state.tick % TICK_INTERVAL ~= 0 then return end

            -- 1. Collecter les nœuds télécoms actifs
            local nodes = collectTelecomNodes()

            -- 2. Collecter les villes
            local towns = collectTowns()

            -- 3. Calculer la couverture
            local coverage = computeCoverage(nodes, towns)

            -- 4. Calculer le bonus global
            local bonus = computeGlobalBonus(coverage, #towns)

            -- 5. Appliquer le bonus
            applyBonus(bonus)

            -- 6. Sauvegarder pour l'UI/calques
            state.nodes     = nodes
            state.coverage  = coverage
            state.lastBonus = bonus
            state.townCount = #towns
            state.nodeCount = #nodes
        end,

        -- Sérialisation pour la sauvegarde
        save = function(state)
            return {
                tick      = state.tick,
                lastBonus = state.lastBonus,
                townCount = state.townCount,
                nodeCount = state.nodeCount,
                -- Note : nodes et coverage sont reconstruits au prochain update
                -- pour éviter de sérialiser de grandes tables
            }
        end,

        -- Désérialisation au chargement d'une sauvegarde
        load = function(saved)
            local state = {
                tick      = saved and saved.tick      or 0,
                lastBonus = saved and saved.lastBonus or 0,
                townCount = saved and saved.townCount or 0,
                nodeCount = saved and saved.nodeCount or 0,
                nodes     = {},
                coverage  = {},
            }
            return state
        end,
    }
end