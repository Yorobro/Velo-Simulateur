-- =============================================================================
--  Réseau de vélos en libre-service — OPTIMISATION
-- =============================================================================
--  Optimisation des performances de la base velo_libre_service, sans toucher
--  au MCD ni au MLD (aucune table ni colonne ajoutée, aucune donnée stockée en
--  double).
--
--  ORDRE D'EXÉCUTION :
--    structure.sql -> peuplement_velo.py (ou donnes.sql) -> automatisation.sql
--    -> optimisation.sql
--  Le script remplace certaines vues de automatisation.sql par une version
--  plus rapide : si automatisation.sql est rejoué, rejouer ensuite ce fichier.
--  Le script est rejouable (index créés seulement s'ils n'existent pas).
--
--  SGBD : MySQL 8.4 LTS / 9.x (testé sur MySQL 9.0) et MariaDB 10.11+ : les
--  quelques instructions propres à un seul SGBD sont choisies à l'exécution.
--
--  Contenu
--    1. Index          ciblés sur les requêtes réelles de l'application
--                      (triggers, procédures, vues, recherches de l'interface)
--    2. Vues réécrites état actuel des vélos (temps réel), statistiques
--                      (durées sans appel de fonction, regroupement avant
--                      jointure, fenêtre de 30 jours), remplissage horaire
--    3. Statistiques   de l'optimiseur : histogrammes, rafraîchissement
--                      hebdomadaire automatique
--    4. Configuration  recommandée du serveur (à reporter dans my.cnf ou
--                      docker-compose.yml)
--    5. Vérification   requêtes EXPLAIN pour contrôler les plans d'exécution
--
--  Principes suivis
--    - un index n'est créé que si une requête de l'application en a besoin ;
--      chaque index est justifié par la requête qu'il sert ;
--    - un index composite dont la première colonne est une clé étrangère
--      remplace l'index créé automatiquement pour cette clé (pas d'index en
--      double, donc pas de coût d'écriture supplémentaire) ;
--    - pas d'index sur les petites tables de référence (formule, station,
--      borne : quelques dizaines de lignes, lues entièrement en mémoire) ;
--    - mouvement est la table qui grossit le plus (une ligne par trajet) :
--      c'est elle qui reçoit l'essentiel des index, en nombre limité car
--      chaque index ralentit les écritures.
--
--  Optimisations écartées
--    - partitionnement de mouvement par date : InnoDB interdit les clés
--      étrangères sur une table partitionnée ;
--    - compteurs stockés (vélos par station, état actuel dans velo) : ce
--      serait de la redondance qui modifie le MLD ; les vues indexées
--      suffisent ;
--    - index fonctionnel sur HOUR(date_heure_depart) (MySQL seulement) : la
--      statistique des heures de pointe lit de toute façon toutes les
--      locations, l'index n'éviterait aucune lecture.
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

-- Supprime un index s'il existe encore. Sert à retirer l'index automatique
-- d'une clé étrangère une fois qu'un index composite le remplace (MySQL le
-- fait parfois seul, MariaDB non).
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
--  Déjà présents grâce à structure.sql (rien à ajouter) :
--    - clés primaires ;
--    - utilisateur.email (UNIQUE) : connexion ;
--    - velo (id_station, numero_borne) (UNIQUE) : vélos d'une station,
--      borne libre, disponibilité en temps réel ;
--    - changement_etat (id_velo, date_heure_changement) (UNIQUE) : dernier
--      état d'un vélo (fn_etat_velo) ;
--    - facture.id_abonnement / facture.id_location (UNIQUE) : facture d'un
--      abonnement ou d'une location ;
--    - un index par clé étrangère (créé par InnoDB) : jointures.

-- ---------------------------------------------------------------- mouvement
-- Historique d'un vélo et dernier mouvement (trigger trg_velo_bu, fiche du
-- vélo, séjours de v_stat_remplissage_horaire) :
--   WHERE id_velo = ? ORDER BY date_heure_depart DESC LIMIT 1
-- Remplace l'index de la clé étrangère fk_mouvement_velo.
CALL opt_creer_index('mouvement', 'idx_mouvement_velo_depart', 'id_velo, date_heure_depart');
CALL opt_supprimer_index('mouvement', 'fk_mouvement_velo');

