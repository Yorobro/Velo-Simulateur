<?php

declare(strict_types=1);

namespace App\Application\Port;

use DateTimeImmutable;

interface StatistiquesRepository
{
    /** @return array<string, int|float> chiffres clés du moment */
    public function indicateurs(): array;

    /** @return list<array<string, mixed>> */
    public function trajetsParJour(DateTimeImmutable $depuis): array;

    /** @return array<int, int> heure => nombre de départs */
    public function departsParHeure(DateTimeImmutable $depuis): array;

    /** @return list<array<string, mixed>> */
    public function origineDestination(DateTimeImmutable $depuis, int $limite): array;

    /** @return list<array<string, mixed>> */
    public function recettesParFormule(DateTimeImmutable $depuis): array;

    /** @return list<array<string, mixed>> */
    public function indisponibilite(): array;

    /** @return list<array<string, mixed>> une ligne par station et par heure */
    public function remplissageHoraire(): array;
}
