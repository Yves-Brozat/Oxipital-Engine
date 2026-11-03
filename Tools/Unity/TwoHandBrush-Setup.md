# Pinceau à deux mains : Azure Kinect et Force Groups

Le pinceau agit sur un `StandardForceGroup` existant : milieu des mains = position du groupe, écart = rayon (`dancerSize`), axe main gauche → main droite = orientation. La direction linéaire peut suivre ce même axe. Cette version ne mesure pas la torsion des poignets et n'utilise pas de geste pour changer de pinceau.

## Préparer le suivi

1. Fermer les Viewers Kinect et les autres applications utilisant l'Azure Kinect.
2. Installer Azure Kinect Body Tracking SDK 1.1.2. Menu Unity **Tools > Oxipital > Import Azure Body Tracking Runtime**, choisir son dossier d'installation, puis redémarrer Unity. Le menu importe `k4abt.dll`, ONNX Runtime, DirectML et le modèle dans StreamingAssets. Le Sensor SDK et ses DLL restent nécessaires.
3. Garder **Optical Flow Source > Azure Kinect IR** actif. Sur **Optical Flow Azure Kinect Input**, activer **Body Tracking**. Le backend utilise DirectML ; GPU index 0 sélectionne l'adaptateur par défaut. Le champ Model Path vide utilise le modèle importé. Vérifier **Body Status** et **Body tracking FPS**.
4. Cliquer **Add Two-Hand Force Brush**. Cela ajoute le contrôleur et active l'option Body Tracking, si elle ne l'est pas déjà.

Une seule capture Azure sert à l'IR et au suivi du corps. L'inférence tourne sur un autre thread et garde uniquement la capture récente : elle ne bloque pas la boucle d'acquisition IR. Le premier démarrage du tracker peut prendre du temps. La fluidité réelle doit être vérifiée avec les VFX et Broadcast actifs.

## Configurer le Force Group et les pinceaux

1. Ajouter/configurer un **Force Group dédié** avec le système habituel d'Oxipital, y compris sa liaison aux VFX. Vérifier d'abord qu'il produit une force visible. Utiliser un groupe avec un prefab de Dancer valide, comme les groupes existants.
2. Si le groupe existe dans la scène, le glisser dans **Two Hand Force Brush > Target**. S'il est créé dynamiquement pendant le Play, laisser **Target vide**, assigner son **Standard Force Manager** à **Force Manager** et choisir **Force Group Number** (par exemple 4 pour Force Group 4). Le contrôleur attend sa création puis s'y reconnecte s'il est recréé. **Resolved Force Group** montre la cible réellement trouvée. Ne pas utiliser le même groupe pour deux contrôleurs.
3. Assigner **Input** à l'entrée Azure et choisir **Position Mapping = Camera Plane**. Assigner **Visualization Camera** à la caméra qui rend les particules (sinon `Camera.main`). Le contrôleur projette les positions des mains dans le cadrage IR, avec les recadrages et miroirs de l'optical flow, puis lance des rayons depuis la caméra des particules vers le plan d'interaction. Des mains en haut de l'image placent ainsi la force en haut de la vue des particules.
4. Quand le groupe existe (y compris pendant le Play), cliquer **Create Attract / Repel / Vortex Presets**. Dans le sélecteur de fichier, choisir un dossier du projet (par exemple `Assets/Brushes`) et valider : trois assets Attract, Repel et Vortex y sont créés et ajoutés à la liste Brushes. Ou configurer les valeurs du groupe et cliquer **Save Force Group as Brush Preset** pour enregistrer sa configuration. La force temporairement coupée par la perte des mains n'est pas enregistrée comme intensité nulle.
5. Choisir le pinceau avec **Selected Brush**, dans l'inspecteur, y compris pendant le Play. **Current Group / Chataigne** laisse les paramètres de force du groupe tels quels, ce qui permet de charger un preset externe dans Chataigne.
6. **Brush Enabled** active/désactive l'effet sans changer le pinceau. Les commandes sont accessibles à OSCQuery ; aucune pédale n'est nécessaire à ce stade.

