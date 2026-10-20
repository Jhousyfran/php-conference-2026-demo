#!/usr/bin/env bash
# Checklist pré-palestra: valida containers, extensão, endpoints e traces no Tempo.
set -u

cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

APP_URL="http://localhost:${APP_PORT:-8080}"
GRAFANA_URL="http://localhost:${GRAFANA_PORT:-3000}"
TEMPO_URL="http://localhost:3200"
SERVICE="demo-pedidos"

ok=0; fail=0
pass() { printf '  \033[32m✔\033[0m %s\n' "$1"; ok=$((ok + 1)); }
nok()  { printf '  \033[31m✘\033[0m %s\n' "$1"; fail=$((fail + 1)); }

echo "1. Containers"
running=$(docker compose ps --status running --services 2>/dev/null)
for svc in app nginx mysql collector tempo grafana; do
  if grep -qx "$svc" <<<"$running"; then pass "$svc rodando"; else nok "$svc NÃO está rodando"; fi
done

echo "2. Extensão opentelemetry"
if out=$(docker compose exec -T app php --ri opentelemetry 2>&1); then
  pass "carregada ($(grep -m1 'extension version' <<<"$out" | sed 's/.*=> //'))"
else
  nok "php --ri opentelemetry falhou: $out"
fi

echo "3. Endpoints"
for path in /api/pedidos /api/pedidos-otimizado; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$APP_URL$path")
  if [ "$code" = "200" ]; then pass "GET $path -> 200"; else nok "GET $path -> $code"; fi
done

echo "4. Grafana"
if curl -sf --max-time 5 "$GRAFANA_URL/api/health" >/dev/null; then pass "Grafana em $GRAFANA_URL"; else nok "Grafana não responde em $GRAFANA_URL"; fi
if curl -sf --max-time 5 "$GRAFANA_URL/api/datasources/uid/tempo" >/dev/null; then pass "datasource Tempo provisionado"; else nok "datasource Tempo não encontrado"; fi

echo "5. Traces do serviço $SERVICE no Tempo"
# Com o Tempo recém-zerado (make clean), o primeiro trace pode levar mais de 30 s
# para aparecer na busca. Espera até TRACE_TIMEOUT segundos (padrão 90).
TRACE_TIMEOUT=${TRACE_TIMEOUT:-90}
found=""
for i in $(seq 1 $((TRACE_TIMEOUT / 3))); do
  [ "$i" -eq 2 ] && printf '  … aguardando o Tempo indexar (até %ss)\n' "$TRACE_TIMEOUT"
  now=$(date +%s)
  res=$(curl -s -G --max-time 5 "$TEMPO_URL/api/search" \
    --data-urlencode "q={ resource.service.name = \"$SERVICE\" }" \
    --data-urlencode "start=$((now - 3600))" --data-urlencode "end=$((now + 60))" \
    --data-urlencode "limit=5")
  if grep -q '"traceID"' <<<"$res"; then found=$res; break; fi
  sleep 3
done
if [ -n "$found" ]; then
  id=$(grep -o '"traceID":"[0-9a-f]*"' <<<"$found" | head -1 | cut -d'"' -f4)
  pass "trace encontrado (ex.: $id)"
else
  nok "nenhum trace de $SERVICE após ${TRACE_TIMEOUT}s (veja a seção Troubleshooting do README)"
fi

echo
if [ "$fail" -eq 0 ]; then
  printf '\033[32mTudo certo: %d verificações OK.\033[0m\n' "$ok"
else
  printf '\033[31m%d falha(s), %d OK.\033[0m\n' "$fail" "$ok"
  exit 1
fi
