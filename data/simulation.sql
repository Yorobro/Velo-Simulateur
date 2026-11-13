-- =============================================================================
--  Réseau de vélos en libre-service — SIMULATION D'ACTIVITÉ (événements)
-- =============================================================================
--  Événements planifiés (Event Scheduler) qui font vivre la base en temps
--  réel : emprunts et restitutions, recharge des vélos électriques,
--  signalements, maintenance, tournées de régulation, règlement des
--  factures, abonnements et inscriptions.
--
--  Toutes les écritures passent par les procédures de automatisation.sql :
--  les triggers (règles R1 à R22) s'appliquent donc comme pour un vrai
--  usager ou opérateur. Une action refusée par une règle (vélo pris entre-
--  temps, station pleine, usager déjà en location…) est simplement ignorée.
--  Aucune table ni colonne n'est ajoutée.
--
--  Les comptes de démonstration (admin@, regulation@, maintenance@ et
--  usager@velo.example.org) ne sont jamais utilisés par la simulation :
--  les tests faits à la main dans l'interface ne sont pas perturbés.
--
--  ORDRE D'EXÉCUTION :
--    structure.sql -> peuplement_velo.py -> automatisation.sql
--    -> optimisation.sql -> simulation.sql
--  Le script est rejouable : il supprime puis recrée tous ses objets.
--
--  Pilotage
--    CALL sim_arreter();     suspend tous les événements de simulation
--    CALL sim_demarrer();    les relance
--    CALL sim_etat();        état et dernière exécution de chaque événement
--    SELECT * FROM v_simulation_activite;   activité de la dernière heure
--  Volume : sim_facteur_demo() (mode démo, 5 par défaut ; 1 = volume
--  réaliste de l'historique) x 900 trajets par jour, modulé par l'heure, le
--  jour de la semaine et la saison comme dans peuplement_velo.py.
--
--  Un trajet simulé est un vrai trajet : l'emprunt retire le vélo de sa
--  borne (il n'est plus disponible, la borne se libère), la restitution le
--  pose sur une borne libre de la station d'arrivée et crée la facture.
--  L'usager part le plus souvent de sa station habituelle à cette heure ;
--  la station d'arrivée est à une distance cohérente avec la durée du trajet.
--
--  Prérequis : planificateur d'événements actif (event_scheduler = ON,
--  valeur par défaut de MySQL 8 et 9).
--
--  Événements
--    evt_sim_emprunts         1 min   emprunts (pointes le matin et le soir)
--    evt_sim_restitutions     1 min   restitutions, batterie consommée
--    evt_sim_recharge         5 min   recharge des vélos électriques sur borne
--    evt_sim_signalements    10 min   signalements de vélos et de stations
--    evt_sim_maintenance     15 min   retraits, réparations, réformes, travaux (7 h - 20 h)
--    evt_sim_regulation      20 min   tournées de rééquilibrage (6 h - 22 h)
--    evt_sim_factures         1 h     règlement des factures récentes
--    evt_sim_inscriptions     1 h     nouveaux usagers et tickets journée (7 h - 22 h)
--    evt_sim_abonnements      1 jour  renouvellements et changements de formule (0 h 05)
-- =============================================================================

SET NAMES utf8mb4;
USE velo_libre_service;


-- =============================================================================
--  0. Nettoyage (le script est rejouable)
-- =============================================================================

DROP EVENT IF EXISTS evt_sim_emprunts;
DROP EVENT IF EXISTS evt_sim_restitutions;
DROP EVENT IF EXISTS evt_sim_recharge;
DROP EVENT IF EXISTS evt_sim_signalements;
DROP EVENT IF EXISTS evt_sim_maintenance;
DROP EVENT IF EXISTS evt_sim_regulation;
DROP EVENT IF EXISTS evt_sim_factures;
DROP EVENT IF EXISTS evt_sim_inscriptions;
DROP EVENT IF EXISTS evt_sim_abonnements;

DROP VIEW IF EXISTS v_simulation_activite;

DROP PROCEDURE IF EXISTS sim_emprunts;
DROP PROCEDURE IF EXISTS sim_restitutions;
DROP PROCEDURE IF EXISTS sim_recharge;
DROP PROCEDURE IF EXISTS sim_signalements;
DROP PROCEDURE IF EXISTS sim_maintenance;
DROP PROCEDURE IF EXISTS sim_regulation;
DROP PROCEDURE IF EXISTS sim_factures;
DROP PROCEDURE IF EXISTS sim_inscriptions;
DROP PROCEDURE IF EXISTS sim_abonnements;
DROP PROCEDURE IF EXISTS sim_demarrer;
DROP PROCEDURE IF EXISTS sim_arreter;
DROP PROCEDURE IF EXISTS sim_basculer;
DROP PROCEDURE IF EXISTS sim_etat;

DROP FUNCTION IF EXISTS sim_facteur_demo;
DROP FUNCTION IF EXISTS sim_trajets_par_jour;
DROP FUNCTION IF EXISTS sim_velo_disponible;
DROP FUNCTION IF EXISTS sim_station_habituelle;
DROP FUNCTION IF EXISTS sim_minutes_trajet;
DROP FUNCTION IF EXISTS sim_taux_emprunts;
DROP FUNCTION IF EXISTS sim_compte_demo;
DROP FUNCTION IF EXISTS sim_duree_trajet;
DROP FUNCTION IF EXISTS sim_texte_panne;
DROP FUNCTION IF EXISTS sim_texte_fausse_alerte;
DROP FUNCTION IF EXISTS sim_est_fausse_alerte;
DROP FUNCTION IF EXISTS sim_texte_panne_station;
DROP FUNCTION IF EXISTS sim_station_destination;
DROP FUNCTION IF EXISTS sim_operateur;


DELIMITER $$

-- =============================================================================
--  1. Paramètres et fonctions utilitaires
-- =============================================================================

-- Mode démo : multiplie le volume d'activité pour que le réseau bouge à
-- l'œil nu (5 = environ 3 600 trajets par jour en novembre, une
-- cinquantaine de vélos en circulation en journée, plus d'une centaine aux
-- heures de pointe). 1 = volume réaliste, celui de l'historique généré.
-- Modifier la valeur puis rejouer ce script.
CREATE FUNCTION sim_facteur_demo()
RETURNS DECIMAL(4,1)
DETERMINISTIC NO SQL
BEGIN
  RETURN 5;
END$$

-- Trajets moyens par jour, avant modulation par l'heure, le jour et la saison.
CREATE FUNCTION sim_trajets_par_jour()
RETURNS INT
DETERMINISTIC NO SQL
BEGIN
  RETURN ROUND(900 * sim_facteur_demo());
END$$

