@{
    # ------------------------------------------------------------------
    # Configuração central do DevStack. NÃO grave segredos aqui.
    # Caminhos aceitam variáveis de ambiente no formato %VAR%.
    # Caminhos relativos são resolvidos a partir da raiz do pacote.
    # ------------------------------------------------------------------

    StackName          = 'DevStack'

    # Raiz isolada da nova stack (uv, Python gerenciado, Node 26, caches).
    StackRoot          = '%LOCALAPPDATA%\DevStack'

    # Logs e inventários (relativo à raiz do pacote).
    LogDirectory       = 'logs'

    # Diretório-base dos testes temporários (backend/frontend).
    TempRoot           = '%TEMP%\devstack-tests'

    # ---------------- Python / uv ----------------
    PythonVersion      = '3.14'
    UvVersion          = '0.13.7'
    UvReleaseBaseUrl   = 'https://github.com/astral-sh/uv/releases/download'

    # ---------------- Node.js ----------------
    NodeMajorVersion   = 26
    # Versão exata (reprodutível). Deixe '' para usar a LTS mais recente da major.
    NodeVersion        = '26.13.0'
    NodeDistBaseUrl    = 'https://nodejs.org/dist'

    # create-vite fixado para reprodutibilidade do teste de frontend.
    CreateViteVersion  = '9.3.4'

    # ---------------- WinGet ----------------
    WinGetPackages     = @{
        PowerShell = @{ Id = 'Microsoft.PowerShell';       Scope = '' }      # WinGet escolhe MSIX ou MSI (o MSI exige UAC)
        Git        = @{ Id = 'Git.Git';                    Scope = '' }
        VSCode     = @{ Id = 'Microsoft.VisualStudioCode'; Scope = 'user' }
    }

    # ---------------- VS Code ----------------
    VSCodeExtensions   = @(
        'ms-python.python'          # Python
        'ms-python.vscode-pylance'  # Pylance
        'charliermarsh.ruff'        # Ruff
        'dbaeumer.vscode-eslint'    # ESLint
        'esbenp.prettier-vscode'    # Prettier
        'ms-vscode.powershell'      # PowerShell
    )

    # ---------------- Testes ----------------
    BackendPort        = 8000
    FrontendPort       = 5173
    HttpTimeoutSeconds = 90
}
