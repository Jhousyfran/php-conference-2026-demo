<?php

namespace App\Http\Controllers;

use App\Models\Pedido;
use Illuminate\Support\Facades\Log;
use RuntimeException;

class PagamentoController extends Controller
{
    /**
     * Simula a chamada a um gateway de pagamento que falha em ~20% das vezes
     * (PAGAMENTO_TAXA_ERRO; o `make deploy` muda o valor para simular uma versão ruim).
     * A exceção vira HTTP 500 e o span raiz sai com status ERROR, o que alimenta
     * o painel de taxa de erros do dashboard. Os logs saem com trace_id e span_id
     * (no laravel.log e no Loki), e a exceção é logada pelo handler do Laravel.
     */
    public function store()
    {
        $pedido = Pedido::inRandomOrder()->first();
        Log::info("Cobrando pedido {$pedido->id} no gateway de pagamento");

        if (random_int(1, 100) <= config('services.gateway.taxa_erro')) {
            throw new RuntimeException("Gateway de pagamento indisponível (pedido {$pedido->id})");
        }

        Log::info("Pagamento do pedido {$pedido->id} aprovado");

        return ['pedido' => $pedido->id, 'status' => 'aprovado'];
    }
}
