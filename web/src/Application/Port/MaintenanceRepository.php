<?php

declare(strict_types=1);

namespace App\Application\Port;

interface MaintenanceRepository
{
    /** @return list<array<string, mixed>> vélos sur borne, signalés ou défectueux, à retirer */
    public function velosARetirer(): array;

    /** @return list<array<string, mixed>> interventions en cours (vélo à l'atelier) */
    public function enAtelier(): array;

    /** @return list<array<string, mixed>> signalements de station ouverts sans travaux en cours */
    public function signalementsStation(): array;

    /** @return list<array<string, mixed>> */
    public function travauxEnCours(): array;

    /** @return array<string, int> */
    public function compteurs(): array;

    public function retirer(int $operateur, int $velo, string $description): int;

    public function remettre(int $intervention, int $station): void;

    public function reformer(int $intervention): void;

    public function demarrerTravaux(int $operateur, int $signalement, string $description): int;

    public function terminerTravaux(int $intervention, bool $resolu): void;
}
