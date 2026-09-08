-- Matériau de sol : couverture réseau mobile (vert)
-- Utilisé par groundFaces dans les constructions télécom mobiles (1990, 2030)

function data()
    return {
        -- Référence un matériau terrain vanilla avec teinte personnalisée
        -- Le moteur TF2 applique cette texture au polygone groundFaces
        name = "Telecom Mobile Coverage",
        textures = {
            -- On réutilise la texture gravel vanilla comme base
            map_albedo_opacity = "res/textures/terrain/gravel_albedo.tga",
        },
        -- Couleur de teinte appliquée : vert semi-transparent
        color = { 0.2, 0.9, 0.3, 0.25 },  -- RGBA
    }
end
