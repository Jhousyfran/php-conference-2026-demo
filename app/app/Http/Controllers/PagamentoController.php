<?php

namespace App\Http\Controllers;

use App\Models\Pedido;
use RuntimeException;

class PagamentoController extends Controller
{
    /**
     * Simula a chamada a um gateway de pagamento que falha em ~20% das vezes.
     * A exceção vira HTTP 500 e o span raiz sai com status ERROR, o que alimenta
     * o painel de taxa de erros do dashboard.
     */
    public function store()
    {
        $pedido = Pedido::inRandomOrder()->first();

        if (random_int(1, 100) <= 20) {
            throw new RuntimeException("Gateway de pagamento indisponível (pedido {$pedido->id})");
        }

        return ['pedido' => $pedido->id, 'status' => 'aprovado'];
    }
}
