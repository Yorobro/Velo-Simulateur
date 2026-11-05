<?php

declare(strict_types=1);

namespace App\Application\Admin;

use App\Application\Page;
use App\Application\Port\AbonnementRepository;
use App\Application\Port\UtilisateurRepository;
use App\Application\Validateur;
use App\Domain\Exception\RegleMetierException;
use App\Domain\Role;
use App\Domain\Utilisateur;

/** Administration : utilisateurs et formules tarifaires. */
final class AdminService
{
    public function __construct(
        private readonly UtilisateurRepository $utilisateurs,
        private readonly AbonnementRepository $abonnements,
    ) {
    }

    public function utilisateurs(string $recherche, string $role, int $page): Page
    {
        return $this->utilisateurs->rechercher($recherche, Role::tryFrom($role), $page, 25);
    }

    /** @return array<string, int> */
    public function compterParRole(): array
    {
        return $this->utilisateurs->compterParRole();
    }

    public function changerRole(Utilisateur $acteur, int $id, string $role): void
    {
        $nouveau = Role::tryFrom($role);
        (new Validateur())->si($nouveau === null, 'role', 'Rôle inconnu.')->verifier();
        $this->refuserSoiMeme($acteur, $id);
        $this->utilisateurs->changerRole($id, $nouveau);
    }

    public function supprimer(Utilisateur $acteur, int $id): void
    {
        $this->refuserSoiMeme($acteur, $id);
        $this->utilisateurs->supprimer($id);
    }

    /** @return list<array<string, mixed>> */
    public function formules(): array
    {
        return $this->abonnements->formules();
    }

    /** @param array<string, string> $saisie */
    public function modifierFormule(int $id, array $saisie): void
    {
        $champs = [
            'prix' => ['Le prix', 0, 10000],
            'duree_validite_jours' => ['La durée de validité', 1, 3660],
            'duree_gratuite_min' => ['La durée gratuite', 0, 1440],
            'duree_tranche_min' => ['La durée d\'une tranche', 1, 1440],
            'prix_tranche' => ['Le prix d\'une tranche', 0, 1000],
            'supplement_electrique' => ['Le supplément électrique', 0, 1000],
            'supplement_casque' => ['Le supplément casque', 0, 1000],
        ];
        $validateur = new Validateur();
        $donnees = [];
        foreach ($champs as $champ => [$libelle, $min, $max]) {
            $valeur = str_replace(',', '.', $saisie[$champ] ?? '');
            $nombre = is_numeric($valeur) ? (float) $valeur : null;
            $validateur->requis($champ, $nombre, $libelle)->intervalle($champ, $nombre, $min, $max, $libelle);
            $donnees[$champ] = $nombre;
        }
        $validateur->verifier();
        $this->abonnements->modifierFormule($id, $donnees);
    }

    private function refuserSoiMeme(Utilisateur $acteur, int $id): void
    {
        if ($acteur->id === $id) {
            throw new RegleMetierException('Vous ne pouvez pas modifier ni supprimer votre propre compte ici.');
        }
    }
}
