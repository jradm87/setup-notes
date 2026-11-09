<#
.SYNOPSIS
    Funções compartilhadas do DevStack (logging, config, execução nativa, downloads, processos).
.NOTES
    Deve ser carregado por dot-source:  . (Join-Path $PSScriptRoot '00-Common.ps1')
    Compatível com Windows PowerShell 5.1 e PowerShell 7.
    Este arquivo não altera nada na máquina ao ser carregado.
#>

Set-StrictMode -Version Latest

$script:DevStackScriptsDir = $PSScriptRoot
$script:DevStackPackageRoot = Split-Path -Parent $PSScriptRoot
$script:DevStackCtx = $null

# ======================================================================
# Contexto / configuração
# ======================================================================

function Expand-DevStackPath {
    param([Parameter(Mandatory)][string]$Path)
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if (-not [IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path $script:DevStackPackageRoot $expanded
    }
    return [IO.Path]::GetFullPath($expanded)
}

function Get-DevStackArchitecture {
    # Retorna 'x64' ou 'arm64' (arquitetura do SO, não do processo).
    $arch = $null
    try {
        $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    } catch {
        $arch = $null
    }
    if (-not $arch) {
        $arch = $env:PROCESSOR_ARCHITEW6432
        if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    }
    switch -Regex ($arch) {
        '^(X64|AMD64)$' { return 'x64' }
        '^(Arm64|ARM64)$' { return 'arm64' }
        default { throw "Arquitetura não suportada: $arch (suportadas: x64, arm64)" }
    }
}

function Initialize-DevStackContext {
    <#
        Carrega a configuração e define o arquivo de log.
        -LogFile vazio => cria logs\<LogPrefix>-<timestamp>.log
    #>
    param(
        [string]$LogFile,
        [string]$LogPrefix = 'devstack',
        [switch]$NoLog
    )
    $configPath = Join-Path $script:DevStackPackageRoot 'config\DevStackConfig.psd1'
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Arquivo de configuração não encontrado: $configPath"
    }
    $config = Import-PowerShellDataFile -LiteralPath $configPath

    $logDir = Expand-DevStackPath $config.LogDirectory
    if ($NoLog) {
        $LogFile = $null
    } elseif (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }
    if (-not $LogFile -and -not $NoLog) {
        $LogFile = Join-Path $logDir ('{0}-{1}.log' -f $LogPrefix, (Get-Date -Format 'yyyy-MM-dd-HHmmss'))
    }

    $arch = Get-DevStackArchitecture
    $stackRoot = Expand-DevStackPath $config.StackRoot
    $uvTriple = if ($arch -eq 'arm64') { 'aarch64-pc-windows-msvc' } else { 'x86_64-pc-windows-msvc' }

    $paths = [ordered]@{
        PackageRoot      = $script:DevStackPackageRoot
        StackRoot        = $stackRoot
        DownloadDir      = Join-Path $stackRoot 'downloads'
        UvBinDir         = Join-Path $stackRoot 'uv\bin'
        UvCacheDir       = Join-Path $stackRoot 'uv\cache'
        PythonInstallDir = Join-Path $stackRoot 'python'
        NodeRoot         = Join-Path $stackRoot 'node'
        LogDir           = $logDir
        TempRoot         = Expand-DevStackPath $config.TempRoot
    }

    $script:DevStackCtx = [pscustomobject]@{
        Config   = $config
        Paths    = [pscustomobject]$paths
        Arch     = $arch
        UvTriple = $uvTriple
        LogFile  = $LogFile
    }
    return $script:DevStackCtx
}

function Get-DevStackContext {
    if (-not $script:DevStackCtx) { throw 'Contexto não inicializado. Chame Initialize-DevStackContext.' }
    return $script:DevStackCtx
}

# ======================================================================
# Logging
# ======================================================================

