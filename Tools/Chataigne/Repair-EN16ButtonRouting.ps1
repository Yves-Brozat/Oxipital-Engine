param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$sourceFull=(Resolve-Path -LiteralPath $SourcePath).Path
$outputFull=[IO.Path]::GetFullPath($OutputPath)
if($sourceFull -eq $outputFull){throw 'Use a separate output file.'}
$p=[IO.File]::ReadAllText($sourceFull)|ConvertFrom-Json
function Copy-Node($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress|ConvertFrom-Json}
function Put($n,$key,$value){$n|Add-Member -NotePropertyName $key -NotePropertyValue $value -Force}
function Param($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function Set-Parameter($n,$key,$value){
    $param=$n.parameters|Where-Object controlAddress -eq $key
    if($param){$param.value=$value}else{Put $n parameters (@($n.parameters|Where-Object{$null -ne $_})+@((Param $key $value)))}
}
function CV($key){'/customVariables/kinect/variables/'+$key+'/'+$key}
function Button-Key($side,$index){'en16'+$side+'Button'+$index}
$bankAddress=CV en16KinectBank
$g=$p.customVariables.items|Where-Object niceName -eq Kinect
$kinect=$p.states.items|Where-Object shortName -eq kinectEN16
$show=$kinect.processors.items|Where-Object niceName -eq 'Show Active EN16 Bank'
$kmux=$kinect.processors.items|Where-Object type -eq Multiplex
$amux=($p.states.items|Where-Object niceName -eq 'EN16 -> Oxipital CV').processors.items|Where-Object type -eq Multiplex
if(!$g -or !$show -or !$kmux -or !$amux){throw 'Expected Performance dashboards and both EN16 multiplexes.'}
if($g.variables.items|Where-Object shortName -eq en16AbyssesButton1){throw 'Button event routing already installed.'}
$physical=@(($kmux.containers.lists.items|Where-Object niceName -eq 'EN16 Button Page 1').parameters|ForEach-Object{$_.value})
if($physical.Count -ne 16){throw 'Expected 16 physical button addresses.'}
$reserved=$physical[15]
$resetCommands=@()
foreach($side in @('Abysses','Kinect')){
    foreach($i in 1..16){
        $key=Button-Key $side $i
        $name='en16 '+$side+' Button '+$i
        $v=Copy-Node ($g.variables.items|Where-Object shortName -eq forceGroupNumber)
        $v.niceName=$name;$v.shortName=$key
        $param=$v.parameters[0];$param.niceName=$name;$param.controlAddress='/'+$key
        Put $param value 0;Put $param default 0;Put $param minValue 0;Put $param maxValue 127
        Put $param description 'Internal bank-routed MIDI input. Cleared on bank changes; excluded from show presets.'
        Put $v hideInEditor $true
        $g.variables.items+=@($v)
        $resetCommands+=@([pscustomobject]@{
            niceName='Clear '+$side+' Button '+$i;type='Consequence';commandModule='generic';commandPath='';commandType='Set Parameter Value'
            command=[pscustomobject]@{parameters=@((Param '/target' (CV $key)),(Param '/component' 'All'),(Param '/operator' 'Equals'),(Param '/value' 0));paramLinks=[pscustomobject]@{}}
        })
    }
}
# Actions no longer subscribe to the bank selector. Their physical inputs
# become virtual notes, populated only by actual MIDI events in that bank.
$script:rewired=0
function Rewire-Actions($nodes){foreach($n in $nodes){
    if($n.type -eq 'Action' -and $n.niceName -ne 'Show Active EN16 Bank'){
        $gates=@($n.conditions.items|Where-Object{($_.parameters|Where-Object controlAddress -eq '/inputValue').value -eq $bankAddress})
        if($gates.Count){
            $side=if(($gates[0].comparator.parameters|Where-Object controlAddress -eq '/reference').value){'Kinect'}else{'Abysses'}
            $n.conditions.items=@($n.conditions.items|Where-Object{
                $input=($_.parameters|Where-Object controlAddress -eq '/inputValue').value
                $input -ne $bankAddress -and $input -ne $reserved
            })
            foreach($condition in $n.conditions.items){
                $input=($condition.parameters|Where-Object controlAddress -eq '/inputValue').value
                $index=[Array]::IndexOf($physical,$input)
                if($index -ge 0){Set-Parameter $condition '/inputValue' (CV (Button-Key $side ($index+1)))}
                if($n.niceName -eq 'Force1 Reset' -and $condition.type -eq 'From Multiplex List'){
                    # Reset only on a deliberate press, never on a routed zero.
                    Set-Parameter $condition.comparator '/comparisonFunction' '>'
                }
            }
            $script:rewired++
        }
    }
    if($n.processors.items){Rewire-Actions $n.processors.items}
    if($n.containers.processors.items){Rewire-Actions $n.containers.processors.items}
    if($n.states.items){Rewire-Actions $n.states.items}
}}
Rewire-Actions $p.states.items
foreach($side in @('Abysses','Kinect')){
    $mux=if($side -eq 'Abysses'){$amux}else{$kmux}
    $buttons=$mux.containers.lists.items|Where-Object niceName -eq 'EN16 Button Page 1'
    $physicalList=Copy-Node $buttons
    $physicalList.niceName='en16 Physical Buttons'
    Put $physicalList shortName en16PhysicalButtons
    # Slot 16 belongs exclusively to Switch EN16 Bank, never to either bank.
    $physicalList.parameters[15].value=CV (Button-Key $side 16)
    foreach($i in 1..16){$buttons.parameters[$i-1].value=CV (Button-Key $side $i)}
    $mux.containers.lists.items+=@($physicalList)
    $gate=[pscustomobject]@{niceName='Button Bank Gate';type='Condition';filterParams=[pscustomobject]@{paramLinks=[pscustomobject]@{}};conditions=[pscustomobject]@{items=@([pscustomobject]@{
        niceName='From Input Value';type='From Input Value';parameters=@((Param '/inputValue' $bankAddress))
        comparator=[pscustomobject]@{parameters=@((Param '/comparisonFunction' '='),(Param '/reference' ($side -eq 'Kinect')));hideInEditor=$true}
    })}}
    $route=[pscustomobject]@{
        niceName='Route EN16 Buttons';shortName='routeEN16Buttons';type='Mapping';editorIsCollapsed=$true
        im=[pscustomobject]@{items=@([pscustomobject]@{niceName='Physical Buttons';type='Input List';parameters=@((Param '/inputList' '/en16PhysicalButtons'))})}
        params=[pscustomobject]@{parameters=@((Param '/sendOnInputChangeOnly' $true),(Param '/sendOnOutputChangeOnly' $false),(Param '/sendOnActivate' $false),(Param '/sendAfterLoad' $false),(Param '/forceContinuousProcess' $false))}
        filters=[pscustomobject]@{items=@($gate)}
        outputs=[pscustomobject]@{items=@([pscustomobject]@{
            niceName='Routed Button';type='BaseItem';commandModule='generic';commandPath='';commandType='Set Parameter Value'
            command=[pscustomobject]@{parameters=@((Param '/component' 'All'),(Param '/operator' 'Equals'));paramLinks=[pscustomobject]@{
                target=[pscustomobject]@{linkType=2;list='en16ButtonPage1'}
                value=[pscustomobject]@{linkType=1;mappingValueIndex=0}
            }}
        })}
    }
    $mux.containers.processors.items+=@($route)
}
# Clear held/routed inputs on BOTH transitions. Zero cannot validate a press
# and also cancels long-press validation timers, without touching show values.
$show.consequences.items=@($resetCommands)+@($show.consequences.items)
$show.consequencesOff.items=@((Copy-Node $resetCommands))+@($show.consequencesOff.items)
[IO.File]::WriteAllText($outputFull,($p|ConvertTo-Json -Depth 100 -Compress),[Text.UTF8Encoding]::new($false))
"EN16_BUTTON_ROUTING_REPAIRED: $script:rewired actions isolated; 32 internal note values, two event-only routers, held inputs cleared on both bank transitions."
