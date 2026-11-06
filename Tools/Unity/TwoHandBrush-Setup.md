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
2. Si le groupe existe dans la scène, le glisser dans **Two Hand Force Brush > Target**. S'il est créé dynamiquement pendant le Play, laisser **Target vide** et choisir **Force Group Number** (par exemple 4 pour Force Group 4). Si **Force Manager** est vide, le contrôleur retrouve automatiquement le **Standard Force Manager** dans son Ballet, comme pour les orbes. Une référence explicite reste possible. Le contrôleur attend la création du groupe puis s'y reconnecte s'il est recréé. **Resolved Force Group** montre la cible réellement trouvée. Ne pas utiliser le même groupe pour deux contrôleurs.
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

**Show Hand Overlay** affiche le layer géométrique : repères G/D des mains,
ligne entre elles, positions et contours des forces et des orbes.
**Show Force Geometry** affiche les rayons des forces en **bleu** ;
**Show Orb Geometry** affiche les émetteurs des orbes en **magenta**.
Ces deux réglages sont également disponibles dans le moniteur via
**Reperes forces** et **Reperes orbes**. Les contours restent visibles sans
main détectée, caméra IR affichée ou suivi actif : ils incluent les groupes
classiques pilotés par Chataigne et les éléments générés par leurs patterns.
Chaque élément présent porte un point de position et le nom/numéro du groupe.
Les éléments de poids nul ou de taille nulle ne sont pas affichés ; une
intensité nulle ne masque pas un élément présent, afin de pouvoir le placer.

Les forces utilisent un cercle de rayon `Dancer.size`, comme le shader de
force (avec les variations de taille du groupe/pattern). Les orbes Sphere
utilisent un cercle/une ellipse, Circle un contour dans son plan orienté,
Plane un rectangle basé sur le mesh chargé, et Line une enveloppe rectangulaire
fine suivant l'axe local X. Les autres formes utilisent une boîte orientée
basée sur les bounds du mesh : c'est une enveloppe indicative, sans détailler
le volume, le bruit d'émission ou les particules déjà émises. Les contours
d'orbes intègrent `Emitter Scale`, la rotation et la taille de chaque élément.
La projection passe par **Visualization Camera** (sinon `Camera.main`), dans
le référentiel des particules, indépendamment de la calibration IR des mains.
Les groupes créés pendant le Play sont détectés automatiquement (au plus
0,5 seconde après leur création). Une direction blanche montre toujours
l'axe du pinceau lorsque son orientation est pilotée ; son point d'activation
conserve la couleur rouge/verte.

Le moniteur propose des **sélections multiples des Force Groups et Orb Groups
visibles** ; seuls **Force Group 1** et **Orb Group 1** sont sélectionnés par défaut.
Ces filtres masquent les contours, points, noms et la direction de force associés
aux groupes décochés, sans modifier les effets ou les groupes pilotés par les mains.
Les mêmes numéros sont réglables dans **Overlay Force Groups** et **Overlay Orb
Groups** dans l'inspecteur. Avec **Control Force Position** et le
pinceau actifs, le centre des éléments de la force ciblée est réappliqué après
les patterns, juste avant le remplissage du buffer VFX : le cercle bleu et les
particules lisent la même position suivie. Les autres forces restent classiques.

**Control Orb Orientation** est indépendant du rayon, de la position et de
Brush Enabled. Il utilise l'axe entre deux mains valides et **Orientation Offset**
pour orienter le groupe d'orbes ; ses éléments partagent cette orientation.

Le panneau de paramètres fixe en haut à gauche (preset, activation, intensité, rayon, état des mains) suit **Show Monitor** : masquer le Brush Monitor avec X, l'inspecteur ou Chataigne masque aussi ce panneau. Les repères géométriques restent visibles avec **Show Hand Overlay** actif. Show Hand Overlay désactivé masque seulement la géométrie ; Show Monitor continue de commander les deux panneaux. La visibilité et l'opacité du debug caméra sont indépendantes.

**Overlay Projection = Optical Flow Video** (défaut) projette les mains avec la calibration IR Azure et les mêmes recadrages, miroirs et retournements que l'optical flow. Activer **Optical Flow Debug View > Fullscreen** pour afficher le flux vidéo ou l'optical flow sur toute la fenêtre, avec conservation du rapport d'image. Les repères utilisent exactement ce rectangle d'image, y compris lorsque **View = Off** masque l'image. Une cible RawImage personnalisée conserve son propre cadrage.

Les repères IR restent calibrés sans facteur d'échelle visuel. Le placement de la force dans le référentiel des particules se règle avec **Position Mapping**, **Visualization Camera** et le plan ou la profondeur d'interaction.

