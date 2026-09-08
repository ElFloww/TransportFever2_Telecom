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
--     5. Modifie game.config.townDevelopInterval dynamiquement
--
--   La partie UI (guiInit / guiUpdate) tourne sur le thread UI séparé.
--   Elle utilise api.gui pour afficher une fenêtre de statut avec un bouton
--   toggle dans la barre du jeu.
--
-- BONUS PAR ÉPOQUE (cumulatif, plafonné à MAX_BONUS) :
--   WIRE  1850 : +5%  par ville couverte
--   WIRE  2020 : +20% par ville couverte (remplace le 1850 si les deux existent)
--   MOBILE 1990 : +10% par ville couverte
--   MOBILE 2030 : +15% par ville couverte (remplace le 1990 si les deux existent)
--   Bonus combiné WIRE+MOBILE : multiplicateur x1.2 (synergie)
-- =============================================================================

local TICK_INTERVAL = 60   -- secondes de jeu entre deux recalculs
local BASE_GROWTH   = 1.0  -- valeur par défaut
local MAX_BONUS     = 0.60 -- bonus maximal cumulable (+60%)

-- Bonus de base par type et époque (la meilleure époque disponible est retenue)
local WIRE_BONUS = {
    [1850] = 0.05,
    [2020] = 0.20,
}
local MOBILE_BONUS = {
    [1990] = 0.10,
    [2030] = 0.15,
}

-- Multiplicateur si une ville a à la fois couverture WIRE et MOBILE
local SYNERGY_MULT = 1.2

-- =============================================================================
-- UTILITAIRES
-- =============================================================================

--- Distance euclidienne 2D entre deux positions (ignore Z)
local function dist2D(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

--- Extrait la position XY depuis un composant TRANSFORM
local function posFromTransf(tf)
    if not tf or not tf.transf then return nil end
    local t = tf.transf
    -- La matrice TF2 est column-major : indices 13, 14, 15 = translation X, Y, Z
    return { x = t[13] or 0, y = t[14] or 0, z = t[15] or 0 }
end

-- =============================================================================
-- COLLECTE DES NOEUDS TELECOM
-- =============================================================================
local function collectTelecomNodes()
    local nodes = {}

    local ok, entities = pcall(function()
        return api.engine.getEntitiesOfType(api.type.EntityType.CONSTRUCTION)
    end)
    if not ok or not entities then
        ok, entities = pcall(function()
            return api.engine.getEntities()
        end)
    end
    if not ok or not entities then return nodes end

    for _, id in ipairs(entities) do
        local success, con = pcall(function()
            return api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
        end)
        if success and con then
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
                local tf  = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
                local pos = posFromTransf(tf)

                -- Récupérer le rayon depuis les params de construction
                local r = 300
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
                    id     = id,
                    kind   = kind,
                    epoch  = epoch,
                    radius = r,
                    pos    = pos,
                })
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
        ok, townIds = pcall(function()
            return game.interface.getTowns()
        end)
    end
    if not ok or not townIds then return towns end

    for _, id in ipairs(townIds) do
        local tf  = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
        local pos = posFromTransf(tf)

        -- Essayer de récupérer le nom de la ville
        local townName = ""
        pcall(function()
            local nameComp = api.engine.getComponent(id, api.type.ComponentType.NAME)
            if nameComp and nameComp.name then
                townName = nameComp.name
            end
        end)

        if pos then
            table.insert(towns, { id = id, pos = pos, name = townName })
        end
    end
    return towns
end

-- =============================================================================
-- CALCUL DE COUVERTURE
-- =============================================================================
local function computeCoverage(nodes, towns)
    local coverage = {}
    for _, town in ipairs(towns) do
        coverage[town.id] = {
            wireEpoch   = nil,
            mobileEpoch = nil,
            townName    = town.name or "",
        }
    end

    for _, node in ipairs(nodes) do
        if node.pos then
            for _, town in ipairs(towns) do
                if dist2D(node.pos, town.pos) <= node.radius then
                    local c = coverage[town.id]
                    if node.kind == "WIRE" then
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
            if wireB > 0 and mobileB > 0 then
                bonus = bonus * SYNERGY_MULT
            end
            totalBonus   = totalBonus + bonus
            coveredTowns = coveredTowns + 1
        end
    end

    if coveredTowns == 0 then return 0 end

    local avgBonus    = totalBonus / coveredTowns
    local coverRatio  = coveredTowns / totalTowns
    local globalBonus = avgBonus * coverRatio

    return math.min(globalBonus, MAX_BONUS)