## Commandes indépendantes et orientation

Cinq interrupteurs sont disponibles dans l'inspecteur et sous forme de boutons ON/OFF dans le moniteur :

- **Control Force Position / Position forces** : le centre du Force Group suit le milieu des mains. Désactiver laisse la force à sa dernière position.
- **Control Brush Parameters / Intensite / rayon** : l'écart pilote le rayon et, si Intensity Mapping = Hand Distance, l'intensité. Désactiver fige le rayon et le signal d'intensité gestuelle actuels. Le facteur de sécurité d'activation continue de couper la force si le suivi est perdu ; Strength et un changement explicite de preset restent applicables.
- **Control Force Orientation / Orientation forces** : les mains pilotent la rotation et la direction linéaire selon Orient Along Hands et Drive Linear Direction. Désactiver conserve la rotation/direction actuelles.
- **Control Orb Position / Position orbe** : le centre d'un Orb Group suit le milieu des mains, indépendamment de la position de la force et de Brush Enabled. Le reste des paramètres de l'Orb Group est conservé. Le groupe émetteur se déplace ; les trajectoires des particules déjà émises restent celles du VFX.
- **Control Orb Radius / Rayon orbe** : le paramètre `dancerSize` de l'Orb Group suit l'écart des mains avec le même calcul que le rayon de la force, même lorsque le contrôle de taille de la force est désactivé. **Orb Radius Multiplier** (défaut 1) ajuste sa taille relativement à ce calcul. Ce contrôle est indépendant de Position orbe et de Brush Enabled. Désactiver le bouton ou perdre le suivi fige le dernier rayon. Le moniteur affiche une jauge du rayon de l'orbe et un contour magenta lorsqu'il est piloté.

Pour cibler l'orbe, assigner **Orb Target** si le groupe existe dans la scène. Pour un groupe créé au Play, laisser ce champ vide, assigner **Orb Manager**, puis **Orb Group Number** (1 pour Orb Group 1). **Resolved Orb Group** montre le groupe trouvé. À la perte des mains, sa position et son rayon restent figés ; désactiver le contrôleur ou changer la cible restaure les valeurs initiales des propriétés pilotées.

**Orientation Offset** est un vecteur d'angles X/Y/Z en degrés dans les axes de la caméra d'interaction (ou de Sensor Origin en mode Sensor World). Le même offset est appliqué à la rotation complète du groupe et à l'axe de la force linéaire. Les boutons **X/Y/Z -90 / +90 deg** facilitent les changements par quarts de tour. Le défaut Z=90 tourne une direction horizontale de 90° ; selon le sens gauche/droite du suivi, utiliser -90 ou la calibration.

Pour obtenir exactement « mains horizontales → force vers le haut », lancer le Play, écarter les mains horizontalement et cliquer **Calibrate current hand pose -> Up** dans l'inspecteur ou **Calibrer cette pose vers le haut** dans le moniteur. L'offset est calculé pour orienter cette pose vers le haut de la caméra. Ce bouton nécessite un suivi fiable et une projection valide. Comme les autres réglages modifiés au Play, recopier l'offset dans le composant hors Play pour le conserver.

Les assets enregistrés pendant le Play restent dans le projet. En revanche, Unity rétablit la liste Brushes et la sélection du composant à l'arrêt du Play. Après avoir créé les presets pendant le Play, arrêter la scène puis glisser les assets depuis Project dans la liste Brushes en mode édition, choisir le pinceau et sauvegarder la scène. Les références au manager et le numéro de groupe se configurent aussi en mode édition pour être conservés.

## Profondeur et référentiel des particules

Avec **Position Mapping = Camera Plane**, choisir la profondeur où vivent les particules :

