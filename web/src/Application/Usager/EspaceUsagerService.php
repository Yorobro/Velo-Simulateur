<?php

declare(strict_types=1);

namespace App\Application\Usager;

use App\Application\Page;
use App\Application\Port\AbonnementRepository;
use App\Application\Port\FactureRepository;
use App\Application\Port\LocationRepository;
use App\Application\Port\StationRepository;
use App\Application\Validateur;
use App\Domain\Exception\AccesRefuseException;

/**
 * Espace de l'usager : emprunt et restitution, abonnements, factures.
 * Les règles (une location à la fois, abonnement valide, vélo en état…)
 * sont vérifiées par les procédures stockées ; ce service contrôle seulement
 * que l'usager agit sur ses propres locations, abonnements et factures.
 */
final class EspaceUsagerService
{
    public function __construct(
        private readonly LocationRepository $locations,
        private readonly AbonnementRepository $abonnements,
        private readonly FactureRepository $factures,
        private readonly StationRepository $stations,
    ) {
    }

    /** @return array<string, mixed> */
    public function tableauDeBord(int $usager, ?int $station): array
    {
        $location = $this->locations->enCours($usager);
        $abonnement = $this->abonnements->actif($usager);

        return [
            'location' => $location,
            'abonnement' => $abonnement,
            'bilan' => $this->locations->bilan($usager),
            'impayees' => $this->factures->impayees($usager),
            'dernieres' => $this->locations->historique($usager, 1, 5)->elements,
            'stations_depart' => $location === null && $abonnement !== null ? $this->stations->avecVelos() : [],
            'stations_arrivee' => $location !== null ? $this->stations->avecPlace() : [],
            'station_choisie' => $station,
            'velos' => $location === null && $station !== null ? $this->stations->velosDisponibles($station) : [],
        ];
    }

    public function emprunter(int $usager, ?int $velo, bool $casque): int
    {
        (new Validateur())->requis('velo', $velo, 'Le vélo')->verifier();

        return $this->locations->emprunter($usager, (int) $velo, $casque);
    }

    public function restituer(int $usager, int $location, ?int $station): void
    {
        (new Validateur())->requis('station', $station, 'La station d\'arrivée')->verifier();
        $this->verifierTitulaire($this->locations->titulaire($location), $usager);
        $this->locations->restituer($location, (int) $station);
    }

    public function historique(int $usager, int $page): Page
    {
        return $this->locations->historique($usager, $page, 20);
    }

    /**
     * Un usager n'a qu'un abonnement à la fois (règle R22, vérifiée par la
     * base) : une nouvelle souscription commence au lendemain de la fin du
     * dernier abonnement en cours ou à venir. La page l'annonce avant de
     * confirmer un changement de formule.
     *
     * @return array<string, mixed>
     */
    public function abonnements(int $usager): array
    {
        $dernier = $this->abonnements->dernier($usager);
        $prochainDebut = $dernier === null
            ? new \DateTimeImmutable('today')
            : (new \DateTimeImmutable((string) $dernier['date_fin']))->modify('+1 day');

        return [
            'abonnements' => $this->abonnements->duUtilisateur($usager),
            'actif' => $this->abonnements->actif($usager),
            'dernier' => $dernier,
            'prochain_debut' => $prochainDebut->format('Y-m-d'),
            'formules' => $this->abonnements->formules(),
        ];
    }

    /** @return array<string, mixed> l'abonnement créé (date de début comprise) */
    public function souscrire(int $usager, ?int $formule): array
    {
        $ids = array_map(static fn (array $f): int => (int) $f['id_formule'], $this->abonnements->formules());
        (new Validateur())->si(!in_array($formule, $ids, true), 'formule', 'Choisissez une formule.')->verifier();

        $id = $this->abonnements->souscrire($usager, (int) $formule);

        return $this->abonnements->trouver($id) ?? ['id_abonnement' => $id, 'statut' => 'ACTIF'];
    }

    /** @return array<string, mixed> le nouvel abonnement */
    public function renouveler(int $usager, int $abonnement): array
    {
        $this->verifierTitulaire($this->abonnements->titulaire($abonnement), $usager);

        $id = $this->abonnements->renouveler($abonnement);

        return $this->abonnements->trouver($id) ?? ['id_abonnement' => $id, 'statut' => 'ACTIF'];
    }

    public function factures(int $usager, int $page): Page
    {
        return $this->factures->duUtilisateur($usager, $page, 20);
    }

    /** @return array{nb: int, montant: float} */
    public function impayees(int $usager): array
    {
        return $this->factures->impayees($usager);
    }

    public function regler(int $usager, int $facture): void
    {
        $this->verifierTitulaire($this->factures->titulaire($facture), $usager);
        $this->factures->regler($facture);
    }

    private function verifierTitulaire(?int $titulaire, int $usager): void
    {
        if ($titulaire !== $usager) {
            throw new AccesRefuseException();
        }
    }
}
