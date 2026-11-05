<?php

declare(strict_types=1);

namespace App\Infrastructure\Securite;

use App\Application\Port\HacheurMotDePasse;

/** Empreintes bcrypt (compatibles avec les comptes créés par peuplement_velo.py). */
final class HacheurBcrypt implements HacheurMotDePasse
{
    public function hacher(string $motDePasse): string
    {
        return password_hash($motDePasse, PASSWORD_BCRYPT);
    }

    public function verifier(string $motDePasse, string $empreinte): bool
    {
        return $empreinte !== '' && password_verify($motDePasse, $empreinte);
    }
}
