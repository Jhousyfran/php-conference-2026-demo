<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Item extends Model
{
    use HasFactory;

    protected $table = 'itens';

    public $timestamps = false;

    protected $fillable = ['pedido_id', 'produto', 'quantidade', 'preco'];

    public function pedido(): BelongsTo
    {
        return $this->belongsTo(Pedido::class);
    }
}
