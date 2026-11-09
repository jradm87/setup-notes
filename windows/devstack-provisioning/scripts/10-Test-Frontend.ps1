<#
.SYNOPSIS
    [10] Teste do frontend: projeto React + TypeScript + Vite temporário com o Node 26 da stack.
.NOTES
    - Usa explicitamente node.exe/npm-cli.js do Node 26 (não o Node padrão/fnm).
    - Nada global: create-vite via 'npm exec', dependências locais no diretório temporário.
    - Encerra SOMENTE a árvore de processos iniciada por este teste.
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$LogFile, [switch]$KeepTemp)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-Common.ps1')
$ctx = Initialize-DevStackContext -LogFile $LogFile -LogPrefix 'test-frontend'
$script:CurrentStep = 'Teste frontend'
$names = @('React/Vite', 'TypeScript', 'ESLint', 'Prettier', 'Frontend build', 'Vite dev server')
$results = New-Object System.Collections.Generic.List[object]
$state = @{}
foreach ($n in $names) { $state[$n] = $null }

if ($DryRun) {
    Write-DryRun "Criaria projeto React+TS (create-vite $($ctx.Config.CreateViteVersion)) em $($ctx.Paths.TempRoot) com Node $($ctx.Config.NodeMajorVersion)"
    Write-DryRun 'Executaria npm install, npm run lint, prettier --check, npm run build, npm run dev + HTTP check'
    foreach ($n in $names) { New-StepResult -Component $n -Status 'SKIPPED' -Message 'DRY-RUN' }
    return
}

$node = Find-Node26
if (-not $node -or -not $node.NpmCli) {
    Write-Fail "Node $($ctx.Config.NodeMajorVersion) (com npm) não encontrado."
    foreach ($n in $names) { New-StepResult -Component $n -Status 'FAILED' -Message 'Node 26 ausente' }
    return
}
Write-Info "Node: $($node.Version) em $($node.NodeExe)"

$nodeExe = $node.NodeExe
$npmCli = $node.NpmCli
$tmp = $null
$server = $null
$npmEnv = @{
    npm_config_update_notifier = 'false'
    npm_config_fund            = 'false'
    npm_config_audit           = 'false'
    npm_config_yes             = 'true'
    CI                         = '1'
}

