# Reseaux de Communication (Transport Fever 2)

Mod telecom avec NRA, NRO et antennes multi-technologies, plus export de couverture en carte HTML autonome.

## Utilisation

1. Activer le mod dans la sauvegarde.
2. Placer les infrastructures via **Construction > Divers/Misc**.
3. Ouvrir le bouton **Telecom** dans la barre du jeu.
4. Cliquer **Exporter HTML** puis ouvrir le fichier genere.

Le fichier est ecrit dans `map_exports/` a la racine du mod (`telecom_map_*.html`).

## Infrastructures

| Element | Portee | Bonus |
|---|---:|---:|
| NRA (cuivre, 1974+) | 1500 m | +3 % |
| NRO (fibre, 2007+) | 3000 m | +8 % |
| Antenne (1992+) | selon techno | selon techno |

Technologies antenne:

| Technologie | Annee | Portee | Bonus |
|---|---:|---:|---:|
| 2G | 1992 | 2000 m | +2 % |
| 3G | 2004 | 1500 m | +3 % |
| 3G+ | 2006 | 1500 m | +4 % |
| 4G | 2012 | 1200 m | +5 % |
| 4G+ | 2014 | 1200 m | +6 % |
| 5G | 2020 | 800 m | +8 % |
| 5G+ | 2023 | 500 m | +10 % |

## Calcul de couverture

- meilleure contribution fixe retenue par ville
- contributions mobiles additionnees
- synergie x1.2 si fixe + mobile
- moyenne globale plafonnee a +60 %
- application historique conservee:
  `game.config.townDevelopInterval = floor(60 * (1 - bonusGlobal))`

La couverture reste theorique (disques 2D), sans propagation radio avancee ni obstacle batiment par batiment.

## Export HTML

Carte autonome (sans CDN, sans requetes reseau) avec:

- relief/eau embarques (BMP base64)
- routes/rails en courbes vectorielles
- marqueurs et zones de couverture
- filtres, selection, zoom et deplacement

L'export est un instantane: refaire un export apres modification de la partie.

## Compatibilite et migration

- l'ancien apercu natif et ses caches ont ete retires
- les anciens snapshots UI obsoletes sont ignores au chargement
- les donnees telecom utiles sont recalculees automatiquement par le moteur

## Fichiers principaux

| Fichier | Role |
|---|---|
| `res/config/game_script/telecom_growth.lua` | cycle moteur/GUI, sauvegarde, rafraichissement |
| `res/scripts/telecom_network.lua` | collecte et calcul de couverture |
| `res/scripts/telecom_panel.lua` | panneau d'export dans le jeu |
| `res/scripts/telecom_export.lua` | export progressif, fichiers, erreurs IO |
| `res/scripts/telecom_export_view.lua` | rendu HTML/SVG de la carte |
| `strings.lua` | localisations FR/EN |

## Tests

```sh
lua tests/telecom_network_test.lua
lua tests/telecom_export_test.lua
lua tests/telecom_export_view_test.lua
```

Test navigateur (optionnel):

```sh
node --experimental-websocket tests/telecom_export_browser_test.mjs /chemin/vers/telecom-export-test.html
```

## Credits

- Concept: @elfloww
- Base d'impl. initiale: Antigravity / Google DeepMind
- Inspiration export autonome: Cartograph / Tpf2MapExporter (Aadit Jha, MIT)
