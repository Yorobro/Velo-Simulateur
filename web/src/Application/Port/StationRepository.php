<?php

declare(strict_types=1);

namespace App\Application\Port;

interface StationRepository
{
    /** @return list<array<string, mixed>> stations avec disponibilité en temps réel */
    public function lister(string $recherche = '', string $etat = ''): array;

    /** @return array<string, mixed>|null */
    public function detail(int $id): ?array;

    /** @return list<array<string, mixed>> bornes et vélo présent sur chacune */
    public function bornes(int $id): array;

    /** @param array<string, mixed> $donnees */
    public function creer(array $donnees, int $nbBornes): int;

    /** @param array<string, mixed> $donnees */
    public function modifier(int $id, array $donnees): void;

    public function supprimer(int $id): void;

    public function ajouterBorne(int $id): int;

    public function changerEtatBorne(int $id, int $numero, string $etat): void;

    /** @return list<array<string, mixed>> stations en service ayant au moins un vélo empruntable */
    public function avecVelos(): array;

    /** @return list<array<string, mixed>> stations en service ayant au moins une borne libre */
    public function avecPlace(): array;

    /** @return list<array<string, mixed>> vélos empruntables d'une station */
    public function velosDisponibles(int $id): array;
}
