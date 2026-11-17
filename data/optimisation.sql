-- =============================================================================
--  Réseau de vélos en libre-service — OPTIMISATION
-- =============================================================================
--  Index ciblés et statistiques de l'optimiseur. Aucune table ni colonne
--  ajoutée ; les vues optimisées sont directement dans automatisation.sql.
--  Ordre : ... -> automatisation.sql -> optimisation.sql. Rejouable.
--  Chaque index sert une requête précise de l'application. Un index composite
--  qui commence par une clé étrangère remplace l'index automatique de cette
--  clé (pas d'index en double).
-- =============================================================================

SET NAMES utf8mb4;
USE velo_libre_service;


-- =============================================================================
--  0. Outils (procédures temporaires, supprimées en fin de script)
-- =============================================================================

DROP PROCEDURE IF EXISTS opt_creer_index;
DROP PROCEDURE IF EXISTS opt_supprimer_index;

DELIMITER $$

-- Crée un index s'il n'existe pas encore (MySQL n'a pas CREATE INDEX IF NOT EXISTS).
CREATE PROCEDURE opt_creer_index(IN p_table VARCHAR(64), IN p_index VARCHAR(64),
                                 IN p_colonnes VARCHAR(255))
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.statistics
                  WHERE table_schema = DATABASE() AND table_name = p_table
                    AND index_name = p_index) THEN
    SET @opt_sql = CONCAT('CREATE INDEX ', p_index, ' ON ', p_table, ' (', p_colonnes, ')');
    PREPARE opt_stmt FROM @opt_sql;
    EXECUTE opt_stmt;
    DEALLOCATE PREPARE opt_stmt;
  END IF;
END$$

-- Supprime un index s'il existe encore.
CREATE PROCEDURE opt_supprimer_index(IN p_table VARCHAR(64), IN p_index VARCHAR(64))
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.statistics
              WHERE table_schema = DATABASE() AND table_name = p_table
                AND index_name = p_index) THEN
    SET @opt_sql = CONCAT('DROP INDEX ', p_index, ' ON ', p_table);
    PREPARE opt_stmt FROM @opt_sql;
    EXECUTE opt_stmt;
    DEALLOCATE PREPARE opt_stmt;
  END IF;
END$$

DELIMITER ;


-- =============================================================================
--  1. Index
-- =============================================================================
--  Clés primaires, UNIQUE et clés étrangères ont déjà leur index.

-- ---------------------------------------------------------------- mouvement
-- Historique d'un vélo et dernier mouvement (trigger trg_velo_bu, fiche du
-- vélo, séjours de v_stat_remplissage_horaire) :
--   WHERE id_velo = ? ORDER BY date_heure_depart DESC LIMIT 1
CALL opt_creer_index('mouvement', 'idx_mouvement_velo_depart', 'id_velo, date_heure_depart');
CALL opt_supprimer_index('mouvement', 'fk_mouvement_velo');

-- Mouvement en cours d'un vélo (v_velo : situation EN_LOCATION / EN_TOURNEE /
-- EN_ATELIER) et dernière arrivée d'un vélo (trigger trg_mouvement_bi) :
--   WHERE id_velo = ? AND date_heure_arrivee IS NULL
--   SELECT MAX(date_heure_arrivee) WHERE id_velo = ?   -> lu directement dans l'index
CALL opt_creer_index('mouvement', 'idx_mouvement_velo_arrivee', 'id_velo, date_heure_arrivee');

