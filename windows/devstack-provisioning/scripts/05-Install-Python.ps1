<#
.SYNOPSIS
    [05] Python 3.14 gerenciado pelo uv, isolado em StackRoot\python.
.NOTES
    Usa: uv python install <ver> --no-bin --no-registry
      --no-bin       não coloca python3.14.exe em ~\.local\bin (que está no PATH do usuário)
      --no-registry  não registra no Windows (PEP 514) => 'py' continua usando a versão atual
    Nunca usa --default nem --force. Não altera python.exe padrão, Python Launcher,
    associações de arquivo nem outras versões instaladas.
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$LogFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'python'
$script:CurrentStep = 'Python'
$ver = $ctx.Config.PythonVersion
$comp = "Python $ver"

try {
    Write-Info "Verificando Python $ver gerenciado pela stack..."
    $defaultPy = Get-FirstCommandPath 'python'
    if ($defaultPy) { Write-Info "Python padrão do sistema (não será alterado): $(Get-ToolVersionText -FilePath $defaultPy) em $defaultPy" }

    $uv = Find-UvExecutable
    if (-not $uv) {
        if ($DryRun) {
            Write-DryRun "uv ainda não instalado (etapa 04). Instalaria Python $ver isolado: uv python install $ver --no-bin --no-registry"
            Write-DryRun "Diretório: $($ctx.Paths.PythonInstallDir)"
            return (New-StepResult -Component $comp -Status 'SKIPPED' -Message "DRY-RUN: instalaria Python $ver isolado via uv")
        }
        Write-Fail 'uv não encontrado; etapa 04 precisa ter sucesso antes.'
        return (New-StepResult -Component $comp -Status 'FAILED' -Message 'uv ausente')
    }

    $py = Find-ManagedPython -UvExe $uv.Path
    if ($py) {
        $v = Get-ToolVersionText -FilePath $py
        Write-Ok "$v encontrado em $py"
        Write-Info 'Nenhuma instalação necessária.'
        return (New-StepResult -Component $comp -Status 'OK' -Message 'Já existente (gerenciado pela stack)' -Version $v -Path $py)
    }

    Write-Info "Python $ver gerenciado não encontrado em $($ctx.Paths.PythonInstallDir)."
    $installArgs = @('python', 'install', $ver, '--no-bin', '--no-registry')
    if ($DryRun) {
        Write-DryRun "Executaria: uv $($installArgs -join ' ')"
        Write-DryRun "Com UV_PYTHON_INSTALL_DIR=$($ctx.Paths.PythonInstallDir) e UV_CACHE_DIR=$($ctx.Paths.UvCacheDir) (somente no processo)"
        return (New-StepResult -Component $comp -Status 'SKIPPED' -Message "DRY-RUN: instalaria Python $ver isolado")
    }

    Write-Info "Instalando: uv $($installArgs -join ' ')" 'install'
    $uvExe = $uv.Path
    $r = Invoke-WithDevStackEnvironment -Variables (Get-DevStackUvEnvironment) -ScriptBlock {
        Invoke-NativeCommand -FilePath $uvExe -ArgumentList $installArgs
    }
    if ($r.ExitCode -ne 0) { throw "uv python install falhou (exit $($r.ExitCode)): $($r.Text)" }

    $py = Find-ManagedPython -UvExe $uv.Path
    if (-not $py) { throw "Python $ver instalado mas não localizado por 'uv python find'." }
    $v = Get-ToolVersionText -FilePath $py
    Write-Ok "$v instalado em $py" 'install'
    Write-Info "Use em novos projetos: uv venv --python $ver   |   uv run --python $ver python --version"
    return (New-StepResult -Component $comp -Status 'OK' -Message 'Instalado (isolado, sem registro/sem bin)' -Version $v -Path $py -Changed $true)
} catch {
    Write-Fail $_.Exception.Message
    return (New-StepResult -Component $comp -Status 'FAILED' -Message $_.Exception.Message)
}
