# Kinect / EN16 dans Chataigne

## Banque et rappel Méduses

Dans la copie **Synchronized**, le paramètre de preset **EN16 Kinect Bank** est
réglé sur **Mode = None** dans les 11 presets Kinect : il est ignoré lors du
rappel et reste sous le contrôle du bouton 16. Ce réglage natif est conservé
lors de la mise à jour des valeurs d'un preset existant ; conserver le même
mode pour cette variable lors de la création de nouveaux presets.
L'action **Presets > Meduse** rappelle uniquement Orb1 Meduse, Force1 Meduse,
Kinect Meduse et Camera Reset, avec les conséquences internes de synchronisation.
Le rappel Leap Motion Orb Only supplémentaire est retiré.
La correction repart de la sauvegarde Synchronized du 05/11/2026 à 22:17 et
une copie `.before-led-dashboard-20261105-221714.bak` est conservée à côté du
fichier live. `Test-LEDColorAndPresetBank.ps1` contrôle la séparation RGB, le
maintien de la banque dans les deux états et la conservation des autres données.

## Synchronisation des presets et édition dans Unity

La copie **Oxipital Live Kinect Performance Synchronized.noisette** reprend
**Emitter Size Merged** avec les presets modifiés. Après installation des fichiers
du module, relancer Chataigne et ouvrir cette copie.

Chaque action de spectacle dans **Presets** conserve ses rappels Orb/Force/Kinect
et ajoute une réapplication explicite des valeurs du bridge, une fois au début
et une fois après la plus longue interpolation Orb/Force. L'envoi utilise le
transport OSCQuery direct (`local.send`) afin de ne pas être supprimé quand le
cache Chataigne contient déjà zéro. Un nouveau rappel remplace les échéances
du précédent. Le Sync Data habituel bénéficie du même envoi explicite.
Une nouvelle propriété **Setup > Apply Current Values** permet également de
demander cette réapplication sans reconstruire la structure OSCQuery.

Pour concevoir un preset dans Unity :

1. Activer **Edition Unity**, à droite du dashboard **Abysses Kinect**, avant de
   commencer les modifications. Le contrôle existe aussi dans
   **Oxipital > Setup > Unity Edit Mode**.
2. Le contrôleur Kinect est désactivé temporairement, les envois du bridge sont
   suspendus, et l'état **Unity -> Show Editing** importe les valeurs live des
   Orb Groups 1/2 et Force Groups 1/2 vers les CV correspondantes à **5 Hz**.
3. Modifier les paramètres dans Unity. Vérifier les CV dans Chataigne, puis
   enregistrer/mettre à jour les presets Orb/Force souhaités avec les commandes
   habituelles de Chataigne. Le mode n'enregistre jamais un preset tout seul.
4. Désactiver **Edition Unity** pour reprendre la conduite depuis Chataigne.
   Les paramètres capturés sont appliqués et le réglage Kinect Enabled précédent
   reprend son effet. Le retour automatique est inactif hors mode édition.

En mode édition, les rappels de presets ne pilotent pas Unity : sortir du mode
pour les tester. Les anciens paramètres sans champ Unity correspondant (comme
Dancer Weight Intensity Factor) ne sont pas importés. Les macros continuent à
s'appliquer aux valeurs de base lors du retour à la conduite.

Le contrôleur Unity ne verrouille plus l'ancienne position de force lorsqu'il
n'a pas de main valide ou que Brush Enabled est désactivé. Avec des mains valides
et Force Position actif, le suivi reprend ensuite la priorité sur la position
du preset ; désactiver ce contrôle dans le preset Kinect pour garder un centre
fixe. Le retour d'édition et les tests de bridge ne remplacent pas un essai live.

Validation : `Test-ShowSynchronization.js`, `Test-SyncLifecycle.js`,
`Test-Point3DDefaults.js`, `Test-ShowSynchronization.ps1` et compilation C#.

