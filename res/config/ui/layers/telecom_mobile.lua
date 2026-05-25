-- =============================================================================
-- telecom_mobile.lua  —  Calque visuel : couverture mobile
-- Affiché dans le menu Carte sous "Couverture télécom mobile"
-- =============================================================================
--
-- Cercles de couverture autour de chaque nœud MOBILE actif.
-- Couleur selon époque :
--   1990 → vert lime (#66DD44, opacité 0.30)
--   2030 → orange vif (#FF8800, opacité 0.40)
-- =============================================================================

local MOBILE_COLOR_1990 = { r = 0.40, g = 0.87, b = 0.27, a = 0.30 }
local MOBILE_COLOR_2030 = { r = 1.00, g = 0.53, b = 0.00, a = 0.40 }

function data()
    return {
        icon    = "ui/icons/map-layer-pollution.tga",
        tooltip = _("TELECOM_MOBILE"),

        update = function()
            local ok, entities = pcall(function()
                return api.engine.getEntitiesOfType(api.type.EntityType.CONSTRUCTION)
            end)
            if not ok or not entities then return end

            for _, id in ipairs(entities) do
                local con = api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
                if con and con.fileName then
                    local epoch, radius

                    if con.fileName:find("mobile_1990") then
                        epoch  = 1990
                        radius = 600
                    elseif con.fileName:find("mobile_2030") then
                        epoch  = 2030
                        radius = 1200
                    end

                    if epoch then
                        local tf = api.engine.getComponent(id, api.type.ComponentType.TRANSFORM)
                        if tf and tf.transf then
                            local x = tf.transf[13] or 0
                            local y = tf.transf[14] or 0

                            if con.params and con.params[1] then
                                local idx = con.params[1]
                                if epoch == 1990 then
                                    local radii = { 400, 600, 800, 1000 }
                                    radius = radii[idx + 1] or radius
                                else
                                    local radii = { 800, 1200, 1600, 2000 }
                                    radius = radii[idx + 1] or radius
                                end
                            end

                            local color = (epoch == 1990) and MOBILE_COLOR_1990 or MOBILE_COLOR_2030
                            if api.gui and api.gui.mapView and api.gui.mapView.addCircle then
                                api.gui.mapView.addCircle({
                                    x      = x,
                                    y      = y,
                                    radius = radius,
                                    color  = color,
                                    filled = true,
                                })
                            elseif api.gui and api.gui.mapView and api.gui.mapView.addDrawCircle then
                                api.gui.mapView.addDrawCircle(x, y, radius,
                                    color.r, color.g, color.b, color.a)
                            end
                        end
                    end
                end
            end
        end,
    }
end