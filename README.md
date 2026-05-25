# Réseaux de Communication — v0.2

Mod pour **Transport Fever 2** qui ajoute des infrastructures télécoms historiques
permettant d'augmenter la croissance des villes connectées.

---

## Fonctionnalités

### 4 constructions télécoms

| Construction | Disponible | Type | Rayon | Bonus croissance |
|---|---|---|---|---|
| Poteau téléphonique | 1850 | Filaire | 100–500 m | +5% |
| Antenne mobile 2G | 1990 | Mobile | 400–1000 m | +10% |
| Nœud fibre optique | 2020 | Filaire | 300–1200 m | +20% |
| Antenne 5G | 2030 | Mobile | 800–2000 m | +15% |

### Système de bonus

- Le bonus de chaque ville dépend de **la meilleure infrastructure** qui la couvre
  (la fibre 2020 remplace le bonus du filaire 1850 si les deux coexistent)
- **Bonus synergie** : +20% supplémentaire si une ville est couverte à la fois
  en filaire ET en mobile
- **Bonus global** = moyenne pondérée sur toutes les villes × ratio de couverture
- **Plafond** : +60% maximum au-dessus du facteur de base

### Calques visuels

Deux calques disponibles dans le menu Carte :
- 🔵 **Couverture filaire** — cercles bleus/cyan autour des nœuds filaires
- 🟢 **Couverture mobile** — cercles verts/oranges autour des antennes

---

## Installation

1. Copiez le dossier du mod dans :
   - **Mac** : `~/Library/Application Support/Transport Fever 2/mods/`
   - **Windows** : `%APPDATA%\Transport Fever 2\mods\`
2. Activez le mod depuis le menu principal → Mods
3. Lancez une nouvelle partie (ou une sauvegarde existante)

---

## Utilisation

1. Ouvrez l'onglet **Construction** → **Divers/Misc**
2. Placez les nœuds télécoms autour de vos villes
3. Activez les calques depuis l'icône Carte pour visualiser la couverture
4. Les villes couvertes verront leur croissance augmenter au bout de ~60 secondes jeu

### Conseils d'équilibrage

- En zones denses : placez plusieurs nœuds rapprochés avec un petit rayon
- En zones rurales : un seul nœud avec rayon maximum suffit
- Combinez toujours filaire + mobile pour le bonus de synergie
- La fibre 2020 + 5G 2030 = combo optimal

---

## Compatibilité

- Compatible avec la majorité des mods qui ne modifient pas `game.config.townGrowthFactor`
- Si vous utilisez un mod de croissance personnalisée (ex. Natural Town Growth) :
  désactivez l'un des deux, ou ajustez manuellement `BASE_GROWTH` dans `telecom_growth.lua`

---

## Personnalisation

Modifiez les valeurs dans `res/config/game_script/telecom_growth.lua` :

```lua
local TICK_INTERVAL = 60   -- fréquence de recalcul (secondes jeu)
local BASE_GROWTH   = 1.0  -- facteur de croissance de base TF2
local MAX_BONUS     = 0.60 -- bonus maximum cumulé (+60%)
local SYNERGY_MULT  = 1.2  -- multiplicateur synergie filaire+mobile

local WIRE_BONUS = {
    [1850] = 0.05,  -- +5%
    [2020] = 0.20,  -- +20%
}
local MOBILE_BONUS = {
    [1990] = 0.10,  -- +10%
    [2030] = 0.15,  -- +15%
}
```

---

## Structure du projet

```
com.elfloww.telecom_networks/
├── mod.lua                           ← Point d'entrée & enregistrement
├── strings.lua                       ← Localisation FR/EN
└── res/
    ├── config/
    │   ├── game_script/
    │   │   └── telecom_growth.lua    ← Moteur de couverture & bonus
    │   └── ui/
    │       └── layers/
    │           ├── telecom_wire.lua  ← Calque filaire
    │           └── telecom_mobile.lua ← Calque mobile
    ├── construction/
    │   └── telecom/
    │       ├── fixed_line_1850.con
    │       ├── mobile_1990.con
    │       ├── fiber_2020.con
    │       └── mobile_2030.con
    └── models/
        └── model/
            └── telecom/
                ├── pole.mdl          ← À remplacer par asset 3D custom
                ├── tower.mdl         ← À remplacer par asset 3D custom
                └── cabinet.mdl       ← À remplacer par asset 3D custom
```

---

## ⚠️ Note sur les modèles 3D

Les fichiers `.mdl` actuels sont des **placeholders structurels** sans géométrie réelle.
Pour avoir des modèles visibles en jeu, vous avez deux options :

**Option A** — Réutiliser des modèles vanilla TF2 :
- Trouver les chemins dans `[installation TF2]/res/models/model/`
- Remplacer le contenu des `.mdl` par un fichier qui pointe vers un mesh existant

**Option B** — Créer des assets custom :
- Créer des meshes dans Blender
- Les exporter avec le ModelEditor TF2
- Placer les `.msh` dans `res/models/mesh/telecom/`
- Mettre à jour les `.mdl` en conséquence

---

## Backlog / idées futures

- [ ] Assets 3D custom (poteau bois 1850, pylône GSM 1990, coffret fibre 2020, antenne 5G 2030)
- [ ] Coût d'entretien mensuel dynamique
- [ ] Infobulle par ville avec % de couverture
- [ ] Événements : pannes temporaires de couverture
- [ ] Tech tree léger pour débloquer les époques

---

## Crédits

- Concept & design : @elfloww
- Code v0.2 : implémentation complète avec IA (Antigravity / Google DeepMind)