Le moteur JavaScript JUCE de Chataigne n'implémente pas `String.lastIndexOf`.
Le bridge utilise `split/join` pour les chemins et passe l'envoi forcé comme
argument explicite à chaque fonction, sans drapeau global susceptible de rester
actif après une erreur. Le test de bridge désactive volontairement `lastIndexOf`
dans son moteur hôte pour couvrir cette incompatibilité. Après remplacement du
script, recharger Chataigne avec la même copie Synchronized et lancer Sync Data.

## Taille et proportions des émetteurs dans les presets

Ouvrir **Oxipital Live Kinect Performance Emitter Size.noisette** pour la
version avec **Custom Variables > Orb1 / Orb2 > Emitter Size**. Ce vecteur est
enregistré dans tous les presets Orb1/Orb2 existants. Les presets Plane sont
initialisés à `(1, 0.5625, 1)` (16:9 XY), les autres à `(1, 1, 1)` ; aucune
autre valeur des presets, notamment Dancer Size, n'est modifiée.

- Sphere + Emitter Size `(1,1,1)` : sphère ronde.
- Plane + Emitter Size `(1,0.5625,1)` : rectangle 16:9.
- **Dancer Size** règle le rayon/demi-encombrement global. Pour remplir
  l'écran, ajuster cette taille à la caméra et à la profondeur de l'émetteur,
  puis mettre à jour le preset Orb correspondant dans Chataigne. Le ratio seul
  n'ajuste ni la taille ni le placement à la caméra.

Unity conserve le champ `OrbGroup.emitterScale` et envoie au VFX sa valeur
**normalisée par le plus grand axe absolu**, jamais sa longueur euclidienne.
`(2,2,2)` devient `(1,1,1)` ; `(16,9,16)` devient `(1,.5625,1)`.
Les axes nuls restent nuls, les signes deviennent positifs ; un vecteur
entièrement nul ou non fini revient à `(1,1,1)`. Le buffer et l'overlay utilisent
la même valeur `EffectiveEmitterScale`. Un grand ratio brut ne multiplie donc
plus le rayon des particules ou du repère. Les anciens presets qui utilisaient
Emitter Scale comme multiplicateur de taille doivent désormais utiliser
Dancer Size pour cet agrandissement.

Le module Oxipital expose aussi **Orb Groups > Orb Group N > Dancer > Emitter
Scale > Base Value**, de type Point3D avec valeur initiale `(1,1,1)`. Les deux
mappings **Orb 1/2 Emitter Size** y transmettent les valeurs des CV ; le bridge
OSCQuery existant les envoie à Unity. Cette transmission ne dépend pas de
Kinect Enabled. Le module installé possédait déjà ce paramètre et reste intact.
`Add-OrbEmitterSize.ps1` prépare la copie et `Test-OrbEmitterSize.ps1` vérifie
les presets, les liaisons et la conservation de toutes les données préexistantes.

Pour les LED physiques de l'EN16, voir [Retour LED de banque](EN16-LED-Feedback.md).
La copie Chataigne avec retour LED et le profil Grid **EN16 Abysses - Kinect LEDs v5 RGB**
sont préparés ; le guide indique comment charger le profil et tester les couleurs.

La copie **Oxipital Live Kinect Performance LEDs Controls.noisette** reprend la
dernière version **LEDs Color** enregistrée avec les boutons réordonnés ci-dessous.
Elle ajoute **Control Orb Orientation**, ses liaisons Unity et sa valeur initiale
désactivée dans les presets Kinect existants. Le profil EN16 v5 RGB reste valable.

