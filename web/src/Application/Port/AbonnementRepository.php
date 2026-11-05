<?php

declare(strict_types=1);

namespace App\Application\Port;

interface AbonnementRepository
{
    /** @return array<string, mixed>|null */
    public function actif(int $utilisateur): ?array;

    /** @return list<array<string, mixed>> */
    public function duUtilisateur(int $utilisateur): array;

    public function titulaire(int $abonnement): ?int;

    public function souscrire(int $utilisateur, int $formule): int;

    public function renouveler(int $abonnement): int;

    /** @return list<array<string, mixed>> */
    public function formules(): array;

    /** @param array<string, mixed> $donnees */
    public function modifierFormule(int $formule, array $donnees): void;
}
