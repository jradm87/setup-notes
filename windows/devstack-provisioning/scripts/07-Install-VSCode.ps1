<#
.SYNOPSIS
    [07] Visual Studio Code — valida; instala (escopo usuário) SOMENTE se ausente;
    instala SOMENTE as extensões ausentes da lista em DevStackConfig.psd1.
.NOTES
    Não atualiza o VS Code, não remove extensões, não usa --force, não altera settings.json.
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$LogFile, [switch]$SkipExtensions)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'vscode'
$script:CurrentStep = 'VS Code'
$pkg = $ctx.Config.WinGetPackages.VSCode

try {
    Write-Info 'Verificando VS Code...'
    $code = Find-CodeCli
    $changed = $false
    if ($code) {
        $v = Get-ToolVersionText -FilePath $code
        Write-Ok "VS Code $v encontrado ($code)"
        Write-Info 'Não será atualizado nem reinstalado.'
    } else {
        Write-Info 'VS Code não encontrado.'
        if ($DryRun) {
            Write-DryRun 'Dependeria do WinGet, instalado pela etapa anterior na execução real.'
            return (New-StepResult -Component 'VS Code' -Status 'SKIPPED' -Message 'DRY-RUN: instalaria via WinGet')
        }
        if (-not (Test-WinGetAvailable)) { return (New-StepResult -Component 'VS Code' -Status 'FAILED' -Message 'WinGet ausente') }
        $info = Confirm-WinGetPackage -Id $pkg.Id
        if (-not $info) { return (New-StepResult -Component 'VS Code' -Status 'FAILED' -Message "Pacote $($pkg.Id) não confirmado") }
        if ($DryRun) {
            Write-DryRun "Instalaria $($info.Id) $($info.Version) (escopo: $($pkg.Scope)) via winget --no-upgrade"
            Write-DryRun "Instalaria extensões: $($ctx.Config.VSCodeExtensions -join ', ')"
            return (New-StepResult -Component 'VS Code' -Status 'SKIPPED' -Message "DRY-RUN: instalaria $($info.Id) e extensões")
        }
        $res = Install-WinGetPackage -Id $pkg.Id -Scope $pkg.Scope
        Update-SessionPathFromRegistry
        $code = Find-CodeCli
        if (-not $code) { return (New-StepResult -Component 'VS Code' -Status 'FAILED' -Message "winget: $($res.Message)") }
        $v = Get-ToolVersionText -FilePath $code
        Write-Ok "VS Code $v instalado" 'install'
        $changed = $true
    }

    if ($SkipExtensions) {
        Write-Info 'Extensões ignoradas (-SkipExtensions).'
        return (New-StepResult -Component 'VS Code' -Status 'OK' -Message 'Extensões não verificadas' -Version $v -Path $code -Changed $changed)
    }

    $installed = @((Invoke-NativeCommand -FilePath $code -ArgumentList @('--list-extensions') -Quiet).Output |
            Where-Object { $_ } | ForEach-Object { $_.Trim().ToLowerInvariant() })
    $missing = @($ctx.Config.VSCodeExtensions | Where-Object { $installed -notcontains $_.ToLowerInvariant() })
    foreach ($e in @($ctx.Config.VSCodeExtensions | Where-Object { $missing -notcontains $_ })) { Write-Ok "Extensão presente: $e" }
    if ($missing.Count -eq 0) {
        Write-Info 'Nenhuma extensão a instalar.'
        return (New-StepResult -Component 'VS Code' -Status 'OK' -Message 'Extensões já presentes' -Version $v -Path $code -Changed $changed)
    }

    if ($DryRun) {
        foreach ($e in $missing) { Write-DryRun "Instalaria extensão: code --install-extension $e" }
        return (New-StepResult -Component 'VS Code' -Status 'SKIPPED' -Message "DRY-RUN: instalaria $($missing.Count) extensões" -Version $v -Path $code)
    }

    $failed = @()
    foreach ($e in $missing) {
        Write-Info "Instalando extensão $e ..." 'install'
        $r = Invoke-NativeCommand -FilePath $code -ArgumentList @('--install-extension', $e) -Quiet
        if ($r.ExitCode -ne 0 -and $r.Text -match '(?i)certificate') {
            # Inspeção TLS (ex.: Cloudflare WARP): tenta de novo confiando no repositório de certificados do Windows.
            Write-Info 'Erro de certificado; nova tentativa com NODE_OPTIONS=--use-system-ca (só neste comando).' 'install'
            $r = Invoke-WithDevStackEnvironment -Variables @{ NODE_OPTIONS = '--use-system-ca' } -ScriptBlock {
                Invoke-NativeCommand -FilePath $code -ArgumentList @('--install-extension', $e)
            }
        }
        if ($r.ExitCode -eq 0) { Write-Ok "Extensão instalada: $e" 'install'; $changed = $true }
        else { Write-Warn "Falha ao instalar $e (exit $($r.ExitCode))" 'install'; $failed += $e }
    }
    if ($failed.Count -gt 0) {
        return (New-StepResult -Component 'VS Code' -Status 'WARNING' -Message "Extensões com falha: $($failed -join ', ')" -Version $v -Path $code -Changed $changed)
    }
    return (New-StepResult -Component 'VS Code' -Status 'OK' -Message "Extensões instaladas: $($missing.Count)" -Version $v -Path $code -Changed $changed)
} catch {
    Write-Fail $_.Exception.Message
    return (New-StepResult -Component 'VS Code' -Status 'FAILED' -Message $_.Exception.Message)
}
