#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CCWrapGeneratedPowerShellScriptSignature = 'This PowerShell script encloses its environment the way a cell encloses the sea.'
$script:AllowedModelKeys = @('default', 'reasoning', 'opus', 'sonnet', 'haiku')
$script:ModelEnvNameMap = [ordered]@{
  default   = 'ANTHROPIC_MODEL'
  reasoning = 'ANTHROPIC_REASONING_MODEL'
  opus      = 'ANTHROPIC_DEFAULT_OPUS_MODEL'
  sonnet    = 'ANTHROPIC_DEFAULT_SONNET_MODEL'
  haiku     = 'ANTHROPIC_DEFAULT_HAIKU_MODEL'
}

function Exit-WithError {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  [Console]::Error.WriteLine("Error: $Message")
  exit 1
}

function Show-Usage {
  @'
Usage:
  cc-wrap.ps1 deploy [--config <path>]
  cc-wrap.ps1 uninstall [--config <path>]
  cc-wrap.ps1 list [--config <path>]
  cc-wrap.ps1 --help

Commands:
  deploy    Generate PowerShell wrapper scripts for all configured providers
  uninstall Remove managed PowerShell wrapper scripts for all configured providers
  list      List configured providers

Options:
  --config <path>  Path to config file (default: ./cc-wrap.json)
  -h, --help       Show this help message
'@.TrimEnd()
}

function Parse-Arguments {
  param(
    [string[]]$Arguments
  )

  $configPath = './cc-wrap.json'
  $command = $null
  $index = 0

  while ($index -lt $Arguments.Count) {
    $argument = $Arguments[$index]

    switch ($argument) {
      'deploy' {
        if ($null -ne $command) {
          Exit-WithError 'Only one command may be specified'
        }
        $command = $argument
        $index += 1
      }
      'uninstall' {
        if ($null -ne $command) {
          Exit-WithError 'Only one command may be specified'
        }
        $command = $argument
        $index += 1
      }
      'list' {
        if ($null -ne $command) {
          Exit-WithError 'Only one command may be specified'
        }
        $command = $argument
        $index += 1
      }
      '--config' {
        if ($index + 1 -ge $Arguments.Count) {
          Exit-WithError '--config requires a path'
        }
        $configPath = $Arguments[$index + 1]
        $index += 2
      }
      '-h' {
        Show-Usage
        exit 0
      }
      '--help' {
        Show-Usage
        exit 0
      }
      default {
        Exit-WithError "Unknown argument: $argument"
      }
    }
  }

  if ($null -eq $command) {
    Show-Usage
    exit 1
  }

  [pscustomobject]@{
    Command = $command
    ConfigPath = $configPath
  }
}

function Test-JsonObject {
  param($Value)

  return $Value -is [pscustomobject]
}

function Get-JsonTypeName {
  param($Value)

  if ($null -eq $Value) {
    return 'null'
  }
  if ($Value -is [string]) {
    return 'string'
  }
  if ($Value -is [bool]) {
    return 'boolean'
  }
  if ($Value -is [System.Collections.IList]) {
    return 'array'
  }
  if (Test-JsonObject $Value) {
    return 'object'
  }

  return $Value.GetType().Name
}

function Test-HasProperty {
  param(
    $Object,
    [Parameter(Mandatory = $true)]
    [string]$PropertyName
  )

  if ($null -eq $Object) {
    return $false
  }

  return $null -ne $Object.PSObject.Properties[$PropertyName]
}

function Get-PropertyValue {
  param(
    $Object,
    [Parameter(Mandatory = $true)]
    [string]$PropertyName
  )

  $property = $Object.PSObject.Properties[$PropertyName]
  if ($null -eq $property) {
    return $null
  }

  return $property.Value
}

function Resolve-HomePath {
  param(
    [AllowNull()]
    [string]$Value
  )

  if ($null -eq $Value) {
    return $null
  }
  if ($Value -eq '~') {
    return $HOME
  }
  if ($Value.StartsWith('~/')) {
    $childPath = $Value.Substring(2).Replace('/', [IO.Path]::DirectorySeparatorChar)
    return Join-Path -Path $HOME -ChildPath $childPath
  }

  return $Value
}

