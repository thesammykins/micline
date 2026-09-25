$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
try {
    $bin = (& swift build -c release --show-bin-path).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate the release executable' }
    $payload = Join-Path $PSScriptRoot 'dist/MicLine'
    if (Test-Path $payload) { Remove-Item -Recurse -Force $payload }
    New-Item -ItemType Directory -Force $payload | Out-Null
    Copy-Item "$bin/MicLine.exe" $payload
    $exe = Join-Path $payload 'MicLine.exe'
    & mt.exe -nologo -manifest MicLine.manifest "-outputresource:$exe;#1"
    if ($LASTEXITCODE -ne 0) { throw 'Could not embed Windows manifest' }
    # SwiftPM builds a console entry point; retain that entry and suppress a console
    # window for desktop launches. Self-tests still return an observable exit code.
    & editbin.exe /SUBSYSTEM:WINDOWS $exe
    if ($LASTEXITCODE -ne 0) { throw 'Could not set desktop subsystem' }

    $runtimeDirs = @($bin) + @($env:Path -split ';' | Where-Object { $_ -and (Test-Path $_) })
    $crt = Get-ChildItem (Join-Path $env:VCToolsRedistDir 'x64') -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
    if (!$crt) { throw 'MSVC x64 redistributable directory is unavailable' }
    $runtimeDirs = @($crt.FullName) + $runtimeDirs
    $pending = [System.Collections.Generic.Queue[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # Swift also installs LLVM inspection tools; use the MSVC PE dependency reader.
    $dumpbin = Join-Path $env:VCToolsInstallDir 'bin/Hostx64/x64/dumpbin.exe'
    $pending.Enqueue($exe)
    while ($pending.Count) {
        $binary = $pending.Dequeue()
        $imports = & $dumpbin /DEPENDENTS $binary 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect ${binary}: $($imports -join [Environment]::NewLine)" }
        foreach ($line in $imports) {
            if ($line -notmatch '^\s+([\w.+-]+\.dll)\s*$') { continue }
            $name = $Matches[1]
            if (!$seen.Add($name)) { continue }
            if ($name -match '^(api-ms-|ext-ms-)') { continue }
            $source = $null
            foreach ($dir in $runtimeDirs) {
                $candidate = Join-Path $dir $name
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $source = $candidate; break }
            }
            if (!$source) { throw "Unresolved runtime dependency: $name" }
            if ($name -match '^(msvcp|vcruntime|concrt)' -and !$source.StartsWith($crt.FullName, [StringComparison]::OrdinalIgnoreCase)) {
                throw "MSVC dependency must come from the redistributable directory: $name"
            }
            if ($source.StartsWith($env:WINDIR, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($name -notmatch '^(swift|Foundation|_Foundation|dispatch|BlocksRuntime|icu|msvcp|vcruntime|concrt)') {
                throw "Review redistribution terms before packaging $name"
            }
            $dest = Join-Path $payload $name
            Copy-Item -LiteralPath $source -Destination $dest
            $pending.Enqueue($dest)
        }
    }
    Copy-Item ../LICENSE "$payload/LICENSE.txt"
    Copy-Item ../NOTICE "$payload/NOTICE.txt"
    Copy-Item README.md "$payload/TESTING.md"
    # Official toolchain license includes the Swift runtime exception.
    Invoke-WebRequest 'https://raw.githubusercontent.com/swiftlang/swift/swift-6.2.3-RELEASE/LICENSE.txt' -OutFile "$payload/Swift-LICENSE.txt"
    "MicLine Windows test build`nSource: $(& git rev-parse HEAD)`nSwift: 6.2.3 x64`nUnsigned tester build" | Set-Content "$payload/BUILD.txt"
    Copy-Item "$payload/BUILD.txt" 'dist/BUILD.txt'
    # This cannot prove a clean-machine install, but catches undeclared PATH DLLs.
    $savedPath = $env:Path
    try {
        $env:Path = "$env:WINDIR\System32;$env:WINDIR"
        $test = Start-Process $exe -ArgumentList '--self-test' -Wait -PassThru
        if ($test.ExitCode -ne 0) { throw "Packaged offline test failed: $($test.ExitCode)" }
        Write-Host 'Packaged offline self-test passed without developer PATH'
    } finally { $env:Path = $savedPath }
    Get-ChildItem $payload -File | ForEach-Object { 'Delete "$INSTDIR\' + $_.Name + '"' } | Set-Content 'dist/uninstall-files.nsh'
    & "${env:ProgramFiles(x86)}\NSIS\makensis.exe" installer.nsi
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
    Compress-Archive -Path "$payload/*" -DestinationPath 'dist/MicLine-Windows-x64-Portable.zip' -Force
    Get-ChildItem dist -File | Where-Object { $_.Extension -in '.exe', '.zip' } | ForEach-Object {
        $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)" | Set-Content "$($_.FullName).sha256"
    }
} finally { Pop-Location }
