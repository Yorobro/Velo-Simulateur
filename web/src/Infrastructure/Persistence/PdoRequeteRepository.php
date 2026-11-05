<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Application\Port\RequeteRepository;
use App\Application\Requete\Resultat;
use App\Domain\Exception\RegleMetierException;
use PDO;
use PDOException;

/**
 * Requêtes principales de l'application (catalogue) et exécution mesurée.
 * Chaque exécution a lieu dans une transaction en lecture seule, annulée à la
 * fin, avec une durée maximale.
 */
final class PdoRequeteRepository implements RequeteRepository
{
    private const USAGER_DEMO = '(SELECT id_utilisateur FROM utilisateur WHERE email = \'usager@velo.example.org\')';

    public function __construct(private readonly BaseDeDonnees $db)
    {
    }

    public function catalogue(): array
    {
        return [
            'disponibilite' => ['titre' => 'Disponibilité des stations',
                'description' => 'Vélos disponibles par type et bornes libres, en temps réel.',
                'sql' => 'SELECT * FROM v_disponibilite_station'],
            'flotte' => ['titre' => 'Fiche de tous les vélos',
                'description' => 'Type, batterie, état et situation de chaque vélo.',
                'sql' => 'SELECT * FROM v_velo'],
            'en_location' => ['titre' => 'Vélos en location',
                'description' => 'Locations en cours, lues par la situation des vélos.',
                'sql' => 'SELECT * FROM v_velo WHERE situation = \'EN_LOCATION\''],
            'historique_usager' => ['titre' => 'Historique d\'un usager',
                'description' => 'Vingt derniers trajets de l\'usager de démonstration.',
                'sql' => 'SELECT * FROM v_location WHERE id_utilisateur = ' . self::USAGER_DEMO
                    . ' ORDER BY date_heure_depart DESC LIMIT 20'],
            'abonnement_valide' => ['titre' => 'Abonnement valide (emprunt)',
                'description' => 'Fonction fn_abonnement_valide appelée à chaque emprunt.',
                'sql' => 'SELECT fn_abonnement_valide(' . self::USAGER_DEMO . ', CURDATE()) AS abonnement'],
            'dernier_mouvement' => ['titre' => 'Dernier mouvement d\'un vélo',
                'description' => 'Requête des triggers de mouvement (index id_velo, date_heure_depart).',
                'sql' => 'SELECT * FROM mouvement WHERE id_velo = 7 ORDER BY date_heure_depart DESC LIMIT 1'],
            'regulation' => ['titre' => 'Stations à réguler',
                'description' => 'Stations vides, pleines ou déséquilibrées.',
                'sql' => 'SELECT * FROM v_regulation'],
            'propositions' => ['titre' => 'Propositions de déplacement',
                'description' => 'Station vide la plus proche de chaque station pleine.',
                'sql' => 'SELECT * FROM v_proposition_deplacement'],
            'signalements' => ['titre' => 'Signalements ouverts',
                'description' => 'Écran des opérateurs de maintenance.',
                'sql' => 'SELECT * FROM signalement WHERE date_heure_cloture IS NULL ORDER BY date_heure_signalement'],
            'impayees' => ['titre' => 'Factures impayées',
                'description' => 'Relances (index date_reglement).',
                'sql' => 'SELECT * FROM facture WHERE date_reglement IS NULL ORDER BY date_emission'],
            'trajets_30j' => ['titre' => 'Trajets des 30 derniers jours',
                'description' => 'Filtre de période sur date_heure_depart.',
                'sql' => 'SELECT COUNT(*) AS trajets FROM location l JOIN mouvement m ON m.id_mouvement = l.id_mouvement'
                    . ' WHERE m.date_heure_depart >= CURDATE() - INTERVAL 30 DAY'],
            'stat_jours' => ['titre' => 'Statistique : trajets par jour',
                'description' => 'Vue v_stat_trajets_par_jour (tout l\'historique).',
                'sql' => 'SELECT * FROM v_stat_trajets_par_jour'],
            'stat_heures' => ['titre' => 'Statistique : heures de pointe',
                'description' => 'Vue v_stat_heures_pointe.',
                'sql' => 'SELECT * FROM v_stat_heures_pointe'],
            'stat_od' => ['titre' => 'Statistique : origine-destination',
                'description' => 'Vue v_stat_origine_destination.',
                'sql' => 'SELECT * FROM v_stat_origine_destination'],
            'stat_recettes' => ['titre' => 'Statistique : recettes par formule',
                'description' => 'Vue v_stat_recettes_formule.',
                'sql' => 'SELECT * FROM v_stat_recettes_formule'],
            'stat_indispo' => ['titre' => 'Statistique : indisponibilité',
                'description' => 'Vue v_stat_indisponibilite_flotte (30 jours).',
                'sql' => 'SELECT * FROM v_stat_indisponibilite_flotte'],
            'stat_remplissage' => ['titre' => 'Statistique : remplissage horaire',
                'description' => 'Vue v_stat_remplissage_horaire (30 jours, station x heure).',
                'sql' => 'SELECT * FROM v_stat_remplissage_horaire'],
        ];
    }

    public function executer(string $sql, int $maxLignes, int $delaiMs): Resultat
    {
        $pdo = $this->db->pdo();
        $this->limiterDuree($pdo, $delaiMs);
        $pdo->exec('START TRANSACTION READ ONLY');
        $pdo->setAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, false);
        try {
            $debut = hrtime(true);
            $requete = $pdo->query($sql);
            $colonnes = [];
            for ($i = 0; $i < $requete->columnCount(); $i++) {
                $colonnes[] = (string) ($requete->getColumnMeta($i)['name'] ?? "col{$i}");
            }
            $lignes = [];
            $nb = 0;
            while (($ligne = $requete->fetch(PDO::FETCH_ASSOC)) !== false) {
                if (++$nb <= $maxLignes) {
                    $lignes[] = $ligne;
                }
            }
            $duree = (hrtime(true) - $debut) / 1e6;
            $requete->closeCursor();
        } catch (PDOException $e) {
            $traduite = $this->db->traduire($e);
            throw $traduite instanceof RegleMetierException
                ? $traduite
                : new RegleMetierException('Erreur SQL : ' . ($e->errorInfo[2] ?? $e->getMessage()), 0, $e);
        } finally {
            $pdo->setAttribute(PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, true);
            $pdo->exec('ROLLBACK');
            $this->limiterDuree($pdo, 0);
        }

        return new Resultat($sql, $colonnes, $lignes, $nb, round($duree, 2), $nb > $maxLignes);
    }

    /** Durée maximale d'une requête : max_execution_time (MySQL, ms) ou max_statement_time (MariaDB, s). */
    private function limiterDuree(PDO $pdo, int $delaiMs): void
    {
        try {
            $pdo->exec('SET SESSION max_execution_time = ' . $delaiMs);
        } catch (PDOException) {
            try {
                $pdo->exec('SET SESSION max_statement_time = ' . ($delaiMs / 1000));
            } catch (PDOException) {
                // option absente : pas de limite
            }
        }
    }
}