function Test-UsesOnlyEnvReferences {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Value
  )

  $remainder = $Value

  while ($true) {
    $dollarIndex = $remainder.IndexOf('$')
    if ($dollarIndex -lt 0) {
      return $true
    }

    $remainder = $remainder.Substring($dollarIndex)

    if ($remainder -match '^\$\{[A-Za-z_][A-Za-z0-9_]*\}(.*)$') {
      $remainder = $Matches[1]
      continue
    }

    if ($remainder -match '^\$[A-Za-z_][A-Za-z0-9_]*(.*)$') {
      $remainder = $Matches[1]
      continue
    }

    return $false
  }
}

function Validate-ExpandableValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptName,
    [Parameter(Mandatory = $true)]
    [string]$FieldName,
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Value
  )

  if ($Value.Contains('`')) {
    Exit-WithError "Provider '$ScriptName' field '$FieldName' contains unsupported shell syntax: backticks are not allowed"
  }

  if ($Value.Contains('$') -and -not (Test-UsesOnlyEnvReferences -Value $Value)) {
    Exit-WithError "Provider '$ScriptName' field '$FieldName' contains unsupported shell expansion; only `$VAR and `${VAR} are allowed"
  }
}

function Convert-ToSingleQuotedLiteral {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  return "'" + $Value.Replace("'", "''") + "'"
}

function Convert-ShellValueToPowerShellExpression {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Value,
    [switch]$TreatLeadingTildeAsHome
  )

  if ($Value.Length -eq 0) {
    return "''"
  }

  $parts = [System.Collections.Generic.List[string]]::new()
  $index = 0

  if ($TreatLeadingTildeAsHome.IsPresent) {
    if ($Value -eq '~') {
      return '$HOME'
    }
    if ($Value.StartsWith('~/')) {
      $parts.Add('$HOME')
      $index = 1
    }
  }

  while ($index -lt $Value.Length) {
    $dollarIndex = $Value.IndexOf('$', $index)

    if ($dollarIndex -lt 0) {
      $literalValue = $Value.Substring($index)
      if ($literalValue.Length -gt 0) {
        $parts.Add((Convert-ToSingleQuotedLiteral -Value $literalValue))
      }
      break
    }

    if ($dollarIndex -gt $index) {
      $literalValue = $Value.Substring($index, $dollarIndex - $index)
      if ($literalValue.Length -gt 0) {
        $parts.Add((Convert-ToSingleQuotedLiteral -Value $literalValue))
      }
    }

    if ($Value.Substring($dollarIndex) -match '^\$\{([A-Za-z_][A-Za-z0-9_]*)\}') {
      $parts.Add(('${env:{0}}' -f $Matches[1]))
      $index = $dollarIndex + $Matches[0].Length
      continue
    }

    if ($Value.Substring($dollarIndex) -match '^\$([A-Za-z_][A-Za-z0-9_]*)') {
      $parts.Add(('$env:{0}' -f $Matches[1]))
      $index = $dollarIndex + $Matches[0].Length
      continue
    }

    Exit-WithError "Unsupported expandable value: $Value"
  }

  if ($parts.Count -eq 0) {
    return "''"
  }
  if ($parts.Count -eq 1) {
    return $parts[0]
  }

  return ($parts -join ' + ')
}

function Validate-ConfigFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
  )

  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    Exit-WithError "Config file not found: $FilePath"
  }

  try {
    $config = Get-Content -LiteralPath $FilePath -Raw | ConvertFrom-Json -NoEnumerate
  }
  catch {
    Exit-WithError "Config file is not valid JSON: $FilePath"
  }

  if (-not (Test-JsonObject $config)) {
    Exit-WithError 'Config root must be an object'
  }

  $providers = @(Get-PropertyValue -Object $config -PropertyName 'providers')
  if (($providers -isnot [System.Collections.IList]) -or $providers.Count -le 0) {
    Exit-WithError 'Config must define a non-empty providers array'
  }

  return $config
}

