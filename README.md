```
Réseaux de communication – v0.1 (prototype)


Fonctionnalités
- 4 constructions télécoms : 1850 (filaire), 1990 (mobile), 2020 (fibre), 2030 (mobile moderne)
- Deux calques pour visualiser la couverture (filaire / mobile)
- Croissance des villes boostée selon :
* l’époque
* la part de bâtiments couverts (filaire et/ou mobile)
* la densité (en zone dense, il faut plus d’équipements)


Équilibrage par défaut
- 1850 : +5% *couverture filaire*
- 1990 : +10% *couverture mobile*
- 2020 : +20% *couverture filaire* (bonus x1.3 vs filaire seul)
- 2030 : +15% *couverture mobile* (bonus x1.2 vs 1990)
- Cap global par ville : +60%


Installation
- Placez le dossier `com.yourname.telecom_networks` dans `mods/`
- Activez le mod dans une nouvelle partie (ou sauvegarde)
- Placez des nœuds télécoms via l’onglet "Divers/Misc"
- Activez les calques depuis l’icône de carte


Compatibilité
- Compatible avec la plupart des mods qui n’écrasent pas la logique de croissance par script.
- Si vous utilisez des overhauls de croissance, désactivez leur partie script ou réduisez ce mod à l’affichage (désactiver `telecom_growth.lua`).


Personnalisation
- Ajustez les rayons par défaut dans chaque `.con`
- Ajustez les bonus dans `telecom_growth.lua` (table EPOCH_BONUS)


Crédits
- Idée & design : @VOUS
- Code : starter kit
```


---


## Notes techniques / points d’attention
- **Facteur de croissance** : selon les versions, il peut être nécessaire d’appliquer un multiplicateur via une commande différente (ou de biaiser les facteurs globaux). Les appels `api.cmd.make.setTownGrowthFactor` / `game.interface.getGameYear` sont **exemples** à remplacer par l’API exacte disponible chez vous.
- **Densité** : le calcul est volontairement simple (bâtiments/population). Vous pouvez le raffiner avec les surfaces réelles de ville si exposées par l’API.
- **Performance** : l’évaluation tourne ~toutes les 12 s. Augmentez l’intervalle sur des maps immenses.
- **Overlay** : l’exemple de calque laisse le rendu à compléter (quelques lignes selon votre version) ; il s’intègre au bouton "Carte" comme un layer.


---


## Idées d’amélioration (backlog)
- Débits : simuler une "capacité" par nœud et limiter la couverture maximale par antenne.
- Coût d’entretien mensuel pour chaque type de nœud.
- Événements : pannes/maintenance réduisant temporairement la couverture.
- Recherche/tech tree léger pour débloquer 1990/2020/2030 si vous jouez en sandbox.
- UI : infobulle par ville avec % de couverture filaire/mobile & bonus appliqué.