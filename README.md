# GTA MOD : Foule Throttle

Génère une foule de PNJ et la contrôle entièrement depuis un menu (apparence, quantité, position, animations).

## Fonctionnalités

Menu « Crowd Manager » (touche **F2**) :

- **Appearance** : aléatoire parmi tous les modèles, par catégorie (civils hommes/femmes, services, gangs, uniques, personnages d'histoire, animaux), ou modèle choisi (nom saisi au clavier)
- **Quantity** : nombre de PNJ créés à chaque spawn (1 à 1000)
- **Position** : autour du joueur, du repère placé sur la carte, ou de coordonnées personnalisées
- **Spread radius** : zone dans laquelle les PNJ apparaissent (1 à 10 000 m), avec une densité maximale de 2 PNJ/m² (le spawn est réduit automatiquement si la zone est trop petite pour la quantité demandée)
- **Spawn crowd** : crée la foule avec les réglages ci-dessus
- **Set total count** : ajoute ou retire des PNJ pour atteindre un nombre total donné
- **Delete all** : supprime tous les PNJ créés par le mod

Sous-menu « Control crowd » : fait jouer une animation à toute la foule (acclamer, faire la fête, danser, téléphoner, filmer, fumer, prendre un café, boire, discuter, patienter, etc.), la faire déambuler librement (« Wander »), venir vers le joueur (« Come to me ») ou s'arrêter (« Stop »). On peut changer d'ordre (animation ou comportement) à tout moment, y compris pendant qu'un ordre précédent est encore en train de s'appliquer : le plus récent prend toujours le dessus proprement, sans conflit.

Les PNJ créés sont automatiquement supprimés à l'arrêt de la ressource.

## Prérequis

- Serveur FiveM à jour avec accès admin
- Ressource [MenuV](https://github.com/MenuV/MenuV) installée et démarrée avant ce mod

## Installation

1. Télécharge ce dépôt et renomme le dossier `gtamod-foule-throttle` en `foule_throttle` (ce nom exact est utilisé par le mod `pnj_lab` pour retrouver la foule)
2. Copie le dossier `foule_throttle` dans `resources/`
3. Ajoute `ensure menuv` puis `ensure foule_throttle` dans ton `server.cfg`
4. Redémarre le serveur

## Utilisation

Appuie sur **F2** en jeu pour ouvrir le menu, règle l'apparence, la quantité et la position souhaitées, puis sélectionne « Spawn crowd ».

Les autres ressources peuvent récupérer la liste des PNJ de la foule avec `exports['foule_throttle']:GetCrowd()`.

## Structure du dossier

```
foule_throttle/
├─ client.lua           -- script principal (menu, spawn, contrôle de la foule)
├─ models.lua           -- listes des modèles de PNJ par catégorie
├─ fxmanifest.lua
└─ README.md
```

## Crédits

Tuto et mod réalisés par :
Alice MASSART, PAD EMD 2026.
