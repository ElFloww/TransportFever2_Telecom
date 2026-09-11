-- =============================================================================
-- telecom_growth.lua  —  Moteur de croissance télécom
-- Mod : Réseaux de Communication  |  Auteur : elfloww
-- =============================================================================
--
-- FONCTIONNEMENT :
--   Ce game_script est appelé par le moteur TF2 à chaque tick de simulation.
--   Toutes les TICK_INTERVAL secondes de jeu, il :
--     1. Scanne les constructions pour trouver NRA, NRO et Antennes
--     2. Scanne les villes pour obtenir leur position
--     3. Calcule la couverture (fixe + mobile)
--     4. Détermine le bonus global de croissance à appliquer
--     5. Modifie game.config.townDevelopInterval dynamiquement
--
--   La partie UI (guiInit / guiUpdate) tourne sur le thread UI séparé.
--   Elle utilise game.interface.getEntities pour scanner les constructions
--   et api.gui pour afficher une fenêtre de statut.
--
-- INFRASTRUCTURES :
--   NRA  (1974) : Central cuivre, portée 1500 m, bonus +3%
--   NRO  (2007) : Nœud fibre optique, portée 3000 m, bonus +8%
--   Antenne (1992+) : Multi-technologie, portée et bonus par génération
--
-- TECHNOLOGIES ANTENNE (bonus par ville couverte) :
--   2G  (1992) : 2000 m, +2%
--   3G  (2004) : 1500 m, +3%
--   3G+ (2006) : 1500 m, +4%
--   4G  (2012) : 1200 m, +5%
--   4G+ (2014) : 1200 m, +6%
--   5G  (2020) :  800 m, +8%
--   5G+ (2023) :  500 m, +10%
--
-- Bonus synergie : x1.2 si une ville a à la fois couverture fixe ET mobile
-- Bonus cumulatif plafonné à MAX_BONUS.
-- =============================================================================

local TICK_INTERVAL = 60   -- secondes de jeu entre deux recalculs
local MAX_BONUS     = 0.60 -- bonus maximal cumulable (+60%)
local SYNERGY_MULT  = 1.2  -- multiplicateur si fixe + mobile

-- Définition des technologies antenne : { année, portée, bonus }
local ANTENNA_TECHS = {
    { year = 1992, radius = 2000, bonus = 0.02, name = "2G"  },  -- param index 1
    { year = 2004, radius = 1500, bonus = 0.03, name = "3G"  },  -- param index 2
    { year = 2006, radius = 1500, bonus = 0.04, name = "3G+" },  -- param index 3
    { year = 2012, radius = 1200, bonus = 0.05, name = "4G"  },  -- param index 4
    { year = 2014, radius = 1200, bonus = 0.06, name = "4G+" },  -- param index 5
    { year = 2020, radius =  800, bonus = 0.08, name = "5G"  },  -- param index 6
    { year = 2023, radius =  500, bonus = 0.10, name = "5G+" },  -- param index 7
}

-- Bonus fixe par type d'infrastructure
local NRA_BONUS = 0.03
local NRO_BONUS = 0.08

-- =============================================================================
-- UTILITAIRES
-- =============================================================================