function Protect-DevStackText {
    # Mascara padrões comuns de segredos antes de gravar em log.
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    $t = $Text
    $t = [regex]::Replace($t, '(?i)\b(gh[pousr]_[A-Za-z0-9]{10,}|github_pat_[A-Za-z0-9_]{10,})', '***REDACTED***')
    $t = [regex]::Replace($t, '(?i)\b(npm_[A-Za-z0-9]{20,})', '***REDACTED***')
    $t = [regex]::Replace($t, '(?i)(password|passwd|pwd|token|secret|api[_-]?key|authorization|cookie|_authToken)(\s*[:=]\s*)("[^"]*"|''[^'']*''|\S+)', '$1$2***REDACTED***')
    $t = [regex]::Replace($t, '(?i)(https?://)[^/\s:@]+:[^/\s@]+@', '$1***:***@')
    $t = [regex]::Replace($t, '(?i)(Bearer\s+)[A-Za-z0-9\-\._~\+/]+=*', '$1***REDACTED***')
    return $t
}

function Write-DevLog {
    param(
        [ValidateSet('INFO', 'OK', 'WARN', 'FAIL', 'DRYRUN', 'SKIP', 'DEBUG')][string]$Level = 'INFO',
        [string]$Step = '-',
        [string]$Action = '-',
        [string]$Result = '-',
        [string]$Message = ''
    )
    if (-not $script:DevStackCtx -or -not $script:DevStackCtx.LogFile) { return }
    $line = '{0} | {1,-6} | {2} | {3} | {4} | {5}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Step, $Action, $Result, (Protect-DevStackText $Message)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::AppendAllText($script:DevStackCtx.LogFile, $line + [Environment]::NewLine, $enc)
}

$script:CurrentStep = '-'

function Write-StepHeader {
    param([int]$Index, [int]$Total, [string]$Title)
    $script:CurrentStep = $Title
    $bar = '=' * 48
    Write-Host ''
    Write-Host $bar -ForegroundColor Cyan
    Write-Host ('[{0:D2}/{1:D2}] {2}' -f $Index, $Total, $Title) -ForegroundColor Cyan
    Write-Host $bar -ForegroundColor Cyan
    Write-DevLog -Level INFO -Step $Title -Action 'begin' -Message ('[{0:D2}/{1:D2}]' -f $Index, $Total)
}

function Write-Info   { param([string]$Message, [string]$Action = 'info') Write-Host "  $Message"; Write-DevLog -Level INFO -Step $script:CurrentStep -Action $Action -Message $Message }
function Write-Ok     { param([string]$Message, [string]$Action = 'check') Write-Host "  [OK] $Message" -ForegroundColor Green; Write-DevLog -Level OK -Step $script:CurrentStep -Action $Action -Result 'OK' -Message $Message }
function Write-Warn   { param([string]$Message, [string]$Action = 'check') Write-Host "  [WARNING] $Message" -ForegroundColor Yellow; Write-DevLog -Level WARN -Step $script:CurrentStep -Action $Action -Result 'WARNING' -Message $Message }
function Write-Fail   { param([string]$Message, [string]$Action = 'error') Write-Host "  [FAILED] $Message" -ForegroundColor Red; Write-DevLog -Level FAIL -Step $script:CurrentStep -Action $Action -Result 'FAILED' -Message $Message }
function Write-DryRun { param([string]$Message) Write-Host "  [DRY-RUN] $Message" -ForegroundColor Magenta; Write-DevLog -Level DRYRUN -Step $script:CurrentStep -Action 'dry-run' -Result 'SKIPPED' -Message $Message }

# ======================================================================
# Resultados
# ======================================================================

function New-StepResult {
    param(
        [Parameter(Mandatory)][string]$Component,
        [Parameter(Mandatory)][ValidateSet('OK', 'SKIPPED', 'WARNING', 'FAILED')][string]$Status,
        [string]$Message = '',
        [string]$Version = '',
        [string]$Path = '',
        [bool]$Changed = $false,
        [bool]$RestartRequired = $false
    )
    $r = [pscustomobject]@{
        PSTypeName      = 'DevStack.StepResult'
        Component       = $Component
        Status          = $Status
        Message         = $Message
        Version         = $Version
        Path            = $Path
        Changed         = $Changed
        RestartRequired = $RestartRequired
    }
    Write-DevLog -Level INFO -Step $script:CurrentStep -Action 'result' -Result $Status -Message ('{0}: {1}' -f $Component, $Message)
    return $r
}

function Select-StepResult {
    # Filtra a saída de um script, mantendo apenas objetos DevStack.StepResult.
    param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        if ($null -ne $InputObject -and $InputObject.PSObject.TypeNames -contains 'DevStack.StepResult') { $InputObject }
    }
}