-- Emprunts attendus par minute à un instant donné : profil horaire de la
-- semaine ou du week-end, jour de la semaine et saison (mêmes poids que
-- peuplement_velo.py).
CREATE FUNCTION sim_taux_emprunts(p_instant DATETIME)
RETURNS DOUBLE
DETERMINISTIC NO SQL
BEGIN
  DECLARE v_jour INT DEFAULT WEEKDAY(p_instant);
  DECLARE v_h INT DEFAULT HOUR(p_instant) + 1;
  DECLARE v_poids, v_somme, v_facteur DOUBLE;
  IF v_jour < 5 THEN
    SET v_poids = ELT(v_h, 0.2, 0.1, 0.05, 0.05, 0.1, 0.4, 1.5, 4.5, 6.5, 3.5, 2.0, 2.4,
                           3.6, 3.0, 2.2, 2.4, 3.4, 5.8, 6.2, 3.6, 2.2, 1.4, 0.9, 0.5);
    SET v_somme = 56.5, v_facteur = 1.0;
  ELSE
    SET v_poids = ELT(v_h, 0.4, 0.3, 0.2, 0.1, 0.1, 0.2, 0.4, 0.8, 1.5, 2.4, 3.4, 3.8,
                           3.8, 3.6, 4.0, 4.4, 4.4, 4.0, 3.4, 2.6, 1.8, 1.2, 0.9, 0.6);
    SET v_somme = 48.3, v_facteur = IF(v_jour = 5, 0.85, 0.7);
  END IF;
  SET v_facteur = v_facteur * ELT(MONTH(p_instant), 0.55, 0.6, 0.8, 0.95, 1.1, 1.25,
                                                     1.15, 0.95, 1.2, 1.05, 0.8, 0.6);
  RETURN sim_trajets_par_jour() * v_facteur * v_poids / v_somme / 60;
END$$

-- Comptes de démonstration : jamais utilisés par la simulation.
CREATE FUNCTION sim_compte_demo(p_email VARCHAR(254))
RETURNS BOOLEAN
DETERMINISTIC NO SQL
BEGIN
  RETURN p_email IN ('admin@velo.example.org', 'regulation@velo.example.org',
                     'maintenance@velo.example.org', 'usager@velo.example.org');
END$$

-- Durée prévue d'un trajet en minutes, tirée une fois pour toutes d'après
-- le numéro de la location : le plus souvent 3 à 17 min (trajet utilitaire),
-- une fois sur six une balade de 10 à 35 min de plus, une fois sur quarante
-- plus d'une heure. Moyenne : environ 15 min.
CREATE FUNCTION sim_duree_trajet(p_location INT UNSIGNED)
RETURNS INT
DETERMINISTIC NO SQL
BEGIN
  RETURN 3 + MOD(p_location * 37, 15)
           + IF(MOD(p_location, 6) = 0, 10 + MOD(p_location * 13, 26), 0)
           + IF(MOD(p_location, 40) = 7, 60 + MOD(p_location, 90), 0);
END$$

-- Description d'une vraie panne de vélo (les dernières : vélos électriques).
CREATE FUNCTION sim_texte_panne(p_electrique BOOLEAN)
RETURNS VARCHAR(200)
NOT DETERMINISTIC NO SQL
BEGIN
  RETURN ELT(1 + FLOOR(RAND() * IF(p_electrique, 16, 12)),
             'Le frein arrière ne freine presque plus.',
             'Le frein avant grince et freine mal.',
             'La chaîne saute quand on pédale.',
             'Pneu avant crevé.',
             'Pneu arrière à plat.',
             'La selle est cassée et ne se règle plus.',
             'L''éclairage avant ne s''allume pas.',
             'Le guidon est desserré.',
             'Les vitesses ne passent plus.',
             'La pédale gauche est cassée.',
             'La béquille ne tient plus le vélo.',
             'Le feu arrière ne fonctionne plus.',
             'La batterie se vide en quelques minutes.',
             'L''assistance électrique se coupe en route.',
             'L''écran du vélo reste éteint.',
             'Le vélo électrique ne se recharge pas sur la borne.');
END$$

-- Fausses alertes : le signalement est clos sans intervention.
-- (Garder la même liste dans sim_est_fausse_alerte.)
CREATE FUNCTION sim_texte_fausse_alerte()
RETURNS VARCHAR(200)
NOT DETERMINISTIC NO SQL
BEGIN
  RETURN ELT(1 + FLOOR(RAND() * 6),
             'Bruit suspect quand on pédale.',
             'La selle était mouillée et glissante.',
             'Le vélo semblait mal accroché à la borne.',
             'La sonnette ne sonne pas fort.',
             'Le vélo est sale.',
             'Les pneus semblent un peu dégonflés.');
END$$

CREATE FUNCTION sim_est_fausse_alerte(p_description VARCHAR(500))
RETURNS BOOLEAN
DETERMINISTIC NO SQL
BEGIN
  RETURN p_description IN ('Bruit suspect quand on pédale.',
                           'La selle était mouillée et glissante.',
                           'Le vélo semblait mal accroché à la borne.',
                           'La sonnette ne sonne pas fort.',
                           'Le vélo est sale.',
                           'Les pneus semblent un peu dégonflés.',
                           -- fausses alertes de peuplement_velo.py
                           'Le panier est un peu tordu.', 'La selle est trop haute.',
                           'Un autocollant est décollé sur le cadre.',
                           'Le vélo électrique semble moins puissant que d''habitude.');
END$$

CREATE FUNCTION sim_texte_panne_station(p_borne SMALLINT UNSIGNED)
RETURNS VARCHAR(200)
NOT DETERMINISTIC NO SQL
BEGIN
  RETURN ELT(1 + FLOOR(RAND() * 7),
             CONCAT('La borne n°', p_borne, ' ne libère pas le vélo.'),
             CONCAT('La borne n°', p_borne, ' ne détecte pas le vélo restitué.'),
             CONCAT('La borne n°', p_borne, ' affiche une erreur.'),
             'L''écran de la station reste éteint.',
             'Le paiement par carte est impossible à la station.',
             'L''éclairage de la station est en panne.',
             'La station est couverte de tags.');
END$$

-- Temps de trajet estimé en minutes pour une distance à vol d'oiseau (en
-- mètres) : 13 km/h en vélo mécanique, 17 km/h en électrique, détours de
-- la route (x 1,3) et 2 min pour décrocher puis raccrocher le vélo (mêmes
-- hypothèses que peuplement_velo.py).
CREATE FUNCTION sim_minutes_trajet(p_distance_m DOUBLE, p_electrique BOOLEAN)
RETURNS DOUBLE
DETERMINISTIC NO SQL
BEGIN
  RETURN p_distance_m / 1000 / IF(p_electrique, 17, 13) * 60 * 1.3 + 2;
END$$

