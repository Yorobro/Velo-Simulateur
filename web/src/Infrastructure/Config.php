<?php

declare(strict_types=1);

namespace App\Infrastructure;

/** Accès en lecture à config/app.php, par chemin pointé : get('db.hote'). */
final class Config
{
    /** @param array<string, mixed> $valeurs */
    public function __construct(private readonly array $valeurs)
    {
    }

    public function get(string $chemin, mixed $defaut = null): mixed
    {
        $valeur = $this->valeurs;
        foreach (explode('.', $chemin) as $cle) {
            if (!is_array($valeur) || !array_key_exists($cle, $valeur)) {
                return $defaut;
            }
            $valeur = $valeur[$cle];
        }

        return $valeur;
    }
}