La copie **Oxipital Live Kinect Performance Presets.noisette** reprend ensuite
la version **LEDs Controls** enregistrée avec une correction des liaisons de
presets Orb/Force. Le preset Orb1 **Meduse** contient déjà `Emitter Shape = Sphere`.
La sortie **Orb Enum > Orbs to Oxipital** ne transmettait pas la valeur du
mapping : elle utilise maintenant une affectation générique, la liste
`orbOxipital` et `value.mappingValueIndex = 0`, comme les routes numériques.
Cette sortie réapplique les enums même si la CV n'a pas changé, pour que Sphere
reprenne la main après un passage local à Plane dans Unity. Ce rafraîchissement
concerne seulement les enums de forme/rendu, pas les positions/rayons gestuels.
Les six autres sorties corrigées sont les valeurs/couleurs du preset Orb2,
les vecteurs des presets Orb1/Orb2 et les valeurs des presets Force1/Force2.
Les données des presets et leurs durées d'interpolation restent identiques.
`Repair-ShowPresetRoutes.ps1` prépare la copie et `Test-ShowPresetRoutes.ps1`
vérifie les liaisons et la conservation des autres réglages. Un test en session
reste nécessaire : passer l'émetteur à Plane dans Unity, rappeler Méduses et
vérifier **Orb Group 1 > Emitter Shape = Sphere**, y compris au deuxième rappel.

Le projet `Chataigne/Oxipital Live Kinect.noisette` est une copie du projet live
`Oxipital Live EncoderMode - Quest Reset.noisette`, avec les contrôles Kinect.
Le projet original est conservé.

## Démarrage

Pour la version avec dashboard, ouvrir explicitement **Fichier > Ouvrir** puis
`Oxipital Live Kinect Performance.noisette` dans le
dossier du projet Chataigne live. Cette copie porte un nom distinct pour éviter
qu'une session déjà ouverte réenregistre l'ancienne version sur les ajouts.
Vérifier la présence de l'onglet **Abysses Kinect** après le chargement.
Cette version corrige la condition de banque des rotations : elle doit comparer
**EN16 Kinect Bank = true**, comme les appuis, et non `false`.

1. Lancer la scène Unity avec la source Azure Kinect et le body tracking actifs.
2. Ouvrir la copie Kinect dans Chataigne. Dans le module **Oxipital**, conserver
   la connexion OSCQuery à Unity sur `localhost:8999`, puis lancer **Sync Data**.
   L'arbre doit contenir `Ballet / Optical Flow / TwoHandForceBrush`.
3. Dans **Custom Variables > Kinect**, activer **Kinect Enabled** pour donner
   le contrôle au composant Unity. Le désactiver libère les groupes et autorise
   les anciens mappings de position Leap / Quest.
4. Activer **EN16 Kinect Bank** pour affecter les rotations des 16 encodeurs aux
   réglages ci-dessous. Le désactiver restaure leur banque précédente.

Le master Kinect et le choix de banque sont indépendants des presets de scène.
Le dashboard **Abysses Kinect**, dupliqué depuis **Abysses**, présente les 16
rotations à gauche et les 16 appuis à droite. Le **bouton physique 16** bascule
entre les banques, même depuis la banque Abysses. Le bouton correspondant est
placé en position 16 sur les deux dashboards. Un appui change la banque et
sélectionne son dashboard ; le relâchement ne provoque pas un second changement.
Le sélecteur de banque change uniquement les contrôles disponibles, le dashboard
et les couleurs/retours LED. Il ne doit rappeler aucun preset ni lancer
l'initialisation. En particulier, Launch Start exige **bouton de démarrage ET
banque Abysses** : une condition OR rendrait le retour à Abysses suffisant pour
relancer le démarrage. Les deux mappings de rotation traitent les nouveaux
messages MIDI sans réémettre la dernière variation lors de leur activation.

Les appuis sont désormais routés dans des entrées internes séparées pour Abysses
et Kinect. Les actions de spectacle ne lisent plus directement le sélecteur de
banque : un bouton dont la valeur MIDI est encore mémorisée ne peut donc pas
être revalidé par le simple retour à Abysses. Deux mappings transmettent les
nouveaux messages MIDI à la banque active ; les changements de filtre de banque
n'émettent pas de valeur (`Send On Input Change Only = true`, Send On Activate
et Send After Load désactivés). Les 32 entrées internes sont remises à zéro sur
les deux transitions ; cela invalide aussi les appuis longs en cours. Ces valeurs
techniques restent hors des presets du spectacle.

