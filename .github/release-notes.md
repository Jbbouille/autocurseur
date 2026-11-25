Download **AutoCurseur.exe** below and run it: a round half-black, half-white icon appears in the notification area. Nothing to install, no admin rights needed. Right-click the icon for the settings (checks per second, language, colors, shake to find, start with Windows).

The exe is not signed: the first time, Windows SmartScreen may show a warning. Click *More info*, then *Run anyway*.

**What's new in 0.2.0**

- **Your own two colors**: a *Colors* menu with black / white, three other pairs, or two colors picked in the Windows color dialog. The outline stays white or black so the pointer remains visible everywhere.
- **Windows' usual pointer style**, with soft edges, and its exact negative in black. The trace the old arrow left when turning into the text pointer is gone.
- **Sharp on every screen**: with screens at different display scaling, each one gets the image drawn at its size.
- **Enlarged pointer (Accessibility)**: same shapes as Windows 11 at every size, and the pointers come back after the size is changed.
- **Lighter**: the screen is read on a separate thread, and only the pointer on screen is recolored (about 10 ms instead of 90 with the largest pointer).

Updating from 0.1.0: just replace the exe. The pointer files in `%LOCALAPPDATA%\AutoCurseur\cursors` are rewritten at the first launch and the old ones deleted.

---

Téléchargez **AutoCurseur.exe** ci-dessous et lancez-le : une icône ronde mi-noire mi-blanche apparaît dans la zone de notification. Rien à installer, aucun droit administrateur. Clic droit sur l'icône pour les réglages (vérifications par seconde, langue, couleurs, secouer pour retrouver, démarrage avec Windows).

L'exe n'est pas signé : la première fois, Windows SmartScreen peut afficher un avertissement. Cliquez sur *Informations complémentaires*, puis *Exécuter quand même*.

**Nouveautés de la 0.2.0**

- **Vos deux couleurs** : un menu *Couleurs* avec noir / blanc, trois autres couples, ou deux couleurs choisies dans le sélecteur de Windows. Le contour reste blanc ou noir, pour que le curseur reste visible partout.
- **Le style habituel des curseurs de Windows**, aux bords adoucis, et son négatif exact en noir. La trace que laissait l'ancienne flèche en devenant curseur de texte a disparu.
- **Net sur chaque écran** : avec des écrans d'agrandissements différents, chacun reçoit l'image dessinée à sa taille.
- **Pointeur agrandi (Accessibilité)** : les mêmes formes que Windows 11 à toutes les tailles, et les curseurs reviennent après un changement de taille.
- **Plus léger** : l'écran est lu sur un fil à part, et seul le curseur affiché est recoloré (environ 10 ms au lieu de 90 avec le plus grand pointeur).

Mise à jour depuis la 0.1.0 : remplacez simplement l'exe. Les fichiers de curseurs de `%LOCALAPPDATA%\AutoCurseur\cursors` sont réécrits au premier lancement et les anciens supprimés.
