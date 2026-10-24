#!/usr/bin/env bash
# Tráfego contínuo e leve para a VM da palestra: chamado pelo cron a cada minuto,
# roda ~50 s e sai. Mantém o dashboard e os logs com dados sem pesar na máquina.
#
# Por minuto (~0,7 req/s): ~17x otimizado, ~17x pagamento e ~6x N+1.
# Travas: não roda se o disco dos dados passar de MAX_DISCO_PCT ou se a memória
# disponível da máquina estiver abaixo de MIN_MEM_MB (protege os outros sites da VM).
# O cron ainda usa flock (nunca duas execuções juntas) e timeout.
set -u
cd "$(dirname "$0")/.."
[ -f .env.vm ] && set -a && . ./.env.vm && set +a

app="http://127.0.0.1:${APP_PORT:-8090}"
duracao=${DURACAO:-50}
pausa=${PAUSA:-3}
disco=${DISCO_DADOS:-/data}
max_disco=${MAX_DISCO_PCT:-85}
min_mem=${MIN_MEM_MB:-400}

uso_disco=$(df --output=pcent "$disco" | tail -1 | tr -dc '0-9')
mem_livre=$(awk '/MemAvailable/ {print int($2 / 1024)}' /proc/meminfo)
agora=$(date '+%F %T')

if [ "$uso_disco" -ge "$max_disco" ]; then
  echo "$agora PULADO: disco $disco em ${uso_disco}% (limite ${max_disco}%)"; exit 0
fi
if [ "$mem_livre" -lt "$min_mem" ]; then
  echo "$agora PULADO: memória disponível ${mem_livre} MB (mínimo ${min_mem} MB)"; exit 0
fi

fim=$(( $(date +%s) + duracao ))
n=0; erros=0; falhas=0; rodada=0
req() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@") || code=000
  n=$((n + 1))
  case "$code" in
    200) ;;
    500) erros=$((erros + 1)) ;;   # gateway simulado: esperado
    *)   falhas=$((falhas + 1)) ;; # app fora do ar, timeout...
  esac
}

while [ "$(date +%s)" -lt "$fim" ]; do
  rodada=$((rodada + 1))
  req "$app/api/pedidos-otimizado"
  req -X POST "$app/api/pagamentos"
  [ $((rodada % 3)) -eq 0 ] && req "$app/api/pedidos"
  sleep "$pausa"
done

echo "$agora ok: $n requisições, $erros pagamentos com 500, $falhas falhas; disco ${uso_disco}%, mem livre ${mem_livre} MB"