function Validate-Provider {
  param(
    [Parameter(Mandatory = $true)]
    $Provider,
    [Parameter(Mandatory = $true)]
    [int]$ProviderIndex
  )

  $scriptName = [string](Get-PropertyValue -Object $Provider -PropertyName 'script_name')
  if ([string]::IsNullOrEmpty($scriptName)) {
    Exit-WithError "Provider #$ProviderIndex is missing script_name"
  }
  if ($scriptName.Contains('/') -or $scriptName.Contains('\') -or $scriptName -eq '.' -or $scriptName -eq '..') {
    Exit-WithError "Provider #$ProviderIndex has an invalid script_name: $scriptName"
  }

  $envObject = Get-PropertyValue -Object $Provider -PropertyName 'env'
  if (-not (Test-JsonObject $envObject) -or @($envObject.PSObject.Properties).Count -le 0) {
    Exit-WithError "Provider '$scriptName' must define a non-empty env object"
  }

  foreach ($envEntry in $envObject.PSObject.Properties) {
    if ($envEntry.Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
      Exit-WithError "Provider '$scriptName' has invalid env entries"
    }
    if ($envEntry.Value -isnot [string]) {
      Exit-WithError "Provider '$scriptName' has invalid env entries"
    }
    Validate-ExpandableValue -ScriptName $scriptName -FieldName "env.$($envEntry.Name)" -Value $envEntry.Value
  }

  if (Test-HasProperty -Object $Provider -PropertyName 'required_env') {
    $requiredEnv = Get-PropertyValue -Object $Provider -PropertyName 'required_env'
    $requiredVar = [string](Get-PropertyValue -Object $requiredEnv -PropertyName 'var')

    if ([string]::IsNullOrEmpty($requiredVar)) {
      Exit-WithError "Provider '$scriptName' has required_env but required_env.var is missing"
    }
    if ($requiredVar -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
      Exit-WithError "Provider '$scriptName' has an invalid required_env.var: $requiredVar"
    }
  }

  if (Test-HasProperty -Object $Provider -PropertyName 'description') {
    $description = Get-PropertyValue -Object $Provider -PropertyName 'description'
    if ($description -isnot [string]) {
      Exit-WithError "Provider '$scriptName' has a non-string description"
    }
  }

  if (Test-HasProperty -Object $Provider -PropertyName 'config_dir') {
    $configDir = Get-PropertyValue -Object $Provider -PropertyName 'config_dir'
    if ($configDir -isnot [string]) {
      Exit-WithError "Provider '$scriptName' has a non-string config_dir"
    }
    Validate-ExpandableValue -ScriptName $scriptName -FieldName 'config_dir' -Value $configDir
  }

  if (Test-HasProperty -Object $Provider -PropertyName 'models') {
    $models = Get-PropertyValue -Object $Provider -PropertyName 'models'
    $modelsType = Get-JsonTypeName -Value $models

    switch ($modelsType) {
      'string' {
        if ($models.Length -eq 0) {
          Exit-WithError "Provider '$scriptName' has an empty models string"
        }
        Validate-ExpandableValue -ScriptName $scriptName -FieldName 'models' -Value $models
      }
      'object' {
        if (@($models.PSObject.Properties).Count -le 0) {
          Exit-WithError "Provider '$scriptName' has an empty models object"
        }

        foreach ($modelEntry in $models.PSObject.Properties) {
          if ($script:AllowedModelKeys -notcontains $modelEntry.Name) {
            Exit-WithError "Provider '$scriptName' has invalid models entries"
          }
          if ($modelEntry.Value -isnot [string] -or $modelEntry.Value.Length -eq 0) {
            Exit-WithError "Provider '$scriptName' has invalid models entries"
          }
          Validate-ExpandableValue -ScriptName $scriptName -FieldName "models.$($modelEntry.Name)" -Value $modelEntry.Value
        }
      }
      default {
        Exit-WithError "Provider '$scriptName' must set models to a string or object"
      }
    }
  }
}

function Get-BooleanDefaultValue {
  param(
    [Parameter(Mandatory = $true)]
    $Config,
    [Parameter(Mandatory = $true)]
    [string]$PropertyName,
    [Parameter(Mandatory = $true)]
    [string]$ErrorLabel
  )

  $defaults = Get-PropertyValue -Object $Config -PropertyName 'defaults'
  if (-not (Test-JsonObject $defaults)) {
    return $false
  }
  if (-not (Test-HasProperty -Object $defaults -PropertyName $PropertyName)) {
    return $false
  }

  $value = Get-PropertyValue -Object $defaults -PropertyName $PropertyName
  if ($value -isnot [bool]) {
    Exit-WithError "$ErrorLabel must be a boolean"
  }

  return $value
}

function Get-ProviderScriptFileName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptName
  )

  if ($ScriptName.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
    return $ScriptName
  }

  return "$ScriptName.ps1"
}