local function dist2D(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function posFromTransf(tf)
    if not tf or not tf.transf then return nil end
    local t = tf.transf
    return { x = t[13] or 0, y = t[14] or 0, z = t[15] or 0 }
end

-- =============================================================================
-- COLLECTE DES NOEUDS TELECOM (Thread Moteur)
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

    -- Récupérer l'année courante
    local currentYear = 2000
    pcall(function()
        local clock = api.engine.getComponent(0, api.type.ComponentType.GAME_TIME)
        if clock and clock.date then
            currentYear = clock.date.year or 2000
        end
    end)
    pcall(function()
        if game and game.interface and game.interface.getGameTime then
            local gt = game.interface.getGameTime()
            if gt and gt.date and gt.date.year then
                currentYear = gt.date.year
            end
        end
    end)

    for _, id in ipairs(entities) do
        local success, con = pcall(function()
            return api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
        end)
        if success and con then
            local fileName = con.fileName or ""

            if fileName:find("telecom/nra") then
                -- NRA : portée fixe 1500 m
                local tf  = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
                local pos = posFromTransf(tf)
                if pos then
                    table.insert(nodes, {
                        id     = id,
                        kind   = "NRA",
                        radius = 1500,
                        bonus  = NRA_BONUS,
                        pos    = pos,
                    })
                end

            elseif fileName:find("telecom/nro") then
                -- NRO : portée fixe 3000 m
                local tf  = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
                local pos = posFromTransf(tf)
                if pos then
                    table.insert(nodes, {
                        id     = id,
                        kind   = "NRO",
                        radius = 3000,
                        bonus  = NRO_BONUS,
                        pos    = pos,
                    })
                end

            elseif fileName:find("telecom/antenna") then
                -- Antenne : lire les params pour chaque technologie
                local tf  = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
                local pos = posFromTransf(tf)
                if pos then
                    for techIdx, tech in ipairs(ANTENNA_TECHS) do
                        local isActive = false
                        pcall(function()
                            if con.params and con.params[techIdx] then
                                isActive = (con.params[techIdx] == 1)
                            end
                        end)
                        if isActive and currentYear >= tech.year then
                            table.insert(nodes, {
                                id     = id,
                                kind   = "ANTENNA",
                                tech   = tech.name,
                                radius = tech.radius,
                                bonus  = tech.bonus,
                                pos    = pos,
                            })
                        end
                    end
                end
            end
        end
    end
    return nodes
end

-- =============================================================================
-- COLLECTE DES VILLES (Thread Moteur)
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
            hasFixed    = false,   -- couvert par NRA ou NRO
            hasMobile   = false,   -- couvert par au moins une tech antenne
            fixedBonus  = 0,
            mobileBonus = 0,
            townName    = town.name or "",
        }
    end

    for _, node in ipairs(nodes) do
        if node.pos then
            for _, town in ipairs(towns) do
                if dist2D(node.pos, town.pos) <= node.radius then
                    local c = coverage[town.id]
                    if node.kind == "NRA" or node.kind == "NRO" then
                        c.hasFixed = true
                        c.fixedBonus = math.max(c.fixedBonus, node.bonus)
                    elseif node.kind == "ANTENNA" then
                        c.hasMobile = true
                        c.mobileBonus = c.mobileBonus + node.bonus
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

    local totalBonus   = 0
    local coveredTowns = 0

    for _, c in pairs(coverage) do
        local fixedB  = c.fixedBonus
        local mobileB = c.mobileBonus

        if fixedB > 0 or mobileB > 0 then
            local bonus = fixedB + mobileB
            -- Synergie fixe + mobile
            if fixedB > 0 and mobileB > 0 then
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
-- POINT D'ENTREE DU GAME SCRIPT
-- =============================================================================
local _lastTick    = 0
local _firstUpdate = true

