<?php

namespace Database\Factories;

use App\Models\Cliente;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<\App\Models\Pedido>
 */
class PedidoFactory extends Factory
{
    public function definition(): array
    {
        return [
            'cliente_id' => Cliente::factory(),
            'total' => 0,
            'created_at' => fake()->dateTimeBetween('-90 days'),
        ];
    }
}
