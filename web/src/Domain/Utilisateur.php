<?php

declare(strict_types=1);

namespace App\Domain;

final class Utilisateur
{
    public function __construct(
        public readonly int $id,
        public readonly string $nom,
        public readonly string $prenom,
        public readonly string $email,
        public readonly Role $role,
        public readonly string $motDePasseHash = '',
    ) {
    }

    public function nomComplet(): string
    {
        return "{$this->prenom} {$this->nom}";
    }
}