function Get-ManagedSignatureLine {
  return "# $script:CCWrapGeneratedPowerShellScriptSignature"
}

function Test-FileIsManaged {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
  )

  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    return $false
  }

  $signatureLine = Get-ManagedSignatureLine
  foreach ($line in Get-Content -LiteralPath $FilePath) {
    if ($line -eq $signatureLine) {
      return $true
    }
  }

  return $false
}

function Render-ModelsBlock {
  param(
    [Parameter(Mandatory = $true)]
    $Provider
  )

  $models = Get-PropertyValue -Object $Provider -PropertyName 'models'
  $renderedLines = [System.Collections.Generic.List[string]]::new()

  if ($models -is [string]) {
    $expression = Convert-ShellValueToPowerShellExpression -Value $models
    foreach ($envName in $script:ModelEnvNameMap.Values) {
      $renderedLines.Add(('$env:{0} = {1}' -f $envName, $expression))
    }
    return $renderedLines
  }

  foreach ($modelEntry in $models.PSObject.Properties) {
    $envName = $script:ModelEnvNameMap[$modelEntry.Name]
    if ($null -eq $envName) {
      continue
    }

    $expression = Convert-ShellValueToPowerShellExpression -Value $modelEntry.Value
    $renderedLines.Add(('$env:{0} = {1}' -f $envName, $expression))
  }

  return $renderedLines
}

