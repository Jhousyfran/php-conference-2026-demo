<?php

namespace App\Http\Controllers;

use App\Models\Pedido;
use Illuminate\Support\Facades\Log;

class PedidoController extends Controller
{
    /**
     * Propositalmente com N+1: 1 query de pedidos + 100 de clientes + 100 de itens = 201 queries.
     */
    public function index()
    {
        $pedidos = Pedido::limit(100)->get();

        return $pedidos->map(fn ($p) => [
            'id'      => $p->id,
            'cliente' => $p->cliente->nome,
            'itens'   => $p->itens->count(),
        ]);
    }

    /**
     * Mesma resposta, com eager loading: 3 queries.
     */
    public function otimizado()
    {
        $pedidos = Pedido::with(['cliente', 'itens'])->limit(100)->get();

        return $pedidos->map(fn ($p) => [
            'id'      => $p->id,
            'cliente' => $p->cliente->nome,
            'itens'   => $p->itens->count(),
        ]);
    }

    /**
     * Bônus: correlação log <-> trace. Com a instrumentação psr3 em modo "inject",
     * trace_id e span_id entram no contexto do log e substituem os placeholders.
     */
    public function comLog()
    {
        Log::info('Listando pedidos trace_id={trace_id} span_id={span_id}');

        return $this->otimizado();
    }
}
