<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Application\Port\StatistiquesRepository;
use DateTimeImmutable;

/**
 * Statistiques. Les périodes filtrent directement sur date_heure_depart
 * (index idx_mouvement_depart) ; les vues v_stat_* servent pour les
 * indicateurs sur une fenêtre fixe.
 */
final class PdoStatistiquesRepository implements StatistiquesRepository
{
    private const TRAJETS = 'FROM location l JOIN mouvement m ON m.id_mouvement = l.id_mouvement';
    private const DUREE = 'CEIL(TIMESTAMPDIFF(SECOND, m.date_heure_depart, m.date_heure_arrivee) / 60)';

    public function __construct(private readonly BaseDeDonnees $db)
    {
    }

    public function indicateurs(): array
    {
        $ligne = $this->db->ligne(
            'SELECT (SELECT COUNT(*) ' . self::TRAJETS . ' WHERE m.date_heure_depart >= CURDATE()) AS trajets_jour,
                    (SELECT COUNT(*) ' . self::TRAJETS . '
                      WHERE m.date_heure_depart >= CURDATE() - INTERVAL 29 DAY) AS trajets_30j,
                    (SELECT COALESCE(SUM(montant), 0) FROM facture
                      WHERE date_emission >= CURDATE() - INTERVAL 29 DAY) AS recettes_30j,
                    (SELECT COUNT(DISTINCT id_utilisateur) FROM abonnement
                      WHERE CURDATE() BETWEEN date_debut AND date_fin) AS abonnes_actifs,
                    (SELECT COUNT(*) FROM v_velo WHERE situation = \'EN_LOCATION\') AS locations_en_cours,
                    (SELECT COALESCE(SUM(velos_mecaniques_disponibles + velos_electriques_disponibles), 0)
                       FROM v_disponibilite_station) AS velos_disponibles,
                    (SELECT COALESCE(SUM(bornes_libres), 0) FROM v_disponibilite_station) AS bornes_libres,
                    (SELECT COUNT(*) FROM station WHERE etat = \'EN_SERVICE\') AS stations_en_service,
                    (SELECT COUNT(*) FROM station) AS stations',
        ) ?? [];
        $indisponibilite = $this->db->valeur(
            'SELECT taux_indisponibilite_actuel_pct FROM v_stat_indisponibilite_flotte WHERE type_velo = \'TOUS\'',
        );
        $ligne['indisponibilite_pct'] = (float) $indisponibilite;

        return array_map(static fn ($v) => is_numeric($v) ? $v + 0 : 0, $ligne);
    }

    public function trajetsParJour(DateTimeImmutable $depuis): array
    {
        return $this->db->lignes(
            'SELECT DATE(m.date_heure_depart) AS jour, COUNT(*) AS trajets,
                    ROUND(AVG(' . self::DUREE . '), 1) AS duree_moyenne
               ' . self::TRAJETS . '
              WHERE m.date_heure_depart >= ?
              GROUP BY DATE(m.date_heure_depart)
              ORDER BY jour',
            [$depuis->format('Y-m-d H:i:s')],
        );
    }

    public function departsParHeure(DateTimeImmutable $depuis): array
    {
        $parHeure = [];
        foreach ($this->db->lignes(
            'SELECT HOUR(m.date_heure_depart) AS heure, COUNT(*) AS departs ' . self::TRAJETS . '
              WHERE m.date_heure_depart >= ? GROUP BY HOUR(m.date_heure_depart)',
            [$depuis->format('Y-m-d H:i:s')],
        ) as $ligne) {
            $parHeure[(int) $ligne['heure']] = (int) $ligne['departs'];
        }

        return $parHeure;
    }

    public function origineDestination(DateTimeImmutable $depuis, int $limite): array
    {
        return $this->db->lignes(
            'SELECT t.*, sd.nom AS station_depart, sa.nom AS station_arrivee
               FROM (SELECT m.id_station_depart, m.id_station_arrivee, COUNT(*) AS trajets,
                            ROUND(AVG(' . self::DUREE . '), 1) AS duree_moyenne
                       ' . self::TRAJETS . '
                      WHERE m.date_heure_depart >= ? AND m.id_station_arrivee IS NOT NULL
                      GROUP BY m.id_station_depart, m.id_station_arrivee
                      ORDER BY trajets DESC
                      LIMIT ?) t
               JOIN station sd ON sd.id_station = t.id_station_depart
               JOIN station sa ON sa.id_station = t.id_station_arrivee
              ORDER BY t.trajets DESC',
            [$depuis->format('Y-m-d H:i:s'), $limite],
        );
    }

    public function recettesParFormule(DateTimeImmutable $depuis): array
    {
        $date = $depuis->format('Y-m-d H:i:s');

        return $this->db->lignes(
            'SELECT f.id_formule, f.type AS formule,
                    COALESCE(SUM(r.abonnements), 0) AS abonnements, COALESCE(SUM(r.locations), 0) AS locations,
                    COUNT(r.id_formule) AS factures
               FROM formule f
               LEFT JOIN (SELECT a.id_formule, fa.montant AS abonnements, 0 AS locations
                            FROM facture fa JOIN abonnement a ON a.id_abonnement = fa.id_abonnement
                           WHERE fa.date_emission >= ?
                          UNION ALL
                          SELECT a.id_formule, 0, fa.montant
                            FROM facture fa
                            JOIN location l   ON l.id_mouvement = fa.id_location
                            JOIN abonnement a ON a.id_abonnement = l.id_abonnement
                           WHERE fa.date_emission >= ?) r ON r.id_formule = f.id_formule
              GROUP BY f.id_formule, f.type
              ORDER BY f.id_formule',
            [$date, $date],
        );
    }

    public function indisponibilite(): array
    {
        return $this->db->lignes('SELECT * FROM v_stat_indisponibilite_flotte');
    }

    public function remplissageHoraire(): array
    {
        return $this->db->lignes('SELECT id_station, nom, heure, taux_remplissage_pct FROM v_stat_remplissage_horaire');
    }
}