end

-- =============================================================================
-- DIAGNOSTIC (1 seule fois au premier tick)
-- =============================================================================
local _diagDone = false
local function runDiagnostic()
    if _diagDone then return end
    _diagDone = true
    print("[Telecom] === MOD TELECOM ACTIF ===")
    print("[Telecom] Version 2.0 — groundFaces + UI Window")
    if game and game.config then
        local interval = game.config.townDevelopInterval
        print("[Telecom] townDevelopInterval = " .. tostring(interval))
    end
    print("[Telecom] =========================")
end

-- =============================================================================
-- APPLICATION DU BONUS
-- =============================================================================
local _lastLoggedBonus = -1

local function applyBonus(bonus)
    if not game or not game.config then return end

    if game.config.townDevelopInterval ~= nil then
        local DEFAULT_INTERVAL = 60
        local MIN_INTERVAL     = 20
        local newInterval = math.floor(DEFAULT_INTERVAL - (DEFAULT_INTERVAL - MIN_INTERVAL) * bonus / MAX_BONUS)
        newInterval = math.max(MIN_INTERVAL, math.min(DEFAULT_INTERVAL, newInterval))
        game.config.townDevelopInterval = newInterval

        -- Log uniquement si le bonus change significativement
        local bonusPct = math.floor(bonus * 100)
        if bonusPct ~= _lastLoggedBonus then
            _lastLoggedBonus = bonusPct
            print("[Telecom] Bonus: +" .. bonusPct .. "% → townDevelopInterval = " .. newInterval)
        end
    end
end

