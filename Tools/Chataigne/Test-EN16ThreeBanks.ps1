param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Assert($ok,$message){if(!$ok){throw $message}}
function V($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
$before=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$p=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8|ConvertFrom-Json
$bankAddress='/customVariables/en16Banks/variables/bank/bank'
$new=$p.customVariables.items|Where-Object shortName -eq en16Banks
Assert (@($new).Count -eq 1) 'Missing bank group'
Assert (($new.variables.items|Where-Object shortName -eq bank).type -eq 'Int Parameter') 'Bank uses unsupported native variable type'
Assert (@($new.variables.items|Where-Object shortName -like 'fluidButton*').Count -eq 16) 'Missing Fluides virtual inputs'
Assert (!$new.presets.items.Count) 'Controller bank/color should remain global'
$ks=$p.states.items|Where-Object shortName -eq kinectEN16
$as=$p.states.items|Where-Object niceName -eq 'EN16 -> Oxipital CV'
$fs=$p.states.items|Where-Object niceName -eq 'EN16 -> CV OpticalFluid'
$ds=$p.states.items|Where-Object niceName -eq Dashboard
$state=$p.states.items|Where-Object shortName -eq en16Banks
$muxes=@(($as.processors.items|Where-Object type -eq Multiplex),($ks.processors.items|Where-Object type -eq Multiplex),($fs.processors.items|Where-Object type -eq Multiplex))
foreach($bank in 0..2){
    $active=0
    foreach($index in 0..2){
        $mux=$muxes[$index]
        $route=$mux.containers.processors.items|Where-Object niceName -eq 'Route EN16 Buttons'
        Assert ((V $route.params '/sendOnInputChangeOnly') -eq $true -and (V $route.params '/sendOnActivate') -eq $false -and (V $route.params '/sendAfterLoad') -eq $false) 'Button router could replay a cached press'
        $gate=$route.filters.items|Where-Object {$_.conditions.items.parameters.value -contains $bankAddress}
        Assert (@($gate).Count -eq 1) 'Missing explicit bank gate'
        $ref=V $gate.conditions.items[0].comparator '/reference'
        Assert ((V $gate.conditions.items[0].comparator '/comparisonFunction') -eq '=' -and $ref -eq $index) 'Bank selector gate is incorrect'
        if($ref -eq $bank){$active++}
        $physical=$mux.containers.lists.items|Where-Object shortName -eq en16PhysicalButtons
        Assert ($physical.parameters.Count -eq 16) 'Missing native physical note list'
        Assert ($physical.parameters[3].value -notlike '/modules/en16/*') 'Bank note reaches scene button router'
        foreach($i in 0..15|Where-Object {$_ -ne 3}){Assert ($physical.parameters[$i].value -like '/modules/en16/values/_1_*') 'Other native page still required'}
    }
    Assert ($active -eq 1) 'One press can reach multiple banks'
    $a=$state.processors.items|Where-Object shortName -eq "applyBank$bank"
    Assert ((V $a.conditions.items[0] '/inputValue') -eq $bankAddress -and (V $a.conditions.items[0].comparator '/reference') -eq $bank) 'Wrong bank apply event'
    Assert (@($a.consequences.items|Where-Object commandType -eq Script).Count -eq 0) 'Bank application still depends on script traversal'
    $expected=@('showEN16Abysses','showEN16Kinect','showEN16Fluides')[$bank]
    $targetDashboard=@('/abysses','/abyssesKinect','/abyssesFluides')[$bank]
    $selected=@($a.consequences.items|Where-Object {($_.commandType -eq 'Select Dashboard' -and (V $_.command '/dashboard') -eq $targetDashboard) -or (V $_.command '/target') -eq ('/states/dashboard/processors/'+$expected+'/trigger')})
    Assert ($selected.Count -eq 1) 'Bank action does not natively select the matching dashboard'
}
Assert (!($ks.processors.items|Where-Object niceName -eq 'Show Active EN16 Bank')) 'Binary bank action still active'
Assert (!($ds.processors.items|Where-Object shortName -like 'en16NativePage*')) 'Old native-page selectors still active'
$switch=$ks.processors.items|Where-Object shortName -eq switchEN16Bank
Assert ((V $switch.conditions.items[0] '/inputValue') -eq '/modules/en16/values/_1_B1') 'Physical selector moved from slot 4'
Assert ((V $switch.consequences.items[0].command.script.scriptParams '/operation') -eq 'cycle') 'Bank still toggles a Boolean'
foreach($mapping in $fs.processors.items|Where-Object type -eq Mapping){
    $raw=V $mapping.im.items[0] '/inputValue'
    Assert ($raw -notlike '/modules/en16/values/_2_*') 'Fluides still needs native page 2'
    if($raw -like '/modules/en16/values/_1_CC*'){
        $gate=$mapping.filters.items|Where-Object niceName -eq 'Software Bank Gate'
        Assert ((V $gate.conditions.items[0].comparator '/reference') -eq 2) 'Fluides rotary modifies values outside its bank'
        Assert ((V $mapping.params '/sendOnInputChangeOnly') -eq $true) 'Relative encoder can be replayed on gate changes'
        $old=($before.states.items|Where-Object niceName -eq 'EN16 -> CV OpticalFluid').processors.items|Where-Object niceName -eq $mapping.niceName
        Assert ((Json $old.outputs) -ceq (Json $mapping.outputs)) 'Fluides rotary target or component changed'
    }
}
foreach($action in $fs.processors.items|Where-Object type -eq Action){foreach($c in $action.conditions.items){
    Assert ((V $c '/inputValue') -notlike '/modules/en16/values/_2_*') 'Fluides action still reads native page 2'
    if((V $c '/inputValue') -like '*fluidButton*'){
        Assert ((V $c.comparator '/comparisonFunction') -eq '>' -and (V $c.comparator '/reference') -eq 0) 'Cleared inputs can recall Fluides presets'
        Assert ((V $c '/inputValue') -ne '/customVariables/en16Banks/variables/fluidButton4/fluidButton4') 'Fluides action conflicts with Bank'
    }
}}
foreach($dash in $p.dashboardManager.items|Where-Object niceName -in @('Abysses','Abysses Kinect','AbyssesFluides')){
    $w=@($dash.itemManager.items|Where-Object {(V $_ '/target') -eq '/states/kinectEN16/processors/switchEN16Bank/trigger'})
    Assert ($w.Count -eq 1 -and $w[0].type -eq 'DashboardTriggerItem') 'Missing cycle button on a dashboard'
    $orange=V $w[0] '/backgroundColor'
    Assert ($orange[0] -eq 1 -and $orange[1] -gt 0.39 -and $orange[1] -lt 0.4 -and $orange[2] -eq 0) 'Bank UI is not orange'
}
$fd=$p.dashboardManager.items|Where-Object niceName -eq AbyssesFluides
$picker=$fd.itemManager.items|Where-Object shortName -eq fluidesLEDColor
Assert ((V $picker '/target') -eq '/customVariables/en16Banks/variables/fluidLEDColor/fluidLEDColor') 'Missing independent Fluides LED color picker'
$resync=$ks.processors.items|Where-Object shortName -eq en16LEDBankResync
Assert ((V $resync.im.items[0] '/inputValue') -eq $bankAddress -and !($resync.filters.items|Where-Object type -eq Math)) 'LED bank packets are still binary 0/127'
foreach($color in @('Red','Green','Blue')){
    $k=$ks.processors.items|Where-Object shortName -eq ('en16LED'+$color)
    $f=$state.processors.items|Where-Object shortName -eq ('fluidLED'+$color)
    $component=@('Red','Green','Blue').IndexOf($color)
    Assert ((V $k.outputs.items[0].command '/ccNumber') -eq (116+$component)) 'Kinect RGB channel range changed'
    Assert ((V $f.outputs.items[0].command '/ccNumber') -eq (112+$component)) 'Fluides still shares the Kinect RGB channels'
    Assert (!($k.filters.items|Where-Object niceName -eq 'Software Bank Gate') -and !($f.filters.items|Where-Object niceName -eq 'Software Bank Gate')) 'Inactive bank color caches cannot refresh'
}
# Every saved artistic preset and every pre-existing current CV value is preserved.
foreach($g in $before.customVariables.items){
    $after=$p.customVariables.items|Where-Object niceName -eq $g.niceName
    Assert ((Json $g.presets) -ceq (Json $after.presets)) ('Saved presets changed: '+$g.niceName)
    foreach($cv in $g.variables.items){
        $newcv=$after.variables.items|Where-Object niceName -eq $cv.niceName
        Assert ((Json @($cv.parameters.value)) -ceq (Json @($newcv.parameters.value))) ('Current values changed: '+$cv.niceName)
    }
}
foreach($section in @('sequences','modules')){Assert ((Json $before.$section) -ceq (Json $p.$section)) "Changed $section"}
Assert ((Json ($before.states.items|Where-Object niceName -eq Conduite)) -ceq (Json ($p.states.items|Where-Object niceName -eq Conduite))) 'Show buttons or Conduite changed'
foreach($g in $before.dashboardManager.items|Where-Object niceName -notin @('Abysses','Abysses Kinect','AbyssesFluides')){Assert ((Json $g) -ceq (Json ($p.dashboardManager.items|Where-Object niceName -eq $g.niceName))) 'Unrelated dashboard changed'}
'EN16_THREE_BANKS_PASS: exclusive event/rotary gates, preserved Fluides targets, 48 cleared-input contracts, cycle buttons, isolated LED streams, presets/current values/sequences/Conduite preserved.'