- **Use Target Depth** (défaut) place un plan face à la caméra à la profondeur de la position initiale du Force Group.
- Pour choisir une distance précise, décocher **Use Target Depth** et régler **Interaction Depth**, en unités devant la caméra.
- Pour une surface précise dans la scène, assigner **Interaction Plane** à un Transform situé au niveau des particules ; son axe Z est la normale du plan. Il remplace la profondeur automatique.

La position, la direction et le rayon du pinceau sont calculés dans ce référentiel. Le rayon utilise l'écart entre les mains projetées dans la scène. L'intensité Hand Distance continue d'utiliser l'écart physique des mains. Le mode **Sensor World** conserve l'ancienne conversion physique du squelette via **Sensor Origin**, pour les scènes réellement calibrées en 3D.

**Force Factor Outside = 0** annule la force hors de la sphère 3D. Avec Inside > 0, une intensité non nulle et une force du preset activée, l'intérieur reste influencé. La courbe actuelle vaut 1 près du centre, puis décroît entre 60 % et 100 % du rayon. Le cercle de feedback est une projection : une particule peut apparaître dedans mais être hors de la sphère si sa profondeur est différente. Positionner le plan d'interaction à la profondeur des particules pour tester. Le cercle représente maintenant la force réellement placée dans la scène, pas une reprojection de cette position comme si elle appartenait au squelette.

Le contrôleur gère count=1, patternSize=0, patternSpeed=0, dancerRotation=0, dancerLookAtMode=0 et la sécurité d'activation. Les interrupteurs ci-dessus décident quelles propriétés du transform, du rayon et de l'orientation sont animées par les mains. Ne pas mapper les mêmes propriétés depuis Chataigne en parallèle. Les autres paramètres de force peuvent être pilotés depuis Chataigne en mode Current Group. Un preset Unity est appliqué seulement à la sélection, pas à chaque frame.

Les presets enregistrent les champs numériques float et Vector3 du Force Group. Ils ne copient pas les courbes, prefabs, composants de patterns, références de VFX ou mappings Chataigne.

## Retour visuel masquable

**Two Hand Force Brush > Show Monitor** affiche un panneau dans la Game View et dans les builds. Il apparaît automatiquement au démarrage du contrôleur. Déplacer le panneau par sa barre de titre, le réduire avec **-**, ou le masquer avec **X**. Pour le réafficher, cocher **Show Monitor** ou cliquer sur **Show Brush Monitor** dans l'inspecteur. Le panneau peut aussi être désactivé via le composant **Two Hand Brush Monitor**. Masquer le panneau ne désactive ni le pinceau, ni le suivi, ni la visualisation caméra.

**Monitor Scale** règle la lisibilité (1 à 3, défaut 1,5). Le panneau est plus large et le texte agrandi ; une barre « Taille de l'interface » permet aussi de modifier l'échelle pendant le Play.

**Show Hand Overlay** affiche les repères G/D des mains, la ligne entre elles, leur écart et le cercle du rayon réellement appliqué au groupe. Des jauges fixes en haut à gauche montrent activation, intensité et rayon. La couleur de la zone d'influence passe du rouge (intensité nulle) au vert (intensité pleine). Une direction blanche montre l'axe du pinceau lorsque son orientation est pilotée.

**Overlay Projection = Optical Flow Video** (défaut) projette les mains avec la calibration IR Azure et les mêmes recadrages, miroirs et retournements que l'optical flow. Activer **Optical Flow Debug View > Fullscreen** pour afficher le flux vidéo ou l'optical flow sur toute la fenêtre, avec conservation du rapport d'image. Les repères utilisent exactement ce rectangle d'image, y compris lorsque **View = Off** masque l'image. Une cible RawImage personnalisée conserve son propre cadrage.

Les repères IR restent calibrés sans facteur d'échelle visuel. Le placement de la force dans le référentiel des particules se règle avec **Position Mapping**, **Visualization Camera** et le plan ou la profondeur d'interaction.

