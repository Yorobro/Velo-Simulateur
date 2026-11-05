<?php

declare(strict_types=1);

namespace App\Application\Regulation;

use App\Application\Port\RegulationRepository;
use App\Application\Port\StationRepository;
use App\Application\Validateur;
use App\Domain\Exception\AccesRefuseException;
use App\Domain\Role;
use App\Domain\Utilisateur;

/** Rééquilibrage du réseau : état des stations, propositions, tournées. */
final class RegulationService
{
    public function __construct(
        private readonly RegulationRepository $regulation,
        private readonly StationRepository $stations,
    ) {
    }

    /** @return array<string, mixed> */
    public function tableau(Utilisateur $operateur, ?int $station): array
    {
        $tournee = $this->regulation->tourneeEnCours($operateur->id);
        $stations = $this->regulation->stations();
        $compte = array_count_values(array_column($stations, 'statut'));

        return [
            'stations' => $stations,
            'compte' => $compte,
            'propositions' => $this->regulation->propositions(),
            'tournee' => $tournee,
            'transferts' => $tournee !== null ? $this->regulation->transferts((int) $tournee['id_tournee']) : [],
            'recentes' => $this->regulation->tourneesRecentes(8),
            'stations_chargement' => $tournee !== null ? $this->stations->avecVelos() : [],
            'stations_depot' => $tournee !== null ? $this->stations->avecPlace() : [],
            'station_choisie' => $station,
            'velos' => $tournee !== null && $station !== null ? $this->stations->velosDisponibles($station) : [],
        ];
    }

    /** @return list<array<string, mixed>> */
    public function stations(): array
    {
        return $this->regulation->stations();
    }

    public function demarrer(Utilisateur $operateur): int
    {
        return $this->regulation->demarrer($operateur->id);
    }

    public function charger(Utilisateur $operateur, int $tournee, ?int $velo): int
    {
        $this->verifierTournee($operateur, $tournee);
        (new Validateur())->requis('velo', $velo, 'Le vélo')->verifier();

        return $this->regulation->charger($tournee, (int) $velo);
    }

    public function deposer(Utilisateur $operateur, int $transfert, ?int $station): void
    {
        (new Validateur())->requis('station', $station, 'La station de dépôt')->verifier();
        $tournee = $this->regulation->tourneeEnCours($operateur->id);
        $transferts = $tournee !== null ? $this->regulation->transferts((int) $tournee['id_tournee']) : [];
        if (!in_array($transfert, array_map('intval', array_column($transferts, 'id_mouvement')), true)
            && $operateur->role !== Role::Administrateur) {
            throw new AccesRefuseException();
        }
        $this->regulation->deposer($transfert, (int) $station);
    }

    public function cloturer(Utilisateur $operateur, int $tournee): void
    {
        $this->verifierTournee($operateur, $tournee);
        $this->regulation->cloturer($tournee);
    }

    private function verifierTournee(Utilisateur $operateur, int $tournee): void
    {
        $responsable = $this->regulation->operateurDeTournee($tournee);
        if ($responsable !== $operateur->id && $operateur->role !== Role::Administrateur) {
            throw new AccesRefuseException();
        }
    }
}