function Write-ResultSummary {
    param([Parameter(Mandatory)][object[]]$Results, [string]$Title = 'RESUMO')
    Write-Host ''
    Write-Host ('=' * 48) -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('=' * 48) -ForegroundColor Cyan
    foreach ($r in $Results) {
        $color = switch ($r.Status) { 'OK' { 'Green' } 'SKIPPED' { 'DarkGray' } 'WARNING' { 'Yellow' } default { 'Red' } }
        $ver = if ($r.Version) { " ($($r.Version))" } else { '' }
        Write-Host ('{0,-20}{1,-9}{2}{3}' -f $r.Component, $r.Status, $r.Message, $ver) -ForegroundColor $color
        Write-DevLog -Level INFO -Step 'summary' -Action $r.Component -Result $r.Status -Message $r.Message
    }
}

# ======================================================================
# Ambiente / privilégios
# ======================================================================

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-NativeCommand {
    <#
        Executa um executável nativo capturando stdout+stderr e exit code,
        sem que stderr vire exceção no Windows PowerShell 5.1.
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory,
        [switch]$Quiet,
        [switch]$Utf8Output   # decodifica a saída como UTF-8 (ex.: winget), independente da code page do console
    )
    $display = '{0} {1}' -f $FilePath, ($ArgumentList -join ' ')
    Write-DevLog -Level DEBUG -Step $script:CurrentStep -Action 'exec' -Message $display
    $prevEap = $ErrorActionPreference
    $pushed = $false
    $prevOutEnc = $null
    try {
        $ErrorActionPreference = 'Continue'
        if ($Utf8Output) {
            try { $prevOutEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) }
            catch { $prevOutEnc = $null }
        }
        if ($WorkingDirectory) { Push-Location -LiteralPath $WorkingDirectory; $pushed = $true }
        $global:LASTEXITCODE = 0
        $out = & $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
    } catch {
        $out = @("$($_.Exception.Message)")
        $code = -1
    } finally {
        if ($pushed) { Pop-Location }
        if ($prevOutEnc) { try { [Console]::OutputEncoding = $prevOutEnc } catch { Write-DevLog -Level DEBUG -Message 'Falha ao restaurar OutputEncoding' } }
        $ErrorActionPreference = $prevEap
    }
    $lines = @($out)
    $joined = ($lines -join [Environment]::NewLine)
    Write-DevLog -Level DEBUG -Step $script:CurrentStep -Action 'exit' -Result "$code" -Message ($joined.Substring(0, [Math]::Min($joined.Length, 4000)))
    if (-not $Quiet -and $code -ne 0) {
        Write-Host "    comando retornou exit code $code : $display" -ForegroundColor DarkYellow
    }
    return [pscustomobject]@{ ExitCode = $code; Output = $lines; Text = $joined }
}

function Get-CommandPaths {
    # Todos os executáveis (Application) com esse nome no PATH atual, em ordem de precedência.
    param([Parameter(Mandatory)][string]$Name)
    $cmds = @(Get-Command $Name -CommandType Application -All -ErrorAction SilentlyContinue)
    return @($cmds | ForEach-Object { $_.Source } | Select-Object -Unique)
}

function Get-FirstCommandPath {
    param([Parameter(Mandatory)][string]$Name)
    $p = @(Get-CommandPaths $Name)
    if ($p.Count -gt 0) { return $p[0] }
    return $null
}

function Get-ToolVersionText {
    # Executa '<exe> <args>' e devolve a primeira linha não vazia, ou $null.
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$ArgumentList = @('--version'))
    if (-not $FilePath) { return $null }
    $r = Invoke-NativeCommand -FilePath $FilePath -ArgumentList $ArgumentList -Quiet
    if ($r.ExitCode -ne 0) { return $null }
    $first = @($r.Output | Where-Object { $_ -and $_.Trim() }) | Select-Object -First 1
    if ($first) { return $first.Trim() }
    return $null
}

# ======================================================================
# Localização das ferramentas da stack
# ======================================================================

