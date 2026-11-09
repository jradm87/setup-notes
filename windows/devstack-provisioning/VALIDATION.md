# VALIDATION

## Executar

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-DevStack.ps1
```

Opções: `-SkipBackend`, `-SkipFrontend`, `-KeepTemp` (mantém os projetos temporários para inspeção).

`Test-DevStack.ps1` **não instala nada**. Ele:

1. valida as ferramentas (`scripts\11-Validate.ps1`);
2. roda o teste FastAPI (`scripts\09-Test-Backend.ps1`);
3. roda o teste React/Vite (`scripts\10-Test-Frontend.ps1`).

Os testes baixam pacotes do PyPI e do npm **para diretórios temporários** e para os caches
(`DevStack\uv\cache` e o cache padrão do npm). Nada fica instalado globalmente.

## Saída esperada

```
PowerShell          OK       pwsh 7 (7.6.x)
Git                 OK       (git version 2.56.0.windows.4)
uv                  OK       devstack (uv 0.13.7)
Python 3.14         OK       isolado (uv) (Python 3.14.x)
Node 26             OK       devstack (v26.13.0)
npm                 OK       distribuído com o Node 26 (11.x)
VS Code             OK       extensões OK (1.104.0)
OpenSSH             OK       (OpenSSH_for_Windows_9.5p2 ...)
Ambiente existente  OK       Preservado em relação ao baseline
FastAPI             OK       Teste aprovado
pytest              OK       Teste aprovado
Ruff                OK       Teste aprovado
React/Vite          OK       Teste aprovado
TypeScript          OK       Teste aprovado
ESLint              OK       Teste aprovado
Prettier            OK       Teste aprovado
Frontend build      OK       Teste aprovado
Vite dev server     OK       Teste aprovado

Resultado geral:
PASS
```

## Interpretação

| Status | Significado |
|---|---|
| OK | Presente e funcional |
| SKIPPED | Não executado (opção `-Skip*` ou DRY-RUN) |
| WARNING | Funciona, mas há algo a revisar (ex.: extensão VS Code ausente, ESLint com avisos, ambiente antigo diferente do baseline) |
| FAILED | Ausente ou com falha. O resultado geral fica **FAIL** |

**Exit code:** `0` = PASS (nenhum FAILED) · `1` = FAIL · `2` = erro fatal (config ausente etc.).

```powershell
.\Test-DevStack.ps1; if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }
```

## "Ambiente existente"

Compara o estado atual com `logs\inventory-baseline.json`, gravado na **primeira** execução do instalador:

- caminho e versão do `python` padrão;
- caminho e versão do `node` padrão;
- saída de `py -0p` (se o 3.14 aparecer aqui, ele foi registrado no Windows, o que não deveria acontecer);
- nenhuma entrada **removida** do PATH do usuário ou do sistema.

Um WARNING aqui merece investigação. Pode ser causado por algo externo ao DevStack, como um
`fnm use` ou uma atualização feita por outra ferramenta.

## Onde olhar quando algo falha

- `logs\test-<timestamp>.log`: cada comando executado, exit code e saída (com segredos mascarados);
- `-KeepTemp`: mantém `%TEMP%\devstack-tests\...` com `uvicorn.*.log` e `vite.*.log`;
- `.\Show-DevStackStatus.ps1`: caminhos físicos de cada executável.
