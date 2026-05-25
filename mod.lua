-- =============================================================================
-- mod.lua  —  Point d'entrée du mod Réseaux de Communication
-- Mod : com.elfloww.telecom_networks  |  Auteur : elfloww
-- =============================================================================

function data()
    return {
        info = {
            name        = _("Réseaux de communication"),
            description = _([[Ajoute des infrastructures télécoms historiques qui augmentent la croissance de vos villes :
• 1850 — Poteau téléphonique filaire  (+5% croissance)
• 1990 — Antenne mobile 2G            (+10% croissance)
• 2020 — Nœud fibre optique           (+20% croissance)
• 2030 — Antenne 5G                   (+15% croissance mobile)

Bonus synergie : +20% si une ville est couverte en filaire ET en mobile.
Bonus cumulatif plafonné à +60%. Deux calques visuels disponibles (filaire / mobile).
Placez les nœuds depuis l'onglet Construction → Divers.]]),
            minorVersion  = 1,
            severityAdd   = "NONE",
            severityRemove = "NONE",
            authors       = { "elfloww" },
            tags          = { "gameplay", "city growth", "infrastructure" },
            tfnetId       = "com.elfloww.telecom_networks",
        },

        -- runFn : appelé au démarrage de la partie.
        -- Les game_scripts dans res/config/game_script/ sont automatiquement
        -- chargés par TF2 — pas besoin d'enregistrement manuel.
        runFn = function(settings)
        end,

        -- postRunFn : appelé après chargement de tous les mods.
        -- On peut ici injecter des éléments UI ou des overrides de dernier recours.
        postRunFn = function(settings, modParams)
            -- Les calques UI sont déclarés dans res/config/ui/layers/
            -- et seront automatiquement chargés par le jeu si le format est correct.
            -- Aucune action supplémentaire nécessaire ici pour l'instant.
        end,
    }
end