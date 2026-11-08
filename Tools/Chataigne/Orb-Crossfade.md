# Transitions par Chute

Ouvrir **Oxipital Live Kinect Performance Transitions.noisette**. Cette copie
part de la session live **Synchronized** du 8 novembre 2026, en conservant ses
derniers réglages et ses dashboards.

La conduite reste : Méduses → Chute → Cascade → Chute → Tornade → Chute →
Tourbillon → Cercle. Les trois cues Chute relancent la même timeline et ont
des adresses distinctes ; le bouton EN16 conserve la première adresse.

Chute et Chute - Start utilisent maintenant **Orb2 / Force2**. Leurs valeurs
sont des copies exactes des presets Orb1 / Force1, qui restent conservés.
Les presets Kinect correspondants ciblent les groupes 2. La montée de Chute
reste pilotée par sa courbe de timeline sur dix secondes. L'initialisation
précède désormais le premier point de cette courbe.

Chaque rappel d'une scène qui utilise une seule orb, depuis Presets ou une
timeline du spectacle, arrête les autres timelines, annule les interpolations
précédentes, puis lance **Transition Release** sur l'orb sortante. Ce preset
amène son intensité courante à zéro en **10 secondes** ; tous ses autres
paramètres ont le mode **None**. La forme, les couleurs et les positions ne
sont donc pas remplacées par celles de Chute pendant la disparition. Le
groupe de forces sortant suit le même fondu, sauf quand la scène entrante
charge explicitement ce groupe comme arrière-plan (Tourbillon).

La commande immédiate Tourbillon Background Off est remplacée par ce fondu.
Les scènes qui chargent volontairement les deux orbs gardent leur comportement.
Les fondus utilisent les interpolations natives de Chataigne ; une nouvelle
scène annule le fondu précédent avant de charger ses valeurs.

Le sélecteur de presets et Update Chute / Update Chute - Start enregistrent
maintenant Force2, Orb2 et Kinect. Les nouveaux presets créés avec Save restent
sur Force1 / Orb1 et reçoivent aussi le fondu de sortie de dix secondes.

Préparation : `Add-OrbCrossfade.ps1 -SourcePath <session> -OutputPath <copie>`.
Le paramètre `-FadeDuration` règle la durée des fondus générés pour les actions
existantes. Pour les nouveaux presets créés avec Save, la durée est définie
dans `PresetAuthoring.js` (10 secondes).

Validation : `Test-OrbCrossfade.ps1` contrôle les clones, les modes de fondu,
les routes Kinect/Update, l'arrêt des timelines concurrentes, la conduite et
la conservation des presets, modules et dashboards. `Test-PresetAuthoring.js`
vérifie l'enregistrement des deux paires Orb/Force et la création de scènes.

À vérifier dans Unity : Méduses → Chute → Cascade, puis Cascade → Chute →
Tornade → Chute → Tourbillon ; interrompre aussi un fondu à mi-parcours et
rappeler Chute plusieurs fois. Les vérifications automatiques ne mesurent pas
le rendu visuel ni la durée de vie des particules déjà émises. Le contrôle
gestuel Kinect passe au groupe de la scène entrante ; l'orb sortante poursuit
sa disparition avec ses derniers réglages de preset.

## Direction Force2 et Chute - End

La copie **Oxipital Live Kinect Performance Chute End.noisette** reprend la
dernière sauvegarde live de Transitions. Elle ajoute **Force 2 > Linear
Direction**, son mapping vers Unity et son retour en mode Edition Unity.
Les directions vides sont complétées depuis les presets Force1 de même nom,
ou avec `(0,0,0)` lorsqu'il n'existe pas de valeur correspondante. Pour Chute
et Chute - Start, la direction reprend `(0,1,0)`. Transition Release garde
ce champ en mode None.

**Chute - End** copie Chute dans Force2, Orb2 et Kinect. Seule **Force2 >
Linear Intensity** passe à **1**. Le preset dispose de ses entrées de rappel,
de sélection et de mise à jour.

Dans la séquence **Chute**, la couche **Morph Chute vers Chute - End** prend
le relais à **10,1 s**, quand la première montée est terminée, et atteint End
à **15,1 s**. Déplacer le dernier point horizontalement pour changer les cinq
secondes de durée ; modifier l'interpolation des points pour changer la
progression. Les deux couches ont des filtres de phase exclusifs basés sur le
temps de la séquence : la première ne réécrit pas Chute pendant le morph End.
Si l'on déplace aussi le début de cette seconde phase, déplacer le dernier
point de la première courbe et ajuster la référence des deux filtres de phase
au même instant. Les pauses et déplacements dans la timeline utilisent le
temps de la séquence, sans minuterie indépendante.

`Add-ChuteEndMorph.ps1` prépare cette copie ; `Test-ChuteEndMorph.ps1` vérifie
les directions, les deux sens de liaison Unity, les clones End, les phases,
le rappel/Update et la conservation de toutes les autres données de la session.

## Courbes libres et sortie adoucie

La copie **Oxipital Live Kinect Performance Chute Flexible.noisette** reprend
la sauvegarde live de Chute End, y compris les courbes raccourcies/modifiées.
Elle remplace les anciennes conditions fixes par une référence au premier
point de **Morph Chute vers Chute - End**. Déplacer ce point déplace donc aussi
le relais entre les deux couches, sans modifier de seuil à la main. La première
couche écrit avant ce point, la seconde à partir de ce point. Les positions et
interpolations des points sauvegardés restent inchangées. Si les courbes se
chevauchent, la seconde prend la priorité dès son premier point.

Les adresses stables utilisées par la référence sont `chuteEndMorph` pour la
couche et `phaseStart` pour le point. Déplacer ou renommer ce point conserve
la référence ; si on le supprime et le recrée, il faut refaire cette référence.

Les deux couches ont **Send On Stop = false** : arrêter Chute transmet ses
dernières valeurs appliquées au fondu sortant sans réémettre la courbe pendant
l'arrêt/rembobinage. Play et Seek conservent leurs comportements existants.

**Force2 > Transition Release** interpole maintenant l'intensité générale et
l'intensité linéaire vers zéro. Le nombre de forces, la rotation et la direction
restent ignorés pendant ce rappel. Les rappels Force2 Release existants ont
une courbe Bézier à pente nulle au début et à la fin ; leur durée est conservée.
Le rappel Force2 Tourbillon est remplacé par ce fondu dans Presets et dans la
timeline Tourbillon : son preset sauvegardé demande zéro force et coupait donc
la force sortante pendant l'interpolation. Les valeurs sauvegardées du preset
Tourbillon lui-même restent conservées.

Préparer avec `Repair-ChuteFlexibleMorph.ps1`, vérifier avec
`Test-ChuteFlexibleMorph.ps1`. Ce dernier conserve les courbes utilisateur,
vérifie les références aux points, simule le relais pour plusieurs déplacements
et retours dans le temps, et contrôle les fondus et les presets sauvegardés.
Le résultat visuel doit toujours être vérifié dans Unity.
