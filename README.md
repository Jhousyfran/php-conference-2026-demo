<p align="center">
  <a href="https://phpconference.com.br/palestras-php-conference-brasil-2026/">
    <img src="docs/capa-php-conference-brasil-2026.png" alt="PHP Conference Brasil 2026" width="100%">
  </a>
</p>

# Demo: encontrando um N+1 em Laravel com OpenTelemetry

> Live demo da palestra na **[PHP Conference Brasil 2026](https://phpconference.com.br/palestras-php-conference-brasil-2026/)**.

Live demo para palestra sobre observabilidade em PHP. Uma aplicação Laravel com uma
query N+1 proposital é instrumentada **sem nenhuma linha de código de telemetria no
controller**. Os traces vão para o OpenTelemetry Collector, depois para o Grafana Tempo,
e no Grafana o N+1 aparece como uma "escadinha" de 201 spans `sql SELECT`.

```
curl ──> nginx ──> PHP-FPM (Laravel + ext-opentelemetry + SDK)
                        │  OTLP http/protobuf :4318
                        ▼
                   OTel Collector ──(OTLP gRPC)──> Tempo :3200 <──────┐
                        ├── connector span_metrics ──> :8889 <── Prometheus :9090 <── Grafana
                        ├── logs (OTLP) ──> Loki :3100 <───────────────────┘
                        └── exporter debug (log)
```

Além do trace, o Collector transforma os spans em **métricas RED** (Rate, Errors, Duration)
e o Grafana já sobe com um dashboard pronto (veja [Dashboard RED](#dashboard-red-rate-errors-duration)).
Os logs do Laravel também saem via OTLP para o Loki, com `trace_id` e `span_id`, e o Grafana
navega de trace para log e de log para trace (veja [Log ↔ trace](#correlação-log--trace)).

## Stack e versões (todas testadas juntas)

| Componente | Versão |
|---|---|
| PHP (FPM) | 8.3 (`php:8.3-fpm-bookworm`, testado com 8.3.35) |
| Extensão `opentelemetry` (PECL) | 1.4.2 |
| Laravel (`laravel/framework`) | 13.37.0 |
| `open-telemetry/sdk` | 1.15.0 |
| `open-telemetry/exporter-otlp` | 1.4.0 |
| `open-telemetry/opentelemetry-auto-laravel` | 1.10.0 (suporta Laravel 10–13) |
| `open-telemetry/opentelemetry-auto-psr3` | 0.3.0 (instalado, mas desligado: duplicaria os logs, veja abaixo) |
| `guzzlehttp/guzzle` / `nyholm/psr7` | 7.16.0 / 1.8.2 (cliente PSR-18 e fábricas PSR-17 do exporter) |
| MySQL | 8.4.11 |
| nginx | 1.30.6-alpine |
| OTel Collector | `otel/opentelemetry-collector-contrib:0.163.1` |
| Grafana Tempo | 3.0.4 (single binary, `-target=all`, storage local) |
| Grafana Loki | 3.7.8 (single binary, storage local, ingestão OTLP nativa) |
| Prometheus | v3.15.1 (com `--enable-feature=exemplar-storage`) |
| Grafana | 13.2.4 |

## Pré-requisitos

- Docker com Compose v2 (testado com Docker 28.2 e Compose 2.36)
- `make` e `curl`
- Portas livres no host: **8080** (app), **3200** (Tempo), **4318** (Collector), **9090** (Prometheus), **3100** (Loki) e a porta
  do Grafana (veja abaixo)
- Internet no **primeiro** build (imagens Docker + Composer). Depois disso tudo roda offline.
  Faça o primeiro `make up` **antes** do dia da palestra.

> **Porta do Grafana:** nesta máquina a porta 3000 já estava ocupada (container
> `deploypro-api-1`), então o arquivo `.env` da raiz define `GRAFANA_PORT=3001`. Se a 3000
> estiver livre, troque para 3000. Os links abaixo usam 3001.

## Passo a passo

```bash
make up          # build + sobe tudo; na 1ª vez roda migrations e seed (≈ 25 s com imagens em cache)
make checklist   # valida tudo (containers, extensão, endpoints, Grafana, trace no Tempo)
make load        # 20 requests no endpoint com N+1
make load-fast   # 20 requests no endpoint otimizado
make trafego     # 2 min de tráfego misto para o dashboard RED (DURACAO=300 make trafego)
```

`docker compose up` sozinho também funciona: o `make up` só acrescenta `--build --wait` e
imprime os links.

| Comando | O que faz |
|---|---|
| `make up` | Sobe tudo e espera os healthchecks |
| `make down` | Para os containers (mantém banco e traces) |
| `make clean` | Para e apaga os volumes (banco e traces) |
| `make load` / `make load-fast` | ~20 requests em `/api/pedidos` / `/api/pedidos-otimizado` (`REQUESTS=50 make load` muda a quantidade) |
| `make load-pagamentos` | ~20 POSTs em `/api/pagamentos` (~20% respondem 500) |
| `make trafego` | Tráfego misto por `DURACAO` segundos (padrão 120): N+1, otimizado e pagamentos |
| `make deploy` | Simula um deploy: `make deploy VERSAO=1.1.0 TAXA_ERRO=50` recria só a app com outra versão e outra taxa de erro do gateway. `make up` volta para a 1.0.0 |
| `make up-datadog` | Sobe tudo mandando traces e logs **também** para o Datadog (precisa de `.env.datadog`, veja abaixo) |
| `make log-app` | Últimas 20 linhas do `laravel.log` (com `trace_id`/`span_id`) |
| `make logs` | Logs dos containers da app e do collector |
| `make logs-collector` | Reinicia o collector com o exporter `debug` em modo `detailed` (cada span no log) |
| `make checklist` | Roda `scripts/checklist.sh` |

Endpoints:

- `GET http://localhost:8080/api/pedidos`: **com N+1** (1 + 100 + 100 = 201 queries)
- `GET http://localhost:8080/api/pedidos-otimizado`: mesma resposta, com `with(['cliente', 'itens'])` (3 queries)
- `POST http://localhost:8080/api/pagamentos`: simula um gateway de pagamento que lança
  `RuntimeException` em ~20% das chamadas (HTTP 500). Alimenta os painéis de erro.
- `GET http://localhost:8080/api/pedidos-com-log`: o otimizado com um `Log::info` antes (correlação de log)

## Como abrir o trace no Grafana

1. Abra <http://localhost:3001/explore> (sem login: o acesso anônimo entra como Admin).
2. O datasource **Tempo** já vem selecionado (provisionado em `docker/grafana/provisioning`).
3. Em *Query type*, escolha **TraceQL** e rode:

   ```
   { resource.service.name = "demo-pedidos" }
   ```

4. Clique num trace `GET /api/pedidos`. A visão em cascata mostra o span raiz e, embaixo
   dele, a sequência de `App\Models\Cliente::get` → `sql SELECT` e `App\Models\Item::get` →
   `sql SELECT`, repetida 100 vezes.
5. Clique num span `sql SELECT` e veja os atributos `db.query.text`, `db.system.name = mysql`
   e `db.namespace = demo`.

TraceQL extra que "detecta" o N+1 (só retorna traces com mais de 100 spans de MySQL; testado):

```
{ resource.service.name = "demo-pedidos" && span.db.system.name = "mysql" } | count() > 100
```

## Roteiro da demo

Três atos: o **trace** acha o N+1, o **dashboard** mostra a saúde do serviço inteiro e os
**logs** contam o que aconteceu em cada erro. A história que amarra tudo:
**métrica (algo está errado) → trace (onde) → log (por quê)**.

**Antes de subir no palco:** `make up`, `make checklist` (20 ✔) e deixe abertas três abas do
Grafana: Explore com Tempo, o dashboard (`/d/demo-red`) e Explore com Loki. Tenha um
segundo terminal pronto para o `make trafego`.

### Ato 1: o N+1 no trace

1. **O código inocente.** Mostre `app/app/Http/Controllers/PedidoController.php` (`index`):
   um `limit(100)->get()` e um `map`. Não há nenhuma linha de telemetria. Rode `make load`
   e mostre os tempos (~110–200 ms).
2. **Onde está a telemetria?** Mostre o `docker/php/Dockerfile` (extensão `opentelemetry`),
   os pacotes no `composer.json` e as variáveis `OTEL_*` no `docker-compose.yml`.
   "Zero código" significa isto.
3. **O trace.** Grafana → Explore → Tempo →
   `{ resource.service.name = "demo-pedidos" }` → abra um `GET /api/pedidos`. Mostre os
   **403 spans**, entre eles **201 `sql SELECT`**: 1×`pedidos`, 100×
   ``select * from `clientes` where `clientes`.`id` = ? limit 1`` e 100×
   ``select * from `itens` where `itens`.`pedido_id` = ? ...``. Esse é o N+1.
4. **A correção.** Mostre o método `otimizado()` (`with(['cliente', 'itens'])`), rode
   `make load-fast` e abra um `GET /api/pedidos-otimizado`: **7 spans, 3 queries**, com
   `where id in (...)`. Nada é editado ao vivo; o plano B já está pronto.
5. **Lado a lado.** *Split view* do Explore com os dois traces e a tabela de
   [Resultados medidos](#resultados-medidos). Opcional: a TraceQL `| count() > 100` como
   "detector" de N+1.

### Ato 2: o dashboard (do trace à métrica)

6. **Gancho:** "trace mostra **uma** request. E quando são milhares por minuto?". Rode
   `make trafego` no segundo terminal (2 min de tráfego misto; `DURACAO=300 make trafego`
   para mais tempo) e espere uns 20 s para os gráficos encherem.
7. **De onde vêm as métricas.** Mostre o connector `span_metrics` em
   `docker/collector/config.yaml`: o PHP continua sem emitir métrica nenhuma, e o Collector
   transforma cada span em contador e histograma. "Um sinal virou dois sem mudar a app."
8. **Os sinais vitais.** Abra `/d/demo-red`. Leia a linha de cima: requisições/s, taxa de
   erro, p95 e **queries SQL por requisição** (~40: o N+1 aparece numa métrica, sem abrir
   trace).
9. **Latência por rota.** Painel *Latência p95 por rota*: N+1 ~150–200 ms × otimizado
   ~50 ms × pagamento ~10–20 ms. Em *p50 × p95 × p99*, mostre que a **média mente** (~45 ms)
   e o p95 (~175 ms) é ~4× maior: por isso se usa percentil.
10. **Exemplar: da métrica ao trace.** Passe o mouse num losango da linha do
    `GET /api/pedidos` e clique no link do trace: cai direto na escadinha de 201 queries do
    ato 1. É a ponte entre os dois mundos.

### Ato 3: erros e logs (do sintoma à causa)

11. **"E esses erros?"** Painel *Taxa de erro por rota*: a taxa geral (~6%) esconde que só
    `POST /api/pagamentos` falha, em ~20% das chamadas. Mostre o `PagamentoController`: um
    `throw` e dois `Log::info`, nenhuma linha de telemetria.
12. **A exceção no trace.** Painel *Traces com erro* → abra um → clique no span raiz
    `POST /api/pagamentos` → seção **Events** → `exception`: tipo, mensagem e stack trace com
    `PagamentoController.php:23`.
13. **Do trace para o log.** No mesmo span, clique em **Logs for this span**: o Loki abre ao
    lado com os logs **daquela request**: "Cobrando pedido N no gateway…" e o erro.
14. **Do log para o trace.** Na aba do Loki,
    `{service_name="demo-pedidos"} | detected_level="error"` (ou o painel *Logs de erro* do
    dashboard) → expanda uma linha → **Abrir trace no Tempo**.
15. **O log de sempre.** `make log-app`: o `laravel.log` também traz `trace_id` e `span_id`
    no fim de cada linha. Copie um, cole no TraceQL e o trace abre. "O log que vocês já têm
    hoje passa a apontar para o trace."

16. **Opcional: o deploy ruim.** Com o `make trafego` rodando, `make deploy VERSAO=1.1.0
    TAXA_ERRO=50`. Em ~30 s o painel *Taxa de erro por versão* mostra a 1.1.0 em ~50%, ao lado
    da linha da 1.0.0 (~20%) que para no momento do deploy. "Com a tag de versão, a pergunta 'foi o deploy?' se responde num gráfico."
    No fim, `make up` volta para a 1.0.0.
17. **Opcional: mesmo dado, outro backend.** Se tiver conta Datadog, suba antes com
    `make up-datadog` e mostre o mesmo `demo-pedidos` no APM do Datadog: a aplicação não mudou,
    só o Collector. É o argumento contra o *vendor lock-in*.

**Fechamento:** os três sinais (trace, métrica e log) saíram da mesma instrumentação, sem
código de telemetria no controller, e estão ligados pelo `trace_id`.

Faltando tempo? Faça os atos 1 e 2 (passos 1–10) e só mostre o passo 12 do ato 3.

## Dashboard RED (Rate, Errors, Duration)

Abra <http://localhost:3001/d/demo-red> (pasta *Demo OTel PHP*) e rode `make trafego` em
outro terminal. O dashboard atualiza a cada 5 s.

**De onde vêm as métricas:** o PHP **não emite métricas** (`OTEL_METRICS_EXPORTER=none`).
O connector `span_metrics` do Collector lê cada span que passa e gera um contador
(`traces_span_metrics_calls_total`) e um histograma de duração
(`traces_span_metrics_duration_milliseconds_*`), com as dimensões `span_name`,
`status_code`, `http.route`, `http.request.method`, `http.response.status_code` e
`service.version` (resource attribute). O
Prometheus faz scrape do Collector em `:8889`. Ou seja: **um sinal (trace) vira dois
(trace + métrica)** sem mudar a aplicação.

| Painel | O que mostra | O que falar |
|---|---|---|
| Requisições/s, Taxa de erro, Latência p95 | Os três números RED do serviço | Os "sinais vitais": se só puder olhar para três números, olhe para estes |
| Queries SQL por requisição | spans `sql SELECT` ÷ requisições | Sintoma de N+1 visível **numa métrica**, sem abrir trace |
| Requisições/s por rota | Rate, empilhado | Onde está o tráfego |
| Taxa de erro por rota | Errors, linha tracejada em 5% | Só `/api/pagamentos` erra (~15–20%); a média geral (~6%) esconde isso |
| Latência p95 por rota + exemplars | Duration por rota | N+1 ~150–200 ms × otimizado ~50 ms × pagamento ~10–20 ms. **Clique num losango** (exemplar): abre o trace exato daquele ponto no Tempo |
| p50 × p95 × p99 × média | Percentis do conjunto | A média (~45 ms) mente: o p95 (~175 ms) é ~4× maior. Por que se usa percentil e não média |
| Respostas por status HTTP | 200 × 500 | — |
| Queries SQL/s × Requisições/s | Duas linhas | ~16 req/s geram ~660 queries/s no banco |
| Resumo RED por rota | Tabela | Uma linha por rota com req/s, erro e p95 |
| Taxa de erro por versão | Errors agrupados por `service.version` | Depois do `make deploy`, a versão nova vira uma linha própria: "o erro subiu na 1.1.0" |
| Requisições/s e erros/s por versão | Tráfego por versão | Mostra a troca de versão no momento do deploy |
| Traces com erro | TraceQL `status = error` | Abra um: o span raiz tem o evento `exception` com tipo, mensagem e stack trace (seção *Events* do span) |
| Suspeitos de N+1 | TraceQL `\| count() > 100` | A query de "detecção" do roteiro, agora como painel |
| Logs de erro (Loki) | `detected_level="error"` | Expanda uma linha: stack trace nos campos e o botão **Abrir trace no Tempo** |

No [roteiro da demo](#roteiro-da-demo), o dashboard é o ato 2 (passos 6–10) e os painéis de
erro e logs abrem o ato 3.

Números de uma rodada de `scripts/trafego.sh 60` nesta máquina (2026-10-24, janela de 1 min,
960 requests): 15,9 req/s (o próprio script fez 16/s); taxa de erro geral 5,8% (14,6% em
`/api/pagamentos`, sorteio de 20% que nessa rodada saiu baixo); p95 por rota 199 ms (N+1),
49 ms (otimizado) e 22 ms (pagamentos); p50 29 ms, média 46 ms, p95 175 ms; 42 queries SQL
por requisição e 664 queries/s.

### Versões e deploy

A app envia `OTEL_RESOURCE_ATTRIBUTES=service.version=${APP_VERSION:-1.0.0},deployment.environment.name=demo`.
O `span_metrics` usa `service.version` como dimensão, então dá para agrupar qualquer painel
por versão. Para simular um deploy ruim no palco (testado):

```bash
make trafego &                          # tráfego rodando
make deploy VERSAO=1.1.0 TAXA_ERRO=50   # "deploy" da 1.1.0 com o gateway falhando 50%
```

A app é recriada (~10 s; o nginx resolve o nome `app` a cada request, então não precisa
reiniciar). No painel *Taxa de erro por versão* a linha da 1.1.0 aparece em ~50% (medido:
60 chamadas, 30 com HTTP 500, e o contador da 1.1.0 fechou em 30/30). `make up` volta para a
1.0.0 com 20%.

> Mudou `docker/collector/config.yaml`, `docker/prometheus/prometheus.yml`,
> `docker/loki/loki.yaml` ou o provisioning do Grafana? Rode
> `docker compose restart collector prometheus loki grafana`: arquivos montados como volume
> não fazem o compose recriar o container.

## Resultados medidos

Medidos nesta máquina (Intel i7-1365U, 12 threads, 31 GB RAM, Docker 28.2 no Linux) em
2026-10-20, com `scripts/medir.sh <rota> 50`: 5 requests de aquecimento e depois 50
sequenciais, tempo total do `curl`. Foram 2 rodadas por cenário, e a tabela mostra a faixa
entre elas.

| Endpoint | Queries (spans `sql SELECT` no Tempo) | Queries (`Com_select` do MySQL) | Spans no trace | Mediana com OTel | p95 com OTel | Mediana sem OTel¹ |
|---|---|---|---|---|---|---|
| `/api/pedidos` (N+1) | **201** | 201 | 403 | **139,8–149,4 ms** | 185,0–202,3 ms | 108,4–109,5 ms |
| `/api/pedidos-otimizado` | **3** | 3 | 7 | **31,6–32,1 ms** | 37,7–38,1 ms | 28,7–29,8 ms |

¹ `OTEL_SDK_DISABLED=true docker compose up -d app`. Serve para mostrar o custo da
instrumentação: ~30–40 ms a mais no N+1 (são 403 spans criados e exportados na mesma
request) e ~2–3 ms no otimizado.

Como os números foram obtidos:

- **Spans:** `GET http://localhost:3200/api/traces/<id>`, contando por nome. N+1:
  `{'sql SELECT': 201, 'App\Models\Cliente::get': 100, 'App\Models\Item::get': 100, 'App\Models\Pedido::get': 1, 'GET /api/pedidos': 1}`.
  Otimizado: `{'sql SELECT': 3, ...::get: 3, 'GET /api/pedidos-otimizado': 1}`.
- **Queries (conferência independente):** diferença de `SHOW GLOBAL STATUS LIKE 'Com_select'`
  antes e depois de uma request, descontando 1 (o próprio `SHOW STATUS` soma 1; medido
  sem request no meio).
- A sua máquina vai dar outros tempos. Rode `scripts/medir.sh /api/pedidos 50` no
  notebook da palestra e atualize a tabela.

## Detalhes de instrumentação (e o que foi verificado)

- **Um span por query, sem `opentelemetry-auto-pdo`.** O `opentelemetry-auto-laravel` 1.10
  registra um `QueryWatcher` que escuta o evento `QueryExecuted` do Laravel e cria um span
  `sql <OPERAÇÃO>` (kind CLIENT) por query, com `db.query.text`, `db.system.name`,
  `db.namespace`, `server.address`. Verifiquei: 201 spans no N+1 e 3 no otimizado. Por isso
  o auto-pdo **não** foi adicionado, já que duplicaria cada query. Os spans
  `App\Models\X::get` vêm do hook de Eloquent do mesmo pacote.
- **`allow-plugins` do `tbachert/spi` é obrigatório.** O SDK descobre o hook manager da
  extensão (`ExtensionHookManager`) via SPI, e esse mapeamento é gerado pelo plugin Composer
  `tbachert/spi`. Na primeira tentativa o plugin estava bloqueado (o Composer não pergunta em
  modo não interativo), o SDK caiu no `NoopHookManager` e **nenhum span era gerado, sem erro
  nenhum**. Correção: `"allow-plugins": {"tbachert/spi": true, "php-http/discovery": true}` em
  `app/composer.json`.
- **As variáveis `OTEL_*` precisam estar no ambiente do processo.** O SDK é inicializado no
  autoload do Composer, antes de o Laravel ler o `.env`. Por isso elas ficam no
  `docker-compose.yml`, e o pool do FPM usa `clear_env = no` (`docker/php/zz-otel.conf`). No
  `app/.env` elas aparecem só como documentação.
- **`resource_metrics_key_attributes` no `span_metrics` é obrigatório com PHP-FPM.** Cada
  worker do FPM manda spans com um `process.pid` diferente no resource. Sem essa opção o
  connector cria um contador por pid; o exporter Prometheus não tem o pid como label, as
  séries colidem e só uma sobrevive. Com 2 workers, **metade das requests sumia das
  métricas** (medido: 60 requests, contador em 30; o Tempo tinha os 60 traces). Com a chave
  restrita a `service.name`, `service.version` e `deployment.environment.name`, o contador
  bate com o curl.
- **CLI não é traçado** (padrão do auto-laravel; `OTEL_PHP_TRACE_CLI_ENABLED=false`), e o
  entrypoint ainda desliga o SDK em migrations e seed para não gerar traces de bootstrap.

## Correlação log ↔ trace

Cada log escrito durante uma request sai em **dois lugares**, sempre com o `trace_id` e o
`span_id` do span ativo:

1. **`storage/logs/laravel.log`**: um tap do Monolog (`app/app/Logging/AdicionaTraceContext.php`,
   ligado no canal `single` em `config/logging.php`) acrescenta os IDs no fim da linha.
2. **Loki, via OTLP**: com `OTEL_LOGS_EXPORTER=otlp`, o `opentelemetry-auto-laravel` escuta o
   evento `MessageLogged` e exporta cada log como LogRecord OTLP, com o contexto do trace.
   Exceções reportadas pelo handler do Laravel saem com `exception.type`,
   `exception.message` e `exception.stacktrace`. Collector → `otlp_http/loki` → Loki
   (`trace_id`/`span_id` viram *structured metadata*).

O `opentelemetry-auto-psr3` está instalado, mas desligado
(`OTEL_PHP_DISABLED_INSTRUMENTATIONS=psr3`). Testado: em modo `export` ele exporta os mesmos
logs que o auto-laravel já exporta. Na medição, o `info` chegou 2 vezes ao Loki e o `error`,
4 vezes (1 do auto-laravel e 3 do psr3, que engancha em `LoggerInterface` e dispara em mais
de uma camada do logger do Laravel).

O endpoint de pagamento loga `Cobrando pedido N no gateway de pagamento` e, quando falha, o
handler do Laravel loga a exceção. Saída real do `make log-app`:

```
[2026-10-24 04:06:41] local.INFO: Cobrando pedido 66 no gateway de pagamento  {"trace_id":"2b89a58d149e83b078be9d47f5f10808","span_id":"95929e1a181c51bc"}
[2026-10-24 04:06:41] local.ERROR: Gateway de pagamento indisponível (pedido 66) {"exception":"[object] (RuntimeException(code: 0): ... at /var/www/html/app/Http/Controllers/PagamentoController.php:23)
[stacktrace]
#0 ...
"} {"trace_id":"2b89a58d149e83b078be9d47f5f10808","span_id":"95929e1a181c51bc"}
```

Conferido: o mesmo `trace_id` está no `laravel.log`, nos 2 logs do Loki (info + error com
stack trace) e no trace do Tempo (`POST /api/pagamentos`, status ERROR).

**Do trace para os logs (Tempo → Loki):**
1. Abra um trace com erro (painel *Traces com erro* do dashboard, ou Explore → Tempo →
   `{ status = error }`).
2. Clique no span raiz `POST /api/pagamentos`. Nos detalhes do span há o botão
   **Logs for this span** (ícone de documento, ao lado do nome do span).
3. Abre um painel do Loki ao lado com a query
   `{service_name=~".+"} | trace_id="<trace_id>"`: os logs dessa request, inclusive o erro.

**Do log para o trace (Loki → Tempo):**
1. Explore → datasource **Loki** →
   `{service_name="demo-pedidos"} | detected_level="error"` (ou o painel *Logs de erro* do
   dashboard).
2. Clique numa linha para expandir. Nos campos aparecem `exception_stacktrace`, `span_id` e
   `trace_id`. Ao lado de `trace_id` há o botão **Abrir trace no Tempo** (campo derivado
   configurado em `docker/grafana/provisioning/datasources/loki.yaml`).
3. O trace abre num painel ao lado.

**Do arquivo de log para o trace:** copie o `trace_id` de uma linha do `make log-app` e cole
no editor TraceQL do Explore (Tempo). O trace abre direto.

> No provisioning do Grafana, `${...}` é interpretado como variável de ambiente. Por isso as
> variáveis de link estão escritas como `$${__span.traceId}` e `$${__value.raw}`. Sem o `$$`,
> a query do botão sai com `trace_id=""` (aconteceu na primeira tentativa).

## Opcional: mandar também para o Datadog

Desligado por padrão: o `make up` não muda e a demo continua rodando offline. Com
`make up-datadog`, o **mesmo Collector** manda traces e logs para o Tempo e o Loki **e**
para o Datadog. Nada muda no PHP.

```bash
cp .env.datadog.example .env.datadog   # ignorado pelo git
# preencha DD_API_KEY e DD_SITE (datadoghq.com, us5.datadoghq.com, datadoghq.eu...)
make up-datadog
```

Como funciona:

- `docker-compose.datadog.yml` passa um segundo `--config` ao Collector:
  `docker/collector/datadog.yaml`. O Collector **mescla** os dois arquivos. Mapas se juntam,
  mas listas são substituídas, por isso os pipelines `traces` e `logs` repetem os exporters
  do `config.yaml` e acrescentam o `datadog`.
- **Traces:** exporter `datadog`. O connector `datadog/connector` calcula as métricas de APM
  (hits, erros e latência por recurso), que o Datadog usa nas telas de APM; elas vão para o
  pipeline `metrics/datadog`.
- **Logs:** exporter `datadog`. Os logs já têm `trace_id`, e o Datadog liga log ↔ trace
  sozinho.
- **Métricas do `span_metrics`:** ficam só no Prometheus. No Datadog seriam cobradas como
  custom metrics e duplicariam as do connector.
- **Tags:** `service.name` → `service`, `deployment.environment.name` → `env` (`demo`) e
  `service.version` → `version`. No Datadog: APM → Services → `demo-pedidos`, filtro
  `env:demo`, e a comparação entre versões na seção *Deployments* do serviço.

**O que foi testado e o que não foi.** Os componentes `datadog` (exporter e connector)
existem na imagem `otel/opentelemetry-collector-contrib:0.163.1` usada aqui. Subi com uma
**chave falsa**: o Collector carrega a configuração mesclada, loga `api_key ... is invalid` e
**a stack open source não é afetada** (10 de 10 traces no Tempo e 10 de 10 logs no Loki
durante o teste). Eu **não** testei a chegada dos dados no Datadog, porque não havia conta.
Com uma chave real, confira em APM → Services e Logs (`service:demo-pedidos`).

Para desligar: `make up` (o Collector volta a usar só o `config.yaml`).

## Troubleshooting

**O trace não aparece no Grafana**
1. Rode `make checklist`: ele mostra qual etapa falha.
2. O Tempo leva alguns segundos para indexar um trace novo na busca (até ~30 s logo após
   um `make clean`; o checklist espera até 90 s, ajustável com `TRACE_TIMEOUT=120`). Espere e
   rode de novo. Confira também o intervalo de tempo do Explore (ex.: *Last 15 minutes*).
3. Os spans estão chegando no collector? `docker compose logs collector | grep spans` deve
   mostrar linhas `info Traces ... "spans": N` (o exporter `debug` em modo `basic` loga
   uma linha por lote). Se não aparecer nada, o problema está no PHP (veja o
   próximo item). Se aparecer, o problema está entre o collector e o Tempo (`docker compose logs tempo`).
4. Hook manager: `docker compose exec app php -r 'require "vendor/autoload.php"; foreach (Nevay\SPI\ServiceLoader::load(OpenTelemetry\API\Instrumentation\AutoInstrumentation\HookManagerInterface::class) as $h) echo get_class($h), PHP_EOL;'`
   deve imprimir `ExtensionHookManager`. Se não imprimir nada, o plugin `tbachert/spi` não
   rodou (veja `allow-plugins`) e é preciso rebuildar: `docker compose build app`.
5. Variáveis: `docker compose exec app env | grep OTEL`. `OTEL_SDK_DISABLED` deve ser `false`.

**A extensão não carregou**
- `docker compose exec app php --ri opentelemetry` deve mostrar `extension version => 1.4.2`.
- Se não mostrar, rebuild sem cache: `docker compose build --no-cache app`. A extensão é
  compilada pelo `install-php-extensions` no build, e uma falha de rede no build é a causa
  mais comum.
- Sem a extensão, os pacotes `auto-*` não registram hooks (o psr3 emite um warning e o
  Laravel não gera spans).

**Collector fora do ar**
- Sintoma (testado): a app **continua respondendo 200**, mas os spans são descartados
  silenciosamente e nada chega ao Tempo. O checklist acusa `collector NÃO está rodando`.
- `docker compose ps collector` e `docker compose logs collector`. Erro de YAML aparece
  logo no início do log.
- Para subir de novo: `docker compose up -d collector` (mudanças em
  `docker/collector/config.yaml` exigem `docker compose restart collector`).

**Outros**
- *Porta em uso:* ajuste `GRAFANA_PORT`/`APP_PORT` no `.env` da raiz.
- *Banco "sujo" ou quer recomeçar:* `make clean && make up`. O seed roda de novo, porque é
  idempotente e só popula com a tabela `clientes` vazia.
- *Mudou código PHP:* o código vai para dentro da imagem (não há bind mount, para o palco
  ficar previsível). Rode `docker compose up -d --build app`.

## Estrutura

```
docker-compose.yml          # app, nginx, mysql, collector, tempo, loki, prometheus, grafana
docker-compose.datadog.yml  # override opcional: Collector também manda para o Datadog
.env.datadog.example        # modelo do .env.datadog (DD_API_KEY, DD_SITE; não vai para o git)
Makefile
.env                        # portas do host (lido pelo compose)
docker/php/Dockerfile       # PHP 8.3 FPM + ext opentelemetry/protobuf/pdo_mysql
docker/php/entrypoint.sh    # espera o MySQL, migrate, seed idempotente, cache
docker/php/zz-otel.conf     # clear_env = no
docker/nginx/default.conf
docker/collector/config.yaml
docker/collector/datadog.yaml   # camada opcional do Collector para o Datadog
docker/tempo/tempo.yaml
docker/prometheus/prometheus.yml
docker/loki/loki.yaml
docker/grafana/provisioning/datasources/{tempo,prometheus,loki}.yaml
docker/grafana/provisioning/dashboards/json/demo-red.json   # dashboard RED
scripts/checklist.sh        # validação pré-palestra
scripts/medir.sh            # medição de tempo de resposta
scripts/trafego.sh          # tráfego misto para o dashboard
app/                        # Laravel 13
  app/Http/Controllers/{Pedido,Pagamento}Controller.php
  app/Logging/AdicionaTraceContext.php   # trace_id/span_id no laravel.log
  app/Models/{Cliente,Pedido,Item}.php
  database/{migrations,factories,seeders}
  routes/api.php
```
