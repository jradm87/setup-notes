<#
.SYNOPSIS
    [09] Teste do backend: projeto FastAPI temporário com Python 3.14 + uv.
.NOTES
    - Diretório temporário isolado (TempRoot); nenhum projeto existente é acessado.
    - Não instala Python: UV_PYTHON_DOWNLOADS=never (falha se o 3.14 da stack não existir).
    - Dependências (PyPI) ficam no .venv temporário; cache em StackRoot\uv\cache.
    - Encerra SOMENTE a árvore de processos iniciada por este teste.
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$LogFile, [switch]$KeepTemp)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'test-backend'
$script:CurrentStep = 'Teste backend'
$pyVer = $ctx.Config.PythonVersion
$results = New-Object System.Collections.Generic.List[object]
$names = @('FastAPI', 'pytest', 'Ruff')

if ($DryRun) {
    Write-DryRun "Criaria projeto temporário em $($ctx.Paths.TempRoot) com uv + Python $pyVer"
    Write-DryRun 'Adicionaria fastapi[standard], pydantic-settings, httpx, pytest, ruff; testaria GET /health, pytest e ruff'
    foreach ($n in $names) { New-StepResult -Component $n -Status 'SKIPPED' -Message 'DRY-RUN' }
    return
}

$mainPy = @'
from fastapi import FastAPI
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="APP_")

    app_name: str = "devstack-smoke"


settings = Settings()
app = FastAPI(title=settings.app_name)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
'@

$testPy = @'
from fastapi.testclient import TestClient

from main import app


def test_health() -> None:
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
'@

$uv = Find-UvExecutable
if (-not $uv) {
    Write-Fail 'uv não encontrado.'
    foreach ($n in $names) { New-StepResult -Component $n -Status 'FAILED' -Message 'uv ausente' }
    return
}
$uvExe = $uv.Path
$uvEnv = Get-DevStackUvEnvironment
$uvEnv['UV_PYTHON_DOWNLOADS'] = 'never'
$uvEnv['UV_NO_PROGRESS'] = '1'
$tmp = $null
$server = $null
$state = @{ FastAPI = $null; pytest = $null; Ruff = $null }

try {
    $tmp = New-DevStackTempDir -Prefix 'backend'
    Write-Info "Diretório temporário: $tmp"

    Invoke-WithDevStackEnvironment -Variables $uvEnv -ScriptBlock {
        function Step([string]$Desc, [string[]]$UvArgs) {
            Write-Info $Desc 'exec'
            $r = Invoke-NativeCommand -FilePath $uvExe -ArgumentList $UvArgs -WorkingDirectory $tmp
            if ($r.ExitCode -ne 0) { throw "$Desc falhou (exit $($r.ExitCode)): $($r.Text)" }
            return $r
        }

        Step "uv init (Python $pyVer)" @('init', '--app', '--vcs', 'none', '--no-readme', '--no-workspace', '--python', $pyVer, '--name', 'devstack-backend-smoke', '.') | Out-Null
        Step 'uv add fastapi[standard] pydantic-settings httpx' @('add', 'fastapi[standard]', 'pydantic-settings', 'httpx') | Out-Null
        Step 'uv add --dev pytest ruff' @('add', '--dev', 'pytest', 'ruff') | Out-Null

        Write-Utf8File -Path (Join-Path $tmp 'main.py') -Content $mainPy
        $testsDir = Join-Path $tmp 'tests'
        New-Item -ItemType Directory -Path $testsDir | Out-Null
        Write-Utf8File -Path (Join-Path $testsDir '__init__.py') -Content ''
        Write-Utf8File -Path (Join-Path $testsDir 'test_health.py') -Content $testPy

        $r = Step 'uv run python --version' @('run', '--python', $pyVer, 'python', '--version')
        $pv = @($r.Output | Where-Object { $_ -match '^Python ' }) | Select-Object -Last 1
        if ($pv -notmatch ('^Python ' + [regex]::Escape($pyVer) + '\.')) { throw "Versão inesperada no venv: $pv" }
        Write-Ok "Interpretador do projeto: $pv"

        # pytest
        $r = Invoke-NativeCommand -FilePath $uvExe -ArgumentList @('run', 'pytest', '-q', '-p', 'no:cacheprovider') -WorkingDirectory $tmp
        if ($r.ExitCode -eq 0) { Write-Ok 'pytest passou'; $state.pytest = 'OK' } else { Write-Fail "pytest falhou: $($r.Text)"; $state.pytest = 'FAILED' }

        # ruff
        $r = Invoke-NativeCommand -FilePath $uvExe -ArgumentList @('run', 'ruff', 'check', '.', '--no-cache') -WorkingDirectory $tmp
        if ($r.ExitCode -eq 0) { Write-Ok 'ruff check passou'; $state.Ruff = 'OK' } else { Write-Fail "ruff falhou: $($r.Text)"; $state.Ruff = 'FAILED' }

        # FastAPI (uvicorn real) — inicia o python do .venv diretamente para ter o PID exato.
        $venvPy = Join-Path $tmp '.venv\Scripts\python.exe'
        if (-not (Test-Path -LiteralPath $venvPy)) { throw ".venv não encontrado em $tmp" }
        $port = Get-FreeTcpPort -Preferred ([int]$ctx.Config.BackendPort)
        if ($port -ne [int]$ctx.Config.BackendPort) { Write-Warn "Porta $($ctx.Config.BackendPort) ocupada; usando $port" }
        $outLog = Join-Path $tmp 'uvicorn.out.log'
        $errLog = Join-Path $tmp 'uvicorn.err.log'
        $script:server = Start-Process -FilePath $venvPy -ArgumentList @('-m', 'uvicorn', 'main:app', '--host', '127.0.0.1', '--port', "$port") `
            -WorkingDirectory $tmp -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
        Write-Info "FastAPI iniciado (PID $($script:server.Id)) em http://127.0.0.1:$port"
        $url = "http://127.0.0.1:$port/health"
        $resp = Wait-HttpEndpoint -Uri $url -TimeoutSeconds ([int]$ctx.Config.HttpTimeoutSeconds) -Process $script:server
        $json = $resp.Content | ConvertFrom-Json
        if ([int]$resp.StatusCode -eq 200 -and $json.status -eq 'ok') { Write-Ok "GET /health -> HTTP 200 {""status"":""ok""}"; $state.FastAPI = 'OK' }
        else { Write-Fail "Resposta inesperada: HTTP $($resp.StatusCode) $($resp.Content)"; $state.FastAPI = 'FAILED' }
    }

    foreach ($n in $names) {
        $s = $state[$n]
        if (-not $s) { $s = 'FAILED' }
        $results.Add((New-StepResult -Component $n -Status $s -Message $(if ($s -eq 'OK') { 'Teste aprovado' } else { 'Teste falhou (ver log)' })))
    }
} catch {
    $err = $_.Exception.Message
    Write-Fail $err
    foreach ($n in $names) {
        if (-not ($results | Where-Object Component -eq $n)) {
            $s = $state[$n]
            if (-not $s) { $s = 'FAILED' }
            $results.Add((New-StepResult -Component $n -Status $s -Message $(if ($s -eq 'OK') { 'Teste aprovado' } else { $err })))
        }
    }
} finally {
    if ($script:server) { Stop-DevStackProcessTree -Process $script:server }
    if ($tmp -and -not $KeepTemp) { Remove-DevStackTempDir -Path $tmp }
    elseif ($tmp) { Write-Info "Diretório mantido (-KeepTemp): $tmp" }
}
$results