-- Mouvement en cours d'un vélo (v_velo : situation EN_LOCATION / EN_TOURNEE /
-- EN_ATELIER) et dernière arrivée d'un vélo (trigger trg_mouvement_bi) :
--   WHERE id_velo = ? AND date_heure_arrivee IS NULL
--   SELECT MAX(date_heure_arrivee) WHERE id_velo = ?   -> lu directement dans l'index
-- Les locations en cours se listent par v_velo (situation = 'EN_LOCATION'),
-- qui passe par cet index.
CALL opt_creer_index('mouvement', 'idx_mouvement_velo_arrivee', 'id_velo, date_heure_arrivee');

-- Statistiques et recherches par période (trajets par période, heures de
-- pointe, filtre de dates de l'interface) :
--   WHERE date_heure_depart BETWEEN ? AND ?
CALL opt_creer_index('mouvement', 'idx_mouvement_depart', 'date_heure_depart');

-- ---------------------------------------------------------------- abonnement
-- Abonnement valide d'un usager, vérifié à chaque emprunt (fn_abonnement_valide) :
--   WHERE id_utilisateur = ? AND ? BETWEEN date_debut AND date_fin
-- Remplace l'index de la clé étrangère fk_abonnement_utilisateur.
CALL opt_creer_index('abonnement', 'idx_abonnement_utilisateur_fin', 'id_utilisateur, date_fin');
CALL opt_supprimer_index('abonnement', 'fk_abonnement_utilisateur');

-- ---------------------------------------------------------------- facture
-- Recettes par période (statistiques, rapports) :
--   WHERE date_emission BETWEEN ? AND ?
CALL opt_creer_index('facture', 'idx_facture_emission', 'date_emission');
-- Factures impayées (relances, tableau de bord administrateur) :
--   WHERE date_reglement IS NULL
CALL opt_creer_index('facture', 'idx_facture_reglement', 'date_reglement');

-- ---------------------------------------------------------------- signalement
-- Signalements ouverts, du plus ancien au plus récent (écran des opérateurs) :
--   WHERE date_heure_cloture IS NULL ORDER BY date_heure_signalement
CALL opt_creer_index('signalement', 'idx_signalement_ouvert', 'date_heure_cloture, date_heure_signalement');

-- Signalements ouverts et non traités d'un vélo, rattachés au retrait du vélo
-- (trigger trg_intervention_velo_ai) :
--   WHERE id_velo = ? AND id_intervention_velo IS NULL
-- Remplace l'index de la clé étrangère fk_signalement_velo_velo.
CALL opt_creer_index('signalement_velo', 'idx_signalement_velo_traitement', 'id_velo, id_intervention_velo');
CALL opt_supprimer_index('signalement_velo', 'fk_signalement_velo_velo');

-- Intervention en cours sur un signalement de station (v_signalement) :
--   WHERE id_signalement_station = ? AND date_heure_fin IS NULL
-- Remplace l'index de la clé étrangère fk_intervention_station_signalement.
CALL opt_creer_index('intervention_station', 'idx_intervention_station_signalement',
                     'id_signalement_station, date_heure_fin');
CALL opt_supprimer_index('intervention_station', 'fk_intervention_station_signalement');

-- ---------------------------------------------------------------- tournee
-- Tournée en cours d'un opérateur (trigger trg_tournee_bi) :
--   WHERE id_utilisateur = ? AND date_heure_fin IS NULL
-- Remplace l'index de la clé étrangère fk_tournee_utilisateur.
CALL opt_creer_index('tournee', 'idx_tournee_operateur_fin', 'id_utilisateur, date_heure_fin');
CALL opt_supprimer_index('tournee', 'fk_tournee_utilisateur');

-- Tournée en cours d'un véhicule (trigger trg_tournee_bi, R16) et recherche
-- des tournées par véhicule (UC35) :
--   WHERE id_vehicule = ? AND date_heure_fin IS NULL
-- Remplace l'index de la clé étrangère fk_tournee_vehicule.
-- (La charge du véhicule, R15, se compte par fk_transfert_tournee : déjà indexé.)
CALL opt_creer_index('tournee', 'idx_tournee_vehicule_fin', 'id_vehicule, date_heure_fin');
CALL opt_supprimer_index('tournee', 'fk_tournee_vehicule');

-- ---------------------------------------------------------------- utilisateur
-- Recherche d'un utilisateur par nom dans l'interface d'administration :
--   WHERE nom LIKE 'Dup%' [AND prenom LIKE ...]
CALL opt_creer_index('utilisateur', 'idx_utilisateur_nom', 'nom, prenom');


-- =============================================================================
--  2. Vues réécrites (remplacent celles de automatisation.sql, mêmes colonnes)
-- =============================================================================

-- État actuel des vélos. Utilisée par v_velo et v_disponibilite_station
-- (disponibilité en temps réel), donc lue en permanence.
-- Avant : ROW_NUMBER() calculé sur TOUT l'historique des états à chaque
-- lecture (coût proportionnel à la taille de changement_etat).
-- Après : « dernier élément de chaque groupe » par GROUP BY + MAX(). Avec
-- l'index unique (id_velo, date_heure_changement), le SGBD saute d'un vélo
-- au suivant dans l'index (« skip scan » / « loose index scan ») et ne lit
-- qu'une entrée par vélo : coût proportionnel au nombre de vélos.
-- (Une sous-requête corrélée MAX() ou ORDER BY ... LIMIT 1 ne convient pas :
-- MySQL y relit tout l'historique du vélo.)
CREATE OR REPLACE VIEW v_etat_actuel_velo AS
SELECT d.id_velo,
       ce.etat,
       ce.date_heure_changement AS etat_depuis
  FROM (SELECT id_velo, MAX(date_heure_changement) AS dernier_changement
          FROM changement_etat
         GROUP BY id_velo) d
  JOIN changement_etat ce
    ON ce.id_velo = d.id_velo
   AND ce.date_heure_changement = d.dernier_changement;

-- Les vues suivantes calculaient la durée avec fn_duree_minutes() ligne par
-- ligne. Un appel de fonction stockée par ligne est coûteux ; l'expression
-- est maintenant écrite directement (même résultat).

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
       CEIL(TIMESTAMPDIFF(SECOND, m.date_heure_depart,
                          COALESCE(m.date_heure_arrivee, NOW())) / 60) AS duree_min,
       IF(m.date_heure_arrivee IS NULL,
          fn_cout_trajet(a.id_formule,
                         CEIL(TIMESTAMPDIFF(SECOND, m.date_heure_depart, NOW()) / 60),
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
       ROUND(AVG(CEIL(TIMESTAMPDIFF(SECOND, m.date_heure_depart, m.date_heure_arrivee) / 60)), 1)
         AS duree_moyenne_min
  FROM location l
  JOIN mouvement m ON m.id_mouvement = l.id_mouvement
 GROUP BY DATE(m.date_heure_depart);

-- Trajets origine -> destination.
-- Avant : jointure aux deux stations pour CHAQUE trajet, puis regroupement
-- sur les noms.
-- Après : regroupement d'abord sur les identifiants, puis jointure aux
-- stations pour les seuls couples obtenus (quelques dizaines de lignes).
CREATE OR REPLACE VIEW v_stat_origine_destination AS
SELECT RANK() OVER (ORDER BY t.nb_trajets DESC) AS rang,
       t.id_station_depart,
       sd.nom AS station_depart,
       t.id_station_arrivee,
       sa.nom AS station_arrivee,
       t.nb_trajets,
       t.duree_moyenne_min
  FROM (SELECT m.id_station_depart,
               m.id_station_arrivee,
               COUNT(*) AS nb_trajets,
               ROUND(AVG(CEIL(TIMESTAMPDIFF(SECOND, m.date_heure_depart, m.date_heure_arrivee) / 60)), 1)
                 AS duree_moyenne_min
          FROM location l
          JOIN mouvement m ON m.id_mouvement = l.id_mouvement
         WHERE m.id_station_arrivee IS NOT NULL
         GROUP BY m.id_station_depart, m.id_station_arrivee) t
  JOIN station sd ON sd.id_station = t.id_station_depart
  JOIN station sa ON sa.id_station = t.id_station_arrivee;

-- Indisponibilité de la flotte (situation actuelle et sur 30 jours).
-- Avant : LEAD() calculé sur tout l'historique des états de tous les vélos.
-- Après : seuls les changements des 30 derniers jours, plus l'état de
-- chaque vélo au début de la fenêtre (dernier changement antérieur, trouvé
-- par « skip scan » de l'index unique). Même résultat.
CREATE OR REPLACE VIEW v_stat_indisponibilite_flotte AS
WITH changements AS (
  -- changements survenus dans la fenêtre de 30 jours
  SELECT id_velo, etat, date_heure_changement AS debut, id_changement
    FROM changement_etat
   WHERE date_heure_changement >= NOW() - INTERVAL 30 DAY
  UNION ALL
  -- état de chaque vélo au début de la fenêtre
  SELECT ce.id_velo, ce.etat, NOW() - INTERVAL 30 DAY, ce.id_changement
    FROM (SELECT id_velo, MAX(date_heure_changement) AS dernier_changement
            FROM changement_etat
           WHERE date_heure_changement < NOW() - INTERVAL 30 DAY
           GROUP BY id_velo) d
    JOIN changement_etat ce
      ON ce.id_velo = d.id_velo AND ce.date_heure_changement = d.dernier_changement
), periodes AS (
  SELECT id_velo, etat,
         TIMESTAMPDIFF(MINUTE, debut,
                       COALESCE(LEAD(debut) OVER (PARTITION BY id_velo ORDER BY debut, id_changement),
                                NOW())) AS duree
    FROM changements
), minutes_30j AS (
  SELECT id_velo,
         SUM(IF(etat = 'DEFECTUEUX', duree, 0)) AS min_defectueux,
         SUM(IF(etat <> 'REFORME', duree, 0))   AS min_flotte
    FROM periodes
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

-- Remplissage des stations par tranche horaire (30 derniers jours).
-- Avant : pour chaque station et chaque instant (30 j x 24 h), un comptage
-- parmi TOUS les séjours de l'historique, et une sous-requête par mouvement
-- pour trouver le premier départ de chaque vélo.
-- Après :
--   - seuls les séjours qui touchent la fenêtre de 30 jours sont gardés ;
--   - le premier départ de chaque vélo est un MIN() lu dans l'index
--     (id_velo, date_heure_depart) ;
--   - le comptage est une seule jointure séjours x instants groupée, au lieu
--     d'une sous-requête par station et par instant (le coût ne dépend plus
--     du nombre de stations).
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
     AND (fin IS NULL OR fin > CURDATE() - INTERVAL 29 DAY)
  UNION ALL
  -- de la mise en service au premier départ
  SELECT m.id_station_depart, v.date_mise_service, m.date_heure_depart
    FROM (SELECT id_velo, MIN(date_heure_depart) AS premier_depart
            FROM mouvement GROUP BY id_velo) p
    JOIN mouvement m ON m.id_velo = p.id_velo AND m.date_heure_depart = p.premier_depart
    JOIN velo v      ON v.id_velo = p.id_velo
   WHERE p.premier_depart > CURDATE() - INTERVAL 29 DAY
  UNION ALL
  -- vélos qui n'ont jamais bougé
  SELECT v.id_station, v.date_mise_service, NULL
    FROM velo v
   WHERE v.id_station IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM mouvement m WHERE m.id_velo = v.id_velo)
), presences AS (
  SELECT se.id_station, i.instant, COUNT(*) AS nb_velos
    FROM sejours se
    JOIN instants i ON i.instant >= se.debut AND (se.fin IS NULL OR i.instant < se.fin)
   GROUP BY se.id_station, i.instant
)
SELECT s.id_station,
       s.nom,
       i.heure,
       ROUND(AVG(COALESCE(p.nb_velos, 0)), 2) AS velos_moyens,
       ROUND(100 * AVG(COALESCE(p.nb_velos, 0)) / NULLIF(c.bornes_en_service, 0), 1)
         AS taux_remplissage_pct
  FROM station s
  CROSS JOIN instants i
  JOIN (SELECT id_station, SUM(etat = 'EN_SERVICE') AS bornes_en_service
          FROM borne GROUP BY id_station) c ON c.id_station = s.id_station
  LEFT JOIN presences p ON p.id_station = s.id_station AND p.instant = i.instant
 WHERE s.etat = 'EN_SERVICE'
 GROUP BY s.id_station, s.nom, i.heure, c.bornes_en_service;


-- =============================================================================
--  3. Statistiques de l'optimiseur
-- =============================================================================
--  InnoDB recalcule seul les statistiques des index quand 10 % d'une table a
--  changé. En plus :
--    - les histogrammes décrivent la répartition des colonnes non indexées
--      souvent filtrées (rôle, états) et aident l'optimiseur
--      à choisir l'ordre des jointures ; ils ne se mettent pas à jour seuls ;
--    - rafraichir_statistiques() recalcule tout et est appelée chaque semaine
--      par un événement planifié.
--  Syntaxe différente selon le SGBD, choisie à l'exécution :
--    MySQL   : ANALYZE TABLE t UPDATE HISTOGRAM ON col
--    MariaDB : ANALYZE TABLE t PERSISTENT FOR ALL (statistiques indépendantes
--              du moteur, histogrammes compris)

DROP EVENT IF EXISTS evt_rafraichir_statistiques;
DROP PROCEDURE IF EXISTS rafraichir_statistiques;
DROP PROCEDURE IF EXISTS executer_sql;

DELIMITER $$

-- Exécute une instruction écrite dans une chaîne. Une syntaxe propre à un
-- seul SGBD ne peut pas figurer en clair dans une procédure (l'autre SGBD
-- refuserait de la créer) : elle passe donc par ici.
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
-- Nécessite le planificateur d'événements : actif par défaut sous MySQL,
-- à activer sous MariaDB (event_scheduler = ON, voir § 4).
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
--  4. Configuration recommandée du serveur
-- =============================================================================
--  Ces réglages concernent le serveur entier : ils se placent dans le
--  fichier de configuration (my.cnf, section [mysqld]) ou dans
--  docker-compose.yml (command: --option=valeur), pas dans ce script.
--
--    innodb_buffer_pool_size = 512M
--        Mémoire de cache des données et des index. Viser une taille
--        supérieure à la base (données + index) pour tout servir depuis la
--        mémoire ; sur un serveur dédié, 50 à 70 % de la RAM.
--    innodb_flush_log_at_trx_commit = 1
--        Garder 1 (valeur par défaut) : chaque transaction validée est écrite
--        sur disque. Plus lent que 2, mais aucune location ni facture perdue
--        en cas de panne.
--    slow_query_log = ON
--    long_query_time = 0.5
--        Journalise les requêtes de plus de 0,5 s : base du rapport
--        d'analyse des performances.
--    event_scheduler = ON
--        Nécessaire sous MariaDB pour l'événement evt_rafraichir_statistiques
--        (déjà actif par défaut sous MySQL 8 et 9).
--    max_connections = 200
--        À ajuster au nombre d'utilisateurs simultanés de l'interface.
--
--  Côté application : ouvrir une connexion persistante (pool) plutôt qu'une
--  connexion par page, utiliser des requêtes préparées (sécurité et plan
--  réutilisé), et paginer les listes (LIMIT ... OFFSET ...).


-- =============================================================================
--  5. Vérification des plans d'exécution
-- =============================================================================
--  Exemples à exécuter pour contrôler qu'un index est utilisé (colonne key
--  de EXPLAIN) et mesurer le temps réel (EXPLAIN ANALYZE, MySQL 8.0.18+ ;
--  ANALYZE sous MariaDB) :
--
--    EXPLAIN SELECT * FROM mouvement WHERE id_velo = 7
--             ORDER BY date_heure_depart DESC LIMIT 20;
--        -> key = idx_mouvement_velo_depart, sans tri (« Backward index scan »)
--
--    EXPLAIN SELECT MAX(date_heure_arrivee) FROM mouvement WHERE id_velo = 7;
--        -> « Select tables optimized away » : réponse lue dans l'index
--
--    EXPLAIN SELECT fn_abonnement_valide(15, CURDATE());
--    EXPLAIN SELECT * FROM v_velo WHERE situation = 'EN_LOCATION';
--    EXPLAIN SELECT * FROM signalement WHERE date_heure_cloture IS NULL
--             ORDER BY date_heure_signalement;
--        -> key = idx_signalement_ouvert
--
--    EXPLAIN ANALYZE SELECT * FROM v_disponibilite_station;
--        -> « Covering index skip scan for grouping » sur changement_etat
--
--  Statistiques sur une période choisie dans l'interface : filtrer sur la
--  colonne elle-même (sargable, utilise idx_mouvement_depart), jamais sur
--  une fonction de la colonne :
--    oui : WHERE m.date_heure_depart >= '2026-10-01' AND m.date_heure_depart < '2026-11-01'
--    non : WHERE DATE(m.date_heure_depart) BETWEEN ... (parcours complet)
--
--  Index présents :
--    SELECT table_name, index_name, GROUP_CONCAT(column_name ORDER BY seq_in_index)
--      FROM information_schema.statistics
--     WHERE table_schema = 'velo_libre_service'
--     GROUP BY table_name, index_name;
-- =============================================================================
