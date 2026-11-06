# Retour de banque sur les LED de l'EN16

La copie `Chataigne/Oxipital Live Kinect Performance LEDs.noisette` envoie le
signal de banque. Le profil correspondant est
`Chataigne/EN16/EN16 Abysses - Kinect LEDs v5 RGB.json`, dérivé de la sauvegarde complète
effectuée avec Grid Editor 1.6.2 et le firmware 1.5.0 de l'EN16.

Le module MIDI **EN16** utilise déjà **Intech Grid MIDI device** comme sortie.
L'action **Show Active EN16 Bank** contient deux conséquences supplémentaires :

| Banque | Canal MIDI | CC | Valeur |
| --- | --- | --- | --- |
| Kinect | 16 | 119 | 127 |
| Abysses | 16 | 119 | 0 |

Ces messages expriment une banque ; ils sont interprétés par le profil modifié.
Les notes des boutons et les CC des encodeurs restent sur leur canal initial.
L'état est envoyé au changement de banque et répété à 1 Hz pour retrouver les
couleurs après une reconnexion USB ou le chargement d'un profil.

### Correction du flash jaune suivi du bleu

La copie `Oxipital Live Kinect Performance LEDs Resync.noisette` reprend la
dernière copie LEDs enregistrée et corrige uniquement le filtre **Bank to CC
value**, dans **Kinect EN16 > EN16 LED Bank Resync**. Son multiplicateur vaut
127 dans `filterParams.parameters` et dans `operationValue`. Chataigne recrée
ce paramètre dynamique depuis `operationValue` au chargement : omettre ce
champ faisait revenir le multiplicateur à zéro, donc renvoyait périodiquement
le CC119=0 (palette Abysses) après le CC119=127 du changement de banque.
La copie enregistrée par Chataigne confirmait un multiplicateur à 0.

Pour corriger directement la session ouverte, régler **Value** à **127** sur
ce filtre Math puis enregistrer. Le profil Grid v4 peut rester en place.
Les quatre pages natives sélectionnées par le bouton latéral de l'EN16
sont distinctes de la banque logicielle Abysses/Kinect : le profil modifié
s'applique à la page sur laquelle il a été chargé, actuellement la page 1.

