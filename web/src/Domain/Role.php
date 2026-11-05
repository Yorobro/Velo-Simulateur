<?php

declare(strict_types=1);

namespace App\Domain;

/** Rôles des utilisateurs (colonne utilisateur.role). */
enum Role: string
{
    case Usager = 'USAGER';
    case OperateurRegulation = 'OPERATEUR_REGULATION';
    case OperateurMaintenance = 'OPERATEUR_MAINTENANCE';
    case Administrateur = 'ADMINISTRATEUR';

    public function libelle(): string
    {
        return match ($this) {
            self::Usager => 'Usager',
            self::OperateurRegulation => 'Opérateur de régulation',
            self::OperateurMaintenance => 'Opérateur de maintenance',
            self::Administrateur => 'Administrateur',
        };
    }

    public function estPersonnel(): bool
    {
        return $this !== self::Usager;
    }

    /**
     * L'administrateur a tous les droits ; les autres rôles seulement ceux listés.
     *
     * @param list<string> $roles valeurs autorisées
     */
    public function autorise(array $roles): bool
    {
        return $this === self::Administrateur || in_array($this->value, $roles, true);
    }
}
