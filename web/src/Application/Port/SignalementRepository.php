<?php

declare(strict_types=1);

namespace App\Application\Port;

use App\Application\Page;

interface SignalementRepository
{
    public function signalerVelo(int $utilisateur, int $velo, string $description): int;

    public function signalerStation(int $utilisateur, int $station, string $description): int;

    public function dernierVeloEmprunte(int $utilisateur): ?int;

    public function rechercher(string $statut, string $cible, int $page, int $parPage): Page;

    public function cloturer(int $signalement): void;
}
