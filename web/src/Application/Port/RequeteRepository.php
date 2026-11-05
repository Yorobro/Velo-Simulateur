<?php

declare(strict_types=1);

namespace App\Application\Port;

use App\Application\Requete\Resultat;

interface RequeteRepository
{
    /** @return array<string, array{titre: string, description: string, sql: string}> */
    public function catalogue(): array;

    /** Exécute une requête de lecture (transaction en lecture seule, durée limitée). */
    public function executer(string $sql, int $maxLignes, int $delaiMs): Resultat;
}
