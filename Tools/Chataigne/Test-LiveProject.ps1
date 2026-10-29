param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$FixedPath
)
$ErrorActionPreference = 'Stop'
function Assert($condition, [string]$message) { if (!$condition) { throw $message } }
$source = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourcePath)) | ConvertFrom-Json
$fixedText = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $FixedPath))
$fixed = $fixedText | ConvertFrom-Json
Assert ($fixed.modules.items.Count -eq $source.modules.items.Count) 'Module count changed.'
Assert ($fixed.states.items.Count -eq $source.states.items.Count) 'State count changed.'
Assert ($fixed.customVariables.items.Count -eq $source.customVariables.items.Count) 'Custom Variable group count changed.'
Assert ($fixed.sequences.items.Count -eq $source.sequences.items.Count) 'Sequence count changed.'
Assert (!$fixedText.Contains('/customVariables/customVariables/values/')) 'Unresolved legacy Custom Variable addresses.'

$module = $fixed.modules.items | Where-Object niceName -eq Oxipital
$script = $module.scripts.items | Where-Object niceName -eq Oxipital
Assert (($script.parameters | Where-Object controlAddress -eq '/enabled').value -eq $true) 'Oxipital script disabled.'
Assert (($module.params.containers.output.parameters | Where-Object controlAddress -eq '/remoteHost').value -eq '127.0.0.1') 'Incorrect Unity host.'
Assert (($module.params.containers.output.parameters | Where-Object controlAddress -eq '/remotePort').value -eq 8999) 'Incorrect Unity port.'

$encoder = $fixed.modules.items | Where-Object niceName -eq EN16
$mux = ($fixed.states.items | Where-Object niceName -eq 'EN16 -> CV').processors.items | Where-Object type -eq Multiplex
$sourceMux = ($source.states.items | Where-Object niceName -eq 'EN16 -> CV').processors.items | Where-Object type -eq Multiplex
$rotaries = $mux.containers.lists.items | Where-Object niceName -eq 'EN16 Rotary Page 1'
$buttons = $mux.containers.lists.items | Where-Object niceName -eq 'EN16 Button Page 1'
$targets = $mux.containers.lists.items | Where-Object niceName -eq 'Target Force 1'
$sourceRotaries = $sourceMux.containers.lists.items | Where-Object niceName -eq 'EN16 Rotary Page 1'
$increments = $mux.containers.lists.items | Where-Object niceName -eq 'Increment Value'
Assert ($rotaries.parameters.Count -eq 16 -and $buttons.parameters.Count -eq 16 -and $targets.parameters.Count -eq 16) 'EN16 binding count changed.'

for ($i = 0; $i -lt 16; $i++) {
    $rotary = $rotaries.parameters[$i]
    $button = $buttons.parameters[$i]
    Assert ($rotary.value -eq $sourceRotaries.parameters[$i].value) 'Physical encoder order changed.'
    $ccAddress = $rotary.value -replace '^/modules/en16/values', ''
    $noteAddress = $button.value -replace '^/modules/en16/values', ''
    $cc = @($encoder.values.parameters | Where-Object controlAddress -eq $ccAddress)
    $note = @($encoder.values.parameters | Where-Object controlAddress -eq $noteAddress)
    Assert ($cc.Count -eq 1 -and $note.Count -eq 1) 'EN16 MIDI input reference does not resolve.'
    Assert ($cc[0].MIDIType -eq 2 -and $note[0].MIDIType -eq 0) 'Encoder/button MIDI message types do not match.'
    Assert ($cc[0].channel -eq $note[0].channel -and $cc[0].pitchOrNumber -eq $note[0].pitchOrNumber) 'Push button is bound to another physical encoder.'
    Assert ($cc[0].alwaysNotify -eq $true) 'Repeated relative ticks would be discarded.'
    Assert (!$button.ghostValue) 'Stale MIDI Fighter button reference.'
    $parts = $targets.parameters[$i].value.Split('/')
    Assert ($parts.Length -eq 6 -and $parts[3] -eq 'variables') 'Incorrect Custom Variable address shape.'
    # Resolve against the actual saved group/variable/parameter definitions.
    $group = $fixed.customVariables.items | Where-Object {
        (($_.niceName -replace '[^\p{L}\p{Nd}_]', '').ToLowerInvariant()) -eq $parts[2].ToLowerInvariant()
    }
    $variable = $group.variables.items | Where-Object {
        (($_.niceName -replace '[^\p{L}\p{Nd}_]', '').ToLowerInvariant()) -eq $parts[4].ToLowerInvariant()
    }
    Assert ($null -ne ($variable.parameters | Where-Object controlAddress -eq ('/' + $parts[5]))) 'EN16 destination variable does not exist.'
    $step = [double]$increments.parameters[$i].value
    Assert ($step -gt 0) 'Encoder increment must be positive.'
    Assert ([Math]::Abs(((65 - 64) * $step) - $step) -lt .000001) 'Clockwise relative increment is incorrect.'
    Assert ([Math]::Abs(((63 - 64) * $step) + $step) -lt .000001) 'Counterclockwise relative increment is incorrect.'
}

$rotaryMapping = $mux.containers.processors.items | Where-Object niceName -eq 'Force1 MIDI Rotary'
$offset = ($rotaryMapping.filters.items | Where-Object niceName -eq 'Math 1').filterParams.parameters | Where-Object controlAddress -eq '/value'
Assert ($offset.value -eq -64) 'Relative binary-offset decoding changed.'
$feedback = $mux.containers.processors.items | Where-Object niceName -eq 'Force1 MIDI Feedback'
Assert (($feedback.parameters | Where-Object controlAddress -eq '/enabled').value -eq $false) 'Relative MIDI feedback was unexpectedly enabled.'
'CHATAIGNE_REPAIR_PASS: host, script, 16 rotary/button/target bindings, relative decoding and session structure.'
