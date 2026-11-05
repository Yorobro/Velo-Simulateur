<?php

declare(strict_types=1);

namespace App\Application\Port;

use App\Application\Page;

interface FactureRepository
{
    public function duUtilisateur(int $utilisateur, int $page, int $parPage): Page;

    /** @return array{nb: int, montant: float} factures non réglées */
    public function impayees(int $utilisateur): array;

    public function titulaire(int $facture): ?int;

    public function regler(int $facture): void;
}