function Find-PwshExecutable {
    $p = Get-FirstCommandPath 'pwsh'
    if ($p) { return $p }
    foreach ($c in @(
            (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'))) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Find-GitExecutable {
    $p = Get-FirstCommandPath 'git'
    if ($p) { return $p }
    $c = Join-Path $env:ProgramFiles 'Git\cmd\git.exe'
    if (Test-Path -LiteralPath $c) { return $c }
    return $null
}

function Find-CodeCli {
    $p = Get-FirstCommandPath 'code.cmd'
    if (-not $p) { $p = Get-FirstCommandPath 'code' }
    if ($p) { return $p }
    foreach ($c in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'),
            (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd'))) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Find-UvExecutable {
    <#
        Preferência: uv da stack (StackRoot\uv\bin) e depois uv já existente no PATH.
        Retorna objeto { Path; Source } ou $null.
    #>
    $ctx = Get-DevStackContext
    $own = Join-Path $ctx.Paths.UvBinDir 'uv.exe'
    if (Test-Path -LiteralPath $own) { return [pscustomobject]@{ Path = $own; Source = 'devstack' } }
    $p = Get-FirstCommandPath 'uv'
    if ($p) { return [pscustomobject]@{ Path = $p; Source = 'existing' } }
    return $null
}

function Get-NodeDirName {
    param([Parameter(Mandatory)][string]$Version)
    $ctx = Get-DevStackContext
    return ('node-v{0}-win-{1}' -f $Version.TrimStart('v'), $ctx.Arch)
}

function Get-NodeMajor {
    param([string]$VersionText)
    if ($VersionText -match '^v?(\d+)\.') { return [int]$Matches[1] }
    return -1
}

function Find-Node26 {
    <#
        Procura Node da major configurada:
          1) instalações da stack em StackRoot\node\node-v<major>.*-win-<arch>
          2) node existente no PATH, se já for da major configurada
        Retorna { NodeExe; NodeDir; NpmCli; Version; Source } ou $null.
    #>
    $ctx = Get-DevStackContext
    $major = [int]$ctx.Config.NodeMajorVersion
    $candidates = @()
    if (Test-Path -LiteralPath $ctx.Paths.NodeRoot) {
        $pattern = 'node-v{0}.*-win-{1}' -f $major, $ctx.Arch
        $candidates += @(Get-ChildItem -LiteralPath $ctx.Paths.NodeRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like $pattern } |
                Sort-Object { [version](($_.Name -replace '^node-v', '') -replace '-win-.*$', '') } -Descending |
                ForEach-Object { [pscustomobject]@{ Dir = $_.FullName; Source = 'devstack' } })
    }
    $pathNode = Get-FirstCommandPath 'node'
    if ($pathNode) { $candidates += [pscustomobject]@{ Dir = (Split-Path -Parent $pathNode); Source = 'existing' } }

    foreach ($c in $candidates) {
        $exe = Join-Path $c.Dir 'node.exe'
        if (-not (Test-Path -LiteralPath $exe)) { continue }
        $v = Get-ToolVersionText -FilePath $exe
        if ((Get-NodeMajor $v) -eq $major) {
            $npmCli = Join-Path $c.Dir 'node_modules\npm\bin\npm-cli.js'
            if (-not (Test-Path -LiteralPath $npmCli)) { $npmCli = $null }
            return [pscustomobject]@{ NodeExe = $exe; NodeDir = $c.Dir; NpmCli = $npmCli; Version = $v; Source = $c.Source }
        }
    }
    return $null
}

function Get-DevStackUvEnvironment {
    # Variáveis que isolam o uv/Python da stack. Aplicadas só em escopo de processo.
    $ctx = Get-DevStackContext
    return [ordered]@{
        UV_PYTHON_INSTALL_DIR = $ctx.Paths.PythonInstallDir
        UV_CACHE_DIR          = $ctx.Paths.UvCacheDir
        UV_PYTHON_PREFERENCE  = 'only-managed'
        UV_PYTHON_INSTALL_BIN = '0'
    }
}

function Invoke-WithDevStackEnvironment {
    <#
        Executa um scriptblock com variáveis de ambiente/PATH do processo ajustados
        e restaura TUDO no final (finally). Não toca no ambiente persistente.
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [string[]]$PrependPath = @(),
        [hashtable]$Variables = @{}
    )
    $saved = @{}
    $savedPath = $env:Path
    foreach ($k in $Variables.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process') }
    try {
        foreach ($k in $Variables.Keys) { [Environment]::SetEnvironmentVariable($k, [string]$Variables[$k], 'Process') }
        $pre = @($PrependPath | Where-Object { $_ })
        if ($pre.Count -gt 0) { $env:Path = (($pre -join ';') + ';' + $savedPath) }
        & $ScriptBlock
    } finally {
        $env:Path = $savedPath
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
    }
}

# ======================================================================
# Python 3.14 gerenciado (uv)
# ======================================================================

function Find-ManagedPython {
    # Retorna caminho do Python <PythonVersion> gerenciado pela stack, ou $null.
    param([Parameter(Mandatory)][string]$UvExe)
    $ctx = Get-DevStackContext
    $ver = $ctx.Config.PythonVersion
    $found = Invoke-WithDevStackEnvironment -Variables (Get-DevStackUvEnvironment) -ScriptBlock {
        # 'gerenciado' vem de UV_PYTHON_PREFERENCE=only-managed; o uv recusa --managed-python junto com ela.
        $r = Invoke-NativeCommand -FilePath $UvExe -ArgumentList @('python', 'find', $ver, '--no-project') -Quiet
        if ($r.ExitCode -eq 0) {
            $line = @($r.Output | Where-Object { $_ -match '\.exe\s*$' }) | Select-Object -Last 1
            if ($line) { return $line.Trim() }
        }
        return $null
    }
    if ($found -and (Test-Path -LiteralPath $found)) { return $found }
    return $null
}

# ======================================================================
# WinGet
# ======================================================================

function Test-WinGetAvailable {
    return [bool](Get-FirstCommandPath 'winget')
}

function Confirm-WinGetPackage {
    # Confirma que o ID exato existe na fonte 'winget' (somente leitura).
    param([Parameter(Mandatory)][string]$Id)
    $r = Invoke-NativeCommand -FilePath 'winget' -ArgumentList @('show', '--id', $Id, '-e', '--source', 'winget', '--disable-interactivity') -Quiet -Utf8Output
    if ($r.ExitCode -ne 0) { return $null }
    # Tolerante a idioma e a code page ("Version", "Versão", "Vers├úo"...).
    $verLine = @($r.Output | Where-Object { $_ -match '^\s*Vers\S*\s*:\s*\S' }) | Select-Object -First 1
    $ver = if ($verLine) { ($verLine -split ':', 2)[1].Trim() } else { '?' }
    return [pscustomobject]@{ Id = $Id; Version = $ver }
}

# Códigos de retorno do WinGet relevantes (HRESULT como Int32).
$script:WinGetCodes = @{
    -1978335189 = 'Nenhuma atualização aplicável (pacote já instalado)'   # 0x8A15002B
    -1978335135 = 'Pacote já instalado'                                     # 0x8A150061
    -1978334967 = 'Reinicialização necessária para concluir a instalação'  # 0x8A150109
    3010        = 'Reinicialização necessária (MSI 3010)'
}

function Install-WinGetPackage {
    <#
        Instala um pacote por ID exato. NUNCA atualiza (--no-upgrade), nunca usa --force.
        Retorna { Success; RestartRequired; ExitCode; Message }.
    #>
    param([Parameter(Mandatory)][string]$Id, [string]$Scope)
    $wgArgs = @('install', '--id', $Id, '-e', '--source', 'winget', '--no-upgrade',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    if ($Scope) { $wgArgs += @('--scope', $Scope) }
    $r = Invoke-NativeCommand -FilePath 'winget' -ArgumentList $wgArgs -Utf8Output
    $restart = ($r.ExitCode -eq -1978334967 -or $r.ExitCode -eq 3010)
    $msg = if ($script:WinGetCodes.ContainsKey($r.ExitCode)) { $script:WinGetCodes[$r.ExitCode] } else { "exit code $($r.ExitCode)" }
    return [pscustomobject]@{
        Success         = ($r.ExitCode -eq 0 -or $restart)
        RestartRequired = $restart
        ExitCode        = $r.ExitCode
        Message         = $msg
    }
}

function Update-SessionPathFromRegistry {
    <#
        Após uma instalação, ACRESCENTA ao PATH do processo atual as entradas novas do PATH
        persistente (Machine/User) que ainda não estão na sessão. Não remove nada e não grava
        nada no registro.
    #>
    $current = @($env:Path -split ';' | Where-Object { $_ })
    $persist = @(([Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')) -split ';' |
            Where-Object { $_ } | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) })
    $toAdd = @($persist | Where-Object { $current -notcontains $_ } | Select-Object -Unique)
    if ($toAdd.Count -gt 0) { $env:Path = $env:Path.TrimEnd(';') + ';' + ($toAdd -join ';') }
}

# ======================================================================
# Downloads / integridade
# ======================================================================

function Enable-ModernTls {
    try {
        $p = [Net.ServicePointManager]::SecurityProtocol
        $p = $p -bor [Net.SecurityProtocolType]::Tls12
        try { $p = $p -bor [Net.SecurityProtocolType]'Tls13' } catch { Write-DevLog -Level DEBUG -Message 'TLS 1.3 indisponível neste .NET' }
        [Net.ServicePointManager]::SecurityProtocol = $p
    } catch {
        Write-DevLog -Level WARN -Message "Não foi possível ajustar TLS: $($_.Exception.Message)"
    }
}

function Assert-AllowedUrl {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string[]]$AllowedHosts)
    $u = [Uri]$Uri
    if ($u.Scheme -ne 'https') { throw "URL não-HTTPS recusada: $Uri" }
    if ($AllowedHosts -notcontains $u.Host) { throw "Host não permitido ($($u.Host)). Permitidos: $($AllowedHosts -join ', ')" }
}

function Get-RemoteText {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string[]]$AllowedHosts)
    Assert-AllowedUrl -Uri $Uri -AllowedHosts $AllowedHosts
    Enable-ModernTls
    $prevProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        $resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing -ErrorAction Stop
    } finally { $ProgressPreference = $prevProgress }
    if ([int]$resp.StatusCode -ne 200) { throw "HTTP $($resp.StatusCode) em $Uri" }
    $content = $resp.Content
    if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content) }
    return [string]$content
}

