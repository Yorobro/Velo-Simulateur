<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Application\Port\RegulationRepository;

/** Régulation : vues v_regulation et v_proposition_deplacement, tournées par procédures stockées. */
final class PdoRegulationRepository implements RegulationRepository
{
    public function __construct(private readonly BaseDeDonnees $db)
    {
    }

    public function stations(): array
    {
        return $this->db->lignes(
            'SELECT * FROM v_regulation
              ORDER BY FIELD(statut, \'VIDE\', \'PLEINE\', \'PRESQUE_VIDE\', \'PRESQUE_PLEINE\', \'EQUILIBREE\'), nom',
        );
    }

    public function propositions(): array
    {
        return $this->db->lignes('SELECT * FROM v_proposition_deplacement ORDER BY nb_velos_a_deplacer DESC, distance_km');
    }

    public function tourneeEnCours(int $operateur): ?array
    {
        return $this->db->ligne(
            'SELECT t.id_tournee, t.date_heure_debut, v.immatriculation, v.capacite,
                    (SELECT COUNT(*) FROM transfert tr WHERE tr.id_tournee = t.id_tournee) AS nb_transferts
               FROM tournee t
               JOIN vehicule v ON v.id_vehicule = t.id_vehicule
              WHERE t.id_utilisateur = ? AND t.date_heure_fin IS NULL
              LIMIT 1',
            [$operateur],
        );
    }

    public function transferts(int $tournee): array
    {
        return $this->db->lignes(
            'SELECT tr.id_mouvement, m.id_velo, IF(ve.id_velo IS NULL, \'MECANIQUE\', \'ELECTRIQUE\') AS type_velo,
                    sd.nom AS station_depart, m.date_heure_depart, sa.nom AS station_arrivee, m.date_heure_arrivee
               FROM transfert tr
               JOIN mouvement m       ON m.id_mouvement = tr.id_mouvement
               JOIN station sd        ON sd.id_station = m.id_station_depart
               LEFT JOIN station sa   ON sa.id_station = m.id_station_arrivee
               LEFT JOIN velo_electrique ve ON ve.id_velo = m.id_velo
              WHERE tr.id_tournee = ?
              ORDER BY m.date_heure_depart',
            [$tournee],
        );
    }

    public function tourneesRecentes(int $limite): array
    {
        return $this->db->lignes(
            'SELECT t.id_tournee, t.date_heure_debut, t.date_heure_fin, v.immatriculation,
                    CONCAT(u.prenom, \' \', u.nom) AS operateur, COUNT(tr.id_mouvement) AS nb_velos
               FROM (SELECT * FROM tournee ORDER BY date_heure_debut DESC LIMIT ?) t
               JOIN utilisateur u       ON u.id_utilisateur = t.id_utilisateur
               JOIN vehicule v          ON v.id_vehicule = t.id_vehicule
               LEFT JOIN transfert tr   ON tr.id_tournee = t.id_tournee
              GROUP BY t.id_tournee, t.date_heure_debut, t.date_heure_fin, v.immatriculation, u.prenom, u.nom
              ORDER BY t.date_heure_debut DESC',
            [$limite],
        );
    }

    public function operateurDeTournee(int $tournee): ?int
    {
        $id = $this->db->valeur('SELECT id_utilisateur FROM tournee WHERE id_tournee = ?', [$tournee]);

        return $id === null ? null : (int) $id;
    }

    public function vehiculesLibres(): array
    {
        return $this->db->lignes(
            'SELECT v.id_vehicule, v.immatriculation, v.capacite
               FROM vehicule v
              WHERE NOT EXISTS (SELECT 1 FROM tournee t
                                 WHERE t.id_vehicule = v.id_vehicule AND t.date_heure_fin IS NULL)
              ORDER BY v.immatriculation',
        );
    }

    public function demarrer(int $operateur, int $vehicule): int
    {
        return (int) $this->db->appeler('demarrer_tournee', [$operateur, $vehicule], 1)[0];
    }

    public function charger(int $tournee, int $velo): int
    {
        return (int) $this->db->appeler('charger_velo', [$tournee, $velo], 1)[0];
    }

    public function deposer(int $transfert, int $station): void
    {
        $this->db->appeler('deposer_velo', [$transfert, $station, null]);
    }

    public function cloturer(int $tournee): void
    {
        $this->db->appeler('cloturer_tournee', [$tournee]);
    }
}