function Render-WrapperScript {
  param(
    [Parameter(Mandatory = $true)]
    $Provider,
    [Parameter(Mandatory = $true)]
    [bool]$DisableNonessentialTraffic,
    [Parameter(Mandatory = $true)]
    [bool]$ExperimentalAgentTeams
  )

  $scriptName = [string](Get-PropertyValue -Object $Provider -PropertyName 'script_name')
  $description = [string](Get-PropertyValue -Object $Provider -PropertyName 'description')
  $requiredVar = ''
  $configDir = ''

  if (Test-HasProperty -Object $Provider -PropertyName 'required_env') {
    $requiredVar = [string](Get-PropertyValue -Object (Get-PropertyValue -Object $Provider -PropertyName 'required_env') -PropertyName 'var')
  }
  if (Test-HasProperty -Object $Provider -PropertyName 'config_dir') {
    $configDir = [string](Get-PropertyValue -Object $Provider -PropertyName 'config_dir')
  }

  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add('#!/usr/bin/env pwsh')
  $lines.Add((Get-ManagedSignatureLine))
  $lines.Add('')

  if ([string]::IsNullOrEmpty($description)) {
    $lines.Add("# $scriptName - Claude Code wrapper")
  }
  else {
    $lines.Add("# $scriptName - $description")
  }
  $lines.Add('# Generated by cc-wrap')
  $lines.Add('')

  if (-not [string]::IsNullOrEmpty($requiredVar)) {
    $lines.Add("# Check if $requiredVar is set")
    $lines.Add(('if ([string]::IsNullOrEmpty($env:{0})) {{' -f $requiredVar))
    $lines.Add(('  [Console]::Error.WriteLine(''Error: {0} environment variable is not set'')' -f $requiredVar))
    $lines.Add(('  [Console]::Error.WriteLine(''Please set {0}, e.g.: $env:{0} = ''''your-api-key'''''')' -f $requiredVar))
    $lines.Add('  exit 1')
    $lines.Add('}')
    $lines.Add('')
  }

  $lines.Add('# Set provider configuration')
  foreach ($envEntry in (Get-PropertyValue -Object $Provider -PropertyName 'env').PSObject.Properties) {
    $expression = Convert-ShellValueToPowerShellExpression -Value $envEntry.Value
    $lines.Add(('$env:{0} = {1}' -f $envEntry.Name, $expression))
  }

  if (Test-HasProperty -Object $Provider -PropertyName 'models') {
    foreach ($modelLine in @(Render-ModelsBlock -Provider $Provider)) {
      $lines.Add($modelLine)
    }
  }

  if ($DisableNonessentialTraffic) {
    $lines.Add('$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = ''1''')
  }
  if ($ExperimentalAgentTeams) {
    $lines.Add('$env:CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = ''1''')
  }
  if (-not [string]::IsNullOrEmpty($configDir)) {
    $expression = Convert-ShellValueToPowerShellExpression -Value $configDir -TreatLeadingTildeAsHome
    $lines.Add(('$env:CLAUDE_CONFIG_DIR = {0}' -f $expression))
  }

  $lines.Add('')
  $lines.Add('& claude @args')
  $lines.Add('if ($LASTEXITCODE -is [int]) {')
  $lines.Add('  exit $LASTEXITCODE')
  $lines.Add('}')
  $lines.Add('exit 0')

  return ($lines -join "`n") + "`n"
}

function Write-ProviderScript {
  param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDir,
    [Parameter(Mandatory = $true)]
    $Provider,
    [Parameter(Mandatory = $true)]
    [bool]$DisableNonessentialTraffic,
    [Parameter(Mandatory = $true)]
    [bool]$ExperimentalAgentTeams
  )

  $scriptName = [string](Get-PropertyValue -Object $Provider -PropertyName 'script_name')
  $targetPath = Join-Path -Path $OutputDir -ChildPath (Get-ProviderScriptFileName -ScriptName $scriptName)

  if ((Test-Path -LiteralPath $targetPath) -and -not (Test-FileIsManaged -FilePath $targetPath)) {
    [Console]::Out.WriteLine("Skipped existing unmanaged file: $targetPath")
    return $false
  }

  $tempPath = [IO.Path]::GetTempFileName()
  try {
    $content = Render-WrapperScript -Provider $Provider -DisableNonessentialTraffic $DisableNonessentialTraffic -ExperimentalAgentTeams $ExperimentalAgentTeams
    Set-Content -LiteralPath $tempPath -Value $content -Encoding utf8NoBOM -NoNewline
    Move-Item -LiteralPath $tempPath -Destination $targetPath -Force
  }
  finally {
    if (Test-Path -LiteralPath $tempPath) {
      Remove-Item -LiteralPath $tempPath -Force
    }
  }

  return $true
}

function Deploy-Providers {
  param(
    [Parameter(Mandatory = $true)]
    $Config
  )

  $outputDir = Resolve-HomePath -Value ([string](Get-PropertyValue -Object $Config -PropertyName 'output_dir'))
  if ([string]::IsNullOrEmpty($outputDir)) {
    $outputDir = './target'
  }

  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

  $disableNonessentialTraffic = Get-BooleanDefaultValue -Config $Config -PropertyName 'disable_nonessential_traffic' -ErrorLabel 'defaults.disable_nonessential_traffic'
  $experimentalAgentTeams = Get-BooleanDefaultValue -Config $Config -PropertyName 'experimental_agent_teams' -ErrorLabel 'defaults.experimental_agent_teams'

  $providerIndex = 0
  $generatedCount = 0
  $skippedCount = 0

  foreach ($provider in @(Get-PropertyValue -Object $Config -PropertyName 'providers')) {
    $providerIndex += 1
    Validate-Provider -Provider $provider -ProviderIndex $providerIndex

    if (Write-ProviderScript -OutputDir $outputDir -Provider $provider -DisableNonessentialTraffic $disableNonessentialTraffic -ExperimentalAgentTeams $experimentalAgentTeams) {
      $generatedCount += 1
    }
    else {
      $skippedCount += 1
    }
  }

  Write-Output "Generated $generatedCount wrapper script(s) in $outputDir"
  if ($skippedCount -gt 0) {
    Write-Output "Skipped $skippedCount existing unmanaged file(s)"
  }
}

