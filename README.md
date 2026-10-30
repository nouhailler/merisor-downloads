# MERISOR — téléchargements officiels

Ce dépôt public contient uniquement l'installateur et les binaires officiels de
[MERISOR](https://pypi.org/project/merisor/), l'éditeur graphique MERISE pour
Linux. Le dépôt de développement reste privé.

## Installation Linux universelle

L'installateur récupère la dernière AppImage `x86_64`, vérifie sa somme
SHA-256, puis installe MERISOR dans `~/.local` sans utiliser `sudo` :

```bash
curl -fsSL https://raw.githubusercontent.com/nouhailler/merisor-downloads/main/install.sh | bash
```

Pour inspecter le script avant de l'exécuter :

```bash
curl -fsSL https://raw.githubusercontent.com/nouhailler/merisor-downloads/main/install.sh -o /tmp/install-merisor.sh
less /tmp/install-merisor.sh
bash /tmp/install-merisor.sh
```

## Désinstallation

```bash
curl -fsSL https://raw.githubusercontent.com/nouhailler/merisor-downloads/main/install.sh | bash -s -- --uninstall
```

## Téléchargement manuel

Les paquets AppImage et Debian sont disponibles dans les
[releases publiques](https://github.com/nouhailler/merisor-downloads/releases/latest).
Chaque binaire est accompagné d'un fichier `.sha256`.

## Sécurité

- l'installateur refuse un binaire dont le SHA-256 ne correspond pas ;
- aucun jeton GitHub ni secret n'est incorporé dans ce dépôt ;
- les binaires sont générés par la CI du dépôt de développement puis publiés
  ici sans le code source privé ;
- l'installation est limitée au profil utilisateur.

## Plateformes

- Linux `x86_64` : AppImage universelle ;
- Debian/Ubuntu `amd64` : paquet `.deb` ;
- Windows : aucune distribution officielle pour le moment.

MERISOR est distribué sous licence MIT. Consultez [LICENSE](LICENSE).
