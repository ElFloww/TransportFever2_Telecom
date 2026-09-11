# Réseaux de Communication

Mod pour **Transport Fever 2** ajoutant des NRA, NRO et antennes mobiles,
avec une carte graphique de leurs portées et un calcul de bonus de croissance.

## Carte Télécom

Le bouton **Telecom**, dans la barre d'informations du jeu, ouvre la carte.
Elle remplace l'ancien radar textuel. C'est une fenêtre intégrée au jeu,
**pas un nouveau calque du sélecteur natif de Transport Fever 2**.

| Élément | Marqueur | Couverture |
|---|---|---|
| NRA | Carré bleu | Cercle de 1 500 m |
| NRO | Triangle violet | Cercle de 3 000 m |
| Antenne | Rond orange, gris si inactive | Un cercle par technologie active |
| Ville | Croix grise ou verte | Verte si son centre est couvert |

- Coordonnées réelles, limites de la partie et échelle uniforme en mètres.
- Fond simplifié : contours d'altitude, eau échantillonnée, routes et rails.
- Filtres par infrastructure et par technologie mobile, avec légende colorée.
- Boutons **+ / -** pour zoomer, glisser avec le bouton gauche pour déplacer.
- **Carte entière** rétablit la vue générale.
- Clic sur un marqueur ou sélection dans la liste pour afficher les détails.
- **Couverture : sélection** limite les cercles à l'équipement sélectionné.
- **Hachures** matérialise l'intérieur des zones de couverture.
- **Centrer carte** rapproche la vue de l'élément sélectionné ; **Voir en jeu**
  déplace la caméra principale vers cet élément.
- **Actualiser** demande un nouveau calcul et reconstruit le fond géographique.

Une antenne peut proposer plusieurs technologies et plusieurs portées. Les
technologies partageant le même rayon ont des contours superposés : utiliser
leurs filtres pour les distinguer. Désactiver une technologie dans la carte
ne désactive pas l'équipement et ne modifie pas son bonus.

Les croix vertes et les statistiques décrivent **la couverture globale calculée**,
indépendamment des filtres visuels. Le panneau de détails indique les villes
couvertes par chaque service et les contributions reçues par chaque ville.
La liste permet de sélectionner aussi les marqueurs superposés ou hors écran.

### Performances Et Limites

Le fond est calculé progressivement, puis mis en cache. Les constructions et
démolitions invalident ce cache. Un renouvellement toutes les minutes prend aussi
en compte les routes créées automatiquement par les villes. Fermer la fenêtre
suspend le travail graphique. Un index spatial limite le tracé routier à la vue.
Les segments sont regroupés par couleur, avec plusieurs petits renderers plutôt
qu'un unique très gros tampon. Sur une carte dense, le message **Affichage limité**
signale une simplification : zoomer, filtrer ou afficher seulement la sélection.

Le fond est une représentation vectorielle approximative, pas une capture du
terrain. L'eau est déduite du niveau d'eau et d'un échantillonnage de l'altitude ;
les petits cours d'eau peuvent manquer. Les terrassements nécessitent au besoin
**Actualiser**. Une indisponibilité du fond ne supprime pas les données télécom.
Si les dimensions du terrain sont indisponibles, les limites sont estimées à
partir des villes et des disques de portée et signalées comme telles.

**La couverture reste théorique** : disque en deux dimensions, sans obstacles,
relief, capacité, réseau cuivre/fibre physique ni couverture bâtiment par bâtiment.
Une ville est considérée couverte si son point de référence est dans un disque.

## Infrastructures

Constructions disponibles dans **Construction > Divers/Misc** :

| Construction | Année | Portée | Contribution |
|---|---|---|---|
| NRA cuivre | 1974 | 1 500 m | +3 % |
| NRO fibre FTTH | 2007 | 3 000 m | +8 % |
| Antenne multitechnologie | 1992 | Selon technologie | Selon technologie |

| Technologie | Année | Portée | Contribution |
|---|---|---|---|
| 2G | 1992 | 2 000 m | +2 % |
| 3G | 2004 | 1 500 m | +3 % |
| 3G+ | 2006 | 1 500 m | +4 % |
| 4G | 2012 | 1 200 m | +5 % |
| 4G+ | 2014 | 1 200 m | +6 % |
| 5G | 2020 | 800 m | +8 % |
| 5G+ | 2023 | 500 m | +10 % |