function Remove-ProviderScript {
  param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDir,
    [Parameter(Mandatory = $true)]
    $Provider
  )

  $scriptName = [string](Get-PropertyValue -Object $Provider -PropertyName 'script_name')
  $targetPath = Join-Path -Path $OutputDir -ChildPath (Get-ProviderScriptFileName -ScriptName $scriptName)

  if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    [Console]::Out.WriteLine("Missing file: $targetPath")
    return 2
  }

  if (-not (Test-FileIsManaged -FilePath $targetPath)) {
    [Console]::Out.WriteLine("Skipped existing unmanaged file: $targetPath")
    return 1
  }

  Remove-Item -LiteralPath $targetPath -Force
  return 0
}

function Uninstall-Providers {
  param(
    [Parameter(Mandatory = $true)]
    $Config
  )

  $outputDir = Resolve-HomePath -Value ([string](Get-PropertyValue -Object $Config -PropertyName 'output_dir'))
  if ([string]::IsNullOrEmpty($outputDir)) {
    $outputDir = './target'
  }

  $providerIndex = 0
  $removedCount = 0
  $skippedCount = 0
  $missingCount = 0

  foreach ($provider in @(Get-PropertyValue -Object $Config -PropertyName 'providers')) {
    $providerIndex += 1
    Validate-Provider -Provider $provider -ProviderIndex $providerIndex

    $removeStatus = Remove-ProviderScript -OutputDir $outputDir -Provider $provider
    switch ($removeStatus) {
      0 { $removedCount += 1 }
      1 { $skippedCount += 1 }
      2 { $missingCount += 1 }
      default { exit $removeStatus }
    }
  }

  Write-Output "Removed $removedCount wrapper script(s) from $outputDir"
  if ($skippedCount -gt 0) {
    Write-Output "Skipped $skippedCount existing unmanaged file(s)"
  }
  if ($missingCount -gt 0) {
    Write-Output "Missing $missingCount file(s)"
  }
}

function List-Providers {
  param(
    [Parameter(Mandatory = $true)]
    $Config
  )

  $providerIndex = 0
  foreach ($provider in @(Get-PropertyValue -Object $Config -PropertyName 'providers')) {
    $providerIndex += 1
    Validate-Provider -Provider $provider -ProviderIndex $providerIndex
  }

  foreach ($provider in @(Get-PropertyValue -Object $Config -PropertyName 'providers')) {
    $scriptName = [string](Get-PropertyValue -Object $provider -PropertyName 'script_name')
    $description = [string](Get-PropertyValue -Object $provider -PropertyName 'description')

    if ([string]::IsNullOrEmpty($description)) {
      Write-Output $scriptName
    }
    else {
      Write-Output "$scriptName - $description"
    }
  }
}

function Main {
  param(
    [string[]]$Arguments
  )

  $parsedArguments = Parse-Arguments -Arguments $Arguments
  $configPath = Resolve-HomePath -Value $parsedArguments.ConfigPath
  $config = Validate-ConfigFile -FilePath $configPath

  switch ($parsedArguments.Command) {
    'deploy' {
      Deploy-Providers -Config $config
    }
    'uninstall' {
      Uninstall-Providers -Config $config
    }
    'list' {
      List-Providers -Config $config
    }
  }
}

Main -Arguments $args
