# Demo: encontrando um N+1 em Laravel com OpenTelemetry

Live demo para palestra sobre observabilidade em PHP. Uma aplicação Laravel com uma
query N+1 proposital é instrumentada **sem nenhuma linha de código de telemetria no
controller**. Os traces vão para o OpenTelemetry Collector, depois para o Grafana Tempo,
e no Grafana o N+1 aparece como uma "escadinha" de 201 spans `sql SELECT`.

```
curl ──> nginx ──> PHP-FPM (Laravel + ext-opentelemetry + SDK)
                        │  OTLP http/protobuf :4318
                        ▼
                   OTel Collector ──(OTLP gRPC)──> Tempo :3200 <── Grafana
                        └── exporter debug (log)
```

## Stack e versões (todas testadas juntas)

| Componente | Versão |
|---|---|
| PHP (FPM) | 8.3 (`php:8.3-fpm-bookworm`, testado com 8.3.35) |
| Extensão `opentelemetry` (PECL) | 1.4.2 |
| Laravel (`laravel/framework`) | 13.37.0 |
| `open-telemetry/sdk` | 1.15.0 |
| `open-telemetry/exporter-otlp` | 1.4.0 |
| `open-telemetry/opentelemetry-auto-laravel` | 1.10.0 (suporta Laravel 10–13) |
| `open-telemetry/opentelemetry-auto-psr3` | 0.3.0 (bônus, desligado por padrão) |
| `guzzlehttp/guzzle` / `nyholm/psr7` | 7.16.0 / 1.8.2 (cliente PSR-18 e fábricas PSR-17 do exporter) |
| MySQL | 8.4.11 |
| nginx | 1.30.6-alpine |
| OTel Collector | `otel/opentelemetry-collector-contrib:0.163.1` |
| Grafana Tempo | 3.0.4 (single binary, `-target=all`, storage local) |
| Grafana | 13.2.4 |

## Pré-requisitos

- Docker com Compose v2 (testado com Docker 28.2 e Compose 2.36)
- `make` e `curl`
- Portas livres no host: **8080** (app), **3200** (Tempo), **4318** (Collector) e a porta
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
```

`docker compose up` sozinho também funciona: o `make up` só acrescenta `--build --wait` e
imprime os links.

| Comando | O que faz |
|---|---|
| `make up` | Sobe tudo e espera os healthchecks |
| `make down` | Para os containers (mantém banco e traces) |
| `make clean` | Para e apaga os volumes (banco e traces) |
| `make load` / `make load-fast` | ~20 requests em `/api/pedidos` / `/api/pedidos-otimizado` (`REQUESTS=50 make load` muda a quantidade) |
| `make logs` | Logs da app e do collector |
| `make logs-collector` | Reinicia o collector com o exporter `debug` em modo `detailed` (cada span no log) |
| `make up-log` | Sobe com o bônus de correlação log ↔ trace ligado |
| `make checklist` | Roda `scripts/checklist.sh` |

Endpoints:

- `GET http://localhost:8080/api/pedidos`: **com N+1** (1 + 100 + 100 = 201 queries)
- `GET http://localhost:8080/api/pedidos-otimizado`: mesma resposta, com `with(['cliente', 'itens'])` (3 queries)
- `GET http://localhost:8080/api/pedidos-com-log`: bônus de correlação de log (ver abaixo)

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

## Roteiro da demo (5 passos)

1. **O código inocente.** Mostre `app/app/Http/Controllers/PedidoController.php` (`index`):
   um `limit(100)->get()` e um `map`. Não há nenhuma linha de telemetria. Rode `make load`
   e mostre os tempos (~110–200 ms).
2. **Onde está a telemetria?** Mostre o `docker/php/Dockerfile` (extensão `opentelemetry`),
   os três pacotes no `composer.json` e as variáveis `OTEL_*` no `docker-compose.yml`.
   "Zero código" significa isto.
3. **O trace.** Grafana → Explore → Tempo →
   `{ resource.service.name = "demo-pedidos" }` → abra um `GET /api/pedidos`. Mostre os
   **403 spans**, entre eles **201 `sql SELECT`**: 1×`pedidos`, 100×
   ``select * from `clientes` where `clientes`.`id` = ? limit 1`` e 100×
   ``select * from `itens` where `itens`.`pedido_id` = ? ...``. Esse é o N+1.
4. **A correção.** Mostre o método `otimizado()` (`with(['cliente', 'itens'])`), rode
   `make load-fast` e abra um `GET /api/pedidos-otimizado`: **7 spans, 3 queries**, com
   `where id in (...)`. Nada é editado ao vivo; o plano B já está pronto.
5. **Lado a lado e números.** Use o *split view* do Explore com os dois traces e feche com a
   tabela abaixo. Opcional: a TraceQL `| count() > 100` como "alerta" de N+1, e o bônus de
   log ↔ trace.

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
- **CLI não é traçado** (padrão do auto-laravel; `OTEL_PHP_TRACE_CLI_ENABLED=false`), e o
  entrypoint ainda desliga o SDK em migrations e seed para não gerar traces de bootstrap.

## Bônus: correlação log ↔ trace (desligado por padrão)

Usa `open-telemetry/opentelemetry-auto-psr3` com `OTEL_PHP_PSR3_MODE=inject`: a
instrumentação injeta `trace_id` e `span_id` no contexto de cada chamada PSR-3, e o
`replace_placeholders` do canal `single` do Laravel substitui os placeholders na mensagem.

Por padrão o compose define `OTEL_PHP_DISABLED_INSTRUMENTATIONS=psr3`. Para ligar:

```bash
make up-log
curl -s localhost:8080/api/pedidos-com-log > /dev/null
docker compose exec app tail -1 storage/logs/laravel.log
```

**Testado e funcionando** nesta combinação de versões. Saída real:

```
[2026-10-20 01:22:09] local.INFO: Listando pedidos trace_id=6ac90356b6fb4bef15fbb9b00ddef3c1 span_id=2bd22928605db918 {"trace_id":"6ac90356b6fb4bef15fbb9b00ddef3c1","span_id":"2bd22928605db918"}
```

Busquei esse `trace_id` no Tempo (`/api/traces/6ac90356...`): o trace existe, e o `span_id`
do log é exatamente o span raiz `GET /api/pedidos-com-log`. No Grafana, cole o trace_id
no editor TraceQL do Explore para abrir o trace direto.
Com o psr3 desligado (padrão), a mesma linha sai com os placeholders literais
`trace_id={trace_id} span_id={span_id}`. Para voltar ao padrão: `make up`.

## Troubleshooting

**O trace não aparece no Grafana**
1. Rode `make checklist`: ele mostra qual etapa falha.
2. O Tempo leva alguns segundos (até ~15 s) para indexar um trace novo na busca. Espere e
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
docker-compose.yml          # app, nginx, mysql, collector, tempo, grafana
Makefile
.env                        # portas do host (lido pelo compose)
docker/php/Dockerfile       # PHP 8.3 FPM + ext opentelemetry/protobuf/pdo_mysql
docker/php/entrypoint.sh    # espera o MySQL, migrate, seed idempotente, cache
docker/php/zz-otel.conf     # clear_env = no
docker/nginx/default.conf
docker/collector/config.yaml
docker/tempo/tempo.yaml
docker/grafana/provisioning/datasources/tempo.yaml
scripts/checklist.sh        # validação pré-palestra
scripts/medir.sh            # medição de tempo de resposta
app/                        # Laravel 13
  app/Http/Controllers/PedidoController.php
  app/Models/{Cliente,Pedido,Item}.php
  database/{migrations,factories,seeders}
  routes/api.php
```
