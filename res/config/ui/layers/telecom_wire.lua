local api = api
function data()
return {
    icon = "ui/icons/map-layer.tga", -- utilisez une icône existante
    tooltip = _("TELECOM_WIRE"),
    update = function()
    -- Collecte des bâtiments de ville et des nœuds filaires
    -- TODO: utiliser les mêmes helpers que le game_script (factoriser dans un module si vous préférez)
    -- Dessin : utilisez game.gui.mapView:addDrawBox(...) OU équivalent selon version
    end
}
end