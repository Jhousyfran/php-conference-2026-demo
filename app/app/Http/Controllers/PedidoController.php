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
     * Correlação log <-> trace: o log sai com trace_id e span_id no laravel.log
     * (App\Logging\AdicionaTraceContext) e é exportado via OTLP para o Loki (auto-laravel).
     */
    public function comLog()
    {
        Log::info('Listando pedidos');

        return $this->otimizado();
    }
}