Ces repères sont indépendants de l'image IR et du panneau : on peut masquer la caméra et fermer le panneau tout en gardant mains, cercles et direction du pinceau. **Overlay Projection = Scene Camera** permet de revenir à la projection des positions monde par **Visualization Camera** (sinon `Camera.main`). **Sensor Origin** aligne les coordonnées physiques et la scène. **Show Hand Overlay** ou **Hide Hand Overlay** permet de masquer ce retour sans arrêter le pinceau. Désactiver tout le composant Two Hand Brush Monitor masque les deux retours.

Pour garder les particules visibles sous l'aperçu plein écran, **Optical Flow Debug View > Overlay Opacity** vaut 0,25 par défaut et **Transparent Background** rend les pixels noirs transparents. Le moniteur propose **Afficher l'image camera / optical flow** et une jauge **Opacite de l'image**. Décocher l'image masque les aperçus écran et plan vidéo, mais conserve les particules, les repères géométriques et les panneaux si Show Monitor est actif. Mettre seulement l'opacité à zéro masque l'aperçu écran ; le plan vidéo possède son propre réglage Plane View.

Le panneau montre le groupe résolu, le preset sélectionné, l'état des deux mains, un schéma frontal des mains, les FPS IR et corps, l'écart entre les mains, le rayon demandé, l'activation et les valeurs réelles du groupe (position, rotation, rayon, intensité, direction linéaire et huit intensités de force). Le schéma est une projection indicative dans les coordonnées du capteur, pas une superposition calibrée à l'image IR. En l'absence de suivi, les mesures gestuelles sont indiquées comme indisponibles et le panneau continue de montrer l'extinction de la force.