try {
    $tmp = New-DevStackTempDir -Prefix 'frontend'
    $app = Join-Path $tmp 'app'
    Write-Info "Diretório temporário: $tmp"

    Invoke-WithDevStackEnvironment -PrependPath @($node.NodeDir) -Variables $npmEnv -ScriptBlock {
        function Npm([string]$Desc, [string[]]$NpmArgs, [string]$Cwd, [switch]$NoThrow) {
            Write-Info $Desc 'exec'
            $r = Invoke-NativeCommand -FilePath $nodeExe -ArgumentList (@($npmCli) + $NpmArgs) -WorkingDirectory $Cwd
            if ($r.ExitCode -ne 0 -and -not $NoThrow) { throw "$Desc falhou (exit $($r.ExitCode)): $($r.Text)" }
            return $r
        }

        $resolved = Get-ToolVersionText -FilePath 'node'
        if ((Get-NodeMajor $resolved) -ne [int]$ctx.Config.NodeMajorVersion) { throw "Node resolvido na sessão de teste é $resolved (esperado $($ctx.Config.NodeMajorVersion))." }

        Npm "create-vite $($ctx.Config.CreateViteVersion) (react-ts)" @('exec', '--yes', '--', "create-vite@$($ctx.Config.CreateViteVersion)", 'app', '--template', 'react-ts', '--no-interactive', '--no-immediate') $tmp | Out-Null
        if (-not (Test-Path -LiteralPath (Join-Path $app 'package.json'))) { throw 'create-vite não gerou package.json' }

        Npm 'npm install' @('install', '--no-audit', '--no-fund') $app | Out-Null
        Npm 'npm install -D prettier (local)' @('install', '--save-dev', '--no-audit', '--no-fund', 'prettier') $app | Out-Null

        $pkg = Get-Content -LiteralPath (Join-Path $app 'package.json') -Raw | ConvertFrom-Json
        $deps = @()
        foreach ($section in @('dependencies', 'devDependencies')) {
            if ($pkg.PSObject.Properties.Name -contains $section) { $deps += @($pkg.$section.PSObject.Properties.Name) }
        }
        if ($deps -contains 'react' -and $deps -contains 'vite') { Write-Ok 'React + Vite presentes no package.json'; $state['React/Vite'] = 'OK' } else { $state['React/Vite'] = 'FAILED' }
        if ($deps -contains 'typescript') { $state['TypeScript'] = 'OK' } else { $state['TypeScript'] = 'FAILED' }

        $r = Npm 'npm run lint (ESLint)' @('run', 'lint') $app -NoThrow
        if ($r.ExitCode -eq 0) { Write-Ok 'ESLint passou'; $state['ESLint'] = 'OK' } else { Write-Warn 'ESLint reportou problemas'; $state['ESLint'] = 'WARNING' }

        $r = Npm 'prettier --check src' @('exec', '--', 'prettier', '--check', 'src') $app -NoThrow
        if ($r.ExitCode -eq 0) { Write-Ok 'Prettier: código formatado'; $state['Prettier'] = 'OK' }
        else {
            $pv = Npm 'prettier --version' @('exec', '--', 'prettier', '--version') $app -NoThrow
            if ($pv.ExitCode -eq 0) { Write-Warn 'Prettier funciona, mas o template não segue o estilo padrão do Prettier (esperado).'; $state['Prettier'] = 'OK' }
            else { $state['Prettier'] = 'FAILED' }
        }

        $r = Npm 'npm run build (tsc -b && vite build)' @('run', 'build') $app -NoThrow
        if ($r.ExitCode -eq 0 -and (Test-Path -LiteralPath (Join-Path $app 'dist\index.html'))) {
            Write-Ok 'Build gerou dist\index.html'; $state['Frontend build'] = 'OK'
        } else {
            Write-Fail "Build falhou: $($r.Text)"; $state['Frontend build'] = 'FAILED'; $state['TypeScript'] = 'FAILED'
        }

        $port = Get-FreeTcpPort -Preferred ([int]$ctx.Config.FrontendPort)
        if ($port -ne [int]$ctx.Config.FrontendPort) { Write-Warn "Porta $($ctx.Config.FrontendPort) ocupada; usando $port" }
        $quotedCli = '"' + $npmCli + '"'
        $script:server = Start-Process -FilePath $nodeExe -ArgumentList @($quotedCli, 'run', 'dev', '--', '--host', '127.0.0.1', '--port', "$port", '--strictPort') `
            -WorkingDirectory $app -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $tmp 'vite.out.log') -RedirectStandardError (Join-Path $tmp 'vite.err.log')
        Write-Info "npm run dev iniciado (PID $($script:server.Id)) em http://127.0.0.1:$port"
        $resp = Wait-HttpEndpoint -Uri "http://127.0.0.1:$port/" -TimeoutSeconds ([int]$ctx.Config.HttpTimeoutSeconds) -Process $script:server
        if ([int]$resp.StatusCode -eq 200 -and $resp.Content -match 'id="root"') { Write-Ok 'Vite dev server respondeu HTTP 200'; $state['Vite dev server'] = 'OK' }
        else { Write-Fail "Resposta inesperada do dev server: HTTP $($resp.StatusCode)"; $state['Vite dev server'] = 'FAILED' }
    }
} catch {
    Write-Fail $_.Exception.Message
} finally {
    if ($script:server) { Stop-DevStackProcessTree -Process $script:server }
    if ($tmp -and -not $KeepTemp) { Remove-DevStackTempDir -Path $tmp }
    elseif ($tmp) { Write-Info "Diretório mantido (-KeepTemp): $tmp" }
}

foreach ($n in $names) {
    $s = $state[$n]
    if (-not $s) { $s = 'FAILED' }
    $msg = switch ($s) { 'OK' { 'Teste aprovado' } 'WARNING' { 'Funciona, com avisos (ver log)' } default { 'Teste falhou (ver log)' } }
    $results.Add((New-StepResult -Component $n -Status $s -Message $msg))
}
$results
