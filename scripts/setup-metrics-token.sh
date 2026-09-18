#!/usr/bin/env bash
# Configura o secret METRICS_TOKEN usado pelo workflow "Atualizar assets do perfil".
#
# Por que este script existe:
#   O GitHub não permite criar Personal Access Tokens via API — é uma proteção
#   deliberada contra escalonamento de privilégio. O único passo manual possível
#   é o clique em "Generate token". Todo o resto (URL pré-preenchida, validação
#   de escopos, gravação do secret, disparo do workflow) está automatizado aqui.
#
# Uso:
#   ./scripts/setup-metrics-token.sh              # fluxo recomendado (PAT dedicado)
#   ./scripts/setup-metrics-token.sh --use-gh     # atalho: reaproveita o token do gh
#   ./scripts/setup-metrics-token.sh --check      # só diagnostica, não altera nada

set -euo pipefail

REPO="bernardopg/bernardopg"
SECRET="METRICS_TOKEN"
WORKFLOW="profile-assets.yml"
TOKEN_URL="https://github.com/settings/tokens/new?description=metrics-profile-readme&scopes=public_repo,read:user,read:org"

bold=$'\e[1m'; dim=$'\e[2m'; red=$'\e[31m'; green=$'\e[32m'
yellow=$'\e[33m'; cyan=$'\e[36m'; reset=$'\e[0m'

say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s!%s %s\n' "$yellow" "$reset" "$*"; }
die()  { printf '%s✗%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }
step() { printf '\n%s▸ %s%s\n' "$bold" "$*" "$reset"; }

MODE="interactive"
for arg in "$@"; do
  case "$arg" in
    --use-gh) MODE="gh-token" ;;
    --check)  MODE="check" ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Opção desconhecida: $arg" ;;
  esac
done

# ── Pré-requisitos ──────────────────────────────────────────────────────────
step "Verificando pré-requisitos"
command -v gh >/dev/null || die "gh não encontrado. Instale: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh não autenticado. Rode: gh auth login"
ok "gh autenticado como $(gh api user --jq .login)"

# ── Diagnóstico ─────────────────────────────────────────────────────────────
step "Diagnóstico do repositório $REPO"
if gh secret list --repo "$REPO" 2>/dev/null | grep -q "^${SECRET}\b"; then
  ok "$SECRET já existe"
  EXISTS=1
else
  warn "$SECRET ausente — é por isso que o cartão mostra '1 Repository / 0 Languages'"
  EXISTS=0
fi

VISIBLE=$(gh api 'user/repos?per_page=100&affiliation=owner' --jq 'length' 2>/dev/null || echo '?')
say "${dim}  Repositórios que um token completo enxergaria: ${VISIBLE}${reset}"
say "${dim}  Repositórios que o GITHUB_TOKEN padrão enxerga: 1${reset}"

if [ "$MODE" = "check" ]; then
  say ""
  if [ "$EXISTS" -eq 1 ]; then
    ok "Nada a fazer."
  else
    warn "Rode sem --check para configurar."
  fi
  exit 0
fi

if [ "$EXISTS" -eq 1 ]; then
  read -rp $'\n'"Sobrescrever o $SECRET existente? [s/N] " reply
  [[ "$reply" =~ ^[SsYy]$ ]] || { say "Cancelado."; exit 0; }
fi

# ── Obter o token ───────────────────────────────────────────────────────────
if [ "$MODE" = "gh-token" ]; then
  step "Reaproveitando o token da sessão do gh"
  warn "Esse token tem escopo 'repo' e 'workflow' (escrita) — mais amplo que o necessário."
  warn "Ele também é revogado se você rodar 'gh auth login' de novo."
  warn "Para uso duradouro, prefira o fluxo padrão (sem --use-gh)."
  read -rp "Continuar assim mesmo? [s/N] " reply
  [[ "$reply" =~ ^[SsYy]$ ]] || { say "Cancelado."; exit 0; }
  TOKEN="$(gh auth token)"