Les flèches **< / >** permettent d'essayer les pinceaux et **Pinceau active** d'armer/désarmer l'effet. Les mesures des mains restent visibles lorsque l'effet est désarmé, pour faciliter le placement. Les réglages modifiés pendant le Play restent soumis au fonctionnement habituel de Unity (ils sont réinitialisés à l'arrêt).

## Réglages et perte de suivi

- **Radius Multiplier = 0.5** : le rayon de base vaut la moitié de l'écart entre les mains dans la scène des particules, limité par Minimum/Maximum Radius. **Size Multiplier = 1** par défaut conserve ce rayon ; une valeur de 10 le multiplierait par dix (limites comprises). Exemple : écart projeté 4 unités → rayon appliqué 2 unités.
- **Intensity Mapping = Manual** : intensité appliquée = intensité du preset × Strength × activation. Elle ne dépend pas d'un geste ; avec des valeurs à 1 et un suivi valide, le résultat reste à 1.
- **Intensity Mapping = Hand Distance** : l'écart des mains est normalisé avec **Intensity Distance Range** (par défaut 0,1 m → 0 et 1 m → 1), puis multiplie l'intensité du preset, Strength et l'activation. **Invert Gesture Intensity** inverse le geste. Le moniteur montre séparément le signal gestuel et l'intensité réellement appliquée. Le lissage existant amortit aussi ce signal.
- **Smoothing Seconds** amortit position, rayon et orientation. Le cercle de l'orbe centrale suit la position lissée de la source, comme les cercles des deux orbes séparées ; l'ancrage du groupe utilise lui aussi ces positions lissées.
- **Minimum Axis Distance** fige l'orientation quand les mains se rapprochent trop, afin d'éviter un axe instable.
- Le tracker sélectionne le corps le plus proche et conserve son identifiant tant qu'il est présent. Il attend environ 0,75 seconde avant d'adopter un autre corps après une disparition.
- Chaque main est validée séparément (fraîcheur, confiance, profondeur optionnelle, puis cadrage). Une main suffit à piloter la position de la force et de l'orbe centrale. L'écart, le rayon gestuel et l'orientation gardent leurs dernières valeurs tant que les deux mains ne sont pas utilisables. Sans aucune main utilisable, la force s'éteint via Activation Fade Seconds.
- Les gizmos du contrôleur montrent la ligne des mains et le rayon, lorsque l'objet est sélectionné dans la scène.
- Désactiver le composant ou changer sa cible restaure les valeurs et le transform initiaux du groupe. Utiliser un groupe dédié pour ne pas écraser une autre animation.

Le masque hexagonal en NFOV vient de l'illumination IR du capteur : [explication Microsoft](https://learn.microsoft.com/en-us/previous-versions/azure/kinect-dk/depth-camera#illumination-mask). Le pinceau n'agrandit pas la zone physique de suivi.

## Diagnostiquer et calibrer la profondeur des mains

Le suivi du pinceau utilise **Azure Kinect Body Tracking**. `Interaction Depth`
place les effets dans la scène Unity ; il ne règle pas la distance physique
acceptée par le capteur. Le code ne contient pas de limite de suivi à 1,5 m.

Le moniteur et l'inspecteur **Optical Flow Azure Kinect Input** affichent pour
chaque main la profondeur **Z en mètres devant le capteur**, la confiance et la
cause de rejet : aucun corps, image trop ancienne, position invalide, confiance
insuffisante ou hors plage de profondeur. Le moniteur signale séparément une
main suivie mais hors cadrage / impossible à projeter dans la scène.

Pour examiner une perte de suivi en reculant :

1. Désactiver **Limiter l'activation en profondeur** et réduire temporairement
   le zoom pour écarter un rejet de zone ou de cadrage.
2. Lire le diagnostic G/D. Si la confiance est insuffisante, essayer
   **Accepter confiance faible** : le seuil passe de 2 (moyenne) à 1 (faible),
   ce qui accepte davantage d'estimations et peut rendre les positions moins fiables.
3. Si l'image est trop ancienne, examiner les FPS corps et essayer d'augmenter
   le **Délai maximal du suivi** depuis 0,3 s. Cela accepte une pose plus ancienne ;
   cela n'accélère pas le tracker et ne restaure pas un corps perdu.
4. Le bouton de mode permet d'essayer **NFOV** pour travailler plus loin, au prix
   d'un champ plus étroit. Changer de mode redémarre capture et tracking ;
   vérifier ensuite le zoom et le centre de la zone de jeu.

Les plages nominales de mesure de profondeur sont **0,25–2,88 m en WFOV binned**
et **0,5–3,86 m en NFOV unbinned**, selon les conditions décrites par
[Microsoft](https://learn.microsoft.com/en-us/previous-versions/azure/kinect-dk/hardware-specification#depth-camera-supported-operating-modes).
Elles ne garantissent pas un suivi des mains sur toute la plage.

Pour définir une zone d'activation physique, se placer à la distance de jeu avec
au moins une main fiable puis cliquer **Calibrer la profondeur sur ma position**.
Le bouton centre la plage sur la profondeur moyenne des mains valides avec une
marge de **±0,75 m** par défaut. Il ignore l'ancienne plage lors de la calibration,
afin de pouvoir la recentrer même depuis l'extérieur. **Marge autour de la pose**,
les profondeurs minimale/maximale et le filtre restent réglables dans le moniteur
et sur le composant. Cette calibration ajoute une zone d'activation ; elle ne
modifie pas la calibration optique ni la portée matérielle.

Ces réglages sont exposés par OSCQuery sur OpticalFlowAzureKinectInput. Pour les
conserver, recopier les valeurs hors Play sur ce composant puis sauvegarder la scène.

## Zone de jeu 4:3 et zoom pour la projection 8 m × 6 m

Conserver la sortie Unity/Spout en **16:9**. Sur **Optical Flow Source**, activer
**Frame Play Area**, laisser **Play Area Aspect = 1,333333**, puis augmenter
**Play Area Zoom** jusqu'à obtenir un rectangle utile sans coins noirs. Commencer
par 1,2 à 1,5 et ajuster devant le capteur ; la valeur dépend du cadrage réel.
**Play Area Center X/Y = 0,5** centre le rectangle ; déplacer ces valeurs pour
l'aligner sur la position du danseur (Y augmente vers le haut).

Ces commandes sont aussi dans le moniteur : **Recadrer la zone de jeu**, bouton
**Zone 4:3**, zoom et centre horizontal/vertical. Elles sont exposées par OSCQuery
sur OpticalFlowSource ; Sync Data actualise l'arbre Unity dans Chataigne.

Utiliser **Fullscreen** sur Optical Flow Debug View et **Camera Plane** sur le
pinceau. Le même rectangle source pilote l'image IR, l'optical flow, les repères
des mains et les positions des forces/orbes. Le zoom réduit donc l'amplitude
physique nécessaire pour atteindre les bords de la zone. Le rectangle 4:3 reste
centré dans la sortie 16:9, sans déformer l'image. Une RawImage personnalisée
doit elle aussi être cadrée en 4:3.

Le recadrage s'applique aussi aux **forces de l'optical flow**. Avec **Optical
Flow Manager > Fit Plane To Play Area** actif (par défaut), le plan de forces
épouse pendant le Play le même rectangle écran que l'image et les mains.
Il utilise la Visualization Camera du pinceau, sinon Camera.main, et conserve
la profondeur initiale du Flow Plane dans la scène. Son orientation et ses
dimensions suivent le cadrage caméra ; Plane Scale est alors remplacé par ce
calcul automatique. Cela reste actif lorsque l'image de diagnostic est masquée.
Le zoom et le déplacement du centre modifient l'image avant le calcul du flow ;
la traînée est vidée à chaque changement de cadrage pour retirer les anciennes
forces. Depth Band continue de limiter l'influence autour du plan dans la scène.

Pour vérifier l'alignement, afficher temporairement **View = Output** et le
wireframe du Flow Plane : le champ doit couvrir le rectangle 4:3 central.
Le mode manuel reste accessible en désactivant Fit Plane To Play Area.

Dans Resolume, sélectionner les **75 % centraux de la largeur**, soit retirer
**12,5 % à gauche et à droite** : pour 1920 × 1080, retirer 240 pixels de chaque
côté pour obtenir 1440 × 1080. Ce recadrage concerne la zone centrale ; les
particules peuvent continuer à être rendues dans les marges de la sortie Unity.

Les anciens Crop Left/Right/Bottom/Top restent applicables avant le zoom.
Le suivi physique reste celui du capteur : sortir une main de la zone recadrée
invalide seulement la projection de cette main jusqu'à son retour. Le zoom augmente aussi
l'écart projeté des mains et donc le rayon ; ajuster Radius Multiplier si besoin.
Pour conserver la calibration, recopier les valeurs dans Optical Flow Source
hors Play et sauvegarder la scène. Le moniteur ne sauvegarde pas ces réglages.

## Deux orbes et presets Chataigne

**Two Hands Forces** crée deux sources identiques dans le Force Group choisi,
une par main, quand **Control Force Position** est actif. Rayon, orientation et
paramètres du preset restent partagés. Désactiver Two Hands Forces remet la
source unique au centre des mains.

**Single Hand Only** ne concerne que les modes Two Hand Orbs et Two Hands Forces.
Il garde la première main suivie active et passe à l'autre si elle est perdue.
Si les deux arrivent simultanément, la gauche est choisie. Le même choix sert
aux forces et aux orbes ; l'instance inactive a une intensité nulle.
Le mode à une seule source centrée conserve son fonctionnement habituel.
Les interrupteurs sont disponibles dans le moniteur et dans les presets Kinect.

Avec **Control Orb Position** actif, **Two Hand Orbs** utilise deux éléments du
même Orb Group : une émission suit chaque main, avec les paramètres partagés du
groupe. Chaque main active son propre élément, même si l'autre est absente,
peu fiable ou hors cadrage. L'élément de la main perdue garde sa position et son
activation descend à zéro via Activation Fade Seconds ; l'autre continue de suivre.
Les particules déjà émises gardent leur durée de vie habituelle.
Désactivé, un seul élément suit le milieu des mains, ou la seule main utilisable.
Les positions sont
appliquées dans l'étape des patterns avant le buffer VFX, indépendamment de la
rotation, de l'échelle et de Pattern Size du groupe. À la perte du suivi, elles
restent figées. Désactiver le contrôle de position restaure count et la
répartition de taille précédents et laisse les patterns habituels reprendre.

Dans le workflow EN16, les presets de force et d'orbe et la conduite restent
gérés par Chataigne ; Selected Brush reste sur **Current Group / Chataigne**.
L'intensité reçue de Chataigne est actualisée pendant le suivi. Relâcher le
contrôleur restaure ses propriétés de geste sans réappliquer tous les anciens
paramètres de force par-dessus le preset Chataigne courant. Le bouton Deux orbes
est aussi disponible dans le moniteur, et l'overlay affiche les positions G/D.
# Sources fixes et perte des mains

La présence des mains ne conditionne l'activation d'une force que lorsque
`Control Force Position` est activé. Une force fixe conserve sa chorégraphie et
reste active sans mains ; les paramètres gestuels encore activés conservent
leur dernière valeur valide. `Brush Enabled`, Strength et l'intensité du preset
restent applicables. Avec les paramètres gestuels désactivés, un ancien facteur
gestuel nul ne doit pas bloquer la force. Un input manquant ne coupe pas une
force fixe. Les orbes ne reçoivent déjà de masque par main que lorsque
`Control Orb Position` est actif.

Validation : `Tools > Oxipital > Validate Brush Tracking` en Play teste sur des
objets isolés les forces fixes sans mains, la coupure des forces qui suivent les
mains, le retour au mode fixe, la conservation de la chorégraphie et l'absence
d'input. Le test ne démarre ni capture Kinect ni buffers GPU. Compiler ce test
ne remplace pas son exécution dans Unity.