-- Station d'arrivée d'un trajet qui a duré p_minutes : parmi les stations
-- ayant une borne libre, une des trois dont le temps de trajet estimé depuis
-- la station de départ est le plus proche de la durée réelle. Un trajet
-- court finit donc près du départ, un long trajet plus loin ; une balade
-- (30 min et plus) revient parfois à son point de départ. NULL si le réseau
-- est plein.
CREATE FUNCTION sim_station_destination(p_origine INT UNSIGNED, p_minutes INT,
                                        p_electrique BOOLEAN)
RETURNS INT UNSIGNED
NOT DETERMINISTIC READS SQL DATA
BEGIN
  IF p_minutes >= 30 AND RAND() < 0.3 AND fn_borne_libre(p_origine) IS NOT NULL THEN
    RETURN p_origine;   -- balade en boucle
  END IF;
  RETURN (SELECT id_station
            FROM (SELECT s.id_station
                    FROM station s
                    JOIN station o ON o.id_station = p_origine
                   WHERE s.etat = 'EN_SERVICE'
                     AND s.id_station <> p_origine
                     AND fn_borne_libre(s.id_station) IS NOT NULL
                   ORDER BY ABS(sim_minutes_trajet(ST_Distance_Sphere(POINT(s.longitude, s.latitude),
                                                                      POINT(o.longitude, o.latitude)),
                                                   p_electrique) - p_minutes)
                   LIMIT 3) proches
           ORDER BY RAND()
           LIMIT 1);
END$$

-- Station habituelle d'un usager à cette heure-ci : celle d'où il part le
-- plus souvent dans la même tranche horaire (± 2 h, 90 derniers jours). Le
-- matin, c'est en général près de chez lui, le soir près de son travail ou
-- de ses études. NULL s'il n'a pas d'habitude.
CREATE FUNCTION sim_station_habituelle(p_usager INT UNSIGNED, p_instant DATETIME)
RETURNS INT UNSIGNED
NOT DETERMINISTIC READS SQL DATA
BEGIN
  RETURN (SELECT m.id_station_depart
            FROM abonnement a
            JOIN location l  ON l.id_abonnement = a.id_abonnement
            JOIN mouvement m ON m.id_mouvement = l.id_mouvement
           WHERE a.id_utilisateur = p_usager
             AND a.date_fin >= DATE(p_instant) - INTERVAL 90 DAY
             AND m.date_heure_depart >= p_instant - INTERVAL 90 DAY
             AND ABS(HOUR(m.date_heure_depart) - HOUR(p_instant)) <= 2
           GROUP BY m.id_station_depart
           ORDER BY COUNT(*) DESC, RAND()
           LIMIT 1);
END$$

-- Un vélo empruntable dans la station (en service, sur une borne en
-- service, batterie d'au moins 20 % s'il est électrique ; un électrique
-- est préféré une fois sur trois quand il y en a un), ou NULL.
CREATE FUNCTION sim_velo_disponible(p_station INT UNSIGNED)
RETURNS INT UNSIGNED
NOT DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE v_electrique_prefere BOOLEAN DEFAULT RAND() < 0.33;
  RETURN (SELECT v.id_velo
            FROM velo v
            JOIN station s ON s.id_station = v.id_station AND s.etat = 'EN_SERVICE'
            JOIN borne b   ON b.id_station = v.id_station AND b.numero = v.numero_borne
                          AND b.etat = 'EN_SERVICE'
            LEFT JOIN velo_electrique ve ON ve.id_velo = v.id_velo
           WHERE v.id_station = p_station
             AND (ve.id_velo IS NULL OR ve.niveau_batterie >= 20)
             AND fn_etat_velo(v.id_velo) = 'EN_SERVICE'
           ORDER BY IF(v_electrique_prefere, ve.id_velo IS NULL, 0), RAND()
           LIMIT 1);
END$$

-- Un opérateur du rôle demandé, au hasard (hors comptes de démonstration).
-- p_libre : seulement un opérateur sans tournée en cours.
CREATE FUNCTION sim_operateur(p_role VARCHAR(25), p_libre BOOLEAN)
RETURNS INT UNSIGNED
NOT DETERMINISTIC READS SQL DATA
BEGIN
  RETURN (SELECT u.id_utilisateur
            FROM utilisateur u
           WHERE u.role = p_role
             AND NOT sim_compte_demo(u.email)
             AND (NOT p_libre
                  OR NOT EXISTS (SELECT 1 FROM tournee t
                                  WHERE t.id_utilisateur = u.id_utilisateur
                                    AND t.date_heure_fin IS NULL))
           ORDER BY RAND()
           LIMIT 1);
END$$


-- =============================================================================
--  2. Procédures de simulation (une par événement)
-- =============================================================================