Le bouton physique 16 est réservé au sélecteur et absent des entrées routées.
Le reset de paramètre de l'ancienne banque exige explicitement un appui > 0 :
une remise à zéro des entrées ne peut pas rappeler les valeurs de reset.
Les potards Kinect deviennent jaunes quand cette banque est active, et gris
quand elle est inactive. Le retour vidéo partagé est conservé en dessous.

Quand la banque Kinect est active, les appuis physiques pilotent les boutons de
la grille droite. Les actions physiques précédentes sont bloquées dans cette
banque et reprennent lorsqu'elle est désactivée.

| Bouton | Action dans la banque Kinect |
| --- | --- |
| 1 | Orb Position |
| 2 | Orb Radius |
| 3 | Orb Orientation |
| 4 | Two Hand Orbs |
| 5 | Force Position |
| 6 | Force Radius (contrôle existant intensité/rayon) |
| 7 | Force Orientation |
| 8 | Invert Gesture Intensity |
| 9 | Reset Camera |
| 10 | Sync Data |
| 11 | Show Monitor |
| 12 | Meduses |
| 13 | Kinect Enabled |
| 14 | Brush Enabled |
| 15 | Use Target Depth |
| 16 | EN16 Kinect Bank (dans les deux banques) |

**Kinect Enabled** commande `TwoHandForceBrush.remoteControlEnabled` : il active
ou désactive le composant gestuel et libère ses groupes lors de sa désactivation.
Il ne coupe pas le capteur Azure ni l'optical flow. **Brush Enabled** arme seulement
la force ; la position, le rayon et l'orientation des orbes restent indépendants.
**Orb Orientation** oriente l'Orb Group selon l'axe entre les deux mains et les
offsets d'orientation existants. Il faut deux mains valides pour modifier cette
orientation ; désactiver ce contrôle conserve la dernière orientation.
Le réglage d'intensité par l'écart des mains reste disponible dans les Custom
Variables et les presets, mais n'occupe plus de bouton physique dédié.

Les boutons de position utilisent directement les variables **Kinect**. La
recopie permanente depuis Leap Motion est retirée pour conserver ces réglages.
L'overlay des mains reste réglable dans les Custom Variables Kinect et dans
l'inspecteur/moniteur Unity. L'ancien lanceur Leap du dashboard Abysses est
remplacé par le changement de banque ; les mappings physiques précédents du
bouton 16 sont désactivés pour éviter de déclencher deux actions au même appui.

## Banque des encodeurs

L'ordre reprend les 16 canaux de la liste existante **EN16 Rotary Page 1**.

| Encodeur | Variable | Pas |
| --- | --- | --- |
| 1 | Strength | 0,01 |
| 2 | Radius Multiplier | 0,01 |
| 3 | Size Multiplier | 0,05 |
| 4 | Orb Radius Multiplier | 0,05 |
| 5 | Debug: Overlay Opacity | 0,01 |
| 6 | Flow: Intensity | 0,01 |
| 7 | Flow: Strength | 0,5 |
| 8 | Smoothing Seconds | 0,005 |
| 9 | Interaction Depth | 0,1 |
| 10 | Maximum Radius | 0,05 |
| 11 | Minimum Radius | 0,01 |
| 12 | Activation Fade Seconds | 0,01 |
| 13 | Force Group Number | 1 |
| 14 | Orb Group Number | 1 |
| 15 | Monitor Scale (zoom du moniteur) | 0,05 |
| 16 | Minimum Axis Distance | 0,005 |

**Unity Brush Index** est fixé à 0 dans cette configuration : les paramètres
de force restent gérés par les presets Chataigne existants. Le potard 15 règle
désormais le zoom du moniteur. Les numéros de groupes commencent à 1 ; choisir
un groupe réellement créé dans la scène. Maintenir Minimum Radius ≤ Maximum Radius.

