<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('itens', function (Blueprint $table) {
            $table->id();
            $table->foreignId('pedido_id')->constrained('pedidos');
            $table->string('produto');
            $table->unsignedInteger('quantidade');
            $table->decimal('preco', 10, 2);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('itens');
    }
};