else
  step "Criando um Personal Access Token dedicado"
  cat <<EOF

  Vou abrir o formulário do GitHub ${bold}já preenchido${reset} com:

    Nome     ${cyan}metrics-profile-readme${reset}
    Escopos  ${cyan}public_repo${reset}  ler repositórios públicos e linguagens
             ${cyan}read:user${reset}    ler perfil e seguidores
             ${cyan}read:org${reset}     incluir contribuições em organizações

  ${dim}Todos são somente-leitura. Não marque 'repo', 'delete_repo' nem 'admin:*'.${reset}

  Role até o fim da página e clique em ${bold}Generate token${reset}.

EOF
  read -rp "  Pressione ENTER para abrir o navegador (ou Ctrl-C para sair) "

  if command -v xdg-open >/dev/null; then xdg-open "$TOKEN_URL" >/dev/null 2>&1 &
  elif command -v open  >/dev/null; then open "$TOKEN_URL" >/dev/null 2>&1 &
  else warn "Abra manualmente:"; say "  $TOKEN_URL"; fi

  say ""
  read -rsp "  Cole o token aqui (não aparece na tela): " TOKEN
  say ""
fi

TOKEN="${TOKEN//[[:space:]]/}"
[ -n "$TOKEN" ] || die "Token vazio."

# ── Validar antes de gravar ─────────────────────────────────────────────────
step "Validando o token"
HEADERS=$(curl -sS -D - -o /dev/null -H "Authorization: Bearer $TOKEN" \
  https://api.github.com/user) || die "Falha ao contatar a API do GitHub."

grep -qi '^HTTP/[0-9.]* 200' <<<"$HEADERS" || die "Token inválido ou expirado."

LOGIN=$(curl -sS -H "Authorization: Bearer $TOKEN" https://api.github.com/user | \
  grep -o '"login"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
SCOPES=$(grep -i '^x-oauth-scopes:' <<<"$HEADERS" | cut -d: -f2- | tr -d ' \r')

ok "Token válido para o usuário ${bold}${LOGIN}${reset}"
say "${dim}  Escopos: ${SCOPES:-<nenhum>}${reset}"

[ "$LOGIN" = "bernardopg" ] || warn "O token pertence a '$LOGIN', não a 'bernardopg'."

MISSING=""
for scope in public_repo read:user; do
  grep -qE "(^|,)(${scope}|repo|user)(,|$)" <<<"$SCOPES" || MISSING="$MISSING $scope"
done
if [ -n "$MISSING" ]; then
  warn "Escopos possivelmente ausentes:$MISSING"
  read -rp "Gravar mesmo assim? [s/N] " reply
  [[ "$reply" =~ ^[SsYy]$ ]] || die "Cancelado. Gere um token com os escopos corretos."
else
  ok "Escopos suficientes para as métricas"
fi

REPO_COUNT=$(curl -sS -H "Authorization: Bearer $TOKEN" \
  'https://api.github.com/user/repos?per_page=100&affiliation=owner' | \
  grep -c '"full_name"' || true)
ok "Este token enxerga ${bold}${REPO_COUNT}${reset} repositórios (antes: 1)"

# ── Gravar e disparar ───────────────────────────────────────────────────────
step "Gravando o secret"
printf '%s' "$TOKEN" | gh secret set "$SECRET" --repo "$REPO" --body -
ok "$SECRET gravado em $REPO"
unset TOKEN

step "Disparando o workflow"
if gh workflow run "$WORKFLOW" --repo "$REPO" 2>/dev/null; then
  ok "Workflow disparado"
  sleep 4
  gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 1 2>/dev/null || true
  say ""
  say "  Acompanhe:  ${cyan}gh run watch --repo $REPO${reset}"
  say "  Ou no site: ${cyan}https://github.com/$REPO/actions${reset}"
else
  warn "Não consegui disparar automaticamente (o workflow precisa estar em main)."
  say "  Dispare em: https://github.com/$REPO/actions/workflows/$WORKFLOW"
fi

say ""
ok "${bold}Pronto.${reset} Em ~3 min os gráficos do README mostram os ${REPO_COUNT} repositórios."