-- ---------------------------------------------------------------- emprunts
-- Nombre d'emprunts de la minute tiré d'après le taux attendu, puis pour
-- chacun un usager abonné tiré au hasard :
--   - 7 fois sur 10, il part de sa station habituelle à cette heure
--     (domicile le matin, travail le soir) ; si elle est vide, de la station
--     la plus proche à moins de 800 m qui a un vélo ; sinon il renonce
--     (demande perdue : c'est ce que la régulation doit éviter) ;
--   - sinon (trajet occasionnel, ou usager sans habitude), il prend un vélo
--     n'importe où dans le réseau.
CREATE PROCEDURE sim_emprunts()
BEGIN
  DECLARE v_taux DOUBLE DEFAULT sim_taux_emprunts(NOW());
  DECLARE v_nb INT;
  DECLARE v_i INT DEFAULT 0;
  DECLARE v_usager, v_velo, v_location, v_origine INT UNSIGNED;
  SET v_nb = FLOOR(v_taux) + (RAND() < v_taux - FLOOR(v_taux));
  WHILE v_i < v_nb DO
    SET v_i = v_i + 1;
    SET v_usager = (SELECT a.id_utilisateur
                      FROM abonnement a
                      JOIN utilisateur u ON u.id_utilisateur = a.id_utilisateur
                     WHERE CURDATE() BETWEEN a.date_debut AND a.date_fin
                       AND NOT sim_compte_demo(u.email)
                     ORDER BY RAND()
                     LIMIT 1);
    SET v_velo = NULL;
    SET v_origine = IF(RAND() < 0.7, sim_station_habituelle(v_usager, NOW()), NULL);
    IF v_origine IS NOT NULL THEN
      SET v_velo = sim_velo_disponible(v_origine);
      IF v_velo IS NULL THEN
        -- station habituelle vide : la plus proche (moins de 800 m) qui a un vélo
        SET v_velo = sim_velo_disponible(
              (SELECT s.id_station
                 FROM station s
                 JOIN station o ON o.id_station = v_origine
                WHERE s.id_station <> v_origine
                  AND s.etat = 'EN_SERVICE'
                  AND ST_Distance_Sphere(POINT(s.longitude, s.latitude),
                                         POINT(o.longitude, o.latitude)) < 800
                  AND sim_velo_disponible(s.id_station) IS NOT NULL
                ORDER BY ST_Distance_Sphere(POINT(s.longitude, s.latitude),
                                            POINT(o.longitude, o.latitude))
                LIMIT 1));
      END IF;
    ELSE
      SET v_velo = (SELECT v.id_velo
                      FROM velo v
                      JOIN station s ON s.id_station = v.id_station AND s.etat = 'EN_SERVICE'
                      JOIN borne b   ON b.id_station = v.id_station AND b.numero = v.numero_borne
                                    AND b.etat = 'EN_SERVICE'
                      LEFT JOIN velo_electrique ve ON ve.id_velo = v.id_velo
                     WHERE (ve.id_velo IS NULL OR ve.niveau_batterie >= 20)
                       AND fn_etat_velo(v.id_velo) = 'EN_SERVICE'
                     ORDER BY RAND()
                     LIMIT 1);
    END IF;
    IF v_usager IS NOT NULL AND v_velo IS NOT NULL THEN
      BEGIN
        -- refus d'une règle (usager déjà en location, vélo pris…) : emprunt abandonné
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
        CALL emprunter_velo(v_usager, v_velo, RAND() < 0.08, v_location);
      END;
    END IF;
  END WHILE;
END$$

-- ---------------------------------------------------------------- restitutions
-- Les locations dont la durée prévue est écoulée sont restituées dans une
-- station à la bonne distance pour cette durée (sim_station_destination) ;
-- un vélo électrique perd de la batterie.
CREATE PROCEDURE sim_restitutions()
BEGIN
  DECLARE v_fini BOOLEAN DEFAULT FALSE;
  DECLARE v_location, v_velo, v_origine, v_dest INT UNSIGNED;
  DECLARE v_duree INT;
  DECLARE c_dues CURSOR FOR
    SELECT m.id_mouvement, m.id_velo, m.id_station_depart,
           TIMESTAMPDIFF(MINUTE, m.date_heure_depart, NOW())
      FROM velo v
      JOIN mouvement m   ON m.id_velo = v.id_velo AND m.date_heure_arrivee IS NULL
      JOIN location l    ON l.id_mouvement = m.id_mouvement
      JOIN abonnement a  ON a.id_abonnement = l.id_abonnement
      JOIN utilisateur u ON u.id_utilisateur = a.id_utilisateur
     WHERE v.id_station IS NULL
       AND NOT sim_compte_demo(u.email)
       AND TIMESTAMPDIFF(MINUTE, m.date_heure_depart, NOW()) >= sim_duree_trajet(m.id_mouvement)
     LIMIT 100;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fini = TRUE;
  OPEN c_dues;
  boucle: LOOP
    FETCH c_dues INTO v_location, v_velo, v_origine, v_duree;
    IF v_fini THEN
      LEAVE boucle;
    END IF;
    SET v_dest = sim_station_destination(v_origine, v_duree,
                                         EXISTS (SELECT 1 FROM velo_electrique WHERE id_velo = v_velo));
    IF v_dest IS NOT NULL THEN
      BEGIN
        DECLARE v_ok BOOLEAN DEFAULT TRUE;
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_ok = FALSE;
        CALL restituer_velo(v_location, v_dest, NULL);
        IF v_ok THEN
          UPDATE velo_electrique
             SET niveau_batterie = GREATEST(0, niveau_batterie - LEAST(60, CEIL(v_duree / 2)))
           WHERE id_velo = v_velo;
        END IF;
      END;
    END IF;
  END LOOP;
  CLOSE c_dues;
END$$

-- ---------------------------------------------------------------- recharge
-- Un vélo électrique posé sur une borne se recharge (+4 % toutes les 5 min,
-- soit une charge complète en un peu plus de 2 h).
CREATE PROCEDURE sim_recharge()
BEGIN
  UPDATE velo_electrique ve
    JOIN velo v ON v.id_velo = ve.id_velo
     SET ve.niveau_batterie = LEAST(100, ve.niveau_batterie + 4)
   WHERE v.id_station IS NOT NULL
     AND ve.niveau_batterie < 100;
END$$

-- ---------------------------------------------------------------- signalements
-- Un usager qui vient de rendre son vélo signale parfois un problème (une
-- fois sur quatre, une fausse alerte) ; plus rarement, un problème de station.
CREATE PROCEDURE sim_signalements()
BEGIN
  DECLARE v_usager, v_velo, v_station, v_signalement INT UNSIGNED;
  DECLARE v_borne SMALLINT UNSIGNED;
  DECLARE v_electrique BOOLEAN;
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
  DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

  -- vélo : environ 14 par jour
  IF RAND() < 0.10 THEN
    SET v_usager = NULL, v_velo = NULL;
    SELECT a.id_utilisateur, m.id_velo INTO v_usager, v_velo
      FROM mouvement m
      JOIN location l    ON l.id_mouvement = m.id_mouvement
      JOIN abonnement a  ON a.id_abonnement = l.id_abonnement
      JOIN utilisateur u ON u.id_utilisateur = a.id_utilisateur
      JOIN velo v        ON v.id_velo = m.id_velo
     WHERE m.date_heure_depart >= NOW() - INTERVAL 3 HOUR
       AND m.date_heure_arrivee >= NOW() - INTERVAL 20 MINUTE
       AND v.id_station IS NOT NULL
       AND NOT sim_compte_demo(u.email)
       AND fn_etat_velo(m.id_velo) = 'EN_SERVICE'
     ORDER BY RAND()
     LIMIT 1;
    IF v_velo IS NOT NULL THEN
      SET v_electrique = EXISTS (SELECT 1 FROM velo_electrique WHERE id_velo = v_velo);
      CALL signaler_velo(v_usager, v_velo,
                         IF(RAND() < 0.25, sim_texte_fausse_alerte(), sim_texte_panne(v_electrique)),
                         v_signalement);
    END IF;
  END IF;

  -- station : environ 3 par jour
  IF RAND() < 0.02 THEN
    SET v_usager = (SELECT a.id_utilisateur
                      FROM abonnement a
                      JOIN utilisateur u ON u.id_utilisateur = a.id_utilisateur
                     WHERE CURDATE() BETWEEN a.date_debut AND a.date_fin
                       AND NOT sim_compte_demo(u.email)
                     ORDER BY RAND() LIMIT 1);
    SET v_station = (SELECT id_station FROM station WHERE etat = 'EN_SERVICE' ORDER BY RAND() LIMIT 1);
    SET v_borne = (SELECT numero FROM borne WHERE id_station = v_station ORDER BY RAND() LIMIT 1);
    IF v_usager IS NOT NULL AND v_station IS NOT NULL THEN
      CALL signaler_station(v_usager, v_station, sim_texte_panne_station(COALESCE(v_borne, 1)),
                            v_signalement);
    END IF;
  END IF;
END$$

-- ---------------------------------------------------------------- maintenance
-- Aux heures de travail : les signalements de vélo ouverts sont traités
-- (fausse alerte close, ou retrait du vélo pour réparation) ; les vélos à
-- l'atelier reviennent sur une borne au bout de 1 à 5 h (un sur quarante
-- est réformé) ; les signalements de station donnent lieu à des travaux.
CREATE PROCEDURE sim_maintenance()
BEGIN
  DECLARE v_fini BOOLEAN DEFAULT FALSE;
  DECLARE v_id, v_velo, v_operateur, v_station, v_intervention INT UNSIGNED;
  DECLARE v_description VARCHAR(500);
  DECLARE c_signalements_velo CURSOR FOR
    SELECT s.id_signalement, sv.id_velo, s.description
      FROM signalement s
      JOIN signalement_velo sv ON sv.id_signalement = s.id_signalement
     WHERE s.date_heure_cloture IS NULL
       AND sv.id_intervention_velo IS NULL
       AND s.date_heure_signalement <= NOW() - INTERVAL 20 MINUTE
     ORDER BY s.date_heure_signalement
     LIMIT 6;
  DECLARE c_atelier CURSOR FOR
    SELECT iv.id_intervention
      FROM velo v
      JOIN mouvement m          ON m.id_velo = v.id_velo AND m.date_heure_arrivee IS NULL
      JOIN intervention_velo iv ON iv.id_mouvement = m.id_mouvement
     WHERE v.id_station IS NULL
       AND m.date_heure_depart <= NOW() - INTERVAL (1 + MOD(iv.id_intervention, 5)) HOUR
     LIMIT 10;
  DECLARE c_signalements_station CURSOR FOR
    SELECT s.id_signalement, s.description
      FROM signalement s
      JOIN signalement_station ss ON ss.id_signalement = s.id_signalement
      JOIN station st             ON st.id_station = ss.id_station AND st.etat = 'EN_SERVICE'
     WHERE s.date_heure_cloture IS NULL
       AND s.date_heure_signalement <= NOW() - INTERVAL 1 HOUR
       AND NOT EXISTS (SELECT 1 FROM intervention_station i
                        WHERE i.id_signalement_station = s.id_signalement
                          AND i.date_heure_fin IS NULL)
     LIMIT 3;
  DECLARE c_travaux CURSOR FOR
    SELECT i.id_intervention
      FROM intervention_station i
      JOIN signalement_station ss ON ss.id_signalement = i.id_signalement_station
      JOIN station st             ON st.id_station = ss.id_station AND st.etat = 'EN_SERVICE'
     WHERE i.date_heure_fin IS NULL
       AND i.date_heure_debut <= NOW() - INTERVAL (1 + MOD(i.id_intervention, 4)) HOUR;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fini = TRUE;

  IF HOUR(NOW()) BETWEEN 7 AND 19 THEN

    -- 1. signalements de vélo ouverts
    SET v_fini = FALSE;
    OPEN c_signalements_velo;
    sig: LOOP
      FETCH c_signalements_velo INTO v_id, v_velo, v_description;
      IF v_fini THEN LEAVE sig; END IF;
      BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
        IF sim_est_fausse_alerte(v_description) THEN
          CALL cloturer_signalement(v_id);
        ELSE
          -- échoue (ignoré) si le vélo n'est pas sur une borne : on repassera
          CALL retirer_velo(sim_operateur('OPERATEUR_MAINTENANCE', FALSE), v_velo,
                            LEFT(CONCAT('Réparation après signalement : ', v_description), 500),
                            v_intervention);
        END IF;
      END;
    END LOOP;
    CLOSE c_signalements_velo;

    -- 2. fin des réparations à l'atelier
    SET v_fini = FALSE;
    OPEN c_atelier;
    atelier: LOOP
      FETCH c_atelier INTO v_id;
      IF v_fini THEN LEAVE atelier; END IF;
      BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
        IF MOD(v_id, 40) = 0 THEN
          CALL reformer_velo(v_id);
        ELSE
          -- retour vers une station peu remplie
          SET v_station = (SELECT s.id_station
                             FROM station s
                            WHERE s.etat = 'EN_SERVICE'
                              AND fn_borne_libre(s.id_station) IS NOT NULL
                            ORDER BY (SELECT COUNT(*) FROM velo v WHERE v.id_station = s.id_station)
                                     + RAND() * 6
                            LIMIT 1);
          IF v_station IS NOT NULL THEN
            CALL remettre_en_circulation(v_id, v_station, NULL);
          END IF;
        END IF;
      END;
    END LOOP;
    CLOSE c_atelier;

    -- 3. signalements de station : début des travaux
    SET v_fini = FALSE;
    OPEN c_signalements_station;
    station: LOOP
      FETCH c_signalements_station INTO v_id, v_description;
      IF v_fini THEN LEAVE station; END IF;
      BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
        CALL demarrer_intervention_station(sim_operateur('OPERATEUR_MAINTENANCE', FALSE), v_id,
                                           LEFT(CONCAT('Intervention : ', v_description), 500),
                                           v_intervention);
      END;
    END LOOP;
    CLOSE c_signalements_station;

    -- 4. fin des travaux (une fois sur sept, une seconde intervention suivra)
    SET v_fini = FALSE;
    OPEN c_travaux;
    travaux: LOOP
      FETCH c_travaux INTO v_id;
      IF v_fini THEN LEAVE travaux; END IF;
      BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
        CALL terminer_intervention_station(v_id, MOD(v_id, 7) <> 0);
      END;
    END LOOP;
    CLOSE c_travaux;
  END IF;
