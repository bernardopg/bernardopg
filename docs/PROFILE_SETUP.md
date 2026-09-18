# Setup do perfil

Como os gráficos do `README.md` são gerados, e o que fazer quando algum deles aparece vazio.

## 🔴 O problema mais comum: cartão de métricas vazio

Se o cartão **Open-source signals** mostrar algo assim:

```text
1 Repository
0 Languages
No push activity found
Member of 0 organizations
```

…não é bug do `lowlighter/metrics`. É **escopo de token**.

### Causa

O `secrets.GITHUB_TOKEN` é gerado automaticamente pelo Actions e tem escopo
**restrito ao repositório que executa o workflow**. Como este é o repositório de
perfil (`bernardopg/bernardopg`), o token literalmente só enxerga **1 repositório** —
por isso `1 Repository`, `0 Languages` e `No push activity found`.

### Solução rápida — script automatizado

```bash
./scripts/setup-metrics-token.sh
```

O script abre o formulário do GitHub já pré-preenchido com nome e escopos corretos,
valida o token colado (usuário, escopos e quantos repositórios ele enxerga),
grava o secret e dispara o workflow. Só o clique em *Generate token* é manual —
a API do GitHub não permite criar PAT programaticamente, por design.

```bash
./scripts/setup-metrics-token.sh --check   # só diagnostica, não altera nada
./scripts/setup-metrics-token.sh --use-gh  # reaproveita o token do gh (escopo mais amplo)
```

### Solução manual — criar o secret `METRICS_TOKEN`

1. Acesse **[github.com/settings/tokens](https://github.com/settings/tokens)** →
   *Generate new token* → **Tokens (classic)**.
2. Nome sugerido: `metrics-profile-readme`.
3. Validade: `No expiration` (ou 1 ano, com lembrete para renovar).
4. Marque **apenas** estes escopos:

   | Escopo | Para quê |
   | :-- | :-- |
   | `public_repo` | ler os repositórios públicos, linguagens e commits |
   | `read:user` | ler perfil, seguidores e organizações |
   | `read:org` *(opcional)* | incluir contribuições em organizações |

   > ⚠️ **Não** marque `repo` inteiro, `delete_repo`, `admin:*` nem `workflow`.
   > O token é somente-leitura por design.

5. Copie o token gerado.
6. Vá em **Settings → Secrets and variables → Actions → New repository secret**
   deste repositório.
7. Nome: `METRICS_TOKEN` · Valor: o token copiado.

### Verificar

Rode o workflow manualmente:

> **Actions → 🎨 Atualizar assets do perfil → Run workflow**

O primeiro passo (`🔎 Conferir token de métricas`) escreve no *job summary*:

- ✅ `METRICS_TOKEN encontrado` → tudo certo, as métricas cobrem todos os repos.
- ⚠️ `METRICS_TOKEN ausente` → o secret não foi criado ou está com nome diferente.

---

## 🧱 Como os assets funcionam

Todos os gráficos são **gerados por Actions e commitados como SVG** dentro de
`.github/assets/`. O README aponta para arquivos locais, nunca para um serviço externo.

Vantagens:

- o README não quebra se um serviço de terceiros cair ou aplicar rate limit;
- o proxy de imagens do GitHub (camo) serve arquivo local instantaneamente;
- o histórico do repositório vira um registro visual da evolução do perfil.

### Inventário

| Arquivo | Gerado por | Frequência |
| :-- | :-- | :-- |
| `hero-dark.svg` · `hero-light.svg` | **feito à mão** — o workflow nunca sobrescreve | manual |
| `metrics.base.svg` | `lowlighter/metrics` · base + activity + community | diário |
| `metrics.languages.svg` | `lowlighter/metrics` · plugin `languages` (indepth) | diário |
| `metrics.calendar.svg` | `lowlighter/metrics` · plugin `isocalendar` | diário |

> `metrics.habits.svg` foi desativado: o plugin `habits` quebra com commits de bot
> (bug conhecido de destruturação), e este repo é atualizado pelo `github-actions[bot]`.
> O passo permanece no workflow com `if: false` para reavaliação futura.
| `contributions-3d.svg` | `yoshi389111/github-profile-3d-contrib` | diário |
| `snake.svg` · `snake-dark.svg` | `Platane/snk` | diário |

O workflow roda às **06:23 UTC** (≈ 03:23 em São Paulo), fora do pico da API do GitHub.

### Gerar sem publicar

Para testar mudanças sem sujar o histórico:

**Actions → 🎨 Atualizar assets do perfil → Run workflow →**
marque **“Só gerar os assets (sem commitar)”**.

Os SVGs ficam disponíveis como *artifacts* do job por 1 dia.

---

## 🎨 Editar os heroes

`hero-dark.svg` e `hero-light.svg` são SVG escritos à mão — sem dependência de fonte
externa, sem raster, sem build step. As animações usam SMIL (`<animate>`), que o
GitHub renderiza normalmente dentro de `<picture>`.

Ao editar, preserve:

- `width="1280" height="400"` e o `viewBox` — o README assume essa proporção;
- os elementos `<title>` e `<desc>` — são o que leitores de tela anunciam;
- o par claro/escuro em sincronia, para que a troca de tema não mude o layout.

O job `Workflows e SVG` valida os dois arquivos com um parser XML em cada PR.

---

## 🔁 Manutenção

- **Dependabot** acompanha as actions (`.github/dependabot.yml`) e abre PR de bump.
- Toda action está **fixada por SHA** com o comentário da tag ao lado — o
  `actionlint` roda em cada PR.
- Se um gráfico opcional falhar (`habits`, `isocalendar`, `3d-contrib`), o passo tem
  `continue-on-error: true`: o workflow segue e mantém a versão anterior do arquivo.
