<#
.SYNOPSIS
    [08] OpenSSH Client — se 'ssh -V' funciona, nada a fazer. Caso contrário, instala SOMENTE
    a capability OpenSSH.Client (requer administrador).
.NOTES
    Não instala OpenSSH Server. Não gera chaves. Não altera ssh_config / known_hosts / agent.
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$LogFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'openssh'
$script:CurrentStep = 'OpenSSH'

try {
    Write-Info 'Verificando OpenSSH Client...'
    $ssh = Get-FirstCommandPath 'ssh'
    if (-not $ssh) {
        $c = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
        if (Test-Path -LiteralPath $c) { $ssh = $c }
    }
    if ($ssh) {
        $v = Get-ToolVersionText -FilePath $ssh -ArgumentList @('-V')
        if ($v) {
            Write-Ok "$v ($ssh)"
            Write-Info 'Nenhuma alteração necessária.'
            return (New-StepResult -Component 'OpenSSH' -Status 'OK' -Message 'Já existente (não alterado)' -Version $v -Path $ssh)
        }
    }

    Write-Info 'ssh não encontrado/funcional.'
    if (-not (Test-IsAdministrator)) {
        $msg = 'Instalar OpenSSH.Client exige PowerShell como Administrador. Reexecute esta etapa elevada: scripts\08-Install-OpenSSH.ps1'
        if ($DryRun) { Write-DryRun "Instalaria a capability OpenSSH.Client (exigiria elevação)."; return (New-StepResult -Component 'OpenSSH' -Status 'SKIPPED' -Message 'DRY-RUN: instalaria OpenSSH.Client (requer admin)') }
        Write-Warn $msg
        return (New-StepResult -Component 'OpenSSH' -Status 'WARNING' -Message 'Requer elevação; não instalado')
    }

    $cap = @(Get-WindowsCapability -Online -Name 'OpenSSH.Client*') | Select-Object -First 1
    if (-not $cap) { throw 'Capability OpenSSH.Client não encontrada neste Windows.' }
    Write-Info "Capability: $($cap.Name) — estado $($cap.State)"
    if ($cap.State -eq 'Installed') {
        Write-Warn 'Capability instalada mas ssh.exe não respondeu. Pode ser necessário reiniciar a sessão. Nada será alterado.'
        return (New-StepResult -Component 'OpenSSH' -Status 'WARNING' -Message 'Capability instalada mas ssh indisponível na sessão')
    }
    if ($DryRun) {
        Write-DryRun "Executaria: Add-WindowsCapability -Online -Name $($cap.Name)"
        return (New-StepResult -Component 'OpenSSH' -Status 'SKIPPED' -Message "DRY-RUN: instalaria $($cap.Name)")
    }
    $res = Add-WindowsCapability -Online -Name $cap.Name
    $restart = [bool]$res.RestartNeeded
    if ($restart) { Write-Warn 'O Windows indica que é necessária REINICIALIZAÇÃO. O script não reinicia automaticamente.' }
    Write-Ok "Capability $($cap.Name) instalada" 'install'
    return (New-StepResult -Component 'OpenSSH' -Status 'OK' -Message 'Instalado (somente cliente)' -Changed $true -RestartRequired $restart)
} catch {
    Write-Fail $_.Exception.Message
    return (New-StepResult -Component 'OpenSSH' -Status 'FAILED' -Message $_.Exception.Message)
}
