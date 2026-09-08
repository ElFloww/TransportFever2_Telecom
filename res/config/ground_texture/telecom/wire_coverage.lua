-- Matériau de sol : couverture réseau filaire (bleu)
-- Utilisé par groundFaces dans les constructions télécom filaires (1850, 2020)

function data()
    return {
        -- Référence un matériau terrain vanilla avec teinte personnalisée
        -- Le moteur TF2 applique cette texture au polygone groundFaces
        name = "Telecom Wire Coverage",
        textures = {
            -- On réutilise la texture gravel vanilla comme base
            map_albedo_opacity = "res/textures/terrain/gravel_albedo.tga",
        },
        -- Couleur de teinte appliquée : bleu semi-transparent
        color = { 0.2, 0.4, 0.9, 0.25 },  -- RGBA
    }
end
