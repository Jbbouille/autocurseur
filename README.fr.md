# AutoCurseur

[![CI](https://github.com/Jbbouille/autocurseur/actions/workflows/ci.yml/badge.svg)](https://github.com/Jbbouille/autocurseur/actions/workflows/ci.yml)

[English](README.md) · **Français**

Petit utilitaire Windows écrit en Zig : le curseur devient **noir sur fond clair** et **blanc sur fond sombre**, en entier. Quand on secoue la souris, il grossit et devient rouge pour qu'on le retrouve.

Code natif, environ 80 Ko, aucune allocation dynamique, environ 0,2 % d'un cœur de processeur.

## Pourquoi

Windows propose un pointeur « inversé », mais il inverse chaque pixel séparément. Sur un fond coloré, le curseur prend des couleurs étranges. Dans Chrome ou Edge avec l'accélération graphique, il reste parfois blanc sur une page blanche, parce que l'inversion est calculée sur une couche de l'écran qui n'est pas la page.

AutoCurseur utilise des curseurs opaques, vraiment noirs ou vraiment blancs. Il choisit lequel afficher en regardant ce qu'il y a sous la souris.

## Utilisation

Téléchargez `AutoCurseur.exe` dans les [releases](https://github.com/Jbbouille/autocurseur/releases) (ou compilez-le, voir plus bas) et lancez-le. L'exe n'est pas signé : la première fois, Windows SmartScreen peut afficher un avertissement. Cliquez sur *Informations complémentaires*, puis *Exécuter quand même*.

Une icône ronde mi-noire mi-blanche apparaît dans la zone de notification :

- **clic droit** :
  - *Actif* ;
  - *Vérifications par seconde (souris en mouvement)* : 3, 5, 10 (par défaut) ou 20 ;
  - *Langue* : automatique (celle de Windows), English ou Français ;
  - *Secouer pour retrouver le curseur (agrandi, en rouge)* : actif par défaut ;
  - *Lancer au démarrage de Windows* ;
  - *Quitter* ;
- **double-clic** : pause ou reprise.

Le registre ne sert qu'à vos réglages : l'option de démarrage, et les choix faits dans le menu (`HKCU\Software\AutoCurseur`, créé seulement si vous en changez un). En pause ou à la fermeture, Windows recharge vos curseurs habituels. Aucun droit administrateur n'est nécessaire et il n'y a rien à installer : les formes viennent du jeu « Windows Black » fourni avec Windows.

**Ce n'est pas un service Windows**, mais un petit programme de votre session, comme une icône de la barre des tâches. Il n'agit que tant qu'il tourne :

- **pour l'arrêter** : clic droit sur l'icône, puis *Quitter*. Vos curseurs habituels reviennent aussitôt ;
- **pour qu'il démarre tout seul** : cochez *Lancer au démarrage de Windows*. Il sera lancé à chaque ouverture de session ;
- **s'il est arrêté de force** (Gestionnaire des tâches) : les derniers curseurs noirs ou blancs restent en place jusqu'à la prochaine ouverture de session ou au prochain lancement d'AutoCurseur, qui remet d'abord ceux de Windows.

Un service ne conviendrait pas : il tourne en dehors de votre session et ne peut ni voir votre écran ni changer votre curseur.

## Comment la couleur est choisie

1. L'outil lit la position de la souris, ce qui ne coûte presque rien : 10 fois par seconde par défaut, ou 3, 5 ou 20 fois selon le réglage du menu. Quand elle est immobile depuis 1 s, il ne vérifie plus que toutes les 250 ms (toutes les 333 ms au réglage 3).
2. Il copie un carré de l'écran qui couvre le corps du curseur. Le carré fait les trois quarts de la taille du curseur, soit 48 px pour un curseur de 64 px. Il commence un peu au-dessus et à gauche de la pointe et s'étend surtout vers le bas à droite.
3. Il calcule la **luminance moyenne** du carré, de 0 à 255, en pondérant comme l'œil : 30 % rouge, 59 % vert, 11 % bleu.
4. Il décide avec une **hystérésis** :
   - à partir de 150, le curseur passe en noir ;
   - à 105 ou moins, il passe en blanc ;
   - entre les deux, il ne change pas. Cela évite le clignotement sur les gris moyens et le long d'une frontière.

**Avec du texte dessous**, c'est le fond qui décide, pas la lettre survolée. Les tests le vérifient sur des images dessinées en mémoire :

| Contenu | Luminance lue | Curseur |
|---|---|---|
| Texte noir sur page blanche | 181 à 255 | noir partout, aucune bascule |
| Très gros titre en gras | 139 à 255 | noir partout, grâce à l'hystérésis |
| Éditeur de code sombre | 30 à 50 | blanc partout |
| Damier fin noir/blanc, gris moyen | environ 128 | ne change jamais |

Chaque curseur a un contour de la couleur opposée, il reste donc visible même posé sur une lettre.

La **taille** des curseurs est celle de la flèche que Windows affiche à ce moment-là. À 250 % d'affichage, Windows utilise 64 px, et non 32 × 2,5 = 80.

## Secouer pour retrouver le curseur

Comme sur macOS, un va-et-vient rapide de la souris rend le curseur deux fois plus grand et rouge, avec un contour blanc. Il redevient normal 0,6 s après la fin de la secousse.

- **Détection** : seulement pendant que la souris bouge, sa position est lue environ toutes les 30 ms. Il faut 4 demi-tours rapides en moins d'une seconde, chaque aller faisant au moins deux fois la taille du curseur (128 px à 250 %), à l'horizontale ou à la verticale. Viser une cible et corriger un dépassement, sélectionner du texte ou aller et venir lentement ne déclenche rien.
- **Forme** : les curseurs rouges sont fabriqués à partir du jeu noir chargé en taille double (64 → 128 px à 250 %). Cette taille existe dans les fichiers de Windows, le contour reste donc net.
- **Coût** : environ 4 ns de calcul par lecture de position. Les 17 curseurs rouges sont préparés une fois (environ 9 ms). Ils ne sont pas chargés du tout quand l'option est désactivée.

## Consommation

Mesures faites par les tests de performance et les tests système, sur un PC portable avec un écran à 250 % :

| | |
|---|---|
| Exécutable | environ 80 Ko en ReleaseFast (environ 65 Ko avec `-Doptimize=small`) |
| Mémoire privée | environ 1,9 Mo |
| Processeur, souris immobile | environ 0,15 % d'un cœur |
| Processeur, souris en mouvement | environ 0,1 % (3/s), 0,2 % (5/s), 0,3 % (10/s), 0,7 % (20/s) d'un cœur |
| Une lecture d'écran | environ 0,3 ms de processeur |
| Bascule noir ↔ blanc des 17 curseurs | environ 1,3 ms |
| 1,5 s de secousse (lectures d'écran comprises) | environ 16 ms de processeur |

**Aucune allocation dynamique** : tous les tampons sont des tableaux globaux de taille fixe, environ 330 Ko, prévus pour des curseurs jusqu'à 256 px. Un test refuse toute trace d'allocateur dans le code de l'application. Seuls les objets Windows (curseurs, bitmaps, fenêtre, icône) sont créés par le système.

## Compiler

Il faut [Zig](https://ziglang.org) 0.17.

```powershell
zig build
```

L'exécutable est produit dans `zig-out\bin\AutoCurseur.exe`, compilé en **ReleaseFast**. Pour un exe plus petit, utilisez `zig build -Doptimize=small`. Pour l'option « Lancer au démarrage », lancez-le depuis l'endroit où il restera, car c'est ce chemin qui est enregistré.

## Tests

```powershell
zig build test
```

Cette commande lance 107 tests, sans toucher au curseur de votre session :

- **unitaires** (`src/*.zig`) : décision et hystérésis, luminance, inversion des pixels couleur et monochromes, teinte rouge, détection de secousse (vraies secousses, corrections de visée, va-et-vient lents, passage par zéro du compteur de millisecondes), géométrie de la zone lue, tailles, rythme de la minuterie (budgets de lectures par seconde), textes dans les deux langues, identifiants du menu, icône, absence d'allocation et budget de mémoire statique ;
- **intégration** (`tests/integration.zig`) :
  - les 17 vrais fichiers de curseurs de Windows, à 7 tailles ;
  - inversion exacte et réversible, point chaud conservé ;
  - jeu rouge : chaque curseur deux fois plus grand, la flèche identique à la noire avec seulement ses pixels noirs passés en rouge, contour sans trou ;
  - aucun objet Windows perdu après 20 rechargements ;
  - texte et thèmes dessinés en mémoire ;
  - frontière parcourue pixel par pixel, damier, couleurs vives ;
- **performance** (`tests/perf.zig`, compilés dans le même mode que l'exe publié, ReleaseFast par défaut) : chaque mesure est affichée et comparée à un seuil environ 10 fois plus large que la valeur mesurée.

```powershell
zig build test-system
```

Ces 10 tests système changent réellement le curseur pendant une trentaine de secondes, déplacent la souris, puis remettent tout en place. Quittez AutoCurseur avant de les lancer. Ils vérifient :

- l'application puis la restauration des curseurs, et leur taille ;
- des curseurs d'une autre taille laissés par un ancien lancement, qui ne doivent pas être repris ;
- les réglages « vérifications par seconde », « langue » et « secouer » envoyés par le menu, puis mémorisés ; vos réglages du registre sont remis ensuite ;
- 200 bascules successives ;
- une vraie secousse de la souris : la flèche affichée devient la rouge en taille double, puis redevient normale ; un simple balayage de l'écran ne déclenche rien, une secousse avec l'option désactivée non plus ;
- le vrai exécutable : consommation sur 10 s, mémoire, instance unique, fermeture propre et retour du curseur d'origine.

## Intégration continue

À chaque push et pull request, [GitHub Actions](.github/workflows/ci.yml) installe Zig sur une machine Windows. Il lance `zig build test` et `zig build test-system`, compile l'exe en ReleaseFast et le met à disposition comme artefact.

Pour publier une version, poussez un tag `v*` (par exemple `git tag v0.1.0` puis `git push origin v0.1.0`). Une fois les tests passés, la pipeline crée la release GitHub avec l'exe testé.

## Structure

```
src/core.zig      logique pure, sans Windows (décision, luminance, inversion, teinte rouge, secousse, minuterie)
src/cursors.zig   chargement et fabrication des jeux noir, blanc et rouge, application au système
src/sampler.zig   lecture de l'écran sous la souris
src/icon.zig      icône de la zone de notification
src/i18n.zig      textes du menu en anglais et en français
src/settings.zig  réglages mémorisés (HKCU\Software\AutoCurseur)
src/main.zig      fenêtre cachée, menu, minuteries : relie le tout
src/win32.zig     déclarations de l'API Windows utilisées
src/lib.zig       point d'entrée des tests unitaires
tests/            intégration, performance, système
```

## Réglages

| Où | Nom | Défaut | Rôle |
|---|---|---|---|
| `core.zig` | `Thresholds.to_black` | 150 | luminance à partir de laquelle le curseur passe en noir |
| `core.zig` | `Thresholds.to_white` | 105 | luminance en dessous de laquelle il repasse en blanc |
| menu | vérifications par seconde | 10 | 3, 5, 10 ou 20 quand la souris bouge (`core.RATES`) |
| menu | langue | automatique | suit la langue d'affichage de Windows : français pour toute variante du français, anglais sinon |
| menu | secouer pour retrouver | actif | curseur agrandi et rouge quand on secoue la souris |
| `core.zig` | `SHAKE_TURNS`, `SHAKE_WINDOW_MS` | 4, 1000 | demi-tours nécessaires, et la durée dans laquelle ils doivent tenir |
| `core.zig` | `SHAKE_HOLD_MS` | 600 | durée pendant laquelle le curseur reste agrandi après le dernier demi-tour |
| `core.zig` | `STILL_MS` | 1000 | délai sans mouvement avant le mode lent |
| `core.zig` | `IDLE_MS` | 250 | période en mode lent (jamais plus fréquente qu'en mouvement) |
| `core.zig` | `MAX_CUR` | 256 | taille max d'un curseur, qui dimensionne les tampons statiques |

Les choix du menu sont des valeurs `DWORD` dans `HKCU\Software\AutoCurseur` : `LecturesParSeconde`, `Langue` (0 automatique, 1 anglais, 2 français) et `SecouerPourRetrouver` (0 ou 1).

## Limites

- Windows 10 ou 11 uniquement.
- Les curseurs animés (attente) sont remplacés par leur version fixe du jeu « Windows Black ».
- La lecture de l'écran ne voit pas les vidéos protégées (DRM), qui apparaissent noires : le curseur y sera blanc.
- L'exécutable n'est pas signé (voir SmartScreen plus haut).

## Licence

[MIT](LICENSE).

## Alternatives

- Le pointeur « inversé » de Windows (Paramètres → Accessibilité → Pointeur de la souris et interaction tactile) : rien à installer, mais inversion pixel par pixel, avec les défauts décrits plus haut.
- [DynamicCursor](https://github.com/ItsProfessional/DynamicCursor) : script PowerShell, archivé depuis 2023. Il compare 5 pixels sans hystérésis, capture tout l'écran en boucle continue, modifie le registre et demande les droits administrateur.
