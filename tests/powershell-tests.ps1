#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$FixturesDir = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures'
$PowerShellExe = (Get-Process -Id $PID).Path

function New-TestWorkspace {
  $workdir = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("cc-wrap.ps." + [IO.Path]::GetRandomFileName())
  $outputDir = Join-Path -Path $workdir -ChildPath 'output'
  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

  return [pscustomobject]@{
    Workdir = $workdir
    OutputDir = $outputDir
  }
}

function Get-FixturePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RelativePath
  )

  return Join-Path -Path $FixturesDir -ChildPath $RelativePath
}

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$Content
  )

  Set-Content -LiteralPath $Path -Value $Content -Encoding utf8NoBOM -NoNewline
}

function Prepare-Config {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FixtureName,
    [Parameter(Mandatory = $true)]
    [string]$Workdir,
    [Parameter(Mandatory = $true)]
    [string]$OutputDir
  )

  $destination = Join-Path -Path $Workdir -ChildPath 'config.json'
  $config = Get-Content -LiteralPath (Get-FixturePath -RelativePath ("configs/$FixtureName")) -Raw | ConvertFrom-Json -NoEnumerate
  $config.output_dir = $OutputDir
  Write-Utf8NoBomFile -Path $destination -Content (($config | ConvertTo-Json -Depth 10) + "`n")
  return $destination
}

function Normalize-Text {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Text,
    [Parameter(Mandatory = $true)]
    [string]$OutputDir
  )

  $normalized = $Text.Replace("`r`n", "`n")
  return $normalized.Replace($OutputDir, '__OUTPUT_DIR__')
}

function Invoke-CCWrap {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $scriptPath = Join-Path -Path $ProjectRoot -ChildPath 'cc-wrap.ps1'
  $outputLines = & $PowerShellExe -NoProfile -File $scriptPath @Arguments 2>&1 | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) {
      $_.ToString()
    }
    else {
      [string]$_
    }
  }

  $outputText = ''
  if ($null -ne $outputLines) {
    $outputText = (($outputLines | ForEach-Object { $_.Replace("`r`n", "`n") }) -join "`n").TrimEnd("`n")
  }

  return [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = $outputText
  }
}

function Assert-Equal {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Expected,
    [Parameter(Mandatory = $true)]
    [string]$Actual,
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  if ($Actual -ne $Expected) {
    throw "$Label mismatch.`n--- expected ---`n$Expected`n--- actual ---`n$Actual"
  }
}

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Text,
    [Parameter(Mandatory = $true)]
    [string]$Fragment,
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  if (-not $Text.Contains($Fragment)) {
    throw "$Label did not contain expected fragment.`n--- expected fragment ---`n$Fragment`n--- actual ---`n$Text"
  }
}

function Assert-FileContentMatchesFixture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ActualPath,
    [Parameter(Mandatory = $true)]
    [string]$FixtureRelativePath
  )

  if (-not (Test-Path -LiteralPath $ActualPath -PathType Leaf)) {
    throw "Missing generated file: $ActualPath"
  }

  $expected = Get-Content -LiteralPath (Get-FixturePath -RelativePath $FixtureRelativePath) -Raw
  $actual = Get-Content -LiteralPath $ActualPath -Raw
  Assert-Equal -Expected $expected -Actual $actual -Label $ActualPath
}

function Assert-OutputMatchesFixture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ActualOutput,
    [Parameter(Mandatory = $true)]
    [string]$FixtureRelativePath,
    [Parameter(Mandatory = $true)]
    [string]$OutputDir
  )

  $expected = Get-Content -LiteralPath (Get-FixturePath -RelativePath $FixtureRelativePath) -Raw
  $expected = $expected.Replace("`r`n", "`n").TrimEnd("`n")
  $actual = Normalize-Text -Text $ActualOutput -OutputDir $OutputDir
  Assert-Equal -Expected $expected -Actual $actual -Label $FixtureRelativePath
}

function Assert-GeneratedFiles {
  param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDir,
    [Parameter(Mandatory = $true)]
    [string[]]$ExpectedNames
  )

  $actual = @(
    Get-ChildItem -LiteralPath $OutputDir -File |
      Select-Object -ExpandProperty Name |
      Sort-Object
  )
  $expected = $ExpectedNames | Sort-Object

  Assert-Equal -Expected ($expected -join "`n") -Actual ($actual -join "`n") -Label 'generated file set'
}

function Run-Test {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Action
  )

  try {
    & $Action
    Write-Host "ok - $Name"
    return $true
  }
  catch {
    Write-Host "not ok - $Name"
    Write-Host $_
    return $false
  }
}