END$$

-- ---------------------------------------------------------------- régulation
-- 1. Les vélos chargés depuis plus de 8 min sont déposés dans la station la
--    plus vide proche de leur station de départ ; 2. les tournées vidées sont
--    clôturées ; 3. jusqu'à trois nouvelles tournées partent d'après
--    v_proposition_deplacement (station pleine -> station vide la plus proche).
CREATE PROCEDURE sim_regulation()
BEGIN
  DECLARE v_fini BOOLEAN DEFAULT FALSE;
  DECLARE v_transfert, v_source, v_dest, v_tournee, v_operateur, v_vehicule, v_velo INT UNSIGNED;
  DECLARE v_nb, v_k, v_charges, v_essai INT;
  DECLARE c_charges CURSOR FOR
    SELECT t.id_mouvement, m.id_station_depart
      FROM tournee tr
      JOIN utilisateur u ON u.id_utilisateur = tr.id_utilisateur
      JOIN transfert t   ON t.id_tournee = tr.id_tournee
      JOIN mouvement m   ON m.id_mouvement = t.id_mouvement AND m.date_heure_arrivee IS NULL
     WHERE tr.date_heure_fin IS NULL
       AND NOT sim_compte_demo(u.email)
       AND m.date_heure_depart <= NOW() - INTERVAL 8 MINUTE;
  DECLARE c_a_cloturer CURSOR FOR
    SELECT tr.id_tournee
      FROM tournee tr
      JOIN utilisateur u ON u.id_utilisateur = tr.id_utilisateur
     WHERE tr.date_heure_fin IS NULL
       AND NOT sim_compte_demo(u.email)
       AND tr.date_heure_debut <= NOW() - INTERVAL 10 MINUTE
       AND NOT EXISTS (SELECT 1 FROM transfert t
                         JOIN mouvement m ON m.id_mouvement = t.id_mouvement
                        WHERE t.id_tournee = tr.id_tournee AND m.date_heure_arrivee IS NULL);
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fini = TRUE;

  IF HOUR(NOW()) BETWEEN 6 AND 21 THEN

    -- 1. dépôts
    SET v_fini = FALSE;
    OPEN c_charges;
    depots: LOOP
      FETCH c_charges INTO v_transfert, v_source;
      IF v_fini THEN LEAVE depots; END IF;
      SET v_dest = (SELECT s.id_station
                      FROM station s
                      JOIN station o ON o.id_station = v_source
                     WHERE s.etat = 'EN_SERVICE'
                       AND s.id_station <> v_source
                       AND fn_borne_libre(s.id_station) IS NOT NULL
                     ORDER BY (SELECT COUNT(*) FROM velo v WHERE v.id_station = s.id_station)
                              / GREATEST(1, (SELECT COUNT(*) FROM borne b
                                              WHERE b.id_station = s.id_station AND b.etat = 'EN_SERVICE')) * 4
                              + ST_Distance_Sphere(POINT(s.longitude, s.latitude),
                                                   POINT(o.longitude, o.latitude)) / 1000
                     LIMIT 1);
      IF v_dest IS NOT NULL THEN
        BEGIN
          DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
          CALL deposer_velo(v_transfert, v_dest, NULL);
        END;
      END IF;
    END LOOP;
    CLOSE c_charges;

    -- 2. clôtures
    SET v_fini = FALSE;
    OPEN c_a_cloturer;
    clotures: LOOP
      FETCH c_a_cloturer INTO v_tournee;
      IF v_fini THEN LEAVE clotures; END IF;
      BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
        CALL cloturer_tournee(v_tournee);
      END;
    END LOOP;
    CLOSE c_a_cloturer;

    -- 3. nouvelles tournées
    SET v_essai = 0;
    nouvelles: WHILE v_essai < 3 DO
      SET v_essai = v_essai + 1;
      SET v_fini = FALSE, v_source = NULL, v_nb = NULL;
      -- source pleine dont aucun vélo n'est déjà en cours de transfert
      SELECT p.id_station_source, p.nb_velos_a_deplacer INTO v_source, v_nb
        FROM v_proposition_deplacement p
       WHERE NOT EXISTS (SELECT 1 FROM transfert t
                           JOIN mouvement m ON m.id_mouvement = t.id_mouvement
                          WHERE m.id_station_depart = p.id_station_source
                            AND m.date_heure_arrivee IS NULL)
       ORDER BY p.nb_velos_a_deplacer DESC, RAND()
       LIMIT 1;
      SET v_operateur = sim_operateur('OPERATEUR_REGULATION', TRUE);
      SET v_vehicule = (SELECT ve.id_vehicule FROM vehicule ve
                         WHERE NOT EXISTS (SELECT 1 FROM tournee t
                                            WHERE t.id_vehicule = ve.id_vehicule
                                              AND t.date_heure_fin IS NULL)
                         ORDER BY RAND() LIMIT 1);
      IF v_source IS NULL OR v_operateur IS NULL OR v_vehicule IS NULL THEN
        LEAVE nouvelles;
      END IF;
      SET v_nb = LEAST(v_nb, (SELECT capacite FROM vehicule WHERE id_vehicule = v_vehicule));
      BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
        SET v_tournee = NULL;
        CALL demarrer_tournee(v_operateur, v_vehicule, v_tournee);
        SET v_k = 0, v_charges = 0;
        WHILE v_tournee IS NOT NULL AND v_k < v_nb DO
          SET v_k = v_k + 1;
          SET v_velo = (SELECT v.id_velo FROM velo v
                         WHERE v.id_station = v_source
                           AND fn_etat_velo(v.id_velo) = 'EN_SERVICE'
                         ORDER BY RAND() LIMIT 1);
          IF v_velo IS NOT NULL THEN
            SET v_transfert = NULL;
            CALL charger_velo(v_tournee, v_velo, v_transfert);
            SET v_charges = v_charges + (v_transfert IS NOT NULL);
          END IF;
        END WHILE;
        IF v_tournee IS NOT NULL AND v_charges = 0 THEN
          CALL cloturer_tournee(v_tournee);
        END IF;
      END;
    END WHILE nouvelles;
  END IF;
