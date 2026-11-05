<?php

declare(strict_types=1);

namespace App\Application\Port;

interface HacheurMotDePasse
{
    public function hacher(string $motDePasse): string;

    public function verifier(string $motDePasse, string $empreinte): bool;
}
