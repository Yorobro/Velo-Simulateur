<?php

declare(strict_types=1);

namespace App\Application\Station;

use App\Application\Port\StationRepository;
use App\Application\Validateur;
use App\Domain\Exception\IntrouvableException;

/** Consultation et gestion des stations et de leurs bornes. */
final class StationService
{
    public const ETATS = ['EN_SERVICE', 'HORS_SERVICE', 'EN_TRAVAUX'];
    public const ETATS_BORNE = ['EN_SERVICE', 'HORS_SERVICE'];

    public function __construct(private readonly StationRepository $stations)
    {
    }

    /** @return list<array<string, mixed>> */
    public function lister(string $recherche, string $etat): array
    {
        return $this->stations->lister($recherche, in_array($etat, self::ETATS, true) ? $etat : '');
    }

    /** @return array<string, mixed> */
    public function detail(int $id): array
    {
        return $this->stations->detail($id) ?? throw new IntrouvableException();
    }

    /** @return list<array<string, mixed>> */
    public function bornes(int $id): array
    {
        return $this->stations->bornes($id);
    }

    /** @param array<string, string> $saisie */
    public function creer(array $saisie): int
    {
        $donnees = $this->valider($saisie, true);

        return $this->stations->creer($donnees, (int) $saisie['nb_bornes']);
    }

    /** @param array<string, string> $saisie */
    public function modifier(int $id, array $saisie): void
    {
        $this->detail($id);
        $this->stations->modifier($id, $this->valider($saisie, false));
    }

    public function supprimer(int $id): void
    {
        $this->detail($id);
        $this->stations->supprimer($id);
    }

    public function ajouterBorne(int $id): int
    {
        $this->detail($id);

        return $this->stations->ajouterBorne($id);
    }

    public function changerEtatBorne(int $id, int $numero, string $etat): void
    {
        (new Validateur())
            ->si(!in_array($etat, self::ETATS_BORNE, true), 'etat', 'État de borne inconnu.')
            ->verifier();
        $this->stations->changerEtatBorne($id, $numero, $etat);
    }

    /**
     * @param array<string, string> $saisie
     * @return array<string, mixed>
     */
    private function valider(array $saisie, bool $creation): array
    {
        $latitude = is_numeric($saisie['latitude'] ?? '') ? (float) $saisie['latitude'] : null;
        $longitude = is_numeric($saisie['longitude'] ?? '') ? (float) $saisie['longitude'] : null;
        $validateur = (new Validateur())
            ->requis('nom', $saisie['nom'] ?? '', 'Le nom')
            ->requis('adresse', $saisie['adresse'] ?? '', 'L\'adresse')
            ->requis('code_postal', $saisie['code_postal'] ?? '', 'Le code postal')
            ->requis('latitude', $latitude, 'La latitude')
            ->requis('longitude', $longitude, 'La longitude')
            ->longueur('nom', $saisie['nom'] ?? '', 1, 100, 'Le nom')
            ->longueur('adresse', $saisie['adresse'] ?? '', 1, 255, 'L\'adresse')
            ->motif('code_postal', $saisie['code_postal'] ?? '', '/^\d{5}$/', 'Le code postal doit contenir 5 chiffres.')
            ->intervalle('latitude', $latitude, -90, 90, 'La latitude')
            ->intervalle('longitude', $longitude, -180, 180, 'La longitude')
            ->si(!in_array($saisie['etat'] ?? '', self::ETATS, true), 'etat', 'État de station inconnu.');
        if ($creation) {
            $nb = (int) ($saisie['nb_bornes'] ?? 0);
            $validateur->si($nb < 1 || $nb > 60, 'nb_bornes', 'Le nombre de bornes doit être compris entre 1 et 60.');
        }
        $validateur->verifier();

        return [
            'nom' => $saisie['nom'],
            'adresse' => $saisie['adresse'],
            'code_postal' => $saisie['code_postal'],
            'latitude' => $latitude,
            'longitude' => $longitude,
            'etat' => $saisie['etat'],
        ];
    }
}
