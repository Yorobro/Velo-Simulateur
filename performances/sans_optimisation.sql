-- =============================================================================
--  Réseau de vélos en libre-service — RETOUR À L'ÉTAT « SANS OPTIMISATION »
-- =============================================================================
--  Sert uniquement à la mesure « avant » du rapport de performances
--  (V2/rapport_performances.md). Il annule ce qu'ajoute optimisation.sql :
--    - les 12 index idx_* (et remet les index de clés étrangères qu'ils
--      remplaçaient) ;
--    - les histogrammes de l'optimiseur ;
--    - l'événement de rafraîchissement des statistiques.
--    - les vues optimisées de automatisation.sql (remplacées par leurs
--      versions de référence, plus lentes, conservées ici).
--  Aucune donnée n'est modifiée.
--
--    mysql velo_libre_service < performances/sans_optimisation.sql
--    ... mesures « avant » ...
--    mysql velo_libre_service < data/automatisation.sql   (retour à l'état normal :
--    mysql velo_libre_service < data/optimisation.sql      vues optimisées, puis index)
-- =============================================================================

USE velo_libre_service;

-- 0. Vues de référence (versions lentes d'origine), à la place des versions
--    optimisées de automatisation.sql
CREATE OR REPLACE VIEW v_etat_actuel_velo AS
SELECT id_velo, etat, date_heure_changement AS etat_depuis
  FROM (SELECT id_velo, etat, date_heure_changement,
               ROW_NUMBER() OVER (PARTITION BY id_velo
                                  ORDER BY date_heure_changement DESC, id_changement DESC) AS rang
          FROM changement_etat) e
 WHERE rang = 1;

CREATE OR REPLACE VIEW v_location AS
SELECT l.id_mouvement AS id_location,
       a.id_utilisateur,
       CONCAT(u.prenom, ' ', u.nom) AS usager,
       l.id_abonnement,
       f.libelle AS formule,
       m.id_velo,
       IF(ve.id_velo IS NULL, 'MECANIQUE', 'ELECTRIQUE') AS type_velo,
       l.avec_casque,
       m.id_station_depart,
       sd.nom AS station_depart,
       m.date_heure_depart,
       m.id_station_arrivee,
       sa.nom AS station_arrivee,
       m.date_heure_arrivee,
       IF(m.date_heure_arrivee IS NULL, 'EN_COURS', 'TERMINEE') AS statut,
       fn_duree_minutes(m.date_heure_depart, COALESCE(m.date_heure_arrivee, NOW())) AS duree_min,
       IF(m.date_heure_arrivee IS NULL,
          fn_cout_trajet(a.id_formule, fn_duree_minutes(m.date_heure_depart, NOW()),
                         ve.id_velo IS NOT NULL, l.avec_casque),
          COALESCE(fa.montant, 0)) AS montant,
       fa.id_facture,
       fa.date_reglement
  FROM location l
  JOIN mouvement m        ON m.id_mouvement = l.id_mouvement
  JOIN abonnement a       ON a.id_abonnement = l.id_abonnement
  JOIN formule f          ON f.id_formule = a.id_formule
  JOIN utilisateur u      ON u.id_utilisateur = a.id_utilisateur
  LEFT JOIN velo_electrique ve ON ve.id_velo = m.id_velo
  LEFT JOIN station sd    ON sd.id_station = m.id_station_depart
  LEFT JOIN station sa    ON sa.id_station = m.id_station_arrivee
  LEFT JOIN facture fa    ON fa.id_location = l.id_mouvement;

CREATE OR REPLACE VIEW v_stat_trajets_par_jour AS
SELECT DATE(m.date_heure_depart) AS jour,
       COUNT(*) AS nb_trajets,
       ROUND(AVG(fn_duree_minutes(m.date_heure_depart, m.date_heure_arrivee)), 1) AS duree_moyenne_min
  FROM location l
  JOIN mouvement m ON m.id_mouvement = l.id_mouvement
 GROUP BY DATE(m.date_heure_depart);

CREATE OR REPLACE VIEW v_stat_origine_destination AS
SELECT RANK() OVER (ORDER BY COUNT(*) DESC) AS rang,
       m.id_station_depart,
       sd.nom AS station_depart,
       m.id_station_arrivee,
       sa.nom AS station_arrivee,
       COUNT(*) AS nb_trajets,
       ROUND(AVG(fn_duree_minutes(m.date_heure_depart, m.date_heure_arrivee)), 1) AS duree_moyenne_min
  FROM location l
  JOIN mouvement m  ON m.id_mouvement = l.id_mouvement
  JOIN station sd   ON sd.id_station = m.id_station_depart
  JOIN station sa   ON sa.id_station = m.id_station_arrivee
 GROUP BY m.id_station_depart, sd.nom, m.id_station_arrivee, sa.nom;

CREATE OR REPLACE VIEW v_stat_indisponibilite_flotte AS
WITH periodes AS (
  SELECT id_velo, etat, date_heure_changement AS debut,
         COALESCE(LEAD(date_heure_changement) OVER (PARTITION BY id_velo
                                                    ORDER BY date_heure_changement, id_changement),
                  NOW()) AS fin
    FROM changement_etat
), minutes_30j AS (
  SELECT id_velo,
         SUM(IF(etat = 'DEFECTUEUX', duree, 0)) AS min_defectueux,
         SUM(IF(etat <> 'REFORME', duree, 0))   AS min_flotte
    FROM (SELECT id_velo, etat,
                 GREATEST(0, TIMESTAMPDIFF(MINUTE, GREATEST(debut, NOW() - INTERVAL 30 DAY),
                                           LEAST(fin, NOW()))) AS duree
            FROM periodes) p
   GROUP BY id_velo
)
SELECT COALESCE(v.type_velo, 'TOUS') AS type_velo,
       SUM(v.etat <> 'REFORME') AS velos_en_flotte,
       SUM(v.etat = 'EN_SERVICE') AS en_service,
       SUM(v.etat = 'DEFECTUEUX') AS defectueux,
       SUM(v.etat = 'REFORME') AS reformes,
       ROUND(100 * SUM(v.etat = 'DEFECTUEUX') / NULLIF(SUM(v.etat <> 'REFORME'), 0), 1)
         AS taux_indisponibilite_actuel_pct,
       ROUND(100 * SUM(m.min_defectueux) / NULLIF(SUM(m.min_flotte), 0), 2)
         AS taux_indisponibilite_30j_pct
  FROM v_velo v
  LEFT JOIN minutes_30j m ON m.id_velo = v.id_velo
 GROUP BY v.type_velo WITH ROLLUP;

CREATE OR REPLACE VIEW v_stat_remplissage_horaire AS
WITH RECURSIVE jours (jour) AS (
  SELECT CURDATE() - INTERVAL 29 DAY
  UNION ALL
  SELECT jour + INTERVAL 1 DAY FROM jours WHERE jour < CURDATE()
), heures (heure) AS (
  SELECT 0
  UNION ALL
  SELECT heure + 1 FROM heures WHERE heure < 23
), instants AS (
  SELECT TIMESTAMP(j.jour) + INTERVAL h.heure HOUR + INTERVAL 30 MINUTE AS instant, h.heure
    FROM jours j CROSS JOIN heures h
   WHERE TIMESTAMP(j.jour) + INTERVAL h.heure HOUR + INTERVAL 30 MINUTE <= NOW()
), sejours AS (
  -- de chaque arrivée sur une borne au départ suivant du même vélo
  SELECT id_station, debut, fin
    FROM (SELECT m.id_station_arrivee AS id_station,
                 m.date_heure_arrivee AS debut,
                 LEAD(m.date_heure_depart) OVER (PARTITION BY m.id_velo
                                                 ORDER BY m.date_heure_depart, m.id_mouvement) AS fin
            FROM mouvement m) a
   WHERE id_station IS NOT NULL
  UNION ALL
  -- de la mise en service au premier départ
  SELECT m.id_station_depart, v.date_mise_service, m.date_heure_depart
    FROM mouvement m
    JOIN velo v ON v.id_velo = m.id_velo
   WHERE NOT EXISTS (SELECT 1 FROM mouvement p
                      WHERE p.id_velo = m.id_velo
                        AND (p.date_heure_depart < m.date_heure_depart
                             OR (p.date_heure_depart = m.date_heure_depart
                                 AND p.id_mouvement < m.id_mouvement)))
  UNION ALL
  -- vélos qui n'ont jamais bougé
  SELECT v.id_station, v.date_mise_service, NULL
    FROM velo v
   WHERE v.id_station IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM mouvement m WHERE m.id_velo = v.id_velo)
), occupation AS (
  SELECT s.id_station, i.heure,
         (SELECT COUNT(*) FROM sejours se
           WHERE se.id_station = s.id_station
             AND se.debut <= i.instant
             AND (se.fin IS NULL OR se.fin > i.instant)) AS nb_velos
    FROM instants i
   CROSS JOIN station s
   WHERE s.etat = 'EN_SERVICE'
)
SELECT o.id_station,
       s.nom,
       o.heure,
       ROUND(AVG(o.nb_velos), 2) AS velos_moyens,
       ROUND(100 * AVG(o.nb_velos) / NULLIF(c.bornes_en_service, 0), 1) AS taux_remplissage_pct
  FROM occupation o
  JOIN station s ON s.id_station = o.id_station
  JOIN (SELECT id_station, SUM(etat = 'EN_SERVICE') AS bornes_en_service
          FROM borne GROUP BY id_station) c ON c.id_station = o.id_station
 GROUP BY o.id_station, s.nom, o.heure, c.bornes_en_service;


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
