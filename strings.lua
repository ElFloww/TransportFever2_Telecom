-- strings.lua  —  Localisations FR / EN du mod Réseaux de Communication

function data()
    return {
        -- Anglais
        en = {
            ["Reseaux de communication"] = "Telecom Networks",
            ["Telecom - Carte de couverture"] = "Telecom - Coverage Map",
            ["Afficher la carte de couverture telecom"] = "Show telecom coverage map",
            ["Chargement des donnees telecom..."] = "Loading telecom data...",
            ["Selectionnez un equipement ou une ville sur la carte."] = "Select equipment or a town on the map.",
            ["Antennes"] = "Antennas",
            ["Villes"] = "Towns",
            ["Ville"] = "Town",
            ["Noms"] = "Names",
            ["Carte entiere"] = "Fit map",
            ["Couverture : selection"] = "Coverage: selected only",
            ["Hachures"] = "Hatching",
            ["Relief / eau"] = "Terrain / water",
            ["Routes"] = "Roads",
            ["Rails"] = "Tracks",
            ["Actualiser"] = "Refresh",
            ["Voir en jeu"] = "Locate in game",
            ["Centrer carte"] = "Centre map",
            ["Selectionner..."] = "Select...",
            ["Portee theorique, sans relief. Croix verte : centre de ville couvert."] = "Theoretical range, ignoring terrain. Green cross: covered town centre.",
            ["Glisser pour deplacer. Boutons + / - pour zoomer. Cliquer pour selectionner."] = "Drag to pan. Use + / - to zoom. Click to select.",
            ["Camera indisponible (voir journal)"] = "Camera unavailable (see log)",
            ["Carte indisponible (voir journal)"] = "Map unavailable (see log)",
            ["Donnees telecom en attente (voir journal)"] = "Waiting for telecom data (see log)",
            ["Donnees non actualisees (voir journal)"] = "Stale data (see log)",
            ["Contributions : fixe %.0f%% | mobile %.0f%%"] = "Contributions: fixed %.0f%% | mobile %.0f%%",
            ["actif"] = "active",
            ["disponible en %d"] = "available in %d",
            ["desactive"] = "disabled",
            ["Villes : "] = "Towns: ",
            ["aucune"] = "none",
            ["Annee %d | NRA %d | NRO %d | Antennes %d\nVilles couvertes : %d / %d | Bonus global calcule : %.1f%%"] = "Year %d | NRA %d | NRO %d | Antennas %d\nCovered towns: %d / %d | Calculated global bonus: %.1f%%",
            ["Zoom x%.1f | Portee circulaire theorique"] = "Zoom x%.1f | Theoretical circular range",
            ["Preparation du fond de carte..."] = "Preparing map background...",
            ["Fond incomplet (voir journal)"] = "Incomplete background (see log)",
            ["Limites estimees"] = "Estimated map bounds",
            ["Affichage limite : zoomez ou filtrez"] = "Display limit: zoom in or filter",
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
            ["Reseaux de communication"] = "Réseaux de communication",
            ["Telecom - Carte de couverture"] = "Télécom - Carte de couverture",
            ["Afficher la carte de couverture telecom"] = "Afficher la carte de couverture télécom",
            ["Chargement des donnees telecom..."] = "Chargement des données télécom...",
            ["Selectionnez un equipement ou une ville sur la carte."] = "Sélectionnez un équipement ou une ville sur la carte.",
            ["Couverture : selection"] = "Couverture : sélection",
            ["Carte entiere"] = "Carte entière",
            ["Selectionner..."] = "Sélectionner...",
            ["Portee theorique, sans relief. Croix verte : centre de ville couvert."] = "Portée théorique, sans relief. Croix verte : centre de ville couvert.",
            ["Glisser pour deplacer. Boutons + / - pour zoomer. Cliquer pour selectionner."] = "Glisser pour déplacer. Boutons + / - pour zoomer. Cliquer pour sélectionner.",
            ["Camera indisponible (voir journal)"] = "Caméra indisponible (voir journal)",
            ["Donnees telecom en attente (voir journal)"] = "Données télécom en attente (voir journal)",
            ["Donnees non actualisees (voir journal)"] = "Données non actualisées (voir journal)",
            ["desactive"] = "désactivé",
            ["Annee %d | NRA %d | NRO %d | Antennes %d\nVilles couvertes : %d / %d | Bonus global calcule : %.1f%%"] = "Année %d | NRA %d | NRO %d | Antennes %d\nVilles couvertes : %d / %d | Bonus global calculé : %.1f%%",
            ["Zoom x%.1f | Portee circulaire theorique"] = "Zoom x%.1f | Portée circulaire théorique",
            ["Preparation du fond de carte..."] = "Préparation du fond de carte...",
            ["Limites estimees"] = "Limites estimées",
            ["Affichage limite : zoomez ou filtrez"] = "Affichage limité : zoomez ou filtrez",
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