$testsPassed = $true

$testsPassed = (Run-Test -Name 'list prints the minimal provider name' -Action {
  $workspace = New-TestWorkspace
  try {
    $config = Prepare-Config -FixtureName 'minimal.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    $result = Invoke-CCWrap -Arguments @('list', '--config', $config)
    Assert-Equal -Expected '0' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-OutputMatchesFixture -ActualOutput $result.Output -FixtureRelativePath 'expected/powershell/list/minimal.txt' -OutputDir $workspace.OutputDir
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'list prints the provider description when present' -Action {
  $workspace = New-TestWorkspace
  try {
    $config = Prepare-Config -FixtureName 'complete-single.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    $result = Invoke-CCWrap -Arguments @('list', '--config', $config)
    Assert-Equal -Expected '0' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-OutputMatchesFixture -ActualOutput $result.Output -FixtureRelativePath 'expected/powershell/list/complete-single.txt' -OutputDir $workspace.OutputDir
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'help mentions uninstall' -Action {
  $result = Invoke-CCWrap -Arguments @('--help')
  Assert-Equal -Expected '0' -Actual ([string]$result.ExitCode) -Label 'exit code'
  Assert-Contains -Text $result.Output -Fragment 'cc-wrap.ps1 uninstall [--config <path>]' -Label 'help output'
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'deploy generates the minimal wrapper script' -Action {
  $workspace = New-TestWorkspace
  try {
    $config = Prepare-Config -FixtureName 'minimal.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    $result = Invoke-CCWrap -Arguments @('deploy', '--config', $config)
    Assert-Equal -Expected '0' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-OutputMatchesFixture -ActualOutput $result.Output -FixtureRelativePath 'expected/powershell/deploy/minimal/stdout.txt' -OutputDir $workspace.OutputDir
    Assert-GeneratedFiles -OutputDir $workspace.OutputDir -ExpectedNames @('mini-code.ps1')
    Assert-FileContentMatchesFixture -ActualPath (Join-Path $workspace.OutputDir 'mini-code.ps1') -FixtureRelativePath 'expected/powershell/deploy/minimal/mini-code.ps1'
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'deploy generates the complete single-provider wrapper script' -Action {
  $workspace = New-TestWorkspace
  try {
    $config = Prepare-Config -FixtureName 'complete-single.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    $result = Invoke-CCWrap -Arguments @('deploy', '--config', $config)
    Assert-Equal -Expected '0' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-OutputMatchesFixture -ActualOutput $result.Output -FixtureRelativePath 'expected/powershell/deploy/complete-single/stdout.txt' -OutputDir $workspace.OutputDir
    Assert-GeneratedFiles -OutputDir $workspace.OutputDir -ExpectedNames @('basic-code.ps1')
    Assert-FileContentMatchesFixture -ActualPath (Join-Path $workspace.OutputDir 'basic-code.ps1') -FixtureRelativePath 'expected/powershell/deploy/complete-single/basic-code.ps1'
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'deploy generates both scripts for the multi-provider fixture' -Action {
  $workspace = New-TestWorkspace
  try {
    $config = Prepare-Config -FixtureName 'complete-multi.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    $result = Invoke-CCWrap -Arguments @('deploy', '--config', $config)
    Assert-Equal -Expected '0' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-OutputMatchesFixture -ActualOutput $result.Output -FixtureRelativePath 'expected/powershell/deploy/complete-multi/stdout.txt' -OutputDir $workspace.OutputDir
    Assert-GeneratedFiles -OutputDir $workspace.OutputDir -ExpectedNames @('glm-code.ps1', 'or-code.ps1')
    Assert-FileContentMatchesFixture -ActualPath (Join-Path $workspace.OutputDir 'glm-code.ps1') -FixtureRelativePath 'expected/powershell/deploy/complete-multi/glm-code.ps1'
    Assert-FileContentMatchesFixture -ActualPath (Join-Path $workspace.OutputDir 'or-code.ps1') -FixtureRelativePath 'expected/powershell/deploy/complete-multi/or-code.ps1'
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'deploy overwrites an existing managed wrapper script' -Action {
  $workspace = New-TestWorkspace
  try {
    $config = Prepare-Config -FixtureName 'complete-single.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    Write-Utf8NoBomFile -Path (Join-Path $workspace.OutputDir 'basic-code.ps1') -Content @'
#!/usr/bin/env pwsh
# This PowerShell script encloses its environment the way a cell encloses the sea.
Write-Host stale
'@

    $result = Invoke-CCWrap -Arguments @('deploy', '--config', $config)
    Assert-Equal -Expected '0' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-OutputMatchesFixture -ActualOutput $result.Output -FixtureRelativePath 'expected/powershell/deploy/complete-single/stdout.txt' -OutputDir $workspace.OutputDir
    Assert-FileContentMatchesFixture -ActualPath (Join-Path $workspace.OutputDir 'basic-code.ps1') -FixtureRelativePath 'expected/powershell/deploy/complete-single/basic-code.ps1'
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'deploy skips an existing unmanaged file and continues' -Action {
  $workspace = New-TestWorkspace
  try {
    $config = Prepare-Config -FixtureName 'complete-multi.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    Copy-Item -LiteralPath (Get-FixturePath -RelativePath 'expected/powershell/deploy/complete-multi/glm-code.ps1') -Destination (Join-Path $workspace.OutputDir 'glm-code.ps1')
    $originalContent = @'
#!/usr/bin/env pwsh
Write-Host custom
'@
    $originalPath = Join-Path $workspace.Workdir 'original-or-code.ps1'
    Write-Utf8NoBomFile -Path (Join-Path $workspace.OutputDir 'or-code.ps1') -Content $originalContent
    Write-Utf8NoBomFile -Path $originalPath -Content $originalContent

    $result = Invoke-CCWrap -Arguments @('deploy', '--config', $config)
    Assert-Equal -Expected '0' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-Contains -Text $result.Output -Fragment ("Skipped existing unmanaged file: " + (Join-Path $workspace.OutputDir 'or-code.ps1')) -Label 'deploy output'
    Assert-Contains -Text $result.Output -Fragment ("Generated 1 wrapper script(s) in " + $workspace.OutputDir) -Label 'deploy output'
    Assert-Contains -Text $result.Output -Fragment 'Skipped 1 existing unmanaged file(s)' -Label 'deploy output'
    Assert-GeneratedFiles -OutputDir $workspace.OutputDir -ExpectedNames @('glm-code.ps1', 'or-code.ps1')
    Assert-FileContentMatchesFixture -ActualPath (Join-Path $workspace.OutputDir 'glm-code.ps1') -FixtureRelativePath 'expected/powershell/deploy/complete-multi/glm-code.ps1'
    Assert-Equal -Expected (Get-Content -LiteralPath $originalPath -Raw) -Actual (Get-Content -LiteralPath (Join-Path $workspace.OutputDir 'or-code.ps1') -Raw) -Label 'unmanaged file'
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'deploy rejects env values that use command substitution' -Action {
  $workspace = New-TestWorkspace
  try {
    $configPath = Prepare-Config -FixtureName 'complete-single.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -NoEnumerate
    $config.providers[0].env.ANTHROPIC_AUTH_TOKEN = '$(uname -a)'
    Write-Utf8NoBomFile -Path $configPath -Content (($config | ConvertTo-Json -Depth 10) + "`n")

    $result = Invoke-CCWrap -Arguments @('deploy', '--config', $configPath)
    Assert-Equal -Expected '1' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-Contains -Text $result.Output -Fragment "Provider 'basic-code' field 'env.ANTHROPIC_AUTH_TOKEN' contains unsupported shell expansion; only `$VAR and `${VAR} are allowed" -Label 'deploy output'
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'deploy rejects env values that use backticks' -Action {
  $workspace = New-TestWorkspace
  try {
    $configPath = Prepare-Config -FixtureName 'complete-single.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -NoEnumerate
    $config.providers[0].env.ANTHROPIC_AUTH_TOKEN = '`uname -a`'
    Write-Utf8NoBomFile -Path $configPath -Content (($config | ConvertTo-Json -Depth 10) + "`n")

    $result = Invoke-CCWrap -Arguments @('deploy', '--config', $configPath)
    Assert-Equal -Expected '1' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-Contains -Text $result.Output -Fragment "Provider 'basic-code' field 'env.ANTHROPIC_AUTH_TOKEN' contains unsupported shell syntax: backticks are not allowed" -Label 'deploy output'
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'uninstall removes an existing managed wrapper script' -Action {
  $workspace = New-TestWorkspace
  try {
    $config = Prepare-Config -FixtureName 'complete-single.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    Copy-Item -LiteralPath (Get-FixturePath -RelativePath 'expected/powershell/deploy/complete-single/basic-code.ps1') -Destination (Join-Path $workspace.OutputDir 'basic-code.ps1')

    $result = Invoke-CCWrap -Arguments @('uninstall', '--config', $config)
    Assert-Equal -Expected '0' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-OutputMatchesFixture -ActualOutput $result.Output -FixtureRelativePath 'expected/powershell/uninstall/complete-single/stdout.txt' -OutputDir $workspace.OutputDir
    if (Test-Path -LiteralPath (Join-Path $workspace.OutputDir 'basic-code.ps1')) {
      throw 'Managed file was not removed'
    }
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'uninstall removes both managed scripts for the multi-provider fixture' -Action {
  $workspace = New-TestWorkspace
  try {
    $config = Prepare-Config -FixtureName 'complete-multi.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    Copy-Item -LiteralPath (Get-FixturePath -RelativePath 'expected/powershell/deploy/complete-multi/glm-code.ps1') -Destination (Join-Path $workspace.OutputDir 'glm-code.ps1')
    Copy-Item -LiteralPath (Get-FixturePath -RelativePath 'expected/powershell/deploy/complete-multi/or-code.ps1') -Destination (Join-Path $workspace.OutputDir 'or-code.ps1')

    $result = Invoke-CCWrap -Arguments @('uninstall', '--config', $config)
    Assert-Equal -Expected '0' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-OutputMatchesFixture -ActualOutput $result.Output -FixtureRelativePath 'expected/powershell/uninstall/complete-multi/stdout.txt' -OutputDir $workspace.OutputDir
    if (Test-Path -LiteralPath (Join-Path $workspace.OutputDir 'glm-code.ps1')) {
      throw 'Managed file glm-code.ps1 was not removed'
    }
    if (Test-Path -LiteralPath (Join-Path $workspace.OutputDir 'or-code.ps1')) {
      throw 'Managed file or-code.ps1 was not removed'
    }
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

$testsPassed = (Run-Test -Name 'uninstall skips unmanaged files, reports missing files, and continues' -Action {
  $workspace = New-TestWorkspace
  try {
    $configPath = Prepare-Config -FixtureName 'complete-multi.json' -Workdir $workspace.Workdir -OutputDir $workspace.OutputDir
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -NoEnumerate
    $missingProvider = [pscustomobject]@{
      script_name = 'missing-code'
      env = [pscustomobject]@{
        ANTHROPIC_BASE_URL = 'https://example.com'
        ANTHROPIC_AUTH_TOKEN = 'token'
      }
    }
    $config.providers += $missingProvider
    Write-Utf8NoBomFile -Path $configPath -Content (($config | ConvertTo-Json -Depth 10) + "`n")

    Copy-Item -LiteralPath (Get-FixturePath -RelativePath 'expected/powershell/deploy/complete-multi/glm-code.ps1') -Destination (Join-Path $workspace.OutputDir 'glm-code.ps1')
    $originalContent = @'
#!/usr/bin/env pwsh
Write-Host custom
'@
    $originalPath = Join-Path $workspace.Workdir 'original-or-code.ps1'
    Write-Utf8NoBomFile -Path (Join-Path $workspace.OutputDir 'or-code.ps1') -Content $originalContent
    Write-Utf8NoBomFile -Path $originalPath -Content $originalContent

    $result = Invoke-CCWrap -Arguments @('uninstall', '--config', $configPath)
    Assert-Equal -Expected '0' -Actual ([string]$result.ExitCode) -Label 'exit code'
    Assert-Contains -Text $result.Output -Fragment ("Skipped existing unmanaged file: " + (Join-Path $workspace.OutputDir 'or-code.ps1')) -Label 'uninstall output'
    Assert-Contains -Text $result.Output -Fragment ("Missing file: " + (Join-Path $workspace.OutputDir 'missing-code.ps1')) -Label 'uninstall output'
    Assert-Contains -Text $result.Output -Fragment ("Removed 1 wrapper script(s) from " + $workspace.OutputDir) -Label 'uninstall output'
    Assert-Contains -Text $result.Output -Fragment 'Skipped 1 existing unmanaged file(s)' -Label 'uninstall output'
    Assert-Contains -Text $result.Output -Fragment 'Missing 1 file(s)' -Label 'uninstall output'
    if (Test-Path -LiteralPath (Join-Path $workspace.OutputDir 'glm-code.ps1')) {
      throw 'Managed file glm-code.ps1 was not removed'
    }
    Assert-Equal -Expected (Get-Content -LiteralPath $originalPath -Raw) -Actual (Get-Content -LiteralPath (Join-Path $workspace.OutputDir 'or-code.ps1') -Raw) -Label 'unmanaged file'
  }
  finally {
    Remove-Item -LiteralPath $workspace.Workdir -Recurse -Force
  }
}) -and $testsPassed

if (-not $testsPassed) {
  exit 1
}
