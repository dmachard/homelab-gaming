# homelab-gaming

Ce guide permet de transformer un PC Linux en station de jeu hybride TV / PC avec passthrough GPU.

## 🧩 Introduction

Ce dépôt documente:

- Un **PC hébergeant une machine virtuelle (VM)** avec **GPU passthrough** est utilisé comme station de jeu.
- La VM est **connectée à une TV** pour du gaming familial avec des manettes sans fil.
- La même VM peut également être utilisée depuis le **bureau du PC** si besoin pour jouer.
- Le PC peut toujours être utilisé comme un ordinateur classique.

## 🖥️ Hôte

| Composant      | Détails                     |
|----------------|-----------------------------|
| CPU            | AMD Ryzen 9 9900X           |
| GPU            | AMD Radeon™ RX 7800 XT      |
| Affichage      | Sortie HDMI vers TV + écran |
| Manette        | Xbox                        |

## 🖥️ Système

| Composant      | Détails                     |
|----------------|-----------------------------|
| OS             | Ubuntu 25.10                |
| Hyperviseur    | QEMU + libvirt              |
| OS VM          | Windows 10                  |

## Partie 1 - Configuration de l’hôte (Ubuntu)

### Isoler la carte graphique et l’USB

Exécution le script GPU passthrough pour isoler la carte graphique

```bash
cd gpu_passthrough/
sudo ./config.sh
```

Redémarrer la machine et exécuter une seconde fois pour vérifier l'isolation

```bash
cd gpu_passthrough/
sudo ./check.sh
```

### Importer la VM

Import de la VM

```bash
cd vm_qemu
./import_vm.sh
```

### Install Looking Glass Client

cd looking_glass
./install.sh

L'application est disponible via l'icone

![looking_glass](img/looking_glass.png)

## Partie 2 - VM configuration

Installer les composants suivants

### Status du GPU depuis API

- **Python + API serveur**: pour obtenir le status de la vm depuis le hote
  * scripts_vm/status_gpu.py
  * scripts_vm/status_gpu.bat

### Accès à la VM depuis l'hote 
  * Looking Glass Host: installation du binaire "host" https://looking-glass.io/artifact/stable/host

### AutoHotkey
  * Installer Autohotkey https://www.autohotkey.com/ pour ajouter des raccourcis supplémentaires avec les manettes
  * Utilise pour fermer l'émulateur switch depuis une manette xbox par exemple 
  * Déployer les scritps autohotkey/xinput.ahk et autohotkey/gamepad.ahk
  * A mettre en démarrage automatique de la VM

### SoundSwitch
  * Changement rapide de carte son via raccourci clavier → utile pour basculer entre PC et TV HDMI
  * Installer le logiciel https://soundswitch.aaflalo.me/
  * Projet github https://github.com/Belphemur/SoundSwitch

### OpenRGB
  * pour désactiver LEDs de la carte graphique
    https://openrgb.org/

### Emulateur Switch 1
  * Installer l'émulateur Ryujinx https://ryujinx.app/ Nintendo Switch 1 Emulator

### Pare feu
  * Activer le pare-feu et bloquer l'ensemble des flux entrants et sortants
    exception pour le flux tcp/8081 entrant
