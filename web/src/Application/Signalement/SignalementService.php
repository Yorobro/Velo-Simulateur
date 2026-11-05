<?php

declare(strict_types=1);

namespace App\Application\Signalement;

use App\Application\Page;
use App\Application\Port\SignalementRepository;
use App\Application\Validateur;

final class SignalementService
{
    public const STATUTS = ['OUVERT', 'EN_TRAITEMENT', 'CLOS'];
    public const CIBLES = ['VELO', 'STATION'];

    public function __construct(private readonly SignalementRepository $signalements)
    {
    }

    public function signalerVelo(int $utilisateur, ?int $velo, string $description): int
    {
        $this->valider('velo', $velo, 'Le numéro du vélo', $description);

        return $this->signalements->signalerVelo($utilisateur, (int) $velo, $description);
    }

    public function signalerStation(int $utilisateur, ?int $station, string $description): int
    {
        $this->valider('station', $station, 'La station', $description);

        return $this->signalements->signalerStation($utilisateur, (int) $station, $description);
    }

    public function dernierVelo(int $utilisateur): ?int
    {
        return $this->signalements->dernierVeloEmprunte($utilisateur);
    }

    public function rechercher(string $statut, string $cible, int $page): Page
    {
        return $this->signalements->rechercher(
            in_array($statut, self::STATUTS, true) ? $statut : '',
            in_array($cible, self::CIBLES, true) ? $cible : '',
            $page,
            15,
        );
    }

    public function cloturer(int $signalement): void
    {
        $this->signalements->cloturer($signalement);
    }

    private function valider(string $champ, ?int $id, string $libelle, string $description): void
    {
        (new Validateur())
            ->requis($champ, $id, $libelle)
            ->requis('description', $description, 'La description')
            ->longueur('description', $description, 5, 500, 'La description')
            ->verifier();
    }
}