function Invoke-VerifiedDownload {
    <#
        Baixa para OutFile e valida SHA256. Se OutFile já existe com hash correto, reutiliza.
        Arquivo com hash incorreto é descartado (é um arquivo baixado pelo próprio script).
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile,
        [Parameter(Mandatory)][string]$ExpectedSha256,
        [Parameter(Mandatory)][string[]]$AllowedHosts
    )
    Assert-AllowedUrl -Uri $Uri -AllowedHosts $AllowedHosts
    $expected = $ExpectedSha256.Trim().ToLowerInvariant()
    if (Test-Path -LiteralPath $OutFile) {
        $h = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($h -eq $expected) { Write-Info "Download já presente e íntegro: $OutFile" 'download'; return $OutFile }
    }
    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $tmp = "$OutFile.partial"
    Enable-ModernTls
    Write-Info "Baixando $Uri" 'download'
    $prevProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        $resp = Invoke-WebRequest -Uri $Uri -OutFile $tmp -UseBasicParsing -PassThru -ErrorAction Stop
        if ([int]$resp.StatusCode -ne 200) { throw "HTTP $($resp.StatusCode) em $Uri" }
    } finally { $ProgressPreference = $prevProgress }
    $actual = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        Remove-Item -LiteralPath $tmp
        throw "SHA256 divergente para $Uri. Esperado $expected, obtido $actual."
    }
    if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile }
    Move-Item -LiteralPath $tmp -Destination $OutFile
    Write-Ok "SHA256 verificado ($expected)" 'verify'
    return $OutFile
}

