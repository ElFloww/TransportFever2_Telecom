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

        -- runFn : appelé au démarrage de la partie, avant le chargement des entités.
        -- On configure ici les paramètres globaux du jeu.
        runFn = function(settings)
            -- Enregistrement du game_script qui gère le bonus de croissance.
            -- Le moteur TF2 va automatiquement charger telecom_growth.lua
            -- depuis res/config/game_script/ grâce à ce chemin.
            if api and api.res and api.res.gameScriptRep then
                api.res.gameScriptRep.add("res/config/game_script/telecom_growth.lua")
            end

            -- Valeur de base du facteur de croissance (sera ajustée dynamiquement
            -- par telecom_growth.lua selon la couverture télécom).
            -- Ne pas mettre ici de valeur > 1.0 : c'est le game_script qui gère le bonus.
            if game and game.config then
                -- S'assurer que l'intervalle de développement est raisonnable
                -- (valeur par défaut TF2 = 30, on laisse le défaut)
                -- game.config.townDevelopInterval = 30
            end
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