END$$

-- ---------------------------------------------------------------- factures
-- La plupart des factures récentes (deux derniers jours) sont réglées.
CREATE PROCEDURE sim_factures()
BEGIN
  DECLARE v_fini BOOLEAN DEFAULT FALSE;
  DECLARE v_facture INT UNSIGNED;
  DECLARE c_a_regler CURSOR FOR
    SELECT f.id_facture
      FROM facture f
      LEFT JOIN location l ON l.id_mouvement = f.id_location
      JOIN abonnement a    ON a.id_abonnement = COALESCE(f.id_abonnement, l.id_abonnement)
      JOIN utilisateur u   ON u.id_utilisateur = a.id_utilisateur
     WHERE f.date_reglement IS NULL
       AND f.montant > 0
       AND f.date_emission BETWEEN NOW() - INTERVAL 2 DAY AND NOW() - INTERVAL 5 MINUTE
       AND NOT sim_compte_demo(u.email)
     LIMIT 500;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fini = TRUE;
  OPEN c_a_regler;
  reglements: LOOP
    FETCH c_a_regler INTO v_facture;
    IF v_fini THEN LEAVE reglements; END IF;
    IF RAND() < 0.85 THEN
      BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
        CALL regler_facture(v_facture);
      END;
    END IF;
  END LOOP;
  CLOSE c_a_regler;
END$$

