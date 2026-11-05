<?php

declare(strict_types=1);

namespace App\Application\Maintenance;

use App\Application\Port\MaintenanceRepository;
use App\Application\Port\StationRepository;
use App\Application\Validateur;

/** Maintenance : retrait, réparation, réforme des vélos ; travaux sur les stations. */
final class MaintenanceService
{
    public function __construct(
        private readonly MaintenanceRepository $maintenance,
        private readonly StationRepository $stations,
    ) {
    }

    /** @return array<string, mixed> */
    public function tableau(): array
    {
        return [
            'compteurs' => $this->maintenance->compteurs(),
            'a_retirer' => $this->maintenance->velosARetirer(),
            'atelier' => $this->maintenance->enAtelier(),
            'signalements_station' => $this->maintenance->signalementsStation(),
            'travaux' => $this->maintenance->travauxEnCours(),
            'stations_depot' => $this->stations->avecPlace(),
        ];
    }

    /** @return array<string, int> */
    public function compteurs(): array
    {
        return $this->maintenance->compteurs();
    }

    public function retirer(int $operateur, ?int $velo, string $description): int
    {
        $this->valider('velo', $velo, 'Le vélo', $description);

        return $this->maintenance->retirer($operateur, (int) $velo, $description);
    }

    public function remettre(int $intervention, ?int $station): void
    {
        (new Validateur())->requis('station', $station, 'La station')->verifier();
        $this->maintenance->remettre($intervention, (int) $station);
    }

    public function reformer(int $intervention): void
    {
        $this->maintenance->reformer($intervention);
    }

    public function demarrerTravaux(int $operateur, ?int $signalement, string $description): int
    {
        $this->valider('signalement', $signalement, 'Le signalement', $description);

        return $this->maintenance->demarrerTravaux($operateur, (int) $signalement, $description);
    }

    public function terminerTravaux(int $intervention, bool $resolu): void
    {
        $this->maintenance->terminerTravaux($intervention, $resolu);
    }

    private function valider(string $champ, ?int $id, string $libelle, string $description): void
    {
        (new Validateur())
            ->requis($champ, $id, $libelle)
            ->requis('description', $description, 'La description de l\'intervention')
            ->longueur('description', $description, 3, 500, 'La description')
            ->verifier();
    }
}
