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
--  Les vues optimisées sont écrites directement dans automatisation.sql : ce
--  script n'ajoute que les index et les statistiques de l'optimiseur.
--  Le script est rejouable (index créés seulement s'ils n'existent pas).
--
--  SGBD : MySQL 8.4 LTS / 9.x (testé sur MySQL 9.0) et MariaDB 10.11+ : les
--  quelques instructions propres à un seul SGBD sont choisies à l'exécution.
--
--  Contenu
--    1. Index          ciblés sur les requêtes réelles de l'application
--                      (triggers, procédures, vues, recherches de l'interface)
--    2. Vues           renvoi : les versions optimisées sont dans
--                      automatisation.sql
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
-- Factures à régler (relances, tableau de bord administrateur) :
--   WHERE date_reglement IS NULL AND montant > 0
-- Composite : la plupart des factures non réglées sont des trajets à 0 €
-- (rien à payer). Un index sur date_reglement seul les ramènerait toutes
-- (84 500 lignes sur le jeu par défaut, plus lent qu'un parcours de la
-- table) ; avec montant, seules les 2 600 factures à payer sont lues
-- (rapport de performances : 274 ms -> 18 ms). Il sert aussi les filtres
-- sur date_reglement seule. Remplace l'ancien idx_facture_reglement.
CALL opt_creer_index('facture', 'idx_facture_a_regler', 'date_reglement, montant');
CALL opt_supprimer_index('facture', 'idx_facture_reglement');

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
--  2. Vues
-- =============================================================================
--  Les vues les plus lues ou les plus lourdes sont écrites directement dans
--  leur version optimisée, dans automatisation.sql (une seule définition par
--  vue) : v_etat_actuel_velo, v_location, v_stat_trajets_par_jour,
--  v_stat_origine_destination, v_stat_indisponibilite_flotte et
--  v_stat_remplissage_horaire. Chacune y est précédée de l'explication de son
--  écriture. Leurs versions de référence, plus lentes, sont conservées dans
--  performances/sans_optimisation.sql (mesure « avant » du rapport de
--  performances, V2/rapport_performances.md).


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