# ======================================================================
# Processos / HTTP (testes)
# ======================================================================

function Get-ProcessTreeIds {
    # IDs do processo raiz e de TODOS os descendentes (via ParentProcessId).
    param([Parameter(Mandatory)][int]$RootId)
    $all = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, CreationDate)
    $result = New-Object System.Collections.Generic.List[int]
    $queue = New-Object System.Collections.Generic.Queue[int]
    $queue.Enqueue($RootId)
    while ($queue.Count -gt 0) {
        $id = $queue.Dequeue()
        if ($result.Contains($id)) { continue }
        $result.Add($id)
        foreach ($p in $all) { if ($p.ParentProcessId -eq $id -and $p.ProcessId -ne $id) { $queue.Enqueue([int]$p.ProcessId) } }
    }
    return $result.ToArray()
}

function Stop-DevStackProcessTree {
    <#
        Encerra SOMENTE o processo iniciado pelo teste e seus descendentes.
        Valida o horário de início para não atingir um PID reutilizado.
    #>
    param([Parameter(Mandatory)][System.Diagnostics.Process]$Process)
    try { $Process.Refresh() } catch { Write-DevLog -Level DEBUG -Message "Refresh falhou: $($_.Exception.Message)" }
    if ($Process.HasExited) { Write-Info "Processo $($Process.Id) já havia terminado." 'cleanup'; return }
    $rootStart = $Process.StartTime
    $ids = @(Get-ProcessTreeIds -RootId $Process.Id)
    [array]::Reverse($ids)  # filhos primeiro
    foreach ($id in $ids) {
        $p = Get-Process -Id $id -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        if ($id -ne $Process.Id) {
            try { if ($p.StartTime -lt $rootStart) { continue } } catch { continue }
        }
        Write-Info "Encerrando PID $id ($($p.ProcessName)) iniciado pelo teste" 'cleanup'
        try { Stop-Process -Id $id -ErrorAction Stop } catch { Write-Warn "Não foi possível encerrar PID ${id}: $($_.Exception.Message)" 'cleanup' }
    }
}

