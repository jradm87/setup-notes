<#
.SYNOPSIS
    [11] Validação SOMENTE LEITURA das ferramentas + checagem de que o ambiente
    existente foi preservado (compara com logs\inventory-baseline.json, se existir).
.PARAMETER WriteInventory
    Também grava logs\inventory-after.json.
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$LogFile, [switch]$WriteInventory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'validate'
$script:CurrentStep = 'Validação'

function Test-Tool {
    param([string]$Component, [scriptblock]$Probe)
    try {
        $r = & $Probe
        if ($r -and $r.Ok) {
            Write-Ok "$Component : $($r.Version) ($($r.Path))"
            return (New-StepResult -Component $Component -Status 'OK' -Message $r.Note -Version $r.Version -Path $r.Path)
        }
        $note = if ($r) { $r.Note } else { 'não encontrado' }
        $status = if ($r -and $r.PSObject.Properties.Name -contains 'Status' -and $r.Status) { $r.Status } else { 'FAILED' }
        if ($status -eq 'WARNING' -or $DryRun) { Write-Warn "$Component : $note" } else { Write-Fail "$Component : $note" }
        return (New-StepResult -Component $Component -Status $status -Message $note)
    } catch {
        Write-Fail "$Component : $($_.Exception.Message)"
        return (New-StepResult -Component $Component -Status 'FAILED' -Message $_.Exception.Message)
    }
}

function Probe([bool]$Ok, [string]$Version, [string]$Path, [string]$Note, [string]$Status = '') {
    return [pscustomobject]@{ Ok = $Ok; Version = $Version; Path = $Path; Note = $Note; Status = $Status }
}

$results = New-Object System.Collections.Generic.List[object]

$results.Add((Test-Tool 'PowerShell' {
            $p = Find-PwshExecutable
            if (-not $p) { return (Probe $false '' '' 'PowerShell 7 (pwsh) não encontrado') }
            $v = Get-ToolVersionText -FilePath $p -ArgumentList @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()')
            Probe ([bool]($v -match '^7\.')) $v $p 'pwsh 7'
        }))

$results.Add((Test-Tool 'Git' {
            $p = Find-GitExecutable
            if (-not $p) { return (Probe $false '' '' 'git não encontrado') }
            $v = Get-ToolVersionText -FilePath $p
            Probe ([bool]$v) $v $p ''
        }))

$uv = Find-UvExecutable
$results.Add((Test-Tool 'uv' {
            if (-not $uv) { return (Probe $false '' '' 'uv não encontrado') }
            $v = Get-ToolVersionText -FilePath $uv.Path
            Probe ([bool]$v) $v $uv.Path $uv.Source
        }))

$results.Add((Test-Tool "Python $($ctx.Config.PythonVersion)" {
            if (-not $uv) { return (Probe $false '' '' 'uv ausente') }
            $py = Find-ManagedPython -UvExe $uv.Path
            if (-not $py) { return (Probe $false '' '' "Python $($ctx.Config.PythonVersion) gerenciado não encontrado") }
            $v = Get-ToolVersionText -FilePath $py
            Probe ([bool]($v -match ('^Python ' + [regex]::Escape($ctx.Config.PythonVersion) + '\.'))) $v $py 'isolado (uv)'
        }))

$n26 = Find-Node26
$results.Add((Test-Tool "Node $($ctx.Config.NodeMajorVersion)" {
            if (-not $n26) { return (Probe $false '' '' "Node $($ctx.Config.NodeMajorVersion) não encontrado") }
            Probe $true $n26.Version $n26.NodeExe $n26.Source
        }))

$results.Add((Test-Tool 'npm' {
            if (-not $n26 -or -not $n26.NpmCli) { return (Probe $false '' '' 'npm do Node 26 não encontrado') }
            $v = Get-ToolVersionText -FilePath $n26.NodeExe -ArgumentList @($n26.NpmCli, '--version')
            Probe ([bool]$v) $v $n26.NpmCli 'distribuído com o Node 26'
        }))

