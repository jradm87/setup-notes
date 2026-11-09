<#
.SYNOPSIS
    Mostra (SOMENTE LEITURA) as versões e caminhos do ambiente existente e da nova stack.
.NOTES
    Não instala, não altera PATH, não grava log.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\00-Common.ps1')
$ctx = Initialize-DevStackContext -NoLog

function Show-Row([string]$Label, [string]$Version, [string]$Path) {
    if (-not $Version) { $Version = '(não encontrado)' }
    Write-Host ('  {0,-22} {1,-34} {2}' -f $Label, $Version, $Path)
}
function Show-Header([string]$t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan; Write-Host ('-' * 48) -ForegroundColor Cyan }

$active = if ($env:DEVSTACK_ACTIVE -eq '1') { 'SIM (Enter-DevStack aplicado nesta sessão)' } else { 'não' }
Write-Host "DevStack ativo nesta sessão: $active" -ForegroundColor Yellow

Show-Header 'VERSÕES EXISTENTES (PATH atual)'
$py = Get-FirstCommandPath 'python'
Show-Row 'Python padrão' $(if ($py) { Get-ToolVersionText -FilePath $py }) $py
foreach ($p in @(Get-CommandPaths 'python' | Select-Object -Skip 1)) { Show-Row '  python (outro)' (Get-ToolVersionText -FilePath $p) $p }
$pyl = Get-FirstCommandPath 'py'
if ($pyl) {
    Show-Row 'Python Launcher' (Get-ToolVersionText -FilePath $pyl) $pyl
    foreach ($l in @((Invoke-NativeCommand -FilePath $pyl -ArgumentList @('-0p') -Quiet).Output | Where-Object { $_ })) { Write-Host "      $l" }
} else { Show-Row 'Python Launcher' '' '' }
$node = Get-FirstCommandPath 'node'
Show-Row 'Node padrão' $(if ($node) { Get-ToolVersionText -FilePath $node }) $node
$npm = Get-FirstCommandPath 'npm.cmd'
Show-Row 'npm padrão' $(if ($npm) { Get-ToolVersionText -FilePath $npm }) $npm
$fnm = Get-FirstCommandPath 'fnm'
if ($fnm) { Show-Row 'fnm' (Get-ToolVersionText -FilePath $fnm) $fnm }
$git = Find-GitExecutable
Show-Row 'Git' $(if ($git) { Get-ToolVersionText -FilePath $git }) $git
Show-Row 'Windows PowerShell' $PSVersionTable.PSVersion.ToString() (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
$pwsh = Find-PwshExecutable
Show-Row 'PowerShell 7' $(if ($pwsh) { Get-ToolVersionText -FilePath $pwsh -ArgumentList @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()') }) $pwsh
$code = Find-CodeCli
Show-Row 'VS Code' $(if ($code) { Get-ToolVersionText -FilePath $code }) $code
$ssh = Get-FirstCommandPath 'ssh'
Show-Row 'OpenSSH' $(if ($ssh) { Get-ToolVersionText -FilePath $ssh -ArgumentList @('-V') }) $ssh

Show-Header "NOVA STACK ($($ctx.Paths.StackRoot))"
$uv = Find-UvExecutable
Show-Row 'uv' $(if ($uv) { "$(Get-ToolVersionText -FilePath $uv.Path) [$($uv.Source)]" }) $(if ($uv) { $uv.Path })
$mp = $null
if ($uv) { $mp = Find-ManagedPython -UvExe $uv.Path }
Show-Row "Python $($ctx.Config.PythonVersion)" $(if ($mp) { Get-ToolVersionText -FilePath $mp }) $mp
$n26 = Find-Node26
Show-Row "Node $($ctx.Config.NodeMajorVersion)" $(if ($n26) { "$($n26.Version) [$($n26.Source)]" }) $(if ($n26) { $n26.NodeExe })
$npmV = $null
if ($n26 -and $n26.NpmCli) { $npmV = Get-ToolVersionText -FilePath $n26.NodeExe -ArgumentList @($n26.NpmCli, '--version') }
Show-Row 'npm (do Node 26)' $npmV $(if ($n26) { $n26.NpmCli })

Show-Header 'ISOLAMENTO'
$userPath = @(([Environment]::GetEnvironmentVariable('Path', 'User')) -split ';')
$machinePath = @(([Environment]::GetEnvironmentVariable('Path', 'Machine')) -split ';')
$leak = @(($userPath + $machinePath) | Where-Object { $_ -and $_.StartsWith($ctx.Paths.StackRoot, [StringComparison]::OrdinalIgnoreCase) })
if ($leak.Count -eq 0) { Write-Host '  [OK] Nenhum diretório da stack no PATH persistente (usuário/sistema).' -ForegroundColor Green }
else { Write-Host "  [WARNING] Diretórios da stack no PATH persistente: $($leak -join '; ')" -ForegroundColor Yellow }
if ($node -and $n26 -and $node -ne $n26.NodeExe) { Write-Host '  [OK] Node padrão e Node 26 são executáveis distintos.' -ForegroundColor Green }
if ($py -and $mp -and $py -ne $mp) { Write-Host "  [OK] Python padrão e Python $($ctx.Config.PythonVersion) são executáveis distintos." -ForegroundColor Green }