function Get-FreeTcpPort {
    # Retorna Preferred se livre em 127.0.0.1; caso contrário, uma porta livre qualquer.
    param([int]$Preferred)
    foreach ($port in @($Preferred, 0)) {
        $l = $null
        try {
            $l = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $port)
            $l.Start()
            return ([Net.IPEndPoint]$l.LocalEndpoint).Port
        } catch {
            Write-DevLog -Level DEBUG -Message "Porta $port indisponível: $($_.Exception.Message)"
        } finally {
            if ($l) { $l.Stop() }
        }
    }
    throw 'Nenhuma porta TCP livre encontrada.'
}

function Wait-HttpEndpoint {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [int]$TimeoutSeconds = 60,
        [System.Diagnostics.Process]$Process
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $last = ''
    while ((Get-Date) -lt $deadline) {
        if ($Process) { $Process.Refresh(); if ($Process.HasExited) { throw "Processo $($Process.Id) terminou antes de responder (exit $($Process.ExitCode))." } }
        try {
            $resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            return $resp
        } catch {
            $last = $_.Exception.Message
            Start-Sleep -Milliseconds 750
        }
    }
    throw "Timeout ($TimeoutSeconds s) aguardando $Uri. Último erro: $last"
}

function New-DevStackTempDir {
    param([Parameter(Mandatory)][string]$Prefix)
    $ctx = Get-DevStackContext
    if (-not (Test-Path -LiteralPath $ctx.Paths.TempRoot)) { New-Item -ItemType Directory -Path $ctx.Paths.TempRoot | Out-Null }
    $name = '{0}-{1}-{2}' -f $Prefix, (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 6))
    $dir = Join-Path $ctx.Paths.TempRoot $name
    New-Item -ItemType Directory -Path $dir | Out-Null
    Set-Content -LiteralPath (Join-Path $dir '.devstack-temp') -Value 'Criado pelo DevStack (teste temporário).' -Encoding UTF8
    return $dir
}

function Remove-DevStackTempDir {
    # Remove apenas diretórios criados por New-DevStackTempDir (marcador + dentro de TempRoot).
    param([Parameter(Mandatory)][string]$Path)
    $ctx = Get-DevStackContext
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($ctx.Paths.TempRoot).TrimEnd('\') + '\'
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { Write-Warn "Remoção recusada (fora de TempRoot): $full" 'cleanup'; return }
    if (-not (Test-Path -LiteralPath (Join-Path $full '.devstack-temp'))) { Write-Warn "Remoção recusada (sem marcador): $full" 'cleanup'; return }
    for ($i = 1; $i -le 5; $i++) {
        try {
            Remove-Item -LiteralPath $full -Recurse -ErrorAction Stop
            Write-Info "Diretório temporário removido: $full" 'cleanup'
            return
        } catch {
            if ($i -eq 5) { Write-Warn "Não foi possível remover $full : $($_.Exception.Message)" 'cleanup'; return }
            Start-Sleep -Seconds 2
        }
    }
}

function Write-Utf8File {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, ($Content -replace "`r`n", "`n"), $enc)
}