Les trois **Orientation Offset X/Y/Z** sont placés à droite de la grille des
boutons, dans une colonne de contrôles rotatifs réglables à la souris. Leurs
variables et leurs valeurs dans les presets sont conservées ; les encodeurs
physiques 5/6/7 pilotent désormais les trois paramètres optical flow ci-dessus.

**Debug: Overlay Opacity** correspond à `OpticalFlowDebugView.overlayOpacity`
(0 à 1). Il règle la transparence de l'image caméra / optical flow superposée
aux particules. Il ne règle ni l'opacité du moniteur du pinceau ni celle du
plan vidéo 3D. Choisir une View autre que Off pour voir cette image.
La variable Chataigne doit s'appeler **Debug Overlay Opacity**, avec l'adresse
`/customVariables/kinect/variables/debugOverlayOpacity/debugOverlayOpacity`.
Chataigne reconstruit le conteneur interne à partir du nom affiché : nommer la
variable seulement Overlay Opacity rend cette adresse incohérente après chargement.
`Repair-KinectOverlayOpacity.ps1` corrige les fichiers déjà générés avec l'ancien
nom ; fournir des SourcePath et OutputPath distincts. Le test du dashboard
vérifie désormais aussi les adresses dérivées des noms, et pas seulement le JSON.
**Flow: Intensity** est le gain global de l'optical flow (0 à 1) ;
**Flow: Strength** règle la force de poussée en mode Add (0 à 50). En mode Wind,
Strength n'agit pas sur la composante Wind, qui conserve ses réglages propres.
Ces trois contrôles ont un retour depuis Unity, restent utilisables lorsque
Remote Control Enabled est désactivé et sont globaux : les presets de spectacle
existants ne les rappellent pas. Leurs valeurs initiales reprennent le cache
OSCQuery du fichier source ; les resets sont respectivement 0,25, 1 et 10.

### Profondeur et sélection des groupes

