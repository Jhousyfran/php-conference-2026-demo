<?php

namespace Database\Seeders;

use App\Models\Cliente;
use App\Models\Item;
use App\Models\Pedido;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    /**
     * 50 clientes, 100 pedidos e de 2 a 6 itens por pedido.
     * Idempotente: se já houver clientes, não faz nada.
     */
    public function run(): void
    {
        if (Cliente::exists()) {
            $this->command?->info('Banco já populado, seed ignorado.');

            return;
        }

        $clientes = Cliente::factory()->count(50)->create();

        Pedido::factory()
            ->count(100)
            ->state(fn () => ['cliente_id' => $clientes->random()->id])
            ->create()
            ->each(function (Pedido $pedido) {
                $itens = Item::factory()
                    ->count(fake()->numberBetween(2, 6))
                    ->for($pedido)
                    ->create();

                $pedido->update([
                    'total' => $itens->sum(fn (Item $item) => $item->quantidade * $item->preco),
                ]);
            });
    }
}
