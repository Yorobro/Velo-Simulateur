<?php

declare(strict_types=1);

namespace App\Application\Statistiques;

use App\Application\Port\StatistiquesRepository;
use DateTimeImmutable;

/** Statistiques demandées par le sujet, sur une période choisie. */
final class StatistiquesService
{
    /** clé => [nombre de jours, libellé] */
    public const PERIODES = [
        '30j' => [30, '30 jours'],
        '90j' => [90, '3 mois'],
        '365j' => [365, '12 mois'],
    ];

    public function __construct(private readonly StatistiquesRepository $statistiques)
    {
    }

    /** @return array<string, int|float> */
    public function indicateurs(): array
    {
        return $this->statistiques->indicateurs();
    }

    /** @return array<string, mixed> */
    public function tableau(string $periode): array
    {
        $periode = isset(self::PERIODES[$periode]) ? $periode : '30j';
        $depuis = (new DateTimeImmutable('today'))->modify('-' . (self::PERIODES[$periode][0] - 1) . ' days');
        $parHeure = $this->statistiques->departsParHeure($depuis);

        return [
            'periode' => $periode,
            'periodes' => self::PERIODES,
            'indicateurs' => $this->statistiques->indicateurs(),
            'trajets_par_jour' => $this->statistiques->trajetsParJour($depuis),
            'departs_par_heure' => array_map(static fn (int $h): int => $parHeure[$h] ?? 0, range(0, 23)),
            'origine_destination' => $this->statistiques->origineDestination($depuis, 10),
            'recettes' => $this->statistiques->recettesParFormule($depuis),
            'indisponibilite' => $this->statistiques->indisponibilite(),
        ];
    }

    /**
     * Taux de remplissage par station (lignes) et par heure (colonnes).
     *
     * @return list<array{id: int, nom: string, heures: array<int, float|null>, moyenne: float}>
     */
    public function remplissage(): array
    {
        $stations = [];
        foreach ($this->statistiques->remplissageHoraire() as $ligne) {
            $id = (int) $ligne['id_station'];
            $stations[$id] ??= ['id' => $id, 'nom' => (string) $ligne['nom'], 'heures' => array_fill(0, 24, null)];
            $stations[$id]['heures'][(int) $ligne['heure']] = (float) $ligne['taux_remplissage_pct'];
        }
        foreach ($stations as &$station) {
            $valeurs = array_filter($station['heures'], static fn ($v) => $v !== null);
            $station['moyenne'] = $valeurs === [] ? 0.0 : array_sum($valeurs) / count($valeurs);
        }
        unset($station);
        usort($stations, static fn (array $a, array $b): int => strcmp($a['nom'], $b['nom']));

        return $stations;
    }
}