- **Use Target Depth** : en mode Camera Plane, place le plan d'interaction à
  la profondeur initiale du Force Group ciblé (sinon de l'Orb Group). Une
  Interaction Plane assignée dans Unity est prioritaire.
- **Interaction Depth** : distance du plan devant la caméra Unity quand
  Use Target Depth est désactivé, ou si la cible est derrière le plan proche
  de la caméra. Ce sont des unités de scène ; cela ne règle pas la portée Kinect.
- **Force Group Number / Orb Group Number** : sélectionnent les groupes pilotés,
  à partir de 1. Si une Target / Orb Target est assignée directement dans Unity,
  cette référence est prioritaire sur le numéro.
- **Minimum Axis Distance** : écart physique minimal entre les mains permettant
  de mettre à jour l'orientation du pinceau. En dessous, l'axe est figé pour
  éviter les rotations instables ; cela ne désactive pas le suivi des mains.

**Quand désactiver Use Target Depth ?** Ce bouton suppose que la position initiale
du groupe indique une bonne profondeur d'interaction avec les particules. Ce
n'est pas toujours le cas : un groupe peut être enregistré à l'origine alors
que le nuage de particules se trouve plus loin, ou différents groupes/presets
peuvent avoir des profondeurs initiales différentes. Choisir une Interaction
Depth manuelle permet alors de placer les effets dans la couche de particules
voulue et de garder la même distance quand les cibles changent.

Exemple : caméra en Z = -10 regardant vers +Z, groupe initialement en Z = 0,
particules autour de Z = 5. Use Target Depth place l'interaction à 10 unités
devant la caméra (Z = 0). Le repère peut sembler bien placé à l'écran alors que
la force reste trop loin des particules en 3D. Désactiver le bouton et choisir
Interaction Depth = 15 place le plan à Z = 5. Avec une caméra en perspective,
cette distance change aussi l'échelle en unités de scène des déplacements et
du rayon calculés depuis les mains.

La position utilisée est capturée lorsque le contrôleur se lie au groupe ; elle
ne suit pas la position que les mains animent ensuite. Si Force Group et Orb
Group sont tous deux résolus, le Force Group fournit la profondeur commune,
même quand son suivi de position est désactivé. Une Interaction Plane assignée
dans Unity remplace les deux modes. En Sensor World, ces réglages de plan
ne sont pas utilisés.

## Presets et suivi

Le groupe Kinect contient 11 presets, un par action du State **Preset**. Chaque
action rappelle son preset Kinect par une conséquence supplémentaire, avec les
mêmes paramètres de transition que son rappel du preset Leap Motion.

Dans chacun de ces presets, **Send Forces Position** et **Send Orbs Position**
reprennent initialement les activations du preset Leap correspondant. Elles
sont ensuite modifiables et enregistrables dans le preset Kinect de la scène.
Le State Presets et la conduite du spectacle continuent de rappeler les presets
de Force 1, Orb1, caméra et Kinect existants. Aucun preset de spectacle Unity
ne remplace ces rappels. L'intensité chargée ou interpolée par Chataigne est
prise en compte pendant que le pinceau reste actif.

**Control Intensity Radius**, **Control Orientation** et **Control Orb Radius**
restent des activations indépendantes, enregistrées dans les presets Kinect.
**Intensity From Hand Distance** choisit entre intensité manuelle et écart des
mains ; **Strength** multiplie cette intensité.

## Une ou deux orbes

Activer **Send Orbs Position** et utiliser le bouton 4 **Deux orbes** :

- Désactivé : un élément du groupe suit le milieu des deux mains.
- Activé : le même Orb Group contient deux éléments ; le premier suit la main
  gauche et le second la main droite. Le rendu, les couleurs, les paramètres
  physiques et le rayon sont partagés par le groupe.

Ce mode utilise la multiplication des éléments du groupe (`count = 2`). Un
pattern de position gestuel intervient après les patterns enregistrés et avant
la mise à jour du buffer VFX, sans créer un deuxième Orb Group indépendant.
L'écart des mains continue de régler le rayon commun si Control Orb Radius est
actif. Le lissage s'applique séparément à chaque main. À la perte du suivi, les
positions sont figées ; à l'arrêt du contrôle de position, le nombre d'éléments
et la répartition de taille du groupe sont restaurés.

Le réglage **Two Hand Orbs** est enregistré dans chacun des 11 presets Kinect
existants. Pour le conserver lors d'un rappel de scène, enregistrer ce preset
Kinect depuis Chataigne. Le moniteur Unity et l'overlay affichent les deux orbes.

Le State **Kinect -> Unity** envoie les réglages actifs à 30 Hz et récupère les
changements simples depuis Unity. Les offsets X/Y/Z et le choix du mode
d'intensité sont pilotés depuis Chataigne. Les mappings de position Leap / Quest
sont bloqués tant que Kinect Enabled est actif, pour éviter deux pilotes sur le
même groupe.

## Vérification

Après Sync Data, modifier Strength dans Chataigne et vérifier sa valeur dans
l'inspecteur Unity ; modifier ensuite Strength dans Unity pour tester le retour.
Activer la banque Kinect et tourner l'encodeur 1. Rappeler deux presets ayant
des activations de position différentes et vérifier les deux interrupteurs du
composant. Tester enfin Kinect Enabled désactivé pour reprendre l'ancien suivi.
Tester le bouton 16 dans les deux sens, puis le bouton 4 avec Position orbes
actif : vérifier une émission au centre puis une émission sur chaque main.
Enregistrer deux presets Kinect avec des modes d'orbes différents et les
rappeler depuis les actions Presets de la conduite.

Les scripts `Add-KinectControls.ps1` et `Test-KinectControls.ps1` permettent de
reconstruire et vérifier la copie depuis un projet live sans groupe Kinect.
Ils utilisent les paramètres `-SourcePath` et `-OutputPath`.
`Add-KinectDashboard.ps1` ajoute le dashboard et les appuis physiques à une copie
Kinect déjà enregistrée par Chataigne ; `Test-KinectDashboard.ps1` contrôle les
liaisons et la conservation du dashboard original. La copie produite est
`Chataigne/Oxipital Live Kinect Dashboard.noisette`. La génération utilise la
première copie Kinect comme référence pour restaurer les valeurs perdues lors
de la normalisation des noms internes de variables par Chataigne.
La validation automatique contrôle le JSON et les références ; le test matériel
nécessite Unity en Play et Chataigne connectés.

`Update-KinectPerformance.ps1` applique les nouvelles interactions à la dernière
copie avec dashboard ; `Test-KinectPerformance.ps1` vérifie le bouton réservé,
les couleurs, les références Kinect et la conservation des presets du spectacle.
Ils utilisent également `-SourcePath` et `-OutputPath`. Le résultat de cette
étape est `Chataigne/Oxipital Live Kinect Performance.noisette`.

`Update-KinectOpticalFlowDashboard.ps1` applique ensuite les libellés anglais,
la colonne de rotations à la souris et les contrôles optical flow sur EN16
5/6/7 à une copie Performance existante. Utiliser `-SourcePath` et `-OutputPath`
distincts. `Test-KinectOpticalFlowDashboard.ps1` vérifie les nouvelles routes,
les liaisons des widgets et la conservation des variables, presets, actions
de banque et retours LED existants.

`Repair-EN16BankIsolation.ps1` corrige les fichiers existants ayant la condition
OR de démarrage et configure les deux banques rotatives pour traiter seulement
les nouveaux messages d'entrée. Utiliser SourcePath et OutputPath distincts.
`Test-EN16BankIsolation.ps1` rejoue la logique de démarrage avec les banques
successives, vérifie les sorties UI/LED du sélecteur et contrôle la conservation
des presets, des valeurs et des autres actions du fichier live.

Pour les actions parasites restantes liées aux appuis mémorisés,
`Repair-EN16ButtonRouting.ps1` applique ensuite le routage séparé des deux
banques et retire le sélecteur des conditions des actions de spectacle.
`Test-EN16ButtonRouting.ps1` vérifie les entrées indépendantes, les transitions
avec boutons mémorisés, l'isolation caméra/presets, les resets d'entrées et la
conservation des commandes, délais, presets, dashboards et retours LED.
Cette validation de configuration ne remplace pas un essai MIDI en direct.

Pour les positions des groupes, `Repair-KinectPresetPositionRouting.ps1` retire
la première tentative qui dupliquait les mappings P3D et corrige uniquement
les calculs de position intermédiaire. Quand Kinect est actif, ou quand Kinect
et l'état Meta Quest OSC -> Oxipital sont tous deux désactivés, la position
finale reprend directement celle du preset. Le déplacement Quest est ajouté
uniquement si son état est activé et Kinect désactivé. Toutes ces branches
respectent le mode Edition Unity. Les multiplexes P3D, rotations et réglages
caméra restent ceux de la session. Le suivi Kinect dans Unity prend la main
quand Control Orb Position ou Control Force Position est actif.
Utiliser des SourcePath et OutputPath distincts ;
`Test-KinectPresetPositionRouting.ps1` vérifie les sources, les conditions et
la conservation du reste du projet. Après remplacement du fichier live,
rouvrir la session sans écraser la correction avec l'ancienne session en mémoire.

Le module Oxipital renvoie également un instantané des réglages Kinect lors
de Apply Current Values, de Sync Data et d'une reconnexion après Play. Il lit
les custom variables du spectacle directement, afin que le cache OSCQuery
n'empêche pas l'envoi d'un interrupteur inchangé. Le composant brush est
libéré avant les paramètres des groupes, puis ses réglages indépendants sont
envoyés, et son activation est envoyée en dernier. Le mode Edition Unity
bloque ces envois. `Test-KinectPresetResend.js` vérifie ce chemin avec une
Unity simulée ayant conservé des interrupteurs différents de Chataigne.
La validation dans les applications nécessite ensuite un rappel de preset.
