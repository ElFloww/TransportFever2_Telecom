-- =============================================================================
-- mod.lua  —  Point d'entrée du mod Réseaux de Communication
-- Mod : com.elfloww.telecom_networks  |  Auteur : elfloww
-- =============================================================================

function data()
    return {
        info = {
            name        = _("Reseaux de communication"),
            description = _([[Ajoute des infrastructures telecoms realistes qui augmentent la croissance de vos villes :

Infrastructure fixe :
  NRA (1974) — Central telephonique cuivre, portee 1500 m (+3%)
  NRO (2007) — Noeud fibre optique FTTH, portee 3000 m (+8%)

Infrastructure mobile :
  Antenne telecom (1992+) — Multi-technologies configurables :
    2G (1992, 2000 m), 3G (2004, 1500 m), 3G+ (2006, 1500 m),
    4G (2012, 1200 m), 4G+ (2014, 1200 m), 5G (2020, 800 m),
    5G+ (2023, 500 m)

Bonus synergie x1.2 si couverture fixe + mobile.
Bonus cumulatif plafonne a +60%.
Carte de couverture HTML : bouton Telecom > Exporter HTML.
Ouvrez le fichier dans un navigateur : marqueurs, filtres, zoom et selection.
Placez les noeuds depuis Construction > Divers.]]),
            minorVersion  = 4,
            severityAdd   = "NONE",
            severityRemove = "NONE",
            authors       = { "elfloww" },
            tags          = { "gameplay", "city growth", "infrastructure", "telecom" },
            tfnetId       = "com.elfloww.telecom_networks",
        },

    }
end
