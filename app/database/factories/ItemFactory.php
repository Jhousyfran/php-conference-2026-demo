<?php

namespace Database\Factories;

use App\Models\Pedido;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<\App\Models\Item>
 */
class ItemFactory extends Factory
{
    public function definition(): array
    {
        return [
            'pedido_id' => Pedido::factory(),
            'produto' => fake()->randomElement([
                'Camiseta PHP', 'Caneca elePHPant', 'Adesivo Laravel', 'Livro de PHP',
                'Moletom OpenTelemetry', 'Boné Grafana', 'Mousepad Tempo', 'Pelúcia elePHPant',
            ]),
            'quantidade' => fake()->numberBetween(1, 5),
            'preco' => fake()->randomFloat(2, 10, 300),
        ];
    }
}
