# ARCHITECTURE

## Visão geral

```
                Desenvolvimento (agora)                     Produção (futuro)
┌──────────────────────────────────────────┐        ┌─────────────────────────────┐
│ Windows 11 nativo                        │        │ Linux + containers          │
│                                          │        │ (imagens OCI, ex. python:   │
│  ambiente existente (intocado)           │        │  3.14-slim, node:26-alpine) │
│   python 3.12 · py · node 22 (fnm) · ... │        │                             │
│                                          │  ───►  │ Mesmo código, mesmas deps   │
│  %LOCALAPPDATA%\DevStack (isolado)       │        │ declaradas (pyproject/uv.lock│
│   uv\bin\uv.exe                          │        │ e package-lock.json)        │
│   python\cpython-3.14.x-...              │        │                             │
│   node\node-v26.x-win-x64                │        │                             │
│   uv\cache · downloads                   │        │                             │
│                                          │        │                             │
│  Enter-DevStack.ps1 → PATH do PROCESSO   │        │                             │
└──────────────────────────────────────────┘        └─────────────────────────────┘
```

**Esta etapa NÃO instala** Docker, Docker Desktop, Podman, WSL, Kubernetes, bancos de dados,
Redis, Anaconda/Miniconda, Poetry, Pipenv, Yarn, pnpm nem Bun. Também não escolhe banco nem ORM
e não configura CI/CD, Git remoto ou chaves SSH.

## Isolamento

| Item | Onde fica | Como é ativado |
|---|---|---|
| uv | `DevStack\uv\bin` (ou um uv já existente) | `Enter-DevStack.ps1` (PATH do processo) |
| Python 3.14 | `DevStack\python` (`UV_PYTHON_INSTALL_DIR`) | `uv venv/run --python 3.14` |
| Node 26 + npm | `DevStack\node\node-v26.x-win-<arch>` | `Enter-DevStack.ps1` (PATH do processo) |
| Dependências de projeto | `.venv` e `node_modules` **de cada projeto** | `uv sync` / `npm install` |

O `Enter-DevStack.ps1` mexe **só** nas variáveis de ambiente do processo. Fechar o terminal ou
rodar `Exit-DevStack.ps1` desfaz tudo. Outros terminais, o fnm e outros projetos não percebem nada.

### Coexistência com o fnm (Node 22)

O fnm continua sendo a ferramenta dos projetos existentes. O Node 26 da stack **não** é registrado
no fnm. Se um projeto novo precisar do Node 26 sem o `Enter-DevStack`, uma alternativa futura é
`fnm install 26` + `.node-version`. Essa decisão fica para você; o pacote não a toma.

## Diretrizes para novos projetos (compatibilidade com Linux)

- **Paths relativos** à raiz do projeto, nunca `C:\...`.
- Python: **`pathlib.Path`** para caminhos. Nada de concatenar com `\`.
- Arquivos em **UTF-8**, abertos com `encoding="utf-8"` explícito. Fins de linha LF no repositório (`.gitattributes`).
- Configuração por **variáveis de ambiente** (pydantic-settings). Um `.env` local nunca vai para o versionamento.
- **Nada de Registry** (`winreg`), **COM** (`pywin32`/`comtypes`) ou chamadas a `cmd`/`powershell` dentro da aplicação.
- Nenhuma biblioteca exclusiva de Windows sem justificativa registrada.
- **Case-sensitive**: `Models.py` ≠ `models.py` no Linux. Imports e nomes de arquivos devem bater exatamente.
- **Dependências declaradas e travadas**: `pyproject.toml` + `uv.lock` e `package.json` + `package-lock.json`.
- **Nenhum secret no código** nem em imagens. Use variáveis de ambiente ou secret manager em produção.
- Escutar em host/porta configuráveis (`0.0.0.0` dentro do container, `127.0.0.1` local).
- Scripts de projeto (`package.json` scripts, tarefas) multiplataforma, sem `.bat`/`.ps1` obrigatórios.
