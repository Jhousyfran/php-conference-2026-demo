<?php

use App\Http\Controllers\PedidoController;
use Illuminate\Support\Facades\Route;

Route::get('/pedidos', [PedidoController::class, 'index']);
Route::get('/pedidos-otimizado', [PedidoController::class, 'otimizado']);
Route::get('/pedidos-com-log', [PedidoController::class, 'comLog']);