-- Statistiques et recherches par période (trajets par période, heures de
-- pointe, filtre de dates de l'interface) :
--   WHERE date_heure_depart BETWEEN ? AND ?
CALL opt_creer_index('mouvement', 'idx_mouvement_depart', 'date_heure_depart');

-- ---------------------------------------------------------------- abonnement
-- Abonnement valide d'un usager, vérifié à chaque emprunt (fn_abonnement_valide) :
--   WHERE id_utilisateur = ? AND ? BETWEEN date_debut AND date_fin
CALL opt_creer_index('abonnement', 'idx_abonnement_utilisateur_fin', 'id_utilisateur, date_fin');
CALL opt_supprimer_index('abonnement', 'fk_abonnement_utilisateur');

-- ---------------------------------------------------------------- facture
-- Recettes par période (statistiques, rapports) :
--   WHERE date_emission BETWEEN ? AND ?
CALL opt_creer_index('facture', 'idx_facture_emission', 'date_emission');
-- Factures à régler (relances, tableau de bord administrateur) :
--   WHERE date_reglement IS NULL AND montant > 0
-- Composite : la plupart des factures non réglées sont des trajets à 0 € ;
-- seules celles à payer sont lues.
CALL opt_creer_index('facture', 'idx_facture_a_regler', 'date_reglement, montant');
CALL opt_supprimer_index('facture', 'idx_facture_reglement');

-- ---------------------------------------------------------------- signalement
-- Signalements ouverts, du plus ancien au plus récent (écran des opérateurs) :
--   WHERE date_heure_cloture IS NULL ORDER BY date_heure_signalement
CALL opt_creer_index('signalement', 'idx_signalement_ouvert', 'date_heure_cloture, date_heure_signalement');

-- Signalements ouverts et non traités d'un vélo, rattachés au retrait du vélo
-- (trigger trg_intervention_velo_ai) :
--   WHERE id_velo = ? AND id_intervention_velo IS NULL
CALL opt_creer_index('signalement_velo', 'idx_signalement_velo_traitement', 'id_velo, id_intervention_velo');
CALL opt_supprimer_index('signalement_velo', 'fk_signalement_velo_velo');

-- Intervention en cours sur un signalement de station (v_signalement) :
--   WHERE id_signalement_station = ? AND date_heure_fin IS NULL
CALL opt_creer_index('intervention_station', 'idx_intervention_station_signalement',
                     'id_signalement_station, date_heure_fin');
CALL opt_supprimer_index('intervention_station', 'fk_intervention_station_signalement');

-- ---------------------------------------------------------------- tournee
-- Tournée en cours d'un opérateur (trigger trg_tournee_bi) :
--   WHERE id_utilisateur = ? AND date_heure_fin IS NULL
CALL opt_creer_index('tournee', 'idx_tournee_operateur_fin', 'id_utilisateur, date_heure_fin');
CALL opt_supprimer_index('tournee', 'fk_tournee_utilisateur');

-- Tournée en cours d'un véhicule (trigger trg_tournee_bi, R16) et recherche
-- des tournées par véhicule :
--   WHERE id_vehicule = ? AND date_heure_fin IS NULL
CALL opt_creer_index('tournee', 'idx_tournee_vehicule_fin', 'id_vehicule, date_heure_fin');
CALL opt_supprimer_index('tournee', 'fk_tournee_vehicule');

-- ---------------------------------------------------------------- utilisateur
-- Recherche d'un utilisateur par nom dans l'interface d'administration :
--   WHERE nom LIKE 'Dup%' [AND prenom LIKE ...]
CALL opt_creer_index('utilisateur', 'idx_utilisateur_nom', 'nom, prenom');


-- =============================================================================
--  2. Statistiques de l'optimiseur
-- =============================================================================
--  Histogrammes des colonnes filtrées sans index (rôle, états), recalculés
--  chaque semaine avec les statistiques des index. La syntaxe (MySQL ou
--  MariaDB) est choisie à l'exécution.

DROP EVENT IF EXISTS evt_rafraichir_statistiques;
DROP PROCEDURE IF EXISTS rafraichir_statistiques;
DROP PROCEDURE IF EXISTS executer_sql;

DELIMITER $$

-- Exécute une instruction écrite dans une chaîne (syntaxe propre à un SGBD).
CREATE PROCEDURE executer_sql(IN p_sql VARCHAR(1000))
BEGIN
  SET @opt_sql = p_sql;
  PREPARE opt_stmt FROM @opt_sql;
  EXECUTE opt_stmt;
  DEALLOCATE PREPARE opt_stmt;
END$$

CREATE PROCEDURE rafraichir_statistiques()
BEGIN
  -- statistiques des index de toutes les tables
  ANALYZE TABLE utilisateur, formule, abonnement, station, borne, velo, velo_electrique,
                changement_etat, vehicule, tournee, mouvement, location, transfert, facture,
                intervention, intervention_velo, signalement, signalement_velo,
                signalement_station, intervention_station;
  -- histogrammes des colonnes filtrées sans index
  IF VERSION() LIKE '%MariaDB%' THEN
    CALL executer_sql('ANALYZE TABLE utilisateur, station, borne, changement_etat PERSISTENT FOR ALL');
  ELSE
    CALL executer_sql('ANALYZE TABLE utilisateur UPDATE HISTOGRAM ON role WITH 8 BUCKETS');
    CALL executer_sql('ANALYZE TABLE station UPDATE HISTOGRAM ON etat WITH 8 BUCKETS');
    CALL executer_sql('ANALYZE TABLE borne UPDATE HISTOGRAM ON etat WITH 8 BUCKETS');
    CALL executer_sql('ANALYZE TABLE changement_etat UPDATE HISTOGRAM ON etat WITH 8 BUCKETS');
  END IF;
END$$

DELIMITER ;

-- Rafraîchissement chaque semaine, la nuit (lundi 3 h).
CREATE EVENT evt_rafraichir_statistiques
  ON SCHEDULE EVERY 1 WEEK
  STARTS (CURRENT_DATE + INTERVAL (7 - WEEKDAY(CURRENT_DATE)) DAY + INTERVAL 3 HOUR)
  COMMENT 'Recalcule les statistiques et histogrammes de l''optimiseur'
  DO CALL rafraichir_statistiques();

-- Calcul immédiat (affiche le compte rendu de chaque ANALYZE TABLE).
CALL rafraichir_statistiques();


-- =============================================================================
--  Nettoyage des outils
-- =============================================================================

DROP PROCEDURE IF EXISTS opt_creer_index;
DROP PROCEDURE IF EXISTS opt_supprimer_index;


-- =============================================================================
--  3. Configuration recommandée du serveur (my.cnf, section [mysqld])
-- =============================================================================
--    innodb_buffer_pool_size = 512M    données et index tiennent en mémoire
--    slow_query_log = ON
--    long_query_time = 0.5             journal des requêtes de plus de 0,5 s
-- =============================================================================
