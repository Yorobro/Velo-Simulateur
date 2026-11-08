<?php

declare(strict_types=1);

namespace App\Application\Port;

interface RegulationRepository
{
    /** @return list<array<string, mixed>> stations en service et leur statut (vide, pleine…) */
    public function stations(): array;

    /** @return list<array<string, mixed>> déplacements proposés */
    public function propositions(): array;

    /** @return array<string, mixed>|null */
    public function tourneeEnCours(int $operateur): ?array;

    /** @return list<array<string, mixed>> */
    public function transferts(int $tournee): array;

    /** @return list<array<string, mixed>> */
    public function tourneesRecentes(int $limite): array;

    public function operateurDeTournee(int $tournee): ?int;

    /** @return list<array<string, mixed>> véhicules qui ne sont engagés dans aucune tournée en cours */
    public function vehiculesLibres(): array;

    public function demarrer(int $operateur, int $vehicule): int;

    public function charger(int $tournee, int $velo): int;

    public function deposer(int $transfert, int $station): void;

    public function cloturer(int $tournee): void;
}
