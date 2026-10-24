<?php

namespace App\Logging;

use Illuminate\Log\Logger;
use Monolog\LogRecord;
use OpenTelemetry\API\Trace\Span;

/**
 * Tap do Monolog: acrescenta trace_id e span_id do span ativo em cada linha do
 * laravel.log, para achar o trace a partir do log (e vice-versa).
 */
class AdicionaTraceContext
{
    public function __invoke(Logger $logger): void
    {
        $logger->getLogger()->pushProcessor(function (LogRecord $record): LogRecord {
            $span = Span::getCurrent()->getContext();

            if (! $span->isValid()) {
                return $record;
            }

            return $record->with(extra: $record->extra + [
                'trace_id' => $span->getTraceId(),
                'span_id'  => $span->getSpanId(),
            ]);
        });
    }
}
