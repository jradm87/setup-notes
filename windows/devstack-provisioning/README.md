# devstack-provisioning

Pacote PowerShell para provisionar uma **nova stack de desenvolvimento** em uma estação Windows
que **já possui outros projetos**, de forma **aditiva, idempotente e não destrutiva**.

| Camada | Componentes |
|---|---|
| Backend | Python 3.14 (gerenciado pelo uv), uv, FastAPI, Pydantic, pydantic-settings, httpx, pytest, Ruff |
| Frontend | Node.js 26 LTS, npm, React, TypeScript, Vite, ESLint, Prettier |
| Ferramentas | PowerShell 7, Git for Windows, VS Code, OpenSSH Client |

Desenvolvimento em **Windows nativo**. A produção futura será **Linux em containers** (ver
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)). Esta etapa **não instala Docker** nem nada de containers.

## Princípios

- Nada existente é removido, atualizado, substituído ou reconfigurado.
- Sem `winget upgrade`, sem `--force`, sem `npm install -g`, sem `pip install --upgrade` global.
- O PATH persistente **nunca** é alterado pelos scripts da stack. Os instaladores oficiais via WinGet
  (PowerShell 7 e, se ausentes, Git/VS Code) acrescentam suas próprias entradas.
- O uv, o Python 3.14 e o Node 26 ficam isolados em `%LOCALAPPDATA%\DevStack` e são ativados
  **por sessão** com `Enter-DevStack.ps1`.
- O Python 3.14 é instalado com `--no-registry --no-bin`, então `python` e `py` continuam como estão.
- Os testes encerram **somente** os PIDs que eles mesmos iniciaram.

## Pré-requisitos

- Windows 10/11 x64 ou arm64
- Windows PowerShell 5.1 (nativo) ou PowerShell 7
- WinGet (só se for preciso instalar PowerShell 7, Git ou VS Code)
- Acesso HTTPS a `nodejs.org`, `github.com`, `pypi.org`, `registry.npmjs.org` e ao marketplace do VS Code
- Administrador: **não** é necessário para a maior parte. O PowerShell 7 só pede UAC se o WinGet escolher o instalador MSI.
  O OpenSSH Client exige sessão elevada, mas só se estiver ausente.

## Arquivos

```
devstack-provisioning/
├── README.md                 este arquivo
├── INSTALLATION.md           passo a passo de cada etapa
├── VALIDATION.md             como validar e interpretar resultados
├── PROMPT-DEVSTACK.md        instruções para o Claude: copiar para o projeto como CLAUDE.md
├── Install-DevStack.ps1      orquestrador (suporta -DryRun)
├── Test-DevStack.ps1         validação + testes FastAPI e React/Vite (não instala nada)
├── Show-DevStackStatus.ps1   versões/caminhos: ambiente existente x nova stack (somente leitura)
├── Enter-DevStack.ps1        ativa a stack na sessão atual (PATH/variáveis do processo)
├── Exit-DevStack.ps1         desfaz o Enter-DevStack na sessão atual
├── config/DevStackConfig.psd1  versões, caminhos e portas (sem segredos)
├── scripts/
│   ├── 00-Common.ps1         logging, execução nativa, downloads verificados, processos
│   ├── 01-Inventory.ps1      inventário somente leitura -> JSON
│   ├── 02..08-Install-*.ps1  uma etapa por componente
│   ├── 09-Test-Backend.ps1   projeto FastAPI temporário
│   ├── 10-Test-Frontend.ps1  projeto React+TS+Vite temporário
│   └── 11-Validate.ps1       validação das ferramentas + preservação do ambiente
├── docs/ARCHITECTURE.md | CHANGES.md | TROUBLESHOOTING.md
└── logs/                     logs e inventários (ignorados pelo git)
```

## Uso

Abra o PowerShell **nesta pasta**. A ExecutionPolicy só é contornada no processo, sem alteração permanente:

```powershell
# 1) Simulação: nada é instalado ou alterado
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-DevStack.ps1 -DryRun

# 2) Instalação real (idempotente: pode ser executada de novo)
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-DevStack.ps1

# 3) Validação (exit code 0 = PASS)
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-DevStack.ps1

# 4) Versões e caminhos (antigo x novo)
powershell -NoProfile -ExecutionPolicy Bypass -File .\Show-DevStackStatus.ps1
```

Para usar a stack no terminal atual:

```powershell
Set-ExecutionPolicy -Scope Process Bypass   # só para esta janela
.\Enter-DevStack.ps1
node --version              # v26.x (da stack)
uv venv --python 3.14
.\Exit-DevStack.ps1         # volta ao Node/uv anteriores
```

Opções úteis do instalador: `-SkipTests`, `-SkipVSCodeExtensions`, `-KeepTemp`.

> Se o pacote veio de um ZIP baixado, desbloqueie antes:
> `Get-ChildItem -Recurse | Unblock-File`.
