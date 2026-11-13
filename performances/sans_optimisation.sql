-- =============================================================================
--  Réseau de vélos en libre-service — RETOUR À L'ÉTAT « SANS OPTIMISATION »
-- =============================================================================
--  Sert uniquement à la mesure « avant » du rapport de performances
--  (V2/rapport_performances.md). Il annule ce qu'ajoute optimisation.sql :
--    - les 12 index idx_* (et remet les index de clés étrangères qu'ils
--      remplaçaient) ;
--    - les histogrammes de l'optimiseur ;
--    - l'événement de rafraîchissement des statistiques.
--  Les vues d'origine sont remises en rejouant automatisation.sql AVANT ce
--  script. Aucune donnée n'est modifiée.
--
--    mysql velo_libre_service < data/automatisation.sql
--    mysql velo_libre_service < performances/sans_optimisation.sql
--    ... mesures « avant » ...
--    mysql velo_libre_service < data/optimisation.sql     (retour à l'état normal)
-- =============================================================================

USE velo_libre_service;

DROP PROCEDURE IF EXISTS perf_creer_index;
DROP PROCEDURE IF EXISTS perf_supprimer_index;

DELIMITER $$

CREATE PROCEDURE perf_creer_index(IN p_table VARCHAR(64), IN p_index VARCHAR(64),
                                  IN p_colonnes VARCHAR(255))
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.statistics
                  WHERE table_schema = DATABASE() AND table_name = p_table
                    AND index_name = p_index) THEN
    SET @perf_sql = CONCAT('CREATE INDEX ', p_index, ' ON ', p_table, ' (', p_colonnes, ')');
    PREPARE perf_stmt FROM @perf_sql;
    EXECUTE perf_stmt;
    DEALLOCATE PREPARE perf_stmt;
  END IF;
END$$

CREATE PROCEDURE perf_supprimer_index(IN p_table VARCHAR(64), IN p_index VARCHAR(64))
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.statistics
              WHERE table_schema = DATABASE() AND table_name = p_table
                AND index_name = p_index) THEN
    SET @perf_sql = CONCAT('DROP INDEX ', p_index, ' ON ', p_table);
    PREPARE perf_stmt FROM @perf_sql;
    EXECUTE perf_stmt;
    DEALLOCATE PREPARE perf_stmt;
  END IF;
END$$

DELIMITER ;

-- 1. Index des clés étrangères tels que les crée InnoDB (une clé étrangère
--    doit garder un index : on les remet avant de retirer les composites).
CALL perf_creer_index('mouvement', 'fk_mouvement_velo', 'id_velo');
CALL perf_creer_index('abonnement', 'fk_abonnement_utilisateur', 'id_utilisateur');
CALL perf_creer_index('signalement_velo', 'fk_signalement_velo_velo', 'id_velo');
CALL perf_creer_index('intervention_station', 'fk_intervention_station_signalement', 'id_signalement_station');
CALL perf_creer_index('tournee', 'fk_tournee_utilisateur', 'id_utilisateur');
CALL perf_creer_index('tournee', 'fk_tournee_vehicule', 'id_vehicule');

-- 2. Index ajoutés par optimisation.sql
CALL perf_supprimer_index('mouvement', 'idx_mouvement_velo_depart');
CALL perf_supprimer_index('mouvement', 'idx_mouvement_velo_arrivee');
CALL perf_supprimer_index('mouvement', 'idx_mouvement_depart');
CALL perf_supprimer_index('abonnement', 'idx_abonnement_utilisateur_fin');
CALL perf_supprimer_index('facture', 'idx_facture_emission');
CALL perf_supprimer_index('facture', 'idx_facture_reglement');   -- ancienne version
CALL perf_supprimer_index('facture', 'idx_facture_a_regler');
CALL perf_supprimer_index('signalement', 'idx_signalement_ouvert');
CALL perf_supprimer_index('signalement_velo', 'idx_signalement_velo_traitement');
CALL perf_supprimer_index('intervention_station', 'idx_intervention_station_signalement');
CALL perf_supprimer_index('tournee', 'idx_tournee_operateur_fin');
CALL perf_supprimer_index('tournee', 'idx_tournee_vehicule_fin');
CALL perf_supprimer_index('utilisateur', 'idx_utilisateur_nom');

-- 3. Histogrammes et rafraîchissement planifié
ANALYZE TABLE utilisateur DROP HISTOGRAM ON role;
ANALYZE TABLE station DROP HISTOGRAM ON etat;
ANALYZE TABLE borne DROP HISTOGRAM ON etat;
ANALYZE TABLE changement_etat DROP HISTOGRAM ON etat;
DROP EVENT IF EXISTS evt_rafraichir_statistiques;
DROP PROCEDURE IF EXISTS rafraichir_statistiques;
DROP PROCEDURE IF EXISTS executer_sql;

-- 4. Statistiques des index à jour (les deux états se comparent à statistiques égales)
ANALYZE TABLE utilisateur, formule, abonnement, station, borne, velo, velo_electrique,
              changement_etat, vehicule, tournee, mouvement, location, transfert, facture,
              intervention, intervention_velo, signalement, signalement_velo,
              signalement_station, intervention_station;

DROP PROCEDURE perf_creer_index;
DROP PROCEDURE perf_supprimer_index;
