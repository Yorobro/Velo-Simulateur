<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Application\Port\MaintenanceRepository;

final class PdoMaintenanceRepository implements MaintenanceRepository
{
    public function __construct(private readonly BaseDeDonnees $db)
    {
    }

    public function velosARetirer(): array
    {
        return $this->db->lignes(
            'SELECT v.id_velo, v.type_velo, v.etat, v.id_station, v.station, v.numero_borne,
                    COALESCE(o.nb, 0) AS nb_signalements, o.depuis, o.description
               FROM v_velo v
               LEFT JOIN (SELECT sv.id_velo, COUNT(*) AS nb, MIN(s.date_heure_signalement) AS depuis,
                                 MAX(s.description) AS description
                            FROM signalement_velo sv
                            JOIN signalement s ON s.id_signalement = sv.id_signalement
                           WHERE sv.id_intervention_velo IS NULL AND s.date_heure_cloture IS NULL
                           GROUP BY sv.id_velo) o ON o.id_velo = v.id_velo
              WHERE v.situation = \'SUR_BORNE\' AND (v.etat = \'DEFECTUEUX\' OR o.id_velo IS NOT NULL)
              ORDER BY v.etat = \'DEFECTUEUX\' DESC, o.depuis',
        );
    }

    public function enAtelier(): array
    {
        return $this->db->lignes(
            'SELECT iv.id_intervention, i.description, m.id_velo,
                    IF(ve.id_velo IS NULL, \'MECANIQUE\', \'ELECTRIQUE\') AS type_velo,
                    m.date_heure_depart, sd.nom AS station_depart, CONCAT(u.prenom, \' \', u.nom) AS operateur,
                    (SELECT COUNT(*) FROM signalement_velo sv WHERE sv.id_intervention_velo = iv.id_intervention)
                        AS nb_signalements
               FROM intervention_velo iv
               JOIN intervention i ON i.id_intervention = iv.id_intervention
               JOIN mouvement m    ON m.id_mouvement = iv.id_mouvement
               JOIN station sd     ON sd.id_station = m.id_station_depart
               JOIN utilisateur u  ON u.id_utilisateur = i.id_utilisateur
               LEFT JOIN velo_electrique ve ON ve.id_velo = m.id_velo
              WHERE m.date_heure_arrivee IS NULL
              ORDER BY m.date_heure_depart',
        );
    }

    public function signalementsStation(): array
    {
        return $this->db->lignes(
            'SELECT s.id_signalement, s.description, s.date_heure_signalement, st.id_station, st.nom AS station,
                    st.etat AS etat_station, CONCAT(u.prenom, \' \', u.nom) AS auteur
               FROM signalement s
               JOIN signalement_station ss ON ss.id_signalement = s.id_signalement
               JOIN station st             ON st.id_station = ss.id_station
               JOIN utilisateur u          ON u.id_utilisateur = s.id_utilisateur
              WHERE s.date_heure_cloture IS NULL
                AND NOT EXISTS (SELECT 1 FROM intervention_station i
                                 WHERE i.id_signalement_station = s.id_signalement AND i.date_heure_fin IS NULL)
              ORDER BY s.date_heure_signalement',
        );
    }

    public function travauxEnCours(): array
    {
        return $this->db->lignes(
            'SELECT i.id_intervention, it.description, i.date_heure_debut, st.nom AS station, st.etat AS etat_station,
                    s.description AS signalement, CONCAT(u.prenom, \' \', u.nom) AS operateur
               FROM intervention_station i
               JOIN intervention it        ON it.id_intervention = i.id_intervention
               JOIN signalement s          ON s.id_signalement = i.id_signalement_station
               JOIN signalement_station ss ON ss.id_signalement = s.id_signalement
               JOIN station st             ON st.id_station = ss.id_station
               JOIN utilisateur u          ON u.id_utilisateur = it.id_utilisateur
              WHERE i.date_heure_fin IS NULL
              ORDER BY i.date_heure_debut',
        );
    }

    public function compteurs(): array
    {
        $ligne = $this->db->ligne(
            'SELECT (SELECT COUNT(*) FROM signalement WHERE date_heure_cloture IS NULL) AS signalements_ouverts,
                    (SELECT COUNT(*) FROM v_velo WHERE situation = \'EN_ATELIER\') AS en_atelier,
                    (SELECT COUNT(*) FROM v_velo WHERE situation = \'SUR_BORNE\' AND etat = \'DEFECTUEUX\') AS bloques,
                    (SELECT COUNT(*) FROM intervention_station WHERE date_heure_fin IS NULL) AS travaux,
                    (SELECT COUNT(*) FROM v_velo WHERE etat = \'REFORME\') AS reformes',
        ) ?? [];

        return array_map('intval', $ligne);
    }

    public function retirer(int $operateur, int $velo, string $description): int
    {
        return (int) $this->db->appeler('retirer_velo', [$operateur, $velo, $description], 1)[0];
    }

    public function remettre(int $intervention, int $station): void
    {
        $this->db->appeler('remettre_en_circulation', [$intervention, $station, null]);
    }

    public function reformer(int $intervention): void
    {
        $this->db->appeler('reformer_velo', [$intervention]);
    }

    public function demarrerTravaux(int $operateur, int $signalement, string $description): int
    {
        return (int) $this->db->appeler('demarrer_intervention_station', [$operateur, $signalement, $description], 1)[0];
    }

    public function terminerTravaux(int $intervention, bool $resolu): void
    {
        $this->db->appeler('terminer_intervention_station', [$intervention, $resolu]);
    }
}