-- ---------------------------------------------------------------- inscriptions
-- En journée : un nouvel usager s'inscrit de temps en temps (un ou deux par
-- heure en moyenne) et souscrit une formule ; des usagers sans abonnement
-- prennent un ticket journée.
CREATE PROCEDURE sim_inscriptions()
BEGIN
  DECLARE v_nom, v_prenom VARCHAR(50);
  DECLARE v_usager, v_abonnement, v_ticket INT UNSIGNED;
  DECLARE v_i INT DEFAULT 0;
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

  IF HOUR(NOW()) BETWEEN 7 AND 21 THEN
    SET v_ticket = (SELECT id_formule FROM formule
                     ORDER BY duree_validite_jours, prix LIMIT 1);

    -- nouvel usager (empreinte du mot de passe de démonstration « velo2026 »)
    IF RAND() < 0.6 THEN
      SET v_nom = ELT(1 + FLOOR(RAND() * 20), 'Martin', 'Bernard', 'Thomas', 'Petit', 'Robert',
                      'Richard', 'Durand', 'Dubois', 'Moreau', 'Laurent', 'Simon', 'Michel',
                      'Garcia', 'David', 'Bertrand', 'Roux', 'Vincent', 'Fournier', 'Morel', 'Girard');
      SET v_prenom = ELT(1 + FLOOR(RAND() * 20), 'Emma', 'Louis', 'Jade', 'Gabriel', 'Louise',
                         'Arthur', 'Alice', 'Jules', 'Chloe', 'Hugo', 'Lina', 'Adam', 'Rose',
                         'Paul', 'Anna', 'Noah', 'Julia', 'Tom', 'Lucie', 'Nathan');
      SET v_usager = NULL;
      INSERT INTO utilisateur (nom, prenom, email, mot_de_passe_hash, telephone, role)
      VALUES (v_nom, v_prenom,
              CONCAT(LOWER(v_prenom), '.', LOWER(v_nom), FLOOR(1000 + RAND() * 90000), '@example.org'),
              '$2y$10$F8AZNwHgSxkQUcHkv3NC8OfyvAn3A8JyfOQ6SRNxIibn0u5Xj3KUO',
              CONCAT('06', LPAD(FLOOR(RAND() * 100000000), 8, '0')), 'USAGER');
      IF ROW_COUNT() = 1 THEN
        SET v_usager = LAST_INSERT_ID();
        CALL souscrire_abonnement(v_usager,
                                  (SELECT id_formule FROM formule ORDER BY RAND() LIMIT 1),
                                  NULL, v_abonnement);
      END IF;
    END IF;

    -- tickets journée pour des usagers sans abonnement en cours ni à venir
    WHILE v_i < 1 + (RAND() < 0.5) DO
      SET v_i = v_i + 1;
      SET v_usager = (SELECT u.id_utilisateur
                        FROM utilisateur u
                       WHERE u.role = 'USAGER'
                         AND NOT sim_compte_demo(u.email)
                         AND NOT EXISTS (SELECT 1 FROM abonnement a
                                          WHERE a.id_utilisateur = u.id_utilisateur
                                            AND a.date_fin >= CURDATE())
                       ORDER BY RAND() LIMIT 1);
      IF v_usager IS NOT NULL THEN
        CALL souscrire_abonnement(v_usager, v_ticket, NULL, v_abonnement);
      END IF;
    END WHILE;
  END IF;
END$$