-- =============================================================================
-- POINT D'ENTRÉE DU GAME SCRIPT
-- =============================================================================
function data()
    return {
        -- =====================================================================
        -- ENGINE THREAD : init / update / save / load
        -- =====================================================================

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

        update = function(state)
            if not state then
                state = { tick = 0, nodes = {}, coverage = {}, lastBonus = 0, townCount = 0, nodeCount = 0 }
            end

            runDiagnostic()

            state.tick = (state.tick or 0) + 1
            if state.tick % TICK_INTERVAL ~= 0 then return state end

            local nodes    = collectTelecomNodes()
            local towns    = collectTowns()
            local coverage = computeCoverage(nodes, towns)
            local bonus    = computeGlobalBonus(coverage, #towns)

            applyBonus(bonus)

            state.nodes     = nodes
            state.coverage  = coverage
            state.lastBonus = bonus
            state.townCount = #towns
            state.nodeCount = #nodes

            return state
        end,

        save = function(state)
            if not state then
                return { tick = 0, lastBonus = 0, townCount = 0, nodeCount = 0 }
            end
            return {
                tick      = state.tick      or 0,
                lastBonus = state.lastBonus or 0,
                townCount = state.townCount or 0,
                nodeCount = state.nodeCount or 0,
            }
        end,

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

        -- =====================================================================
        -- UI THREAD : guiInit / guiUpdate
        -- =====================================================================

        guiInit = function()
            -- Tout dans un pcall pour ne jamais crasher le jeu
            pcall(function()
                -- Vérifier que l'API GUI est disponible
                if not api or not api.gui or not api.gui.comp then return end
                if not api.gui.comp.Window then return end
                if not api.gui.layout then return end

                -- Créer le contenu de la fenêtre
                local layout = api.gui.layout.BoxLayout.new("VERTICAL")

                local headerText = api.gui.comp.TextView.new("Réseaux de Communication")
                headerText:setId("telecom_header")
                layout:addItem(headerText)

                local statusText = api.gui.comp.TextView.new(
                    "Placez des infrastructures télécom\n" ..
                    "autour de vos villes pour booster\n" ..
                    "leur croissance.\n\n" ..
                    "Chargement des données..."
                )
                statusText:setId("telecom_status_text")
                layout:addItem(statusText)

                -- Créer la fenêtre (2 arguments : titre, layout)
                local window = api.gui.comp.Window.new("Telecom", layout)
                window:setId("telecom_status_window")

                -- Configurer la fenêtre
                if window.addHideOnCloseHandler then
                    window:addHideOnCloseHandler()
                end
                if api.gui.util and api.gui.util.Size then
                    window:setSize(api.gui.util.Size.new(350, 250))
                end
                if window.setPosition then
                    window:setPosition(100, 200)
                end

                -- Caché par défaut
                window:setVisible(false, false)

                -- Bouton toggle dans la barre du jeu
                local btnLabel = api.gui.comp.TextView.new("Telecom")
                local toggleBtn = api.gui.comp.Button.new(btnLabel, true)
                toggleBtn:setId("telecom_toggle_btn")

                toggleBtn:onClick(function()
                    pcall(function()
                        local w = api.gui.util.getById("telecom_status_window")
                        if w then
                            local vis = w:isVisible()
                            w:setVisible(not vis, false)
                        end
                    end)
                end)

                -- Essayer d'injecter le bouton dans la barre du jeu
                pcall(function()
                    local gameInfo = api.gui.util.getById("gameInfo")
                    if gameInfo and gameInfo.getLayout then
                        gameInfo:getLayout():addItem(toggleBtn)
                    end
                end)

                -- Variable globale pour le compteur de frames UI
                _telecom_gui_tick = 0
                print("[Telecom] UI initialisée avec succès")
            end)
        end,

        guiUpdate = function()
            pcall(function()
                _telecom_gui_tick = (_telecom_gui_tick or 0) + 1
                -- Mise à jour toutes les ~120 frames pour ne pas surcharger l'UI
                if _telecom_gui_tick % 120 ~= 0 then return end

                -- Vérifier que la fenêtre existe
                if not api or not api.gui or not api.gui.util then return end
                local statusText = api.gui.util.getById("telecom_status_text")
                if not statusText then return end

                -- Collecter les données directement (thread UI peut lire api.engine)
                local wireNodes   = 0
                local mobileNodes = 0
                local townCount   = 0
                local coveredTowns = 0

                -- Scanner les entités
                local entities = {}
                pcall(function()
                    entities = api.engine.getEntities() or {}
                end)

                local towns = {}
                local nodes = {}

                for _, id in ipairs(entities) do
                    pcall(function()
                        -- Villes
                        local tComp = api.engine.getComponent(id, api.type.ComponentType.TOWN)
                        if tComp then
                            townCount = townCount + 1
                            local tf = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
                            if tf and tf.transf then
                                table.insert(towns, {
                                    x = tf.transf[13] or 0,
                                    y = tf.transf[14] or 0,
                                })
                            end
                        end

                        -- Constructions télécom
                        local cComp = api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
                        if cComp and cComp.fileName then
                            local fn = cComp.fileName
                            if fn:find("telecom") then
                                local isWire = fn:find("fixed_line") or fn:find("fiber")
                                if isWire then
                                    wireNodes = wireNodes + 1
                                else
                                    mobileNodes = mobileNodes + 1
                                end

                                local tf = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
                                if tf and tf.transf then
                                    table.insert(nodes, {
                                        x = tf.transf[13] or 0,
                                        y = tf.transf[14] or 0,
                                        r = 500, -- rayon approximatif pour l'UI
                                    })
                                end
                            end
                        end
                    end)
                end

                -- Compter les villes couvertes (approximation simple)
                for _, town in ipairs(towns) do
                    for _, node in ipairs(nodes) do
                        local dx = town.x - node.x
                        local dy = town.y - node.y
                        if math.sqrt(dx*dx + dy*dy) <= node.r then
                            coveredTowns = coveredTowns + 1
                            break
                        end
                    end
                end

                -- Lire l'intervalle de développement actuel
                local interval = 60
                pcall(function()
                    if game and game.config and game.config.townDevelopInterval then
                        interval = game.config.townDevelopInterval
                    end
                end)

                local bonusPct = 0
                if interval < 60 then
                    bonusPct = math.floor(60.0 * (1.0 - (interval / 60.0)) + 0.5)
                end

                -- Construire le texte d'affichage
                local lines = {}
                table.insert(lines, "--- Infrastructures ---")
                table.insert(lines, "  Filaire : " .. wireNodes .. " noeuds")
                table.insert(lines, "  Mobile  : " .. mobileNodes .. " antennes")
                table.insert(lines, "")
                table.insert(lines, "--- Couverture ---")
                table.insert(lines, "  Villes couvertes : " .. coveredTowns .. " / " .. townCount)
                table.insert(lines, "")
                table.insert(lines, "--- Bonus ---")
                table.insert(lines, "  Croissance : +" .. bonusPct .. "%")
                table.insert(lines, "  Rythme     : " .. interval .. " ticks")

                if bonusPct > 0 then
                    table.insert(lines, "")
                    table.insert(lines, "Le bonus de croissance est actif !")
                end

                statusText:setText(table.concat(lines, "\n"))
            end)
        end,
    }
end