<?php

declare(strict_types=1);

namespace App\Application;

/** Une page de résultats paginés. */
final class Page
{
    /** @param list<array<string, mixed>> $elements */
    public function __construct(
        public readonly array $elements,
        public readonly int $total,
        public readonly int $numero,
        public readonly int $parPage,
    ) {
    }

    public function nbPages(): int
    {
        return max(1, (int) ceil($this->total / $this->parPage));
    }

    public function decalage(): int
    {
        return ($this->numero - 1) * $this->parPage;
    }

    public static function numeroValide(?int $numero): int
    {
        return max(1, $numero ?? 1);
    }
}
