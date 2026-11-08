param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$FocusScriptPath
)
$ErrorActionPreference='Stop'
function Json($n){ConvertTo-Json -InputObject $n -Depth 100 -Compress}
function Clone($n){Json $n|ConvertFrom-Json}
function P($key,$value){[pscustomobject]@{controlAddress=$key;value=$value}}
function V($n,$key){($n.parameters|Where-Object controlAddress -eq $key).value}
function Command($label,$module,$path,$type,$parameters){[pscustomobject]@{niceName=$label;type='Consequence';commandModule=$module;commandPath=$path;commandType=$type;command=[pscustomobject]@{parameters=@($parameters);paramLinks=[pscustomobject]@{}}}}
if([IO.Path]::GetFullPath($SourcePath) -eq [IO.Path]::GetFullPath($OutputPath)){throw 'Prepare a separate output.'}
$p=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8|ConvertFrom-Json
$state=$p.states.items|Where-Object shortName -eq en16Banks
$dashboard=$p.states.items|Where-Object niceName -eq Dashboard
$targets=@('/abysses','/abyssesKinect','/abyssesFluides')
$names=@('showEN16Abysses','showEN16Kinect','showEN16Fluides')
# FocusScriptPath is retained for old callers. Bank changes now only select
# dashboard content: no restoration, foreground helper or tab activation.
foreach($bank in 0..2){
    $action=$state.processors.items|Where-Object shortName -eq "applyBank$bank"
    if(@($action).Count -ne 1){throw 'Missing bank apply action.'}
    $native=@(
        (Command ('Selectionner '+$targets[$bank]) 'generic' '' 'Select Dashboard' @((P '/dashboard' $targets[$bank]),(P '/setInClients' $true)))
    )
    # Native bank selection is visible directly in Apply Bank, after clearing
    # held inputs and setting compatibility, without a helper action address.
    $kept=@($action.consequences.items|Where-Object {
        $_.commandType -eq 'Set Parameter Value' -and ((V $_.command '/target') -match '^/customVariables/|^/dashboards/abyssesKinect/dashboard/rotary')
    })
    if(@($kept|Where-Object {(V $_.command '/target') -like '/customVariables/*'}).Count -ne 49){throw 'Expected 48 input clears and the Kinect compatibility value.'}
    $action.consequences.items=@($kept)+$native
    # Keep other explicit uses of the previous helper actions consistent.
    $helper=$dashboard.processors.items|Where-Object shortName -eq $names[$bank]
    if($helper){$helper.consequences.items=$native}
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(Json $p),[Text.UTF8Encoding]::new($false))
'EN16_DASHBOARD_SELECTION_READY: explicit Select Dashboard in each Apply Bank; no window restoration, foreground activation or helper process.'