Ces repères sont indépendants de l'image IR et du panneau : on peut masquer la caméra et fermer le panneau tout en gardant mains et jauges. **Overlay Projection = Scene Camera** permet de revenir à la projection des positions monde par **Visualization Camera** (sinon `Camera.main`). **Sensor Origin** aligne les coordonnées physiques et la scène. **Show Hand Overlay** ou **Hide Hand Overlay** permet de masquer ce retour sans arrêter le pinceau. Désactiver tout le composant Two Hand Brush Monitor masque les deux retours.

Pour garder les particules visibles sous l'aperçu plein écran, **Optical Flow Debug View > Overlay Opacity** vaut 0,25 par défaut et **Transparent Background** rend les pixels noirs transparents. Le moniteur propose **Afficher l'image camera / optical flow** et une jauge **Opacite de l'image**. Décocher l'image masque les aperçus écran et plan vidéo, mais conserve les particules, les mains et les jauges. Mettre seulement l'opacité à zéro masque l'aperçu écran ; le plan vidéo possède son propre réglage Plane View.

Le panneau montre le groupe résolu, le preset sélectionné, l'état des deux mains, un schéma frontal des mains, les FPS IR et corps, l'écart entre les mains, le rayon demandé, l'activation et les valeurs réelles du groupe (position, rotation, rayon, intensité, direction linéaire et huit intensités de force). Le schéma est une projection indicative dans les coordonnées du capteur, pas une superposition calibrée à l'image IR. En l'absence de suivi, les mesures gestuelles sont indiquées comme indisponibles et le panneau continue de montrer l'extinction de la force.

Les flèches **< / >** permettent d'essayer les pinceaux et **Pinceau active** d'armer/désarmer l'effet. Les mesures des mains restent visibles lorsque l'effet est désarmé, pour faciliter le placement. Les réglages modifiés pendant le Play restent soumis au fonctionnement habituel de Unity (ils sont réinitialisés à l'arrêt).

## Réglages et perte de suivi

- **Radius Multiplier = 0.5** : le rayon de base vaut la moitié de l'écart entre les mains dans la scène des particules, limité par Minimum/Maximum Radius. **Size Multiplier = 1** par défaut conserve ce rayon ; une valeur de 10 le multiplierait par dix (limites comprises). Exemple : écart projeté 4 unités → rayon appliqué 2 unités.
- **Intensity Mapping = Manual** : intensité appliquée = intensité du preset × Strength × activation. Elle ne dépend pas d'un geste ; avec des valeurs à 1 et un suivi valide, le résultat reste à 1.
- **Intensity Mapping = Hand Distance** : l'écart des mains est normalisé avec **Intensity Distance Range** (par défaut 0,1 m → 0 et 1 m → 1), puis multiplie l'intensité du preset, Strength et l'activation. **Invert Gesture Intensity** inverse le geste. Le moniteur montre séparément le signal gestuel et l'intensité réellement appliquée. Le lissage existant amortit aussi ce signal.
- **Smoothing Seconds** amortit position, rayon et orientation.
- **Minimum Axis Distance** fige l'orientation quand les mains se rapprochent trop, afin d'éviter un axe instable.
- Le tracker sélectionne le corps le plus proche et conserve son identifiant tant qu'il est présent. Il attend environ 0,75 seconde avant d'adopter un autre corps après une disparition.
- Les deux mains doivent atteindre le niveau de confiance demandé. À la perte du corps, à une image trop ancienne ou si une main devient peu fiable, le pinceau s'éteint progressivement via Activation Fade Seconds.
- Les gizmos du contrôleur montrent la ligne des mains et le rayon, lorsque l'objet est sélectionné dans la scène.
- Désactiver le composant ou changer sa cible restaure les valeurs et le transform initiaux du groupe. Utiliser un groupe dédié pour ne pas écraser une autre animation.

Le masque hexagonal en NFOV vient de l'illumination IR du capteur : [explication Microsoft](https://learn.microsoft.com/en-us/previous-versions/azure/kinect-dk/depth-camera#illumination-mask). Le pinceau n'agrandit pas la zone physique de suivi.
