<?php

declare(strict_types=1);

namespace App\Application\Requete;

/** Résultat d'une requête exécutée : colonnes, premières lignes, durée. */
final class Resultat
{
    /**
     * @param list<string> $colonnes
     * @param list<array<string, mixed>> $lignes
     */
    public function __construct(
        public readonly string $sql,
        public readonly array $colonnes,
        public readonly array $lignes,
        public readonly int $nbLignes,
        public readonly float $dureeMs,
        public readonly bool $tronque,
    ) {
    }
}
