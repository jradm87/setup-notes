<#
.SYNOPSIS
    Ativa a nova stack SOMENTE na sessão atual do PowerShell.
.DESCRIPTION
    - Coloca no início do PATH do processo: Node 26 da stack e uv da stack.
    - Define UV_PYTHON_INSTALL_DIR, UV_CACHE_DIR, UV_PYTHON_PREFERENCE=only-managed e
      UV_PYTHON_INSTALL_BIN=0 (para o uv usar o Python 3.14 isolado).
    - Salva os valores anteriores em DEVSTACK_SAVED_* para o Exit-DevStack.ps1 restaurar.
    - NÃO altera PATH persistente (registro), perfil do PowerShell, fnm ou qualquer instalação.
    - O efeito termina ao fechar o terminal ou ao executar .\Exit-DevStack.ps1.
.EXAMPLE
    .\Enter-DevStack.ps1
    node --version   # v26.x
    uv venv --python 3.14
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\00-Common.ps1')
$ctx = Initialize-DevStackContext -NoLog

if ($env:DEVSTACK_ACTIVE -eq '1') {
    Write-Host 'DevStack já está ativo nesta sessão. Use .\Exit-DevStack.ps1 para desativar.' -ForegroundColor Yellow
    return
}

$prepend = @()
$n26 = Find-Node26
if ($n26 -and $n26.Source -eq 'devstack') { $prepend += $n26.NodeDir }
elseif ($n26) { Write-Host "Node $($n26.Version) do PATH já é a major $($ctx.Config.NodeMajorVersion); PATH do Node mantido." }
else { Write-Host "[WARNING] Node $($ctx.Config.NodeMajorVersion) não encontrado. Execute .\Install-DevStack.ps1." -ForegroundColor Yellow }

if (Test-Path -LiteralPath (Join-Path $ctx.Paths.UvBinDir 'uv.exe')) { $prepend += $ctx.Paths.UvBinDir }
elseif (-not (Get-FirstCommandPath 'uv')) { Write-Host '[WARNING] uv não encontrado. Execute .\Install-DevStack.ps1.' -ForegroundColor Yellow }

$vars = Get-DevStackUvEnvironment
[Environment]::SetEnvironmentVariable('DEVSTACK_SAVED_PATH', $env:Path, 'Process')
$saved = @()
foreach ($k in $vars.Keys) {
    $old = [Environment]::GetEnvironmentVariable($k, 'Process')
    if ($null -eq $old) { $old = '<<unset>>' }
    [Environment]::SetEnvironmentVariable("DEVSTACK_SAVED_$k", $old, 'Process')
    [Environment]::SetEnvironmentVariable($k, [string]$vars[$k], 'Process')
    $saved += $k
}
$env:DEVSTACK_SAVED_VARS = ($saved -join ';')
if ($prepend.Count -gt 0) { $env:Path = (($prepend -join ';') + ';' + $env:Path) }
$env:DEVSTACK_ACTIVE = '1'

Write-Host 'DevStack ATIVO nesta sessão (PATH persistente inalterado).' -ForegroundColor Green
$nodeNow = Get-FirstCommandPath 'node'
if ($nodeNow) { Write-Host "  node : $(Get-ToolVersionText -FilePath $nodeNow)  ($nodeNow)" }
$npmNow = Get-FirstCommandPath 'npm.cmd'
if ($npmNow) { Write-Host "  npm  : $(Get-ToolVersionText -FilePath $npmNow)  ($npmNow)" }
$uvNow = Get-FirstCommandPath 'uv'
if ($uvNow) {
    Write-Host "  uv   : $(Get-ToolVersionText -FilePath $uvNow)  ($uvNow)"
    $mp = Find-ManagedPython -UvExe $uvNow
    if ($mp) { Write-Host "  py   : $(Get-ToolVersionText -FilePath $mp)  ($mp) — use 'uv venv --python $($ctx.Config.PythonVersion)'" }
}
Write-Host 'Para desativar: .\Exit-DevStack.ps1'
