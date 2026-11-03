param([string]$UnityEditorData)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$project = Join-Path $repo 'Unity Oxipital/Oxipital-Engine'
if (-not $UnityEditorData) {
    $versionLine = Get-Content (Join-Path $project 'ProjectSettings/ProjectVersion.txt') |
        Where-Object { $_ -match '^m_EditorVersion:' }
    $version = ($versionLine -split ':', 2)[1].Trim()
    $UnityEditorData = Join-Path $env:ProgramFiles "Unity/Hub/Editor/$version/Editor/Data"
}
$dotnet = Join-Path $UnityEditorData 'NetCoreRuntime/dotnet.exe'
$compiler = Join-Path $UnityEditorData 'DotNetSdkRoslyn/csc.dll'
$reference = Join-Path $UnityEditorData 'UnityReferenceAssemblies/unity-4.8-api'
if (-not (Test-Path -LiteralPath $compiler)) { throw "Unity C# compiler not found: $compiler" }

$testOutput = Join-Path ([IO.Path]::GetTempPath()) ('OxipitalKinectTests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testOutput | Out-Null
$assembly = Join-Path $testOutput 'KinectFramePumpTests.dll'
$flow = Join-Path $project 'Assets/Scripts/OpticalFlow'
& $dotnet $compiler -nologo -target:library -nostdlib+ "-out:$assembly" `
    "-r:$(Join-Path $reference 'mscorlib.dll')" "-r:$(Join-Path $reference 'System.dll')" `
    (Join-Path $flow 'KinectV2Capture.cs') (Join-Path $flow 'KinectV2FramePump.cs') `
    (Join-Path $flow 'AzureKinectCapture.cs') `
    (Join-Path $flow 'AzureBodyTracking.cs') `
    (Join-Path $flow 'OpticalFlowVideoMapping.cs') `
    (Join-Path $PSScriptRoot 'KinectFramePumpTests.cs')
if ($LASTEXITCODE -ne 0) { throw 'Kinect frame pump test compilation failed' }
Add-Type -Path $assembly
[KinectFramePumpTests]::Run()