Les technologies sont désactivées par défaut. Une technologie configurée avant
son année de disponibilité reste inactive jusqu'à cette année ; son état est
indiqué dans les détails. Une antenne inactive reste visible sur la carte.

## Calcul Et Synchronisation

Pour chaque ville, le calcul conserve la meilleure contribution fixe et
additionne les contributions mobiles, y compris celles d'antennes différentes.
Le cumul est multiplié par 1,2 si fixe et mobile sont présents. La moyenne sur
toutes les villes, couvertes ou non, est plafonnée à 60 %.

Le comportement historique d'application est conservé :
`game.config.townDevelopInterval = floor(60 * (1 - bonusGlobal))`.
Il s'agit d'un réglage **global**, pas d'une modification locale de chaque ville.
Son effet dynamique sur la croissance doit être confirmé en jeu ; la carte
affiche donc un **bonus global calculé**, pas une croissance mesurée.

La simulation produit un snapshot unique avec positions, services, liens de
couverture et statistiques. `save/load` transmet ce snapshot à l'interface et le
conserve dans la sauvegarde. Premier calcul immédiat, puis toutes les cinq
secondes réelles lorsque le moteur exécute les callbacks, ainsi que sur demande.
En pause, une demande peut attendre la reprise du moteur. L'interface ne recalcule
pas une couverture différente et ne modifie pas la simulation.

Une erreur de collecte conserve les dernières données connues, avec un message
explicite ; avant le premier calcul réussi, aucun faux zéro n'est affiché.

## Installation Et Compatibilité

1. Installer le dossier du mod dans le répertoire `mods` de Transport Fever 2.
2. Activer le mod lors de la création ou du chargement d'une partie.
3. Placer des infrastructures et ouvrir **Telecom** dans la barre du jeu.

Les chemins des trois constructions existantes n'ont pas changé. Les
sauvegardes sans snapshot télécom sont initialisées au premier calcul.
Les mods modifiant également `game.config.townDevelopInterval` peuvent entrer
en conflit avec le réglage de croissance conservé par ce mod.

Les `.mdl` restent des **placeholders sans géométrie 3D**. Cette mise à jour
dessine les marqueurs sur la carte mais ne fournit pas de nouveaux modèles
d'antennes ou de bâtiments pour la scène principale.

## Développement

| Fichier | Rôle |
|---|---|
| `res/config/game_script/telecom_growth.lua` | Cycle moteur/GUI, synchronisation et application du bonus |
| `res/scripts/telecom_network.lua` | Catalogue, collecte et calcul pur de la couverture |
| `res/scripts/telecom_map.lua` | Interface, filtres, sélection et tracé vectoriel |
| `res/scripts/telecom_map_geometry.lua` | Projection, découpage des segments et formes |
| `res/scripts/telecom_map_background.lua` | Fond géographique progressif |
| `res/config/style_sheet/telecom.lua` | Styles de la carte |
| `strings.lua` | Traductions françaises et anglaises |

Tests autonomes depuis la racine, avec Lua 5.3 :

```sh
lua tests/telecom_network_test.lua
lua tests/telecom_map_test.lua
```

Les tests vérifient les calculs et utilisent une API simulée pour l'interface.
Ils ne remplacent pas une validation du rendu natif dans Transport Fever 2.
Vérifier en jeu : ouverture/fermeture, échelle UI/Retina, déplacements de fenêtre,
zoom et sélection, construction/démolition, passage d'année, pause/reprise,
sauvegarde/rechargement et grande carte avec de nombreuses infrastructures.
Les diagnostics sont préfixés `[Telecom]` ou `[Telecom map]` dans le journal du jeu.

Références : [API GUI](https://transportfever2.com/wiki/api/modules/api.gui.html),
[terrain](https://transportfever2.com/wiki/api/modules/api.type.html#Terrain),
[synchronisation des scripts](https://wiki.transportfever2.com/doku.php?id=modding:gamescripts).

## Crédits

- Concept et design : @elfloww.
- Implémentation initiale v0.2 : Antigravity / Google DeepMind.
