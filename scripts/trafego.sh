#!/usr/bin/env bash
# Gera tráfego misto por DURACAO segundos para alimentar o dashboard RED:
# por rodada, 1x N+1, 2x otimizado e 2x pagamento (este falha em ~20% das vezes).
# Uso: scripts/trafego.sh [DURACAO]   (padrão 120 s; Ctrl+C para parar antes)
set -u
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a
app="http://localhost:${APP_PORT:-8080}"
duracao=${1:-120}
fim=$(( $(date +%s) + duracao ))

echo "Gerando tráfego por ${duracao}s em $app (Ctrl+C para parar)"
n=0; erros=0
while [ "$(date +%s)" -lt "$fim" ]; do
  curl -s -o /dev/null "$app/api/pedidos"
  curl -s -o /dev/null "$app/api/pedidos-otimizado"
  curl -s -o /dev/null "$app/api/pedidos-otimizado"
  for _ in 1 2; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$app/api/pagamentos")
    [ "$code" = "500" ] && erros=$((erros + 1))
  done
  n=$((n + 5))
  printf '\r  %d requisições, %d pagamentos com HTTP 500' "$n" "$erros"
done
echo
