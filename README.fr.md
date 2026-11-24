# AutoCurseur

[![CI](https://github.com/Jbbouille/autocurseur/actions/workflows/ci.yml/badge.svg)](https://github.com/Jbbouille/autocurseur/actions/workflows/ci.yml)

[English](README.md) · **Français**

Petit utilitaire Windows écrit en Zig : le curseur devient **noir sur fond clair** et **blanc sur fond sombre**, en entier. Quand on secoue la souris, il grossit et devient rouge pour qu'on le retrouve.

Code natif, environ 100 Ko, aucune allocation dynamique, environ 0,2 % d'un cœur de processeur.

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

Le registre ne sert qu'à vos réglages : l'option de démarrage, et les choix faits dans le menu (`HKCU\Software\AutoCurseur`, créé seulement si vous en changez un). En pause ou à la fermeture, Windows recharge vos curseurs habituels. Aucun droit administrateur n'est nécessaire et il n'y a rien à installer : les formes viennent des curseurs fournis avec Windows (voir *Style des curseurs* plus bas). AutoCurseur écrit une fois leurs versions noire, blanche et rouge manquantes dans `%LOCALAPPDATA%\AutoCurseur\cursors` (34 fichiers, environ 4 Mo ; voir *Plusieurs écrans* plus bas).

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
5. Il change la couleur **du seul pointeur affiché**. Windows a 17 pointeurs (flèche, sélection de texte, main des liens, flèches de redimensionnement…) ; AutoCurseur retient la couleur de chacun, et Windows le prévient chaque fois que la forme du pointeur change : la nouvelle forme prend aussitôt la bonne couleur (en bien moins d'un centième de seconde). Les vérifications ci-dessus regardent aussi le pointeur affiché, au cas où un avis se perdrait.

**Avec du texte dessous**, c'est le fond qui décide, pas la lettre survolée. Les tests le vérifient sur des images dessinées en mémoire :

| Contenu | Luminance lue | Curseur |
|---|---|---|
| Texte noir sur page blanche | 181 à 255 | noir partout, aucune bascule |
| Très gros titre en gras | 139 à 255 | noir partout, grâce à l'hystérésis |
| Éditeur de code sombre | 30 à 50 | blanc partout |
| Damier fin noir/blanc, gris moyen | environ 128 | ne change jamais |

Chaque curseur a un contour de la couleur opposée, il reste donc visible même posé sur une lettre.

## Style des curseurs

Les curseurs ont la forme des curseurs blancs habituels de Windows (« Windows Aero », aux bords adoucis). En noir, AutoCurseur utilise leur négatif exact : seuls les pixels noirs, blancs et gris sont inversés, le rouge de *indisponible* reste donc rouge. Trois sortes de curseurs gardent les formes du jeu « Windows Black » fourni avec Windows :

- la sélection de texte et la précision : le style blanc n'a pas de fichier pour elles (Windows utilise alors des curseurs qui inversent l'écran, justement ce qu'AutoCurseur évite) ;
- les deux curseurs d'attente, animés dans le style blanc : AutoCurseur les affiche fixes.

La flèche « Windows Black », utilisée jusqu'à la version 0.1.0, avait une queue plus longue et des bords en escalier, et quand elle laissait la place à la sélection de texte, elle laissait une trace visible à l'écran. La flèche du style blanc, en noir, n'en laisse pas.

La **taille** des curseurs est celle de la flèche que Windows affiche à ce moment-là. À 250 % d'affichage, Windows utilise 64 px, et non 32 × 2,5 = 80.

## Plusieurs écrans

Quand deux écrans n'ont pas le même agrandissement (par exemple 150 % et 250 %), Windows veut un curseur d'une taille différente sur chacun (48 et 64 px). Un curseur fabriqué en mémoire n'a qu'une taille : Windows l'étire sur l'autre écran, et le contour devient irrégulier.

AutoCurseur écrit donc ses curseurs dans de vrais fichiers `.cur`, dans `%LOCALAPPDATA%\AutoCurseur\cursors`, en gardant toutes les tailles des fichiers de Windows (32, 48, 64, 96 et 128 px) : le négatif noir des curseurs du style blanc, la version blanche des quatre curseurs « Windows Black », et la version rouge de tous. Les autres versions sont les fichiers de Windows eux-mêmes, utilisés tels quels. Les fichiers laissés par une version précédente sont supprimés quand les nouveaux sont écrits. Windows choisit alors, écran par écran, l'image dessinée à la bonne taille, exactement comme pour ses propres curseurs. Les fichiers ne sont écrits que s'ils manquent ou ne sont plus à jour.

## Pointeur agrandi (Accessibilité)

Quand on agrandit le pointeur dans *Paramètres → Accessibilité → Pointeur de la souris et interaction tactile*, Windows 11 n'utilise plus ses images classiques : il dessine ses curseurs à partir de dessins vectoriels (`C:\Windows\Cursors\*.svg`), une fois en 240 × 240 px, et les réduit à la taille affichée. AutoCurseur fait de même, son pointeur a donc exactement la même forme moderne :

- les 17 dessins sont rendus avec Direct2D en 240 × 240, corps noir et contour blanc, puis retournés (les dessins sont rangés à l'envers) ; les versions blanche et rouge en sont tirées ;
- comparé aux images que Windows produit lui-même (`%LOCALAPPDATA%\Microsoft\Windows\Cursors\*_eoa.cur`) : 8 curseurs sur 17 sont identiques au pixel près, les autres diffèrent de quelques pixels de bord (moins de 0,4 %), et tous les points chauds sont les mêmes ;
- ce travail n'a lieu qu'une fois le pointeur agrandi (environ 0,3 s, une fois par session) ; Direct2D n'est chargé que pour lui et déchargé aussitôt (0,4 Mo gardés) ;
- en taille 1, Windows utilise ses images classiques, AutoCurseur aussi ; sans ces dessins (Windows 10), AutoCurseur garde les images classiques à toutes les tailles.

Quand on fait glisser le curseur « Taille », Windows recharge ses propres curseurs après sa notification, sans en envoyer d'autre. AutoCurseur attend que ça se calme et remet les siens 0,5 s, 1,5 s et 3 s après la dernière notification.

Aux très grandes tailles, le curseur rouge ne double plus au-delà de 255 px à l'écran : au-delà, Windows dessine le pointeur lui-même et charger un jeu rouge lui prend jusqu'à une seconde. Un pointeur déjà énorme devient seulement rouge.

Les très grandes tailles coûtent cher à Windows lui-même. Charger un curseur depuis son fichier lui prend alors environ 5 ms, car il en prépare une version géante (384 px à 150 %, 640 px à 250 %), même pour ses propres curseurs. Recharger les 17 curseurs à chaque changement de couleur coûterait environ 90 ms ; comme AutoCurseur ne recharge que celui qui est affiché (voir *Comment la couleur est choisie*), un changement coûte environ 10 ms (mesuré : 40 changements en 20 s d'allers-retours entre une zone sombre et une zone claire coûtent 0,6 s de processeur au lieu de 3,8 s). Au-delà de 255 px à l'écran, Windows dessine aussi le pointeur lui-même dans l'image de l'écran, et les lectures de l'écran peuvent devenir bien plus lentes (jusqu'à 300 à 500 ms dans certaines de nos mesures, 17 ms dans d'autres). C'est pourquoi AutoCurseur lit l'écran sur un fil à part : son fil principal (menu, minuteries, détection de la secousse, messages de Windows) n'attend jamais une lecture. Le fil de lecture dort tant qu'on ne lui demande rien, et si une lecture est en cours, seule la dernière position demandée est gardée. Il coûte 36 Ko de mémoire et 12 µs par demande (0,012 % d'un cœur à 10 lectures par seconde).

## Secouer pour retrouver le curseur

Comme sur macOS, un va-et-vient rapide de la souris rend le curseur deux fois plus grand et rouge, avec un contour blanc. Il redevient normal 0,6 s après la fin de la secousse.

- **Détection** : seulement pendant que la souris bouge, sa position est lue environ toutes les 30 ms. Il faut deux allers-retours et demi d'affilée (5 demi-tours) en moins d'une seconde, chaque aller faisant au moins trois fois la taille du curseur (144 px pour un curseur de 48), à l'horizontale ou à la verticale ; un aller plus court remet le compte à zéro. Viser une cible et corriger un dépassement, sélectionner du texte, un va-et-vient vif mais court, ou aller et venir lentement ne déclenche rien.
- **Forme** : les curseurs rouges sont fabriqués à partir du jeu noir et affichés en taille double (48 → 96 px à 150 %, 64 → 128 px à 250 %). Ces tailles existent dans les fichiers, le contour reste donc net. Avec un pointeur agrandi, le curseur rouge reste sous 255 px à l'écran (voir plus haut).
- **Coût** : environ 4 ns de calcul par lecture de position. Les fichiers rouges sont écrits une fois (environ 30 µs chacun), et pas du tout quand l'option est désactivée.

## Consommation

Mesures faites par les tests de performance et les tests système, sur un PC portable avec un écran à 250 % :

| | |
|---|---|
| Exécutable | environ 98 Ko en ReleaseFast |
| Mémoire privée | environ 2 Mo |
| Fichiers écrits une fois | 34 curseurs classiques, environ 4 Mo, vérifiés en 13 ms environ au démarrage ; avec un pointeur agrandi, 51 curseurs vectoriels (5 Mo) dessinés en 0,3 s environ |
| Processeur, souris immobile | environ 0,15 % d'un cœur |
| Processeur, souris en mouvement | environ 0,1 % (3/s), 0,2 % (5/s), 0,3 % (10/s), 0,7 % (20/s) d'un cœur |
| Une lecture d'écran | environ 0,3 ms de processeur |
| Changement noir ↔ blanc (seul le pointeur affiché, relu depuis son fichier) | environ 0,8 ms (environ 10 ms avec le plus grand pointeur) |
| Recoloration d'une forme de pointeur qui apparaît (main des liens…) | moins de 1 ms après l'avis de Windows |
| 2 s de secousse (lectures d'écran comprises) | environ 20 à 40 ms de processeur |
| Attente la plus longue d'une réponse d'AutoCurseur pendant que la souris bouge | moins de 16 ms (lectures d'écran sur un fil à part) |

**Aucune allocation dynamique** : tous les tampons sont des tableaux globaux de taille fixe, environ 470 Ko (surtout les tampons de 144 Ko et 236 Ko qui servent à lire et écrire les fichiers de curseurs ; le plus gros fichier écrit, un curseur rouge de 240 × 240, fait 233 Ko). Direct2D, quand il sert, fait ses propres allocations et est déchargé aussitôt. Un test refuse toute trace d'allocateur dans le code de l'application. Seuls les objets Windows (curseurs, bitmaps, fenêtre, icône) sont créés par le système.

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

Cette commande lance 147 tests, sans toucher au curseur de votre session :

- **unitaires** (`src/*.zig`) : décision et hystérésis, luminance, inversion des pixels couleur et monochromes, teinte rouge, détection de secousse (vraies secousses, corrections de visée, va-et-vient vifs mais courts ou lents, aller trop court qui interrompt la série, passage par zéro du compteur de millisecondes), géométrie de la zone lue, tailles, rythme de la minuterie (budgets de lectures par seconde), textes dans les deux langues, identifiants du menu, icône, absence d'allocation et budget de mémoire statique ;
  - fichiers `.cur` (`src/curfile.zig`) : lecture, refus des images PNG, compressées ou tronquées, versions inversée et rouge, double inversion qui redonne l'original, alignement sur 4 octets, tampon trop petit, fichiers d'une seule image 1 bit et 32 bits ;
  - curseurs vectoriels (`src/svgcur.zig`) : remplacement des couleurs, conversion en 1 bit (tout pixel touché est visible), couleurs non prémultipliées, points chauds ;
- **intégration** (`tests/integration.zig`) :
  - les 17 vrais fichiers de curseurs de Windows, à 7 tailles ;
  - inversion exacte et réversible, point chaud conservé ;
  - les fichiers écrits : toutes les tailles de 32 à 128 px gardées, écrits une fois, pas réécrits s'ils sont à jour, réécrits s'ils sont abîmés ;
  - jeu rouge : chaque curseur deux fois plus grand, la flèche identique à la noire avec seulement ses pixels noirs passés en rouge (bords adoucis compris), contour sans trou ;
  - fichiers laissés par une version précédente supprimés quand les nouveaux sont écrits ;
  - aucun objet Windows perdu après 20 rechargements ;
  - reconnaissance du pointeur affiché : chacun des 17 curseurs du système à sa poignée, jamais un curseur chargé par un programme ;
  - le fil de lecture de l'écran : répond à une demande, ne garde que la dernière de 50 demandes d'affilée, s'arrête proprement, lit sur place une fois arrêté ;
  - curseurs vectoriels : les 17 dessinés en 240 px, même forme et mêmes points chauds que les images produites par Windows lui-même, blanc = inverse exact du noir, rouge aux bords adoucis, chargeables à toutes les tailles, pas redessinés s'ils sont à jour, Direct2D déchargé ensuite ;
  - texte et thèmes dessinés en mémoire ;
  - frontière parcourue pixel par pixel, damier, couleurs vives ;
- **performance** (`tests/perf.zig`, compilés dans le même mode que l'exe publié, ReleaseFast par défaut) : chaque mesure est affichée et comparée à un seuil environ 10 fois plus large que la valeur mesurée.

```powershell
zig build test-system
```

Ces 18 tests système changent réellement le curseur pendant une minute environ, déplacent la souris, puis remettent tout en place. Quittez AutoCurseur avant de les lancer (`zig build check-system` les compile sans les lancer). Ils vérifient :

- l'application puis la restauration des curseurs, et leur taille ;
- des curseurs d'une autre taille laissés par un ancien lancement, qui ne doivent pas être repris ;
- les réglages « vérifications par seconde », « langue » et « secouer » envoyés par le menu, puis mémorisés ; vos réglages du registre sont remis ensuite ;
- 200 bascules successives ;
- sur une fenêtre de test (fond clair ou sombre, flèche ou main des liens, toujours au premier plan) : seul le pointeur affiché change de couleur, chaque autre forme quand elle apparaît, aucune ne reste rouge après une secousse ; changer la couleur du seul pointeur affiché reste rapide même pointeur agrandi ; avec le vrai exécutable, une main qui apparaît est recolorée en moins de 100 ms pendant que la flèche cachée attend son tour ;
- avec des écrans d'agrandissements différents : sur chaque écran, le curseur réellement affiché par Windows (capturé par l'API de duplication d'écran, `tests/tools/ptrcap.c`) a la taille que Windows donne là à ses propres curseurs, et c'est au pixel près l'image de cette taille dans nos fichiers, pour les jeux noir, blanc et rouge ; test ignoré avec un seul agrandissement ;
- la notification de taille du pointeur (`0x2029`), suivie de Windows qui remet ses curseurs 300 ms plus tard : AutoCurseur reste réactif et remet les siens ; une rafale de 10 notifications ne le bloque pas ;
- avec un pointeur agrandi : sur chaque écran, nos curseurs ont la taille et la forme de ceux de Windows ; test ignoré en taille 1, et quand le pointeur est trop grand pour que Windows donne sa forme ;
- une vraie secousse de la souris : la flèche affichée devient la rouge en taille double, puis redevient normale ; un simple balayage de l'écran, un va-et-vient vif de trois tailles de curseur ou une secousse avec l'option désactivée ne déclenchent rien ;
- pendant que la souris traverse tout l'écran, AutoCurseur répond sans délai à une question toutes les 50 ms ;
- le vrai exécutable : noir, puis blanc, puis noir à nouveau quand le fond de la fenêtre de test change, consommation sur 10 s, mémoire, instance unique, fermeture propre et retour du curseur d'origine.

## Intégration continue

À chaque push et pull request, [GitHub Actions](.github/workflows/ci.yml) installe Zig sur une machine Windows. Il lance `zig build test` et `zig build test-system`, compile l'exe en ReleaseFast et le met à disposition comme artefact.

Pour publier une version, poussez un tag `v*` (par exemple `git tag v0.1.0` puis `git push origin v0.1.0`). Une fois les tests passés, la pipeline crée la release GitHub avec l'exe testé, puis propose la nouvelle version à winget (voir [packaging/winget](packaging/winget/README.md)).

## Structure

```
src/core.zig      logique pure, sans Windows (décision, luminance, inversion, teinte rouge, secousse, minuterie)
src/cursors.zig   écriture des fichiers des jeux noir, blanc et rouge, recoloration du pointeur affiché
src/curfile.zig   lecture et écriture des fichiers .cur (versions inversée et rouge, toutes tailles)
src/svgcur.zig    curseurs vectoriels dessinés avec Direct2D, comme Windows 11 pour un pointeur agrandi
src/sampler.zig   lecture de l'écran sous la souris, sur un fil à part
src/icon.zig      icône de la zone de notification
src/i18n.zig      textes du menu en anglais et en français
src/settings.zig  réglages mémorisés (HKCU\Software\AutoCurseur)
src/main.zig      fenêtre cachée, menu, minuteries : relie le tout
src/win32.zig     déclarations de l'API Windows utilisées
src/lib.zig       point d'entrée des tests unitaires
tests/            intégration, performance, système
tests/tools/      capture du curseur affiché, pour les tests système
packaging/winget/ manifestes winget
```

## Réglages

| Où | Nom | Défaut | Rôle |
|---|---|---|---|
| `core.zig` | `Thresholds.to_black` | 150 | luminance à partir de laquelle le curseur passe en noir |
| `core.zig` | `Thresholds.to_white` | 105 | luminance en dessous de laquelle il repasse en blanc |
| menu | vérifications par seconde | 10 | 3, 5, 10 ou 20 quand la souris bouge (`core.RATES`) |
| menu | langue | automatique | suit la langue d'affichage de Windows : français pour toute variante du français, anglais sinon |
| menu | secouer pour retrouver | actif | curseur agrandi et rouge quand on secoue la souris |
| `core.zig` | `SHAKE_TURNS`, `SHAKE_WINDOW_MS` | 5, 1000 | demi-tours amples et consécutifs nécessaires, et la durée dans laquelle ils doivent tenir |
| `core.zig` | `SHAKE_SEG_FACTOR` | 3 | aller minimal, en tailles de curseur |
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
