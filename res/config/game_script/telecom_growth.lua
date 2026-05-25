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
-- DIAGNOSTIC : affiche les clés game.config disponibles (1 seule fois au démarrage)
-- =============================================================================
local _diagDone = false
local function runDiagnostic()
    if _diagDone then return end
    _diagDone = true
    print("[Telecom] === DIAGNOSTIC game.config ===")
    if game and game.config then
        local found = {}
        for k, v in pairs(game.config) do
            if type(v) == "number" or type(v) == "boolean" then
                table.insert(found, k .. " = " .. tostring(v))
            end
        end
        table.sort(found)
        for _, line in ipairs(found) do print("[Telecom]  " .. line) end
        if #found == 0 then print("[Telecom]  (aucune clé numérique trouvée)") end
    else
        print("[Telecom]  game.config introuvable")
    end
    print("[Telecom] api.engine disponible : " .. tostring(api ~= nil and api.engine ~= nil))
    print("[Telecom] =====================================")
end

-- =============================================================================
-- APPLICATION DU BONUS — stratégies en cascade
-- =============================================================================
local _appliedStrategy = nil  -- mémorise quelle stratégie fonctionne

local function applyBonus(bonus)
    if not game or not game.config then return end

    -- Stratégie 1 : townGrowthFactor (TF1 / certaines versions TF2)
    if game.config.townGrowthFactor ~= nil then
        local newFactor = 1.0 + bonus
        game.config.townGrowthFactor = math.max(1.0, math.min(1.6, newFactor))
        if _appliedStrategy ~= 1 then
            _appliedStrategy = 1
            print("[Telecom] Stratégie : townGrowthFactor = " .. tostring(game.config.townGrowthFactor))
        end
        return
    end

    -- Stratégie 2 : townDevelopInterval (confirmé = 60 dans TF2)
    -- Réduire l'intervalle = villes se développent plus souvent = croissance accélérée
    -- Valeur par défaut TF2 = 60.
    -- bonus  0% → interval 60 (rythme normal)
    -- bonus 30% → interval 40
    -- bonus 60% → interval 20 (3× plus rapide)
    if game.config.townDevelopInterval ~= nil then
        local DEFAULT_INTERVAL = 60
        local MIN_INTERVAL     = 20
        local newInterval = math.floor(DEFAULT_INTERVAL - (DEFAULT_INTERVAL - MIN_INTERVAL) * bonus / MAX_BONUS)
        newInterval = math.max(MIN_INTERVAL, math.min(DEFAULT_INTERVAL, newInterval))
        game.config.townDevelopInterval = newInterval
        if _appliedStrategy ~= 2 then
            _appliedStrategy = 2
            print("[Telecom] Stratégie : townDevelopInterval = " .. tostring(newInterval)
                  .. " (défaut=60, bonus=" .. string.format("%.0f%%", bonus * 100) .. ")")
        end
        return
    end

    -- Stratégie 3 : aucune clé connue trouvée — log une seule fois
    if _appliedStrategy ~= 3 then
        _appliedStrategy = 3
        print("[Telecom] AVERTISSEMENT : aucune clé de croissance trouvée dans game.config")
        print("[Telecom] Le bonus de " .. string.format("%.0f%%", bonus * 100) .. " ne peut pas être appliqué")
        print("[Telecom] Tapez : for k,v in pairs(game.config) do print(k,v) end")
    end
end

