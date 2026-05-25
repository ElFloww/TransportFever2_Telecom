-- strings.lua  —  Localisations FR / EN du mod Réseaux de Communication

function data()
    return {
        -- Anglais
        en = {
            ["Réseaux de communication"]          = "Telecom Networks",
            ["Poteau téléphonique (1850)"]         = "Telephone Pole (1850)",
            ["Infrastructure filaire de base. Raccorde les habitants au réseau téléphonique et augmente la croissance de la ville."]
                = "Basic wireline infrastructure. Connects residents to the telephone network and boosts city growth.",
            ["Antenne mobile (1990)"]              = "Mobile Antenna (1990)",
            ["Premier réseau télécom mobile (2G). Offre une couverture sans fil et stimule davantage la croissance que le réseau filaire."]
                = "First mobile telecom network (2G). Provides wireless coverage and boosts growth more than the wireline network.",
            ["Nœud fibre optique (2020)"]          = "Fiber Optic Node (2020)",
            ["Infrastructure fibre optique à très haut débit. Améliore fortement la croissance des zones raccordées. Remplace avantageusement le réseau filaire 1850."]
                = "Ultra-high-speed fiber optic infrastructure. Strongly boosts growth in covered areas. Supersedes the 1850 wireline network.",
            ["Antenne 5G (2030)"]                  = "5G Antenna (2030)",
            ["Réseau mobile de nouvelle génération (5G). Offre la plus grande portée et le bonus de croissance mobile le plus élevé. Complémentaire à la fibre optique."]
                = "Next-generation mobile network (5G). Provides the widest range and highest mobile growth bonus. Complements fiber optic.",
            ["Rayon de service (m)"]               = "Service Radius (m)",
            ["Rayon de couverture (m)"]            = "Coverage Radius (m)",
            ["TELECOM_WIRE"]                       = "Wireline coverage",
            ["TELECOM_MOBILE"]                     = "Mobile coverage",
            -- Description du mod
            ["Ajoute des infrastructures télécoms historiques qui augmentent la croissance de vos villes :\n• 1850 — Poteau téléphonique filaire  (+5% croissance)\n• 1990 — Antenne mobile 2G            (+10% croissance)\n• 2020 — Nœud fibre optique           (+20% croissance)\n• 2030 — Antenne 5G                   (+15% croissance mobile)\n\nBonus synergie : +20% si une ville est couverte en filaire ET en mobile.\nBonus cumulatif plafonné à +60%. Deux calques visuels disponibles (filaire / mobile).\nPlacez les nœuds depuis l'onglet Construction → Divers."]
                = "Adds historical telecom infrastructures that boost city growth:\n• 1850 — Telephone pole (wireline)  (+5% growth)\n• 1990 — 2G mobile antenna          (+10% growth)\n• 2020 — Fiber optic node           (+20% growth)\n• 2030 — 5G antenna                 (+15% mobile growth)\n\nSynergy bonus: +20% if a city has both wireline AND mobile coverage.\nCumulative bonus capped at +60%. Two visual map layers available.\nPlace nodes via Construction → Misc tab.",
        },

        -- Français
        fr = {
            ["Réseaux de communication"]          = "Réseaux de communication",
            ["Poteau téléphonique (1850)"]         = "Poteau téléphonique (1850)",
            ["Infrastructure filaire de base. Raccorde les habitants au réseau téléphonique et augmente la croissance de la ville."]
                = "Infrastructure filaire de base. Raccorde les habitants au réseau téléphonique et augmente la croissance de la ville.",
            ["Antenne mobile (1990)"]              = "Antenne mobile (1990)",
            ["Premier réseau télécom mobile (2G). Offre une couverture sans fil et stimule davantage la croissance que le réseau filaire."]
                = "Premier réseau télécom mobile (2G). Offre une couverture sans fil et stimule davantage la croissance que le réseau filaire.",
            ["Nœud fibre optique (2020)"]          = "Nœud fibre optique (2020)",
            ["Infrastructure fibre optique à très haut débit. Améliore fortement la croissance des zones raccordées. Remplace avantageusement le réseau filaire 1850."]
                = "Infrastructure fibre optique à très haut débit. Améliore fortement la croissance des zones raccordées. Remplace avantageusement le réseau filaire 1850.",
            ["Antenne 5G (2030)"]                  = "Antenne 5G (2030)",
            ["Réseau mobile de nouvelle génération (5G). Offre la plus grande portée et le bonus de croissance mobile le plus élevé. Complémentaire à la fibre optique."]
                = "Réseau mobile de nouvelle génération (5G). Offre la plus grande portée et le bonus de croissance mobile le plus élevé. Complémentaire à la fibre optique.",
            ["Rayon de service (m)"]               = "Rayon de service (m)",
            ["Rayon de couverture (m)"]            = "Rayon de couverture (m)",
            ["TELECOM_WIRE"]                       = "Couverture filaire",
            ["TELECOM_MOBILE"]                     = "Couverture mobile",
        },
    }
end