function data()
    return {
        init = function()
            pcall(function()
                print("[Telecom] === MOD TELECOM ACTIF ===")
                print("[Telecom] Version 3.0 — NRA / NRO / Antenne multi-tech")
                if game and game.config then
                    print("[Telecom] townDevelopInterval = " .. tostring(game.config.townDevelopInterval))
                end
                print("[Telecom] =========================")
            end)
        end,

        update = function()
            pcall(function()
                if not (api and api.engine and api.type) then return end
                if not (api.type.EntityType and api.type.ComponentType) then return end

                local now = 0
                pcall(function()
                    now = api.engine.getComponent(0, api.type.ComponentType.GAME_TIME).time or 0
                end)
                if now - _lastTick < TICK_INTERVAL then return end
                _lastTick = now

                -- 1. Collecter les noeuds et les villes
                local nodes = collectTelecomNodes()
                local towns = collectTowns()

                if _firstUpdate then
                    _firstUpdate = false
                    local nraCount, nroCount, antCount = 0, 0, 0
                    for _, n in ipairs(nodes) do
                        if n.kind == "NRA" then nraCount = nraCount + 1
                        elseif n.kind == "NRO" then nroCount = nroCount + 1
                        elseif n.kind == "ANTENNA" then antCount = antCount + 1
                        end
                    end
                    print("[Telecom] Premier scan: " .. #towns .. " villes, "
                        .. nraCount .. " NRA, " .. nroCount .. " NRO, "
                        .. antCount .. " tech antenne actives")
                end

                -- 2. Calculer la couverture
                local coverage    = computeCoverage(nodes, towns)
                local townCount   = #towns

                -- 3. Compteurs
                local coveredTowns = 0
                for _, c in pairs(coverage) do
                    if c.hasFixed or c.hasMobile then
                        coveredTowns = coveredTowns + 1
                    end
                end

                -- 4. Calculer le bonus global
                local globalBonus = computeGlobalBonus(coverage, townCount)

                -- 5. Appliquer le nouveau townDevelopInterval
                if game and game.config then
                    local newInterval = math.max(1, math.floor(60 * (1.0 - globalBonus)))
                    game.config.townDevelopInterval = newInterval
                end
            end)
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

                local existing = api.gui.util.getById("telecom_status_window")
                if existing then existing:destroy() end

                -- ----------------------------------------------------------------
                -- CONSTRUCTION DE LA FENETRE
                -- ----------------------------------------------------------------
                local outerLayout = api.gui.layout.BoxLayout.new("VERTICAL")

                -- En-tête
                local title = api.gui.comp.TextView.new("📡  Reseaux de Communication")
                title:setId("telecom_title")
                outerLayout:addItem(title)

                local sep1 = api.gui.comp.TextView.new("────────────────────────────────")
                outerLayout:addItem(sep1)

                -- Section Infrastructure Fixe
                local secFixed = api.gui.comp.TextView.new("[ Infrastructure Fixe ]")
                outerLayout:addItem(secFixed)

                local fixedText = api.gui.comp.TextView.new(
                    "  NRA : 0  |  NRO : 0"
                )
                fixedText:setId("telecom_fixed_text")
                outerLayout:addItem(fixedText)

                local sep2 = api.gui.comp.TextView.new("────────────────────────────────")
                outerLayout:addItem(sep2)

                -- Section Infrastructure Mobile
                local secMobile = api.gui.comp.TextView.new("[ Infrastructure Mobile ]")
                outerLayout:addItem(secMobile)

                local mobileText = api.gui.comp.TextView.new(
                    "  Antennes : 0\n" ..
                    "  Technologies : aucune"
                )
                mobileText:setId("telecom_mobile_text")
                outerLayout:addItem(mobileText)

                local sep3 = api.gui.comp.TextView.new("────────────────────────────────")
                outerLayout:addItem(sep3)

                -- Section Couverture
                local secCov = api.gui.comp.TextView.new("[ Couverture ]")
                outerLayout:addItem(secCov)

                local covText = api.gui.comp.TextView.new(
                    "  Villes couvertes : 0 / 0\n" ..
                    "  Taux             : 0%"
                )
                covText:setId("telecom_cov_text")
                outerLayout:addItem(covText)

                local sep4 = api.gui.comp.TextView.new("────────────────────────────────")
                outerLayout:addItem(sep4)

                -- Section Bonus
                local secBonus = api.gui.comp.TextView.new("[ Effet sur la croissance ]")
                outerLayout:addItem(secBonus)

                local bonusText = api.gui.comp.TextView.new(
                    "  Bonus actuel : +0%\n" ..
                    "  Intervalle   : 60 ticks (defaut)"
                )
                bonusText:setId("telecom_bonus_text")
                outerLayout:addItem(bonusText)

                -- Pied de fenêtre
                local sep5 = api.gui.comp.TextView.new("────────────────────────────────")
                outerLayout:addItem(sep5)

                local footer = api.gui.comp.TextView.new(
                    "Placez NRA/NRO/Antennes pres\n" ..
                    "de vos villes pour les connecter."
                )
                outerLayout:addItem(footer)

                -- ----------------------------------------------------------------
                -- FENETRE PRINCIPALE
                -- ----------------------------------------------------------------
                local window = api.gui.comp.Window.new("Telecom - Reseaux", outerLayout)
                window:setId("telecom_status_window")

                if window.addHideOnCloseHandler then
                    window:addHideOnCloseHandler()
                end
                if api.gui.util and api.gui.util.Size then
                    window:setSize(api.gui.util.Size.new(520, 580))
                end

                window:setVisible(true, false)
                print("[Telecom] Fenetre principale creee et visible")

                -- ----------------------------------------------------------------
                -- BOUTON TOGGLE
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

                local injected = false
                pcall(function()
                    local gi = api.gui.util.getById("gameInfo")
                    if gi then
                        local lay = gi:getLayout()
                        if lay then
                            local ok2 = pcall(function() lay:addItem(toggleBtn) end)
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

                local fixedText  = api.gui.util.getById("telecom_fixed_text")
                local mobileText = api.gui.util.getById("telecom_mobile_text")
                local covText    = api.gui.util.getById("telecom_cov_text")
                local bonusText  = api.gui.util.getById("telecom_bonus_text")
                if not fixedText and not mobileText and not covText and not bonusText then return end

                -- ============================================================
                -- 1. SCAN DES CONSTRUCTIONS TELECOM (UI Thread)
                -- ============================================================
                local nraCount  = 0
                local nroCount  = 0
                local antCount  = 0
                local techCounts = {}  -- tech name -> count
                local nodes = {}       -- { x, y, r } pour calcul couverture

                pcall(function()
                    local ids = game.interface.getEntities({pos={0,0}, radius=999999}, {type="CONSTRUCTION"}) or {}
                    for _, eid in ipairs(ids) do
                        pcall(function()
                            local e = game.interface.getEntity(eid)
                            if e and e.fileName then
                                local fn = e.fileName

                                if fn:find("telecom/nra") then
                                    nraCount = nraCount + 1
                                    local p = e.position
                                    if p then
                                        table.insert(nodes, {
                                            x = p.x or p[1] or 0,
                                            y = p.y or p[2] or 0,
                                            r = 1500,
                                        })
                                    end

                                elseif fn:find("telecom/nro") then
                                    nroCount = nroCount + 1
                                    local p = e.position
                                    if p then
                                        table.insert(nodes, {
                                            x = p.x or p[1] or 0,
                                            y = p.y or p[2] or 0,
                                            r = 3000,
                                        })
                                    end

                                elseif fn:find("telecom/antenna") then
                                    antCount = antCount + 1
                                    local p = e.position
                                    local px = p and (p.x or p[1] or 0) or 0
                                    local py = p and (p.y or p[2] or 0) or 0

                                    -- Lire les params : indices 1-7 pour les 7 technologies
                                    for techIdx, tech in ipairs(ANTENNA_TECHS) do
                                        pcall(function()
                                            if e.params and e.params[techIdx] and e.params[techIdx] == 1 then
                                                techCounts[tech.name] = (techCounts[tech.name] or 0) + 1
                                                if p then
                                                    table.insert(nodes, {
                                                        x = px, y = py,
                                                        r = tech.radius,
                                                    })
                                                end
                                            end
                                        end)
                                    end
                                end
                            end
                        end)
                    end
                end)

                -- ============================================================
                -- 2. SCAN DES VILLES ET CALCUL COUVERTURE (UI Thread)
                -- ============================================================
                local townCount    = 0
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
                                for _, n in ipairs(nodes) do
                                    local dx = tx - n.x
                                    local dy = ty - n.y
                                    if (dx*dx + dy*dy) <= (n.r * n.r) then
                                        coveredTowns = coveredTowns + 1
                                        break
                                    end
                                end
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
                -- AFFICHAGE
                -- ============================================================
                if fixedText then
                    fixedText:setText(
                        "  NRA : " .. nraCount .. "  |  NRO : " .. nroCount
                    )
                end

                if mobileText then
                    -- Construire la liste des technologies actives
                    local techList = ""
                    for _, tech in ipairs(ANTENNA_TECHS) do
                        local cnt = techCounts[tech.name] or 0
                        if cnt > 0 then
                            if techList ~= "" then techList = techList .. ", " end
                            techList = techList .. tech.name .. " (x" .. cnt .. ")"
                        end
                    end
                    if techList == "" then techList = "aucune" end

                    mobileText:setText(
                        "  Antennes : " .. antCount .. "\n" ..
                        "  Technologies : " .. techList
                    )
                end

                if covText then
                    covText:setText(
                        "  Villes couvertes : " .. coveredTowns .. " / " .. townCount .. "\n" ..
                        "  Taux             : " .. coverPct .. "%"
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