-- =============================================================================
-- POINT D'ENTRÉE DU GAME SCRIPT
-- =============================================================================
function data()
    return {
        -- init() : appelé sans argument au démarrage d'une nouvelle partie.
        -- Doit RETOURNER la table d'état initiale.
        init = function()
            return {
                tick      = 0,
                nodes     = {},
                coverage  = {},
                lastBonus = 0,
                townCount = 0,
                nodeCount = 0,
            }
        end,

        -- update(state) : appelé à chaque tick de simulation avec l'état courant.
        -- DOIT retourner state pour que le moteur le conserve entre les ticks.
        update = function(state)
            -- Sécurité : si state est nil (ne devrait pas arriver), on le recrée
            if not state then
                state = { tick = 0, nodes = {}, coverage = {}, lastBonus = 0, townCount = 0, nodeCount = 0 }
            end

            -- Diagnostic au premier tick : affiche les clés game.config disponibles
            runDiagnostic()

            state.tick = (state.tick or 0) + 1

            -- Ne recalculer que toutes les TICK_INTERVAL secondes
            if state.tick % TICK_INTERVAL ~= 0 then return state end

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

            -- 6. Mettre à jour l'état
            state.nodes     = nodes
            state.coverage  = coverage
            state.lastBonus = bonus
            state.townCount = #towns
            state.nodeCount = #nodes

            -- IMPORTANT : retourner state pour que TF2 le conserve
            return state
        end,

        -- save(state) : sérialisation pour la sauvegarde de partie.
        -- Appelé avec state pouvant être nil si update n'a pas encore tourné.
        save = function(state)
            if not state then
                return { tick = 0, lastBonus = 0, townCount = 0, nodeCount = 0 }
            end
            return {
                tick      = state.tick      or 0,
                lastBonus = state.lastBonus or 0,
                townCount = state.townCount or 0,
                nodeCount = state.nodeCount or 0,
                -- nodes et coverage sont reconstruits au prochain update
            }
        end,

        -- load(saved) : restauration depuis une sauvegarde.
        -- Doit retourner l'état complet reconstruit.
        load = function(saved)
            return {
                tick      = saved and saved.tick      or 0,
                lastBonus = saved and saved.lastBonus or 0,
                townCount = saved and saved.townCount or 0,
                nodeCount = saved and saved.nodeCount or 0,
                nodes     = {},
                coverage  = {},
            }
        end,

        -- =============================================================================
        -- INTERFACE UTILISATEUR (UI Thread)
        -- =============================================================================
        guiInit = function()
            -- Sécurité : on utilise pcall pour éviter un crash complet du jeu
            -- si une méthode de l'API UI n'est pas supportée par cette version de TF2.
            pcall(function()
                if not api.gui or not api.gui.comp or not api.gui.comp.Window then return end

                local window = api.gui.comp.Window.new("Réseaux Télécom - Statut", nil)
                if not window then return end
                window:setId("telecom_status_window")
                
                -- L'API correcte pour les layouts est api.gui.layout (et non api.gui.comp)
                local layout = api.gui.layout.BoxLayout.new("VERTICAL")
                local textView = api.gui.comp.TextView.new("Initialisation...\nPlacez des infrastructures télécom pour booster vos villes.")
                textView:setId("telecom_status_text")
                layout:addItem(textView)
                
                window:setContent(layout)
                
                -- Vérification des méthodes avant appel (selon version TF2)
                if window.setResizable then window:setResizable(true) end
                if window.setMovable then window:setMovable(true) end
                if window.addHideOnCloseHandler then window:addHideOnCloseHandler() end
                
                if api.gui.util and api.gui.util.Size then
                    window:setSize(api.gui.util.Size.new(380, 120))
                end
                
                window:setVisible(true)
                _telecom_gui_tick = 0
            end)
        end,

        guiUpdate = function()
            pcall(function()
                _telecom_gui_tick = (_telecom_gui_tick or 0) + 1
                if _telecom_gui_tick % 60 ~= 0 then return end

                if not api.gui or not api.gui.util then return end
                local textView = api.gui.util.getById("telecom_status_text")
                if not textView then return end

                local townCount = 0
                local nodeCount = 0
                local entities = api.engine.getEntities() or {}
                
                for _, id in ipairs(entities) do
                    local tComp = api.engine.getComponent(id, api.type.ComponentType.TOWN)
                    if tComp then townCount = townCount + 1 end
                    
                    local cComp = api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
                    if cComp and cComp.fileName and string.find(cComp.fileName, "telecom") then
                        nodeCount = nodeCount + 1
                    end
                end

                local interval = 60
                if game and game.config and game.config.townDevelopInterval then
                    interval = game.config.townDevelopInterval
                end

                local bonusPct = 0
                if interval < 60 then
                    bonusPct = 60.0 * (1.0 - (interval / 60.0))
                end

                local text = string.format(
                    "▶ Infrastructures actives : %d\n" ..
                    "▶ Villes sur la carte : %d\n\n" ..
                    "📈 Bonus de croissance estimé : +%.1f%%\n" ..
                    "⏱️ Rythme de développement : %d ticks",
                    nodeCount, townCount, bonusPct, interval
                )
                textView:setText(text)
            end)
        end,
    }
end