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

-- Table de communication entre thread moteur (update) et thread UI (guiUpdate).
-- Le thread moteur écrit ici ; guiUpdate lit seulement.
_telecom_ui_data = {
    wireNodes    = 0,
    mobileNodes  = 0,
    townCount    = 0,
    coveredTowns = 0,
    coverPct     = 0,
    bonusPct     = 0,
    interval     = 60,
    ready        = false,
}

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

            -- Compter les nœuds par type
            local wireNodes   = 0
            local mobileNodes = 0
            for _, n in ipairs(nodes) do
                if n.kind == "WIRE" then wireNodes = wireNodes + 1
                else mobileNodes = mobileNodes + 1 end
            end

            -- Villes couvertes
            local coveredTowns = 0
            for townId, c in pairs(coverage) do
                if c.wireEpoch or c.mobileEpoch then
                    coveredTowns = coveredTowns + 1
                end
            end

            local townCount = #towns
            local coverPct  = townCount > 0 and math.floor(coveredTowns * 100 / townCount) or 0
            local interval  = (game and game.config and game.config.townDevelopInterval) or 60
            local bonusPct  = 0
            if interval < 60 then
                bonusPct = math.floor(60.0 * (1.0 - (interval / 60.0)) + 0.5)
            end

            -- Écrire dans la table de communication UI
            _telecom_ui_data.wireNodes    = wireNodes
            _telecom_ui_data.mobileNodes  = mobileNodes
            _telecom_ui_data.townCount    = townCount
            _telecom_ui_data.coveredTowns = coveredTowns
            _telecom_ui_data.coverPct     = coverPct
            _telecom_ui_data.bonusPct     = bonusPct
            _telecom_ui_data.interval     = interval
            _telecom_ui_data.ready        = true

            state.nodes     = nodes
            state.coverage  = coverage
            state.lastBonus = bonus
            state.townCount = townCount
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
            local ok, err = pcall(function()
                if not (api and api.gui and api.gui.comp and api.gui.comp.Window) then
                    print("[Telecom] ERREUR: api.gui.comp.Window indisponible")
                    return
                end
                if not (api.gui.layout and api.gui.layout.BoxLayout) then
                    print("[Telecom] ERREUR: api.gui.layout.BoxLayout indisponible")
                    return
                end

                -- ----------------------------------------------------------------
                -- CONSTRUCTION DE LA FENETRE
                -- ----------------------------------------------------------------
                local existing = api.gui.util.getById("telecom_status_window")
                if existing then existing:destroy() end

                local outerLayout = api.gui.layout.BoxLayout.new("VERTICAL")

                -- En-tête
                local title = api.gui.comp.TextView.new("📡  Réseaux de Communication")
                title:setId("telecom_title")
                outerLayout:addItem(title)

                local sep1 = api.gui.comp.TextView.new("────────────────────────────")
                outerLayout:addItem(sep1)

                -- Section infrastructure
                local secInfra = api.gui.comp.TextView.new("[ Infrastructures ]")
                outerLayout:addItem(secInfra)

                local infraText = api.gui.comp.TextView.new(
                    "  Filaire  : 0 noeud(s)\n" ..
                    "  Mobile   : 0 antenne(s)"
                )
                infraText:setId("telecom_infra_text")
                outerLayout:addItem(infraText)

                local sep2 = api.gui.comp.TextView.new("────────────────────────────")
                outerLayout:addItem(sep2)

                -- Section couverture
                local secCov = api.gui.comp.TextView.new("[ Couverture ]")
                outerLayout:addItem(secCov)

                local covText = api.gui.comp.TextView.new(
                    "  Villes couvertes : 0 / 0\n" ..
                    "  Taux             : 0%"
                )
                covText:setId("telecom_cov_text")
                outerLayout:addItem(covText)

                local sep3 = api.gui.comp.TextView.new("────────────────────────────")
                outerLayout:addItem(sep3)

                -- Section bonus
                local secBonus = api.gui.comp.TextView.new("[ Effet sur la croissance ]")
                outerLayout:addItem(secBonus)

                local bonusText = api.gui.comp.TextView.new(
                    "  Bonus actuel : +0%\n" ..
                    "  Intervalle   : 60 ticks (défaut)"
                )
                bonusText:setId("telecom_status_text")
                outerLayout:addItem(bonusText)

                -- Pied de fenêtre
                local sep4 = api.gui.comp.TextView.new("────────────────────────────")
                outerLayout:addItem(sep4)

                local footer = api.gui.comp.TextView.new(
                    "Placez des infrastructures autour\n" ..
                    "de vos villes pour les connecter."
                )
                outerLayout:addItem(footer)

                -- ----------------------------------------------------------------
                -- FENETRE PRINCIPALE
                -- ----------------------------------------------------------------
                local window = api.gui.comp.Window.new("Telecom — Réseaux de Communication", outerLayout)
                window:setId("telecom_status_window")

                if window.addHideOnCloseHandler then
                    window:addHideOnCloseHandler()
                end
                if api.gui.util and api.gui.util.Size then
                    window:setSize(api.gui.util.Size.new(500, 520))
                end

                window:setVisible(true, false)
                print("[Telecom] Fenetre principale creee et visible")

                -- ----------------------------------------------------------------
                -- BOUTON TOGGLE DANS LE JEU
                -- ----------------------------------------------------------------
                local btnLabel = api.gui.comp.TextView.new("Telecom")
                local toggleBtn = api.gui.comp.Button.new(btnLabel, true)
                toggleBtn:setId("telecom_toggle_btn")
                toggleBtn:setTooltip("Afficher/Masquer Telecom")

                toggleBtn:onClick(function()
                    pcall(function()
                        local w = api.gui.util.getById("telecom_status_window")
                        if w then w:setVisible(not w:isVisible(), true) end
                    end)
                end)

                -- Injection du bouton (peut échouer selon les IDs)
                local injected = false
                pcall(function()
                    local gi = api.gui.util.getById("gameInfo")
                    if gi then
                        local lay = gi:getLayout()
                        if lay then
                            local ok2, err2 = pcall(function() lay:addItem(toggleBtn) end)
                            if ok2 then injected = true end
                        end
                    end
                end)

                _telecom_gui_tick = 0
            end)
            if not ok then
                print("[Telecom] CRASH guiInit: " .. tostring(err))
            end
        end,


        guiUpdate = function()
            pcall(function()
                _telecom_gui_tick = (_telecom_gui_tick or 0) + 1
                if _telecom_gui_tick % 120 ~= 0 then return end
                if not (api and api.gui and api.gui.util) then return end
                if not (game and game.interface) then return end

                local infraText = api.gui.util.getById("telecom_infra_text")
                local covText   = api.gui.util.getById("telecom_cov_text")
                local bonusText = api.gui.util.getById("telecom_status_text")
                if not infraText and not covText and not bonusText then return end

                -- ============================================================
                -- 1. SCAN DES CONSTRUCTIONS / ASSETS (UI Thread)
                -- ============================================================
                local wireNodes = 0
                local mobileNodes = 0
                local nodes = {}
                local debugStr = ""

                pcall(function()
                    local function scanType(typeStr)
                        local ids = game.interface.getEntities({pos={0,0}, radius=999999}, {type=typeStr}) or {}
                        for _, eid in ipairs(ids) do
                            pcall(function()
                                local e = game.interface.getEntity(eid)
                                if e then
                                    local isTelecom = false
                                    local isWire = false
                                    local matchStr = ""
                                    
                                    -- Check fileName (pour les .con)
                                    if e.fileName and e.fileName:find("telecom") then
                                        isTelecom = true
                                        matchStr = e.fileName
                                        if e.fileName:find("fixed_line") or e.fileName:find("fiber") then isWire = true end
                                    end
                                    
                                    -- Check models (pour les assets purs)
                                    if not isTelecom and e.models then
                                        for _, mdl in pairs(e.models) do
                                            local mName = type(mdl) == "string" and mdl or (type(mdl) == "table" and mdl[1] or "")
                                            if mName:find("telecom") then
                                                isTelecom = true
                                                matchStr = mName
                                                if mName:find("pole") or mName:find("cabinet") or mName:find("fixed_line") or mName:find("fiber") then
                                                    isWire = true
                                                end
                                                break
                                            end
                                        end
                                    end
                                    
                                    if isTelecom then
                                        debugStr = debugStr .. "\n[Debug] Trouve: " .. matchStr
                                        if isWire then wireNodes = wireNodes + 1
                                        else mobileNodes = mobileNodes + 1 end
                                        
                                        local radius = 600
                                        pcall(function()
                                            if e.params and e.params[1] then
                                                local p = e.params[1]
                                                if matchStr:find("fixed_line_1850") then radius = ({100,200,300,400,500})[p+1] or 300
                                                elseif matchStr:find("fiber_2020") then radius = ({300,450,600,900,1200})[p+1] or 600
                                                elseif matchStr:find("mobile_1990") then radius = ({400,600,800,1000})[p+1] or 600
                                                elseif matchStr:find("mobile_2030") then radius = ({800,1200,1600,2000})[p+1] or 1200
                                                end
                                            else
                                                if matchStr:find("fixed_line") or matchStr:find("pole") or matchStr:find("cabinet") then radius = 300
                                                elseif matchStr:find("mobile_2030") or matchStr:find("tower") then radius = 1200 end
                                            end
                                        end)
                                        
                                        local p = e.position
                                        if p then
                                            table.insert(nodes, {
                                                x = p.x or p[1] or 0,
                                                y = p.y or p[2] or 0,
                                                r = radius
                                            })
                                        end
                                    end
                                end
                            end)
                        end
                    end
                    
                    scanType("CONSTRUCTION")
                    scanType("ASSET_GROUP")
                end)

                -- ============================================================
                -- 2. SCAN DES VILLES ET CALCUL COUVERTURE (UI Thread)
                -- ============================================================
                local townCount = 0
                local coveredTowns = 0
                pcall(function()
                    local tids = game.interface.getTowns() or {}
                    townCount = #tids
                    for _, tid in ipairs(tids) do
                        pcall(function()
                            local t = game.interface.getEntity(tid)
                            if t and t.position then
                                local tx = t.position.x or t.position[1] or 0
                                local ty = t.position.y or t.position[2] or 0
                                local isCov = false
                                for _, n in ipairs(nodes) do
                                    local dx = tx - n.x
                                    local dy = ty - n.y
                                    if (dx*dx + dy*dy) <= (n.r * n.r) then
                                        isCov = true
                                        break
                                    end
                                end
                                if isCov then coveredTowns = coveredTowns + 1 end
                            end
                        end)
                    end
                end)

                -- ============================================================
                -- 3. BONUS ACTUEL
                -- ============================================================
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
                local coverPct = townCount > 0 and math.floor(coveredTowns * 100 / townCount) or 0

                -- ============================================================
                -- AFFICHAGE AVEC DEBUG
                -- ============================================================
                if infraText then
                    if debugStr == "" then debugStr = "\n[Debug] Aucune antenne/asset trouve" end
                    infraText:setText(
                        "  Filaire  : " .. wireNodes .. " noeud(s)\n" ..
                        "  Mobile   : " .. mobileNodes .. " antenne(s)" .. debugStr
                    )
                end

                if covText then
                    local bonusStr = bonusPct > 0
                        and ("+" .. bonusPct .. "% de croissance actif")
                        or "Placez des infrastructures"
                    covText:setText(
                        "  Villes couvertes : " .. coveredTowns .. " / " .. townCount .. "\n" ..
                        "  Taux             : " .. coverPct .. "%\n" ..
                        "  " .. bonusStr
                    )
                end

                if bonusText then
                    local st = bonusPct > 0 and "ACTIF !" or "inactif"
                    bonusText:setText(
                        "  Bonus actuel : +" .. bonusPct .. "% (" .. st .. ")\n" ..
                        "  Intervalle   : " .. interval .. " ticks" ..
                        (interval < 60 and " (accelere !)" or " (defaut)")
                    )
                end
            end)
        end,
    }
end
