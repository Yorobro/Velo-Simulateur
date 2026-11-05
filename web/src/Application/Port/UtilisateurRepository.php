<?php

declare(strict_types=1);

namespace App\Application\Port;

use App\Application\Page;
use App\Domain\Role;
use App\Domain\Utilisateur;

interface UtilisateurRepository
{
    public function parEmail(string $email): ?Utilisateur;

    public function parId(int $id): ?Utilisateur;

    /** @param array{nom: string, prenom: string, email: string, telephone: string} $donnees */
    public function inscrire(array $donnees, string $motDePasseHash): int;

    public function rechercher(string $recherche, ?Role $role, int $page, int $parPage): Page;

    /** @return array<string, int> nombre d'utilisateurs par rôle */
    public function compterParRole(): array;

    public function changerRole(int $id, Role $role): void;

    public function supprimer(int $id): void;
}