$results.Add((Test-Tool 'VS Code' {
            $c = Find-CodeCli
            if (-not $c) { return (Probe $false '' '' 'VS Code não encontrado') }
            $v = Get-ToolVersionText -FilePath $c
            $installed = @((Invoke-NativeCommand -FilePath $c -ArgumentList @('--list-extensions') -Quiet).Output | Where-Object { $_ } | ForEach-Object { $_.Trim().ToLowerInvariant() })
            $missing = @($ctx.Config.VSCodeExtensions | Where-Object { $installed -notcontains $_.ToLowerInvariant() })
            if ($missing.Count -gt 0) { return (Probe $false $v $c "extensões ausentes: $($missing -join ', ')" 'WARNING') }
            Probe ([bool]$v) $v $c 'extensões OK'
        }))

$results.Add((Test-Tool 'OpenSSH' {
            $p = Get-FirstCommandPath 'ssh'
            if (-not $p) { return (Probe $false '' '' 'ssh não encontrado') }
            $v = Get-ToolVersionText -FilePath $p -ArgumentList @('-V')
            Probe ([bool]$v) $v $p ''
        }))

# --- Preservação do ambiente existente ---
$baselineFile = Join-Path $ctx.Paths.LogDir 'inventory-baseline.json'
if (Test-Path -LiteralPath $baselineFile) {
    try {
        $b = Get-Content -LiteralPath $baselineFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $diffs = @()
        $nowPy = Get-FirstCommandPath 'python'
        if ($b.Python.Default -and $b.Python.Default -ne $nowPy) { $diffs += "python padrão: '$($b.Python.Default)' -> '$nowPy'" }
        $nowNode = Get-FirstCommandPath 'node'
        if ($b.Node.Default -and $b.Node.Default -ne $nowNode) { $diffs += "node padrão: '$($b.Node.Default)' -> '$nowNode'" }
        if ($b.Node.Default -and $nowNode) {
            $bv = @($b.Node.Instances | Where-Object { $_.Path -eq $b.Node.Default } | ForEach-Object { $_.Version }) | Select-Object -First 1
            $nv = Get-ToolVersionText -FilePath $nowNode
            if ($bv -and $bv -ne $nv) { $diffs += "versão node padrão: $bv -> $nv" }
        }
        $py = Get-FirstCommandPath 'py'
        if ($py -and $b.PythonLauncher.Installations) {
            $now = ((Invoke-NativeCommand -FilePath $py -ArgumentList @('-0p') -Quiet).Output -join '|')
            $was = (@($b.PythonLauncher.Installations) -join '|')
            if ($now -ne $was) { $diffs += "py -0p mudou: [$was] -> [$now]" }
        }
        $userPathNow = @(([Environment]::GetEnvironmentVariable('Path', 'User')) -split ';' | Where-Object { $_ })
        $removed = @(@($b.PathUser) | Where-Object { $userPathNow -notcontains $_ })
        if ($removed.Count -gt 0) { $diffs += "entradas removidas do PATH do usuário: $($removed -join '; ')" }
        $machinePathNow = @(([Environment]::GetEnvironmentVariable('Path', 'Machine')) -split ';' | Where-Object { $_ })
        $removedM = @(@($b.PathMachine) | Where-Object { $machinePathNow -notcontains $_ })
        if ($removedM.Count -gt 0) { $diffs += "entradas removidas do PATH do sistema: $($removedM -join '; ')" }

        if ($diffs.Count -eq 0) {
            Write-Ok 'Ambiente existente preservado (python/node padrão, py -0p e PATH sem remoções).'
            $results.Add((New-StepResult -Component 'Ambiente existente' -Status 'OK' -Message 'Preservado em relação ao baseline'))
        } else {
            foreach ($d in $diffs) { Write-Warn $d }
            $results.Add((New-StepResult -Component 'Ambiente existente' -Status 'WARNING' -Message ($diffs -join ' | ')))
        }
    } catch {
        Write-Warn "Não foi possível comparar com o baseline: $($_.Exception.Message)"
        $results.Add((New-StepResult -Component 'Ambiente existente' -Status 'WARNING' -Message 'Comparação com baseline falhou'))
    }
} else {
    Write-Info 'logs\inventory-baseline.json não existe; comparação de preservação ignorada.'
}

if ($WriteInventory) {
    $inv = Join-Path $PSScriptRoot '01-Inventory.ps1'
    & $inv -LogFile $ctx.LogFile -OutputName 'inventory-after.json' | Out-Null
    Write-Info 'Inventário final gravado em logs\inventory-after.json'
}

$results