-- ---------------------------------------------------------------- abonnements
-- Chaque nuit : 85 % des abonnements arrivés à échéance hier sont
-- renouvelés (le renouvellement commence aujourd'hui) ; quelques usagers
-- dont l'abonnement finit dans 7 jours changent de formule (le nouvel
-- abonnement est programmé au lendemain de la fin de l'actuel, R22).
CREATE PROCEDURE sim_abonnements()
BEGIN
  DECLARE v_fini BOOLEAN DEFAULT FALSE;
  DECLARE v_abonnement, v_usager, v_formule, v_nouvel INT UNSIGNED;
  DECLARE c_echus CURSOR FOR
    SELECT a.id_abonnement
      FROM abonnement a
      JOIN formule f     ON f.id_formule = a.id_formule AND f.duree_validite_jours > 1
      JOIN utilisateur u ON u.id_utilisateur = a.id_utilisateur
     WHERE a.date_fin = CURDATE() - INTERVAL 1 DAY
       AND NOT sim_compte_demo(u.email)
       AND NOT EXISTS (SELECT 1 FROM abonnement s
                        WHERE s.id_utilisateur = a.id_utilisateur AND s.date_debut > a.date_fin);
  DECLARE c_changements CURSOR FOR
    SELECT a.id_utilisateur, a.id_formule
      FROM abonnement a
      JOIN formule f     ON f.id_formule = a.id_formule AND f.duree_validite_jours > 1
      JOIN utilisateur u ON u.id_utilisateur = a.id_utilisateur
     WHERE a.date_fin = CURDATE() + INTERVAL 7 DAY
       AND NOT sim_compte_demo(u.email)
       AND NOT EXISTS (SELECT 1 FROM abonnement s
                        WHERE s.id_utilisateur = a.id_utilisateur AND s.date_debut > a.date_fin);
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fini = TRUE;

  OPEN c_echus;
  renouvellements: LOOP
    FETCH c_echus INTO v_abonnement;
    IF v_fini THEN LEAVE renouvellements; END IF;
    IF RAND() < 0.85 THEN
      BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
        CALL renouveler_abonnement(v_abonnement, v_nouvel);
      END;
    END IF;
  END LOOP;
  CLOSE c_echus;

  SET v_fini = FALSE;
  OPEN c_changements;
  changements: LOOP
    FETCH c_changements INTO v_usager, v_formule;
    IF v_fini THEN LEAVE changements; END IF;
    IF RAND() < 0.05 THEN
      BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
        CALL souscrire_abonnement(v_usager,
                                  (SELECT id_formule FROM formule
                                    WHERE id_formule <> v_formule AND duree_validite_jours > 1
                                    ORDER BY RAND() LIMIT 1),
                                  NULL, v_nouvel);
      END;
    END IF;
  END LOOP;
  CLOSE c_changements;
END$$


-- =============================================================================
--  3. Pilotage
-- =============================================================================

CREATE PROCEDURE sim_basculer(IN p_actif BOOLEAN)
BEGIN
  IF p_actif THEN
    ALTER EVENT evt_sim_emprunts ENABLE;
    ALTER EVENT evt_sim_restitutions ENABLE;
    ALTER EVENT evt_sim_recharge ENABLE;
    ALTER EVENT evt_sim_signalements ENABLE;
    ALTER EVENT evt_sim_maintenance ENABLE;
    ALTER EVENT evt_sim_regulation ENABLE;
    ALTER EVENT evt_sim_factures ENABLE;
    ALTER EVENT evt_sim_inscriptions ENABLE;
    ALTER EVENT evt_sim_abonnements ENABLE;
  ELSE
    ALTER EVENT evt_sim_emprunts DISABLE;
    ALTER EVENT evt_sim_restitutions DISABLE;
    ALTER EVENT evt_sim_recharge DISABLE;
    ALTER EVENT evt_sim_signalements DISABLE;
    ALTER EVENT evt_sim_maintenance DISABLE;
    ALTER EVENT evt_sim_regulation DISABLE;
    ALTER EVENT evt_sim_factures DISABLE;
    ALTER EVENT evt_sim_inscriptions DISABLE;
    ALTER EVENT evt_sim_abonnements DISABLE;
  END IF;
END$$

CREATE PROCEDURE sim_demarrer()
BEGIN
  CALL sim_basculer(TRUE);
END$$

CREATE PROCEDURE sim_arreter()
BEGIN
  CALL sim_basculer(FALSE);
END$$

CREATE PROCEDURE sim_etat()
BEGIN
  SELECT event_name AS evenement, status AS statut,
         CONCAT(interval_value, ' ', interval_field) AS frequence,
         last_executed AS derniere_execution, event_comment AS role
    FROM information_schema.events
   WHERE event_schema = DATABASE() AND event_name LIKE 'evt\_sim\_%'
   ORDER BY event_name;
  SELECT @@event_scheduler AS planificateur;
END$$

DELIMITER ;


-- =============================================================================
--  4. Vue de contrôle : activité de la dernière heure
-- =============================================================================

CREATE VIEW v_simulation_activite AS
SELECT 'Emprunts' AS activite,
       (SELECT COUNT(*) FROM location l JOIN mouvement m ON m.id_mouvement = l.id_mouvement
         WHERE m.date_heure_depart >= NOW() - INTERVAL 1 HOUR) AS derniere_heure
UNION ALL
SELECT 'Restitutions',
       (SELECT COUNT(*) FROM location l JOIN mouvement m ON m.id_mouvement = l.id_mouvement
         WHERE m.date_heure_depart >= NOW() - INTERVAL 1 DAY
           AND m.date_heure_arrivee >= NOW() - INTERVAL 1 HOUR)
UNION ALL
SELECT 'Locations en cours',
       (SELECT COUNT(*) FROM velo v JOIN mouvement m ON m.id_velo = v.id_velo AND m.date_heure_arrivee IS NULL
          JOIN location l ON l.id_mouvement = m.id_mouvement WHERE v.id_station IS NULL)
UNION ALL
SELECT 'Signalements',
       (SELECT COUNT(*) FROM signalement WHERE date_heure_signalement >= NOW() - INTERVAL 1 HOUR)
UNION ALL
SELECT 'Tournées démarrées',
       (SELECT COUNT(*) FROM tournee WHERE date_heure_debut >= NOW() - INTERVAL 1 HOUR)
UNION ALL
SELECT 'Vélos à l''atelier',
       (SELECT COUNT(*) FROM velo v JOIN mouvement m ON m.id_velo = v.id_velo AND m.date_heure_arrivee IS NULL
          JOIN intervention_velo iv ON iv.id_mouvement = m.id_mouvement WHERE v.id_station IS NULL)
UNION ALL
SELECT 'Factures émises',
       (SELECT COUNT(*) FROM facture WHERE date_emission >= NOW() - INTERVAL 1 HOUR)
UNION ALL
SELECT 'Factures réglées',
       (SELECT COUNT(*) FROM facture WHERE date_reglement >= NOW() - INTERVAL 1 HOUR)
UNION ALL
SELECT 'Nouveaux usagers',
       (SELECT COUNT(*) FROM utilisateur WHERE date_inscription >= NOW() - INTERVAL 1 HOUR)
UNION ALL
SELECT 'Abonnements souscrits',
       (SELECT COUNT(*) FROM facture WHERE id_abonnement IS NOT NULL
                                      AND date_emission >= NOW() - INTERVAL 1 HOUR);


-- =============================================================================
--  5. Événements
-- =============================================================================
--  Créés actifs : l'activité démarre dès le chargement du script.
--  ON COMPLETION PRESERVE : un événement suspendu (sim_arreter) est conservé.

CREATE EVENT evt_sim_emprunts
  ON SCHEDULE EVERY 1 MINUTE STARTS CURRENT_TIMESTAMP + INTERVAL 5 SECOND
  ON COMPLETION PRESERVE ENABLE
  COMMENT 'Simulation : emprunts de vélos selon l''heure de la journée'
  DO CALL sim_emprunts();

CREATE EVENT evt_sim_restitutions
  ON SCHEDULE EVERY 1 MINUTE STARTS CURRENT_TIMESTAMP + INTERVAL 35 SECOND
  ON COMPLETION PRESERVE ENABLE
  COMMENT 'Simulation : restitution des locations terminées'
  DO CALL sim_restitutions();

CREATE EVENT evt_sim_recharge
  ON SCHEDULE EVERY 5 MINUTE STARTS CURRENT_TIMESTAMP + INTERVAL 50 SECOND
  ON COMPLETION PRESERVE ENABLE
  COMMENT 'Simulation : recharge des vélos électriques sur borne'
  DO CALL sim_recharge();

CREATE EVENT evt_sim_signalements
  ON SCHEDULE EVERY 10 MINUTE STARTS CURRENT_TIMESTAMP + INTERVAL 2 MINUTE
  ON COMPLETION PRESERVE ENABLE
  COMMENT 'Simulation : signalements de vélos et de stations'
  DO CALL sim_signalements();

CREATE EVENT evt_sim_maintenance
  ON SCHEDULE EVERY 15 MINUTE STARTS CURRENT_TIMESTAMP + INTERVAL 3 MINUTE
  ON COMPLETION PRESERVE ENABLE
  COMMENT 'Simulation : retraits, réparations, réformes et travaux de station'
  DO CALL sim_maintenance();

CREATE EVENT evt_sim_regulation
  ON SCHEDULE EVERY 20 MINUTE STARTS CURRENT_TIMESTAMP + INTERVAL 1 MINUTE
  ON COMPLETION PRESERVE ENABLE
  COMMENT 'Simulation : tournées de rééquilibrage des stations'
  DO CALL sim_regulation();

CREATE EVENT evt_sim_factures
  ON SCHEDULE EVERY 1 HOUR STARTS CURRENT_TIMESTAMP + INTERVAL 4 MINUTE
  ON COMPLETION PRESERVE ENABLE
  COMMENT 'Simulation : règlement des factures récentes'
  DO CALL sim_factures();

CREATE EVENT evt_sim_inscriptions
  ON SCHEDULE EVERY 1 HOUR STARTS CURRENT_TIMESTAMP + INTERVAL 6 MINUTE
  ON COMPLETION PRESERVE ENABLE
  COMMENT 'Simulation : nouveaux usagers et tickets journée'
  DO CALL sim_inscriptions();

CREATE EVENT evt_sim_abonnements
  ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 5 MINUTE)
  ON COMPLETION PRESERVE ENABLE
  COMMENT 'Simulation : renouvellements et changements de formule (chaque nuit)'
  DO CALL sim_abonnements();
