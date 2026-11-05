<?php

declare(strict_types=1);

namespace App\Application\Port;

use App\Application\Page;

interface LocationRepository
{
    /** @return array<string, mixed>|null */
    public function enCours(int $utilisateur): ?array;

    public function historique(int $utilisateur, int $page, int $parPage): Page;

    /** @return array{nb: int, minutes: int, depense: float} */
    public function bilan(int $utilisateur): array;

    public function titulaire(int $location): ?int;

    /** Appelle emprunter_velo ; renvoie l'identifiant de la location. */
    public function emprunter(int $utilisateur, int $velo): int;

    /** Appelle restituer_velo (borne choisie automatiquement). */
    public function restituer(int $location, int $station, bool $casque): void;
}
