param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$RemoteHost = '127.0.0.1',
    [int]$RemotePort = 8999
)

$ErrorActionPreference = 'Stop'
$sourceFullPath = (Resolve-Path -LiteralPath $SourcePath).Path
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if ($sourceFullPath -eq $outputFullPath) { throw 'Write to a separate output file; keep the original session intact.' }
$project = [IO.File]::ReadAllText($sourceFullPath) | ConvertFrom-Json

function Get-ShortName([string]$name) {
    $name = $name -replace '[^\p{L}\p{Nd}_]', ''
    if (!$name) { throw 'Empty control name' }
    return $name.Substring(0, 1).ToLowerInvariant() + $name.Substring(1)
}

# Custom Variable groups are now /customVariables/group/variables/variable/parameter.
# Resolve each legacy address against real variables, rather than just changing a prefix.
$addressMap = @{}
foreach ($group in $project.customVariables.items) {
    $groupName = Get-ShortName $group.niceName
    foreach ($variable in $group.variables.items) {
        foreach ($parameter in $variable.parameters) {
            $parameterName = $parameter.controlAddress.TrimStart('/')
            $variableName = Get-ShortName $variable.niceName
            $addressMap[('/customVariables/customVariables/values/' + $groupName + '/' + $parameterName)] =
                '/customVariables/' + $groupName + '/variables/' + $variableName + '/' + $parameterName
        }
    }
}

$script:migratedReferences = 0
$script:unresolvedReferences = [Collections.Generic.HashSet[string]]::new()
function Repair-References($node) {
    if ($null -eq $node -or $node -is [string] -or $node -is [ValueType]) { return }
    if ($node -is [Array]) {
        for ($i = 0; $i -lt $node.Count; $i++) {
            if ($node[$i] -is [string] -and $addressMap.ContainsKey($node[$i])) {
                $node[$i] = $addressMap[$node[$i]]
                $script:migratedReferences++
            } else { Repair-References $node[$i] }
        }
        return
    }
    foreach ($property in $node.PSObject.Properties) {
        if ($property.Value -is [string]) {
            if ($addressMap.ContainsKey($property.Value)) {
                $property.Value = $addressMap[$property.Value]
                $script:migratedReferences++
            } elseif ($property.Value.StartsWith('/customVariables/customVariables/values/')) {
                $null = $script:unresolvedReferences.Add($property.Value)
            }
        } else { Repair-References $property.Value }
    }
}
Repair-References $project

$oxipital = @($project.modules.items | Where-Object niceName -eq 'Oxipital')
$encoder = @($project.modules.items | Where-Object niceName -eq 'EN16')
if ($oxipital.Count -ne 1 -or $encoder.Count -ne 1) { throw 'Expected exactly one Oxipital module and one EN16 MIDI module.' }
$oxipital = $oxipital[0]
$encoder = $encoder[0]
$bridge = @($oxipital.scripts.items | Where-Object niceName -eq 'Oxipital')
if ($bridge.Count -ne 1) { throw 'Oxipital module script not found.' }
$scriptEnabled = $bridge[0].parameters | Where-Object controlAddress -eq '/enabled'
if (!$scriptEnabled) { throw 'Oxipital script enabled parameter not found.' }
$scriptEnabled.value = $true

$outputParameters = $oxipital.params.containers.output.parameters
($outputParameters | Where-Object controlAddress -eq '/remoteHost').value = $RemoteHost
($outputParameters | Where-Object controlAddress -eq '/remotePort').value = $RemotePort

$state = $project.states.items | Where-Object niceName -eq 'EN16 -> CV'
$mux = $state.processors.items | Where-Object type -eq 'Multiplex'
$rotaries = $mux.containers.lists.items | Where-Object niceName -eq 'EN16 Rotary Page 1'
$buttons = $mux.containers.lists.items | Where-Object niceName -eq 'EN16 Button Page 1'
$targets = $mux.containers.lists.items | Where-Object niceName -eq 'Target Force 1'
if (!$rotaries -or !$buttons -or !$targets) { throw 'EN16 multiplex lists not found.' }
if ($rotaries.parameters.Count -ne 16 -or $buttons.parameters.Count -ne 16 -or $targets.parameters.Count -ne 16) {
    throw 'Expected 16 EN16 rotary, button and target references.'
}

for ($i = 0; $i -lt 16; $i++) {
    $ccAddress = $rotaries.parameters[$i].value -replace '^/modules/en16/values', ''
    $cc = @($encoder.values.parameters | Where-Object { $_.controlAddress -eq $ccAddress -and $_.MIDIType -eq 2 })
    if ($cc.Count -ne 1) { throw ('EN16 rotary does not resolve: ' + $ccAddress) }
    $note = @($encoder.values.parameters | Where-Object {
        $_.MIDIType -eq 0 -and $_.channel -eq $cc[0].channel -and $_.pitchOrNumber -eq $cc[0].pitchOrNumber
    })
    if ($note.Count -ne 1) { throw ('EN16 push button does not resolve: ' + $ccAddress) }
    $buttons.parameters[$i].value = '/modules/en16/values' + $note[0].controlAddress
    $buttons.parameters[$i].PSObject.Properties.Remove('ghostValue')
    # Relative encoders can send the same increment on successive ticks.
    $cc[0] | Add-Member -NotePropertyName alwaysNotify -NotePropertyValue $true -Force
    if ($targets.parameters[$i].value.StartsWith('/customVariables/customVariables/values/')) {
        throw ('Unresolved EN16 target: ' + $targets.parameters[$i].value)
    }
}

# Input-relative mode is already correct: binary offset, neutral 64. Preserve its
# subtraction, sensitivity, button condition, reset values and disabled feedback.
$json = $project | ConvertTo-Json -Depth 100 -Compress
$null = $json | ConvertFrom-Json
$outputDirectory = Split-Path -Parent $outputFullPath
if (!(Test-Path -LiteralPath $outputDirectory)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
[IO.File]::WriteAllText($outputFullPath, $json, [Text.UTF8Encoding]::new($false))
[PSCustomObject]@{
    Source = $sourceFullPath
    Output = $outputFullPath
    MigratedReferences = $script:migratedReferences
    UnresolvedLegacyReferences = @($script:unresolvedReferences)
    RotaryBindings = 16
    ButtonBindings = 16
    RemoteHost = $RemoteHost
    RemotePort = $RemotePort
    BridgeEnabled = $scriptEnabled.value
} | ConvertTo-Json -Depth 4
