param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $ScriptPath))
function Replace-Function([string]$name, [string]$replacement) {
    $pattern = '(?ms)^function ' + [regex]::Escape($name) + '\([^\r\n]*\)\s*\{.*?^\}'
    $matches = [regex]::Matches($script:source, $pattern)
    if ($matches.Count -ne 1) { throw "Expected one function $name" }
    $script:source = [regex]::Replace($script:source, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }.GetNewClosure())
}
Replace-Function 'update' @'
function update(deltaTime)
{
	if (syncRequestTime >= 0 && util.getTime() >= syncRequestTime) {
		syncRequestTime = -1;
		structureReceived = false;
		local.parameters.syncData.trigger();
		return;
	}
	// Structure and connection callbacks can arrive in either order.
	// Push once, from update, after the final structure has been applied.
	if (pushOnNextStructure && structureReceived && syncRequestTime < 0) {
		pushOnNextStructure = false;
		pushAllToUnity();
	}
}
'@
Replace-Function 'dataStructureEvent' @'
function dataStructureEvent() {
	// This response satisfies a reconnect request even when the socket
	// opened before Chataigne dispatched the structure callback.
	syncRequestTime = -1;
	structureReceived = false;
	var countsChanged = linkUnity();
	if (countsChanged) {
		if (!countResyncRequested) {
			countResyncRequested = true;
			requestSync(0.5);
		} else {
			script.logWarning("Unity group counts are not ready; use Sync Data to retry");
		}
		return;
	}
	countResyncRequested = false;
	structureReceived = true;
	pushOnNextStructure = true;
}
'@
Replace-Function 'onConnected' @'
function onConnected() {
	// requestStructure() dispatches its result asynchronously, while the
	// WebSocket opens independently. Give that callback time to arrive.
	if (!structureReceived && syncRequestTime < 0) requestSync(0.5);
}
'@
$oldCallback = @'
	if (param.is(local.parameters.syncData)) {
		pushOnNextStructure = true;
	} else if (param.is(local.parameters.isConnected)) {
		if (param.get()) onConnected();
'@
$newCallback = @'
	if (param.is(local.parameters.syncData)) {
		pushOnNextStructure = true;
		structureReceived = false;
	} else if (param.is(local.parameters.isConnected)) {
		if (param.get()) onConnected();
		else structureReceived = false;
'@
# Normalize newlines only for matching the known callback block.
$source = $source.Replace("`r`n", "`n")
$oldCallback = $oldCallback.Replace("`r`n", "`n")
$newCallback = $newCallback.Replace("`r`n", "`n")
if ($source.Contains($oldCallback)) { $source = $source.Replace($oldCallback, $newCallback) }
elseif (!$source.Contains($newCallback)) { throw 'Unexpected connection callback; no output written' }
$outputAbsolute = [IO.Path]::GetFullPath($OutputPath)
[IO.File]::WriteAllText($outputAbsolute, $source.Replace("`n", "`r`n"), [Text.UTF8Encoding]::new($false))
Write-Output "Prepared sync lifecycle repair: $outputAbsolute"
