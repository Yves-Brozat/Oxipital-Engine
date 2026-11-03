# Azure Kinect IR dans Oxipital (Windows x64)

La source `Azure Kinect IR` est distincte de `Kinect` (V2). Elle utilise le Sensor SDK Azure Kinect ; le Body Tracking SDK est optionnel pour le suivi des mains. Le champ **Depth Mode** permet de choisir **NFOV Unbinned (640 × 576)** ou **WFOV Binned (512 × 512)**. Les deux modes demandent 30 FPS, avec illumination active et caméra couleur désactivée. Le mode Passive IR n'est pas utilisé pour ce workflow en faible luminosité.

## Installation et validation Windows

1. Installer **Azure Kinect Sensor SDK 1.4.2** depuis la [liste officielle Microsoft](https://github.com/microsoft/Azure-Kinect-Sensor-SDK/blob/develop/docs/usage.md#installers). Le SDK Kinect V2 installé précédemment ne remplace pas ce SDK.
2. Brancher l'alimentation dédiée de l'Azure Kinect puis son câble de données directement sur un port USB 3.0 du PC. Pour le premier test, débrancher la Kinect V2.
3. Dans les paramètres de confidentialité Windows, autoriser l'accès à la caméra et l'accès des applications de bureau si ces options sont désactivées.
4. Lancer **Azure Kinect Viewer** (`k4aviewer.exe`, dans le dossier `tools` du SDK), puis **Open Device**.
5. Régler **Color Resolution = OFF**, **Depth Mode = NFOV Unbinned** ou **WFOV 2x2 Binned**, **FPS = 30**, synchronisation autonome (**Standalone**). Démarrer la capture et vérifier l'image IR et sa cadence pendant au moins dix secondes, en conservant l'éclairage réel du spectacle.
6. Si le Viewer signale un firmware incompatible, suivre le [guide Microsoft de mise à jour](https://learn.microsoft.com/en-us/azure/kinect-dk/update-device-firmware). Ne pas modifier le firmware sans ce besoin de compatibilité.
7. Arrêter et fermer le Viewer avant de capturer dans Unity : l'ouverture SDK du capteur est exclusive.

Référence branchement et Viewer : [configuration Microsoft](https://learn.microsoft.com/en-us/azure/kinect-dk/set-up-azure-kinect-dk). Les documents Microsoft ciblent Windows 10 ; sur Windows 11, valider d'abord avec le Viewer sur la machine réelle.

## Intégration Unity

1. Arrêter le mode Play.
2. Menu **Tools > Oxipital > Import Azure Kinect Runtime** : choisir le dossier d'installation du SDK (généralement `C:\Program Files\Azure Kinect SDK v1.4.2`). L'outil importe les versions x64 de `k4a.dll` et `depthengine_2_0.dll` dans `Assets/Plugins/AzureKinect/x86_64`, avec activation pour l'éditeur Windows et les builds Windows x64. Il n'installe aucun pilote.
3. Redémarrer Unity après cette importation.
4. Dans **Optical Flow Source**, sélectionner **Azure Kinect IR** et désactiver **Use Test Source**.
5. Cliquer sur **Add Azure Kinect IR Controls**. Dans **Optical Flow Azure Kinect Input**, commencer avec **Device Index = 0**, **Processing Width = 256**, **Infrared Gain = 32**. Choisir **Depth Mode = NFOV Unbinned** (champ étroit) ou **WFOV Binned** (champ large). Ajuster le gain sans saturer les détails de l'image. Le changement de mode redémarre automatiquement la capture et le body tracking avec la calibration adaptée ; attendre la réinitialisation du tracker. NFOV conserve un masque hexagonal ; WFOV utilise un masque circulaire.
6. Lancer la scène. Comparer **Kinect acquisition FPS**, **Unity upload FPS** et **Unity update FPS** après quelques secondes. Une demande de 30 FPS n'est pas une garantie de cadence sur le matériel réel.
7. Réactiver ensuite les autres éléments du workflow un par un. Conserver une webcam distincte dans NVIDIA Broadcast pendant le premier test Azure IR.

L'acquisition se fait sur un thread dédié, avec conservation de la dernière image. Le changement de source arrête la capture du capteur précédent. Les valeurs sérialisées des anciennes sources sont conservées.

## Dépannage

- **Native SDK not found / DllNotFound** : importer les deux DLL x64 et redémarrer Unity. Si le problème persiste, vérifier les dépendances natives et le [runtime Visual C++ x64 Microsoft](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).
- **Cannot open Azure Kinect** : fermer Viewer, enregistreur et autres applications utilisant l'Azure Kinect.
- **IR startup failed** : tester la même configuration dans le Viewer ; vérifier `depthengine_2_0.dll`, alimentation, câble USB 3.0 et firmware.
- **IR sombre** : augmenter le gain IR d'Oxipital. Ce gain change l'image d'analyse, pas l'exposition ni la cadence du capteur.
- **Cadence basse dans le Viewer aussi** : diagnostiquer le chemin capteur / alimentation / USB avant de modifier le calcul d'optical flow.

Les binaires Microsoft sont importés depuis l'installation locale et ne sont pas fournis par ce changement. Conserver les licences et notices du SDK avec toute redistribution des binaires.