`Repair-EN16LedResync.ps1` prépare une copie corrigée sans changer les autres
données de la session et vérifie les deux représentations sauvegardées du
multiplicateur ainsi que la conversion des banques vers 0/127.
[Chargement/sauvegarde du paramètre Math dans Chataigne](https://github.com/benkuper/Chataigne/blob/master/Source/Common/Processor/Mapping/Filter/filters/number/MathFilter.cpp).

## Charger la copie dans Grid Editor

1. Utiliser Grid Editor **1.6.2**, sans mise à jour du firmware pour cette étape.
2. Dans **My Configs**, sélectionner **EN16 Abysses - Kinect LEDs v5 RGB**. Le profil
   original sauvegardé reste disponible séparément.
3. Charger cette copie sur l'EN16 et sur la même page que celle utilisée pour
   Chataigne, actuellement la page **1**. Les affectations automatiques dépendent
   de la page : ne pas choisir une autre page pour ce test.
4. Ouvrir **Oxipital Live Kinect Performance LEDs Color.noisette** dans Chataigne.
5. Tester les couleurs et les commandes, puis utiliser **Store** dans Grid Editor
   pour rendre la copie persistante sur cette page du contrôleur.

Le fichier de sauvegarde d'origine reste indépendant de cette copie. Charger
un profil l'applique au contrôleur pour le tester ; Store le conserve après
déconnexion. Pour revenir en arrière, charger le profil original sur la même
page puis Store.

## Choisir la couleur depuis Chataigne

La copie **LEDs Color** ajoute le sélecteur **Couleur LED Kinect** à droite du
dashboard **Abysses Kinect**, sous les réglages d'orientation. La même couleur
est accessible dans **Custom Variables > Kinect > EN16 LED Color**.
Le jaune est la valeur initiale ; les composantes RGB pilotent les LED, et
l'alpha du sélecteur est ignoré. Le noir éteint les LED en banque Kinect.
La banque Abysses conserve la palette automatique du profil d'origine.

Le profil **v5 RGB** est nécessaire une seule fois pour recevoir ces réglages.
Sur le canal MIDI 16, CC116/117/118 portent respectivement rouge/vert/bleu
(0..127), convertis en 0..255 dans le firmware. CC119 conserve son rôle de
sélection de banque. Les mappings **EN16 LED Red/Green/Blue** extraient les
composantes du paramètre Color avec un filtre **Mega Converter**, une sortie Float
et un lien explicite `sourceValueIndex` 0/1/2, puis les multiplient par 127 en
sauvegardant aussi `operationValue`. Le sélecteur dynamique de **Convert To Float**
perdait ses options après chargement (`retarget:null`) : les trois sorties
lisaient la même composante, produisant du blanc avec une luminosité variable.
Les indices fixes évitent cette dépendance à un enum reconstruit au chargement.
Le type sérialisé doit être exactement `Mega Converter` : `Conversion` est
le nom interne de la classe, et Chataigne supprime ce type non enregistré au
chargement, laissant seulement le filtre Math et éteignant les LED.
La couleur et la banque sont répétées à 1 Hz pour retrouver l'état après
reconnexion ou rechargement de page, y compris si le contrôleur est rebranché
alors que la couleur n'a pas changé.

`Add-EN16LedColor.ps1` ajoute ces contrôles à une copie de la session enregistrée.
La v5 conserve les commandes natives validées sur la v4. Les tests Lua vérifient
les composantes RGB, noir/blanc, les couleurs pendant les interactions et les
changements de banque, ainsi que le filtrage MIDI et l'absence d'écho.

## Fonctionnement du profil

La fonction `self.midirx_cb` est définie dans **System > Setup** et reconnaît
uniquement le CC119 du canal 16. La v4 utilise directement les fonctions natives
`glc`, `glf`, `gls` et `glp`, sur les adresses physiques 0 à 15 de l'EN16.
En banque Kinect, elle éteint la couche bouton et allume la couche encodeur
en jaune fixe (255,210,0), phase 255, sans animation. Ces commandes ont été
validées par un test manuel sur une LED du contrôleur. En banque Abysses, elle
restaure la palette automatique et les phases calculées depuis les valeurs
bouton/encodeur (plages 0..127 du profil original). Les actions de couleur des 16
encodeurs et 16 appuis consultent le même état pour conserver le jaune lors des
interactions. Le réglage automatique des couleurs revient sur Abysses.
La luminosité devient fixe sur Kinect et retrouve son comportement habituel sur
Abysses. Les réglages MIDI/mode/sensibilité sont conservés. Les autres
événements, dont la réception MIDI existante, restent présents.

La première version utilisait à tort l'ancien événement MIDI RX. La v2 utilisait
l'ordre des arguments de la documentation récente. La v3 est vérifiée contre
le code officiel **v1.5.0**, dont `pass_midi` appelle
`self.midirx_cb(self, event, header)` : le message de quatre valeurs est premier,
l'en-tête de trois valeurs est second. Elle utilise également la table native
`ele` du firmware, sans dépendre du nom long `element` côté éditeur.
Le canal MIDI 16 correspond à `event[1] == 15`, le CC à `event[2] == 176` et
`event[3] == 119`, et sa valeur à `event[4]`. La page démarre dans ses couleurs
habituelles puis reçoit la banque active de Chataigne.
La v3 recevait correctement les messages mais ne changeait pas les LED sur le
contrôleur. La cause précise dans le chemin des fonctions `self:glc`/`self:glp`
reste indéterminée ; la v4 emploie le chemin natif validé physiquement.
Le Setup affiche `Oxipital LEDs: init v4 Native`. Après application des couleurs,
un changement reçu affiche `Oxipital LEDs v4: 127` ou `Oxipital LEDs v4: 0`.

Sources fabricant : [réception MIDI](https://docs.intech.studio/wiki/more/midi-rx/),
[couleur des LED](https://docs.intech.studio/wiki/actions/led/simple-led-color/).
[Migration vers le callback, réponse Intech](https://forum.intech.studio/t/cannot-update-pbf4-firmware/803).
[Décodeur exact du firmware v1.5.0](https://github.com/intechstudio/grid-fw/blob/v1.5.0/grid_common/lua_src/decode.lua).

## Test une fois le profil installé

Ouvrir la copie avec retour LED et basculer une fois le bouton Bank dans chaque
sens. Vérifier le jaune sur Kinect, les couleurs d'origine sur Abysses et la
conservation des couleurs lors des rotations et appuis. Vérifier également le
comportement après reconnexion USB ; la répétition à 1 Hz renvoie l'état.

## Génération et vérifications

`Add-EN16KinectLedProfile.ps1` construit un profil distinct depuis la sauvegarde
et refuse une palette personnalisée non reconnue. Il vérifie les 68 événements,
la conservation des commandes hors LED et la limite de 908 caractères par
script (moins de 908 caractères). Le contrôle de régression vérifie que le callback
est dans Setup et que la réception des banques ne dépend plus de l'événement legacy.

`Test-EN16LedProfile.js` exécute le profil avec les fichiers **decode.lua** et
**simplecolor.lua** officiels du tag **v1.5.0**, dans un interpréteur Lua Fengari.
Seules les fonctions natives d'accès au matériel sont remplacées pour observer
les couleurs, phases et émissions MIDI. Le test reproduit l'échec de la v2,
puis vérifie les messages 127/0, mauvais canal/CC/commande ignorés, couleurs des
16 LED, rotations/appuis, phases actualisées, absence d'écho MIDI et
réinitialisation/resynchronisation. Pour la v4, les fonctions de couleur des
éléments sont volontairement remplacées par des erreurs afin de vérifier leur
absence d'utilisation. Le test contrôle aussi le jaune à pleine phase lorsque
les encodeurs valent zéro et la restauration de la luminosité sur Abysses.
Les appels natifs sont simulés ; ce test ne remplace pas la
confirmation sur le contrôleur physique.

Commande : `node Tools/Chataigne/Test-EN16LedProfile.js chemin/fengari-web.js chemin/sources-fw150 chemin/profil.json`.
Ajouter `--expect-broken` avec le profil v2 pour le test de non-régression.

`Add-EN16BankLedFeedback.ps1` ajoute les deux conséquences MIDI et le mapping
de resynchronisation. Les contrôles et presets existants sont préservés. Le
rendu physique des LED doit être validé sur le contrôleur.
