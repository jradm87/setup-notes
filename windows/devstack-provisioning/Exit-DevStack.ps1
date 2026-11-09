<#
.SYNOPSIS
    Desfaz o Enter-DevStack.ps1 na sessão atual: restaura PATH e variáveis UV_* salvas.
.NOTES
    Atua somente nas variáveis de ambiente do processo atual.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:DEVSTACK_ACTIVE -ne '1') {
    Write-Host 'DevStack não está ativo nesta sessão. Nada a fazer.' -ForegroundColor Yellow
    return
}

if ($null -ne $env:DEVSTACK_SAVED_PATH) { $env:Path = $env:DEVSTACK_SAVED_PATH }
$names = @()
if ($env:DEVSTACK_SAVED_VARS) { $names = $env:DEVSTACK_SAVED_VARS -split ';' | Where-Object { $_ } }
foreach ($k in $names) {
    $old = [Environment]::GetEnvironmentVariable("DEVSTACK_SAVED_$k", 'Process')
    if ($old -eq '<<unset>>') { $old = $null }
    [Environment]::SetEnvironmentVariable($k, $old, 'Process')
    [Environment]::SetEnvironmentVariable("DEVSTACK_SAVED_$k", $null, 'Process')
}
foreach ($k in 'DEVSTACK_SAVED_PATH', 'DEVSTACK_SAVED_VARS', 'DEVSTACK_ACTIVE') { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }

Write-Host 'DevStack desativado. PATH e variáveis restaurados para o estado anterior ao Enter-DevStack.' -ForegroundColor Green
$n = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($n) { Write-Host "  node agora: $($n.Source)" }
