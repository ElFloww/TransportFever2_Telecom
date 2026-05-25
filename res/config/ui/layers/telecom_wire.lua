-- =============================================================================
-- telecom_wire.lua  —  Calque visuel : couverture filaire
-- Affiché dans le menu Carte sous "Couverture télécom filaire"
-- =============================================================================
--
-- Ce calque utilise l'API gui de TF2 pour dessiner des cercles semi-transparents
-- autour de chaque nœud WIRE actif (fixe 1850 et fibre 2020).
-- La couleur varie selon l'époque :
--   1850 → bleu acier (#4488BB, opacité 0.35)
--   2020 → cyan électrique (#00CCEE, opacité 0.45)
-- =============================================================================

local WIRE_COLOR_1850 = { r = 0.27, g = 0.53, b = 0.73, a = 0.35 }
local WIRE_COLOR_2020 = { r = 0.00, g = 0.80, b = 0.93, a = 0.45 }

function data()
    return {
        -- Icône affichée dans le menu Carte (utilise une icône existante du jeu)
        -- Remplacez par une icône custom si vous en créez une.
        icon    = "ui/icons/map-layer-pollution.tga",
        tooltip = _("TELECOM_WIRE"),

        -- update() est appelé par le moteur à chaque frame où le calque est actif.
        update = function()
            -- Récupérer les constructions télécoms filaires
            local ok, entities = pcall(function()
                return api.engine.getEntitiesOfType(api.type.EntityType.CONSTRUCTION)
            end)
            if not ok or not entities then return end

            for _, id in ipairs(entities) do
                local con = api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
                if con and con.fileName then
                    local epoch, radius

                    if con.fileName:find("fixed_line_1850") then
                        epoch  = 1850
                        radius = 300 -- rayon par défaut (sera affiné avec les params)
                    elseif con.fileName:find("fiber_2020") then
                        epoch  = 2020
                        radius = 600
                    end

                    if epoch then
                        -- Récupérer la position du nœud
                        local tf = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
                        if tf and tf.transf then
                            local x = tf.transf[13] or 0
                            local y = tf.transf[14] or 0

                            -- Lire le rayon réel depuis les paramètres de construction
                            if con.params and con.params[1] then
                                local idx = con.params[1]
                                if epoch == 1850 then
                                    local radii = { 100, 200, 300, 400, 500 }
                                    radius = radii[idx + 1] or radius
                                else
                                    local radii = { 300, 450, 600, 900, 1200 }
                                    radius = radii[idx + 1] or radius
                                end
                            end

                            -- Dessiner le cercle de couverture sur la carte
                            -- api.gui.mapView n'est pas exposé dans toutes les versions de TF2.
                            -- On utilise addMapCircle si disponible, sinon aucune erreur.
                            local color = (epoch == 1850) and WIRE_COLOR_1850 or WIRE_COLOR_2020
                            if api.gui and api.gui.mapView and api.gui.mapView.addCircle then
                                api.gui.mapView.addCircle({
                                    x      = x,
                                    y      = y,
                                    radius = radius,
                                    color  = color,
                                    filled = true,
                                })
                            elseif api.gui and api.gui.mapView and api.gui.mapView.addDrawCircle then
                                -- Variante selon version TF2
                                api.gui.mapView.addDrawCircle(x, y, radius,
                                    color.r, color.g, color.b, color.a)
                            end
                            -- Note : si aucune des deux méthodes n'est disponible,
                            -- le calque reste vide mais ne génère pas d'erreur.
                        end
                    end
                end
            end
        end,
    }
end