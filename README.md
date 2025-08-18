# homelab-gaming

Ce guide permet de transformer un PC Linux en station de jeu hybride TV / PC avec passthrough GPU.

## 🧩 Introduction

Ce dépôt documente:

- Un **PC hébergeant une machine virtuelle (VM)** avec **GPU passthrough** est utilisé comme station de jeu.
- La VM est **connectée à une TV** pour du gaming familial avec des manettes sans fil.
- La même VM peut également être utilisée depuis le **bureau du PC** si besoin pour jouer.
- Le PC peut toujours être utilisé comme un ordinateur classique.

## 🖥️ L'hôte

| Composant      | Détails                     |
|----------------|-----------------------------|
| CPU            | [Votre modèle CPU]          |
| GPU            | [Votre modèle GPU]          |
| Affichage      | Sortie HDMI vers TV + écran |
| Manette        | ....                        |

## 🖥️ Système

| Composant      | Détails                     |
|----------------|-----------------------------|
| OS             | [ex: Ubuntu 24.04]          |
| Hyperviseur    | [ex: QEMU + libvirt]        |
| OS invité      | [ex: Windows 11]            |

## Partie 1 - Configuration de l’hôte (Ubuntu)

### Isoler la carte graphique et l’USB

```bash
$ sudo cat /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash iommu=pt vfio-pci.ids=1002:747e,1002:ab30,15b7:5011"
```

### Créer la VM

👉 Exemple de configuration libvirt XML (Windows 10) :

```xml
<domain xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0" type="kvm">
   ...
</domain>
```

Tuning
```xml
  <qemu:commandline>
    <qemu:arg value="-device"/>
    <qemu:arg value="ivshmem-plain,id=shmem0,memdev=looking-glass,bus=pcie.0,addr=0x11"/>
    <qemu:arg value="-object"/>
    <qemu:arg value="memory-backend-file,id=looking-glass,mem-path=/dev/kvmfr0,size=128M,share=yes"/>
  </qemu:commandline>
```

### Reconfigurer le réseau pour une IP fixe

```bash
$ virsh net-edit default
```

```xml
<network>
  <name>default</name>
  <uuid>927dcee2-c122-4c1d-9a60-0e331e7910c2</uuid>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:23:ab:8b'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.2'/>
    </dhcp>
  </ip>
</network>
```

### Déployer le script de gestion GPU vm-gpu.py

Le script `vm-gpu.py` est un workaround pour éviter des freezes à l'arrêt de la VM avec la carte graphique.

A déployer dans /home/user/console. Le script permet de lancer, arrêter, contrôler et monitorer la VM et le GPU.

Scripts de lancement rapide (/home/user/console/launcher)
- StartGaming.sh → démarre la VM
- StopGaming.sh → arrête la VM
- Ctrl+Alt+Del.sh → envoie Ctrl+Alt+Del à la VM
- SwitchAudio.sh → change la sortie audio

### Ajouter un raccourci Looking Glass

Créer ~/.local/share/applications/looking-glass-client.desktop :

```
[Desktop Entry]
Name=Windows Gaming
Exec=looking-glass-client -F
Icon=/home/user/.local/share/icons/looking-glass.png
Type=Application
Categories=Utility;System;
Terminal=false
```

## Part 2 - VM configuration

### Installer les composants

- Python + API serveur: pour obtenir le status de la vm depuis le hote
- Looking Glass Host
    https://looking-glass.io/artifact/stable/host

- AutoHotkey: script pour intercepter les touches manette et fermer un émulateur (Ryujinx) 
    https://www.autohotkey.com/
- SoundSwitch: changement rapide de carte son via raccourci clavier → utile pour basculer entre PC et TV HDMI
    https://soundswitch.aaflalo.me/
    https://github.com/Belphemur/SoundSwitch
- OpenRGB: pour désactiver LEDs de la carte graphique
    https://openrgb.org/

### Gestion RGB

## Part 3 - Game setup tuning

