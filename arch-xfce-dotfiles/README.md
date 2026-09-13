# arch-xfce-dotfiles

Dépôt portable pour reproduire une configuration Arch Linux + XFCE sur n'importe
quelle autre machine : liste de paquets (pacman + AUR) et fichiers de config
XFCE/GTK/Thunar/thèmes/icônes/polices.

Aucun outil externe requis (pas de stow/chezmoi) : juste `git`, `bash`,
`pacman`, `rsync`.

## Utilisation

### 1. Sur la machine source (celle à cloner)

```bash
git clone <votre-remote> arch-xfce-dotfiles   # ou juste ce dossier initialisé
cd arch-xfce-dotfiles
git init   # si pas encore un repo
./scripts/backup.sh
git add -A
git commit -m "backup config $(date +%F)"
git remote add origin <url-de-votre-repo-github-ou-gitlab>
git push -u origin main
```

`backup.sh` régénère :
- `packages/pacman.txt` — paquets officiels installés explicitement
- `packages/aur.txt` — paquets AUR / hors dépôts officiels
- `config/` — `~/.config/xfce4` (inclut `xfce4-terminal`), `Thunar`, `gtk-3.0`,
  `autostart`, thèmes, icônes, polices, launchers `.desktop`, `user-dirs.dirs`
- `config/mozilla/firefox/` — préférences Firefox du profil par défaut
  (`prefs.js`, `user.js`, moteurs de recherche, containers, `chrome/` pour
  userChrome.css/userContent.css)
- `config/wallpapers/` — les images de fond d'écran réellement utilisées
  (détectées dans `xfce4-desktop.xml`) + `manifest.txt` qui fait le lien
  ancien chemin → fichier du dépôt

Relancez `./scripts/backup.sh` + commit chaque fois que vous voulez capturer
l'état actuel de la configuration.

### 2. Sur une nouvelle machine (cible)

```bash
sudo pacman -S --needed git
git clone <votre-remote> arch-xfce-dotfiles
cd arch-xfce-dotfiles
./scripts/install.sh
```

`install.sh` :
- installe `xfce4`/`xfce4-goodies` + les paquets de `packages/pacman.txt`
- installe `yay` si nécessaire, puis les paquets de `packages/aur.txt`
- restaure tous les fichiers de config dans `$HOME`
- reconstruit le cache des polices

Déconnectez-vous/reconnectez-vous (ou redémarrez) pour que tout s'applique
proprement.

## Ce qui n'est PAS couvert (volontairement)

- Configuration système (`/etc`), display manager (lightdm/sddm), pilotes,
  partitionnement : trop spécifique à chaque machine pour être portable sans
  risque.
- Fonds d'écran : uniquement ceux référencés par `xfce4-desktop.xml` sont
  détectés et copiés automatiquement (`config/wallpapers/`) ; `install.sh` les
  place dans `~/.local/share/backgrounds/dotfiles/` et réécrit les chemins
  absolus dans les fichiers xfconf restaurés (utile si le nom d'utilisateur
  diffère entre les deux machines).
- **Historique, cookies, mots de passe et sessions Firefox** : volontairement
  exclus (`backup.sh` ne copie que `prefs.js`, `user.js`, `search.json.mozlz4`,
  `containers.json`, `handlers.json` et `chrome/`), pour ne pas finir dans un
  dépôt git potentiellement partagé. Utilisez un compte **Firefox Sync** pour
  synchroniser mots de passe/historique/marque-pages entre machines.

## Personnaliser

- Ajoutez/retirez des chemins copiés en éditant `copy`/`restore` dans
  `scripts/backup.sh` et `scripts/install.sh`.
- Éditez à la main `packages/pacman.txt` / `packages/aur.txt` avant un
  `install.sh` si vous voulez ajuster la liste sans repasser par la machine
  source.
