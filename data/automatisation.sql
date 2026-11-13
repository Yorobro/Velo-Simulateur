-- =============================================================================
--  Réseau de vélos en libre-service — AUTOMATISATION
-- =============================================================================
--  Fonctions, procédures stockées, triggers et vues de la base
--  velo_libre_service. Ne modifie ni le MCD ni le MLD : aucune table ni
--  colonne n'est ajoutée.
--
--  ORDRE D'EXÉCUTION :
--    structure.sql -> peuplement_velo.py (ou donnes.sql) -> automatisation.sql
--  (les triggers créent eux-mêmes factures et changements d'état : chargés
--  avant les données, ils produiraient des doublons).
--  Le script est rejouable : il supprime puis recrée tous ses objets.
--
--  SGBD : MySQL 8.4 LTS / 9.x (testé sur MySQL 9.0). N'utilise que des
--  fonctionnalités présentes aussi dans MariaDB 10.11+.
--
--  Contenu
--    1. Fonctions        fn_etat_velo, fn_abonnement_valide, fn_duree_minutes,
--                        fn_cout_trajet, fn_cout_location, fn_borne_libre
--    2. Contrôles        lever_erreur, verifier_borne_accueil,
--                        verifier_mouvement_libre, verifier_traitement,
--                        verifier_abonnement_unique
--    3. Triggers         règles R1 à R22 de structure.sql + historisation
--                        et calculs automatiques
--    4. Procédures       une par cas d'utilisation (emprunter_velo, ...)
--    5. Vues             disponibilité temps réel, régulation, consultation,
--                        statistiques du sujet
--
--  Ce qui est automatique
--    - position du vélo tenue à jour à chaque départ / arrivée (R5) ;
--    - historique des états : EN_SERVICE à la mise en service, DEFECTUEUX au
--      signalement d'un problème ou au retrait pour maintenance, EN_SERVICE à
--      la remise en circulation ou à la clôture d'une fausse alerte, REFORME
--      quand le vélo arrive à l'atelier sans borne (R19, R20) ;
--    - date de fin d'un abonnement calculée depuis la formule (R11) ;
--    - facture créée à la souscription d'un abonnement et à la restitution
--      de chaque location, même gratuite (durée et coût calculés, R4, R18) ;
--    - signalements de vélo rattachés à l'intervention qui retire le vélo,
--      puis clos à la fin de l'intervention ;
--    - e-mail normalisé en minuscules.
--
--  Les procédures sont la voie normale d'écriture : chacune est une
--  transaction complète (elle valide ou annule tout) et pose les verrous
--  (SELECT ... FOR UPDATE) qui évitent, par exemple, que deux usagers
--  empruntent le même vélo au même instant. Elles garantissent aussi les
--  généralisations {complete} : un mouvement est toujours créé avec son type,
--  un signalement avec sa cible. Les triggers restent un filet de sécurité
--  pour les écritures directes dans les tables.
--  Attention : une procédure ouvre sa propre transaction ; l'appeler au milieu
--  d'une transaction en cours valide cette dernière.
--
--  Limite connue de MySQL / MariaDB : les suppressions en cascade
--  (ON DELETE CASCADE) ne déclenchent pas les triggers.
-- =============================================================================

SET NAMES utf8mb4;
USE velo_libre_service;


-- =============================================================================
--  0. Nettoyage (le script est rejouable)
-- =============================================================================

DROP VIEW IF EXISTS v_proposition_deplacement;
DROP VIEW IF EXISTS v_regulation;
DROP VIEW IF EXISTS v_stat_indisponibilite_flotte;
DROP VIEW IF EXISTS v_disponibilite_station;
DROP VIEW IF EXISTS v_velo;
DROP VIEW IF EXISTS v_etat_actuel_velo;
DROP VIEW IF EXISTS v_location;
DROP VIEW IF EXISTS v_abonnement;
DROP VIEW IF EXISTS v_signalement;
DROP VIEW IF EXISTS v_stat_trajets_par_jour;
DROP VIEW IF EXISTS v_stat_heures_pointe;
DROP VIEW IF EXISTS v_stat_origine_destination;
DROP VIEW IF EXISTS v_stat_recettes_formule;
DROP VIEW IF EXISTS v_stat_remplissage_horaire;

DROP TRIGGER IF EXISTS trg_utilisateur_bi;
DROP TRIGGER IF EXISTS trg_utilisateur_bu;
DROP TRIGGER IF EXISTS trg_abonnement_bi;
DROP TRIGGER IF EXISTS trg_abonnement_ai;
DROP TRIGGER IF EXISTS trg_abonnement_bu;
DROP TRIGGER IF EXISTS trg_facture_bi;
DROP TRIGGER IF EXISTS trg_facture_bu;
DROP TRIGGER IF EXISTS trg_borne_bd;
DROP TRIGGER IF EXISTS trg_velo_bi;
DROP TRIGGER IF EXISTS trg_velo_ai;
DROP TRIGGER IF EXISTS trg_velo_bu;
DROP TRIGGER IF EXISTS trg_changement_etat_bi;
DROP TRIGGER IF EXISTS trg_mouvement_bi;
DROP TRIGGER IF EXISTS trg_mouvement_ai;
DROP TRIGGER IF EXISTS trg_mouvement_bu;
DROP TRIGGER IF EXISTS trg_mouvement_au;
DROP TRIGGER IF EXISTS trg_location_bi;
DROP TRIGGER IF EXISTS trg_tournee_bi;
DROP TRIGGER IF EXISTS trg_tournee_bu;
DROP TRIGGER IF EXISTS trg_transfert_bi;
DROP TRIGGER IF EXISTS trg_intervention_bi;
DROP TRIGGER IF EXISTS trg_intervention_bu;
DROP TRIGGER IF EXISTS trg_intervention_velo_bi;
DROP TRIGGER IF EXISTS trg_intervention_velo_ai;
DROP TRIGGER IF EXISTS trg_intervention_station_bi;
DROP TRIGGER IF EXISTS trg_intervention_station_bu;
DROP TRIGGER IF EXISTS trg_signalement_bi;
DROP TRIGGER IF EXISTS trg_signalement_velo_bi;
DROP TRIGGER IF EXISTS trg_signalement_velo_ai;
DROP TRIGGER IF EXISTS trg_signalement_velo_bu;
DROP TRIGGER IF EXISTS trg_signalement_station_bi;

DROP PROCEDURE IF EXISTS creer_station;
DROP PROCEDURE IF EXISTS souscrire_abonnement;
DROP PROCEDURE IF EXISTS renouveler_abonnement;
DROP PROCEDURE IF EXISTS regler_facture;
DROP PROCEDURE IF EXISTS emprunter_velo;
DROP PROCEDURE IF EXISTS restituer_velo;
DROP PROCEDURE IF EXISTS demarrer_tournee;
DROP PROCEDURE IF EXISTS charger_velo;
DROP PROCEDURE IF EXISTS deposer_velo;
DROP PROCEDURE IF EXISTS cloturer_tournee;
DROP PROCEDURE IF EXISTS signaler_velo;
DROP PROCEDURE IF EXISTS signaler_station;
DROP PROCEDURE IF EXISTS cloturer_signalement;
DROP PROCEDURE IF EXISTS retirer_velo;
DROP PROCEDURE IF EXISTS remettre_en_circulation;
DROP PROCEDURE IF EXISTS reformer_velo;
DROP PROCEDURE IF EXISTS demarrer_intervention_station;
DROP PROCEDURE IF EXISTS terminer_intervention_station;
DROP PROCEDURE IF EXISTS enregistrer_arrivee;
DROP PROCEDURE IF EXISTS verifier_traitement;
DROP PROCEDURE IF EXISTS verifier_abonnement_unique;
DROP PROCEDURE IF EXISTS verifier_mouvement_libre;
DROP PROCEDURE IF EXISTS verifier_borne_accueil;
DROP PROCEDURE IF EXISTS lever_erreur;

DROP FUNCTION IF EXISTS fn_etat_velo;
DROP FUNCTION IF EXISTS fn_abonnement_valide;
DROP FUNCTION IF EXISTS fn_duree_minutes;
DROP FUNCTION IF EXISTS fn_cout_trajet;
DROP FUNCTION IF EXISTS fn_cout_location;
DROP FUNCTION IF EXISTS fn_borne_libre;


DELIMITER $$

-- =============================================================================
--  1. Fonctions
-- =============================================================================

-- État actuel d'un vélo = son dernier changement d'état (NULL si aucun).
CREATE FUNCTION fn_etat_velo(p_velo INT UNSIGNED)
RETURNS VARCHAR(12)
READS SQL DATA
BEGIN
  RETURN (SELECT etat
            FROM changement_etat
           WHERE id_velo = p_velo
           ORDER BY date_heure_changement DESC, id_changement DESC
           LIMIT 1);
END$$

-- Abonnement valable un jour donné pour un usager (le plus récent), ou NULL.
CREATE FUNCTION fn_abonnement_valide(p_utilisateur INT UNSIGNED, p_jour DATE)
RETURNS INT UNSIGNED
READS SQL DATA
BEGIN
  RETURN (SELECT id_abonnement
            FROM abonnement
           WHERE id_utilisateur = p_utilisateur
             AND p_jour BETWEEN date_debut AND date_fin
           ORDER BY date_debut DESC, id_abonnement DESC
           LIMIT 1);
END$$

-- Durée en minutes entamées (toute minute commencée compte).
CREATE FUNCTION fn_duree_minutes(p_debut DATETIME, p_fin DATETIME)
RETURNS INT
DETERMINISTIC
NO SQL
BEGIN
  RETURN CEIL(TIMESTAMPDIFF(SECOND, p_debut, p_fin) / 60);
END$$

-- Coût d'un trajet selon la formule :
--   tranches entamées au-delà de la durée gratuite x prix d'une tranche
--   + supplément vélo électrique + supplément casque.
CREATE FUNCTION fn_cout_trajet(p_formule INT UNSIGNED, p_minutes INT,
                               p_electrique BOOLEAN, p_casque BOOLEAN)
RETURNS DECIMAL(8,2)
READS SQL DATA
BEGIN
  DECLARE v_gratuit, v_tranche INT;
  DECLARE v_prix_tranche, v_supp_electrique, v_supp_casque DECIMAL(5,2);
  SELECT duree_gratuite_min, duree_tranche_min, prix_tranche,
         supplement_electrique, supplement_casque
    INTO v_gratuit, v_tranche, v_prix_tranche, v_supp_electrique, v_supp_casque
    FROM formule
   WHERE id_formule = p_formule;
  IF v_tranche IS NULL OR p_minutes IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN CEIL(GREATEST(0, p_minutes - v_gratuit) / v_tranche) * v_prix_tranche
       + IF(p_electrique, v_supp_electrique, 0)
       + IF(p_casque, v_supp_casque, 0);
END$$

-- Coût d'une location terminée (NULL si elle est en cours).
CREATE FUNCTION fn_cout_location(p_location INT UNSIGNED)
RETURNS DECIMAL(8,2)
READS SQL DATA
BEGIN
  RETURN (SELECT fn_cout_trajet(a.id_formule,
                                fn_duree_minutes(m.date_heure_depart, m.date_heure_arrivee),
                                ve.id_velo IS NOT NULL, l.avec_casque)
            FROM location l
            JOIN mouvement m       ON m.id_mouvement = l.id_mouvement
            JOIN abonnement a      ON a.id_abonnement = l.id_abonnement
            LEFT JOIN velo_electrique ve ON ve.id_velo = m.id_velo
           WHERE l.id_mouvement = p_location);
END$$

-- Première borne libre et en service d'une station en service, ou NULL.
CREATE FUNCTION fn_borne_libre(p_station INT UNSIGNED)
RETURNS SMALLINT UNSIGNED
READS SQL DATA
BEGIN
  RETURN (SELECT MIN(b.numero)
            FROM borne b
            JOIN station s ON s.id_station = b.id_station
           WHERE b.id_station = p_station
             AND b.etat = 'EN_SERVICE'
             AND s.etat = 'EN_SERVICE'
             AND NOT EXISTS (SELECT 1 FROM velo v
                              WHERE v.id_station = b.id_station
                                AND v.numero_borne = b.numero));
END$$


-- =============================================================================
--  2. Procédures de contrôle (utilisées par les triggers et les procédures)
-- =============================================================================

-- Lève une erreur métier (SQLSTATE 45000) avec un message lisible.
CREATE PROCEDURE lever_erreur(IN p_message VARCHAR(128))
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = p_message;
END$$

-- R6 : un vélo n'arrive que sur une borne existante, libre et en service,
-- d'une station en service.
CREATE PROCEDURE verifier_borne_accueil(IN p_station INT UNSIGNED,
                                        IN p_numero SMALLINT UNSIGNED,
                                        IN p_velo INT UNSIGNED)
BEGIN
  DECLARE v_etat_borne, v_etat_station VARCHAR(12);
  SET v_etat_borne = (SELECT etat FROM borne
                       WHERE id_station = p_station AND numero = p_numero);
  SET v_etat_station = (SELECT etat FROM station WHERE id_station = p_station);
  IF v_etat_borne IS NULL THEN
    CALL lever_erreur('Borne inexistante.');
  ELSEIF v_etat_station <> 'EN_SERVICE' THEN
    CALL lever_erreur('Cette station n''est pas en service.');
  ELSEIF v_etat_borne <> 'EN_SERVICE' THEN
    CALL lever_erreur('Cette borne est hors service.');
  ELSEIF EXISTS (SELECT 1 FROM velo
                  WHERE id_station = p_station AND numero_borne = p_numero
                    AND id_velo <> p_velo) THEN
    CALL lever_erreur('Cette borne est déjà occupée par un autre vélo.');
  END IF;
END$$

-- R8 : un mouvement reçoit son type (location, transfert, maintenance) une
-- seule fois, et pendant qu'il est en cours.
CREATE PROCEDURE verifier_mouvement_libre(IN p_mouvement INT UNSIGNED)
BEGIN
  IF (SELECT date_heure_arrivee FROM mouvement
       WHERE id_mouvement = p_mouvement) IS NOT NULL THEN
    CALL lever_erreur('Le type d''un mouvement se déclare au départ, pas après l''arrivée.');
  ELSEIF EXISTS (SELECT 1 FROM location WHERE id_mouvement = p_mouvement)
      OR EXISTS (SELECT 1 FROM transfert WHERE id_mouvement = p_mouvement)
      OR EXISTS (SELECT 1 FROM intervention_velo WHERE id_mouvement = p_mouvement) THEN
    CALL lever_erreur('Ce mouvement est déjà une location, un transfert ou une maintenance.');
  END IF;
END$$

-- R22 : un usager n'a qu'un abonnement à la fois. La période
-- [p_debut, p_fin] ne doit chevaucher aucun autre abonnement de l'usager
-- (p_abonnement : l'abonnement modifié, exclu de la comparaison ; NULL à
-- l'insertion). Un renouvellement commence après la fin du précédent : il
-- ne chevauche donc jamais celui qu'il renouvelle.
CREATE PROCEDURE verifier_abonnement_unique(IN p_utilisateur INT UNSIGNED,
                                            IN p_abonnement INT UNSIGNED,
                                            IN p_debut DATE,
                                            IN p_fin DATE)
BEGIN
  IF EXISTS (SELECT 1 FROM abonnement
              WHERE id_utilisateur = p_utilisateur
                AND NOT (id_abonnement <=> p_abonnement)
                AND date_debut <= p_fin
                AND date_fin >= p_debut) THEN
    CALL lever_erreur('Un usager n''a qu''un abonnement à la fois : cette période chevauche un abonnement existant.');
  END IF;
END$$

-- R13 / R14 : un signalement de vélo n'est traité que par une intervention
-- sur le même vélo, commencée après le signalement.
CREATE PROCEDURE verifier_traitement(IN p_signalement INT UNSIGNED,
                                     IN p_velo INT UNSIGNED,
                                     IN p_intervention INT UNSIGNED)
BEGIN
  DECLARE v_velo INT UNSIGNED;
  DECLARE v_debut DATETIME;
  SELECT m.id_velo, m.date_heure_depart INTO v_velo, v_debut
    FROM intervention_velo iv
    JOIN mouvement m ON m.id_mouvement = iv.id_mouvement
   WHERE iv.id_intervention = p_intervention;
  IF v_velo <> p_velo THEN
    CALL lever_erreur('Cette intervention ne porte pas sur le vélo signalé.');
  ELSEIF v_debut < (SELECT date_heure_signalement FROM signalement
                     WHERE id_signalement = p_signalement) THEN
    CALL lever_erreur('L''intervention a commencé avant le signalement.');
  END IF;
END$$


-- =============================================================================
--  3. Triggers
-- =============================================================================

-- ---------------------------------------------------------------- utilisateur

CREATE TRIGGER trg_utilisateur_bi BEFORE INSERT ON utilisateur FOR EACH ROW
BEGIN
  SET NEW.email = LOWER(TRIM(NEW.email));
  IF NEW.date_inscription > NOW() THEN
    CALL lever_erreur('La date d''inscription ne peut pas être dans le futur.');
  END IF;
END$$

CREATE TRIGGER trg_utilisateur_bu BEFORE UPDATE ON utilisateur FOR EACH ROW
BEGIN
  SET NEW.email = LOWER(TRIM(NEW.email));
END$$

-- ---------------------------------------------------------------- abonnement

-- R11 : date de fin calculée depuis la formule ; seul un usager s'abonne ;
-- un renouvellement suit l'abonnement précédent du même usager.
-- R22 : pas de chevauchement avec un autre abonnement de l'usager.
CREATE TRIGGER trg_abonnement_bi BEFORE INSERT ON abonnement FOR EACH ROW
BEGIN
  DECLARE v_utilisateur_prec INT UNSIGNED;
  DECLARE v_fin_prec DATE;
  IF (SELECT role FROM utilisateur WHERE id_utilisateur = NEW.id_utilisateur) <> 'USAGER' THEN
    CALL lever_erreur('Seul un usager peut souscrire un abonnement.');
  END IF;
  SET NEW.date_debut = COALESCE(NEW.date_debut, CURDATE());
  SET NEW.date_fin = NEW.date_debut + INTERVAL
      ((SELECT duree_validite_jours FROM formule WHERE id_formule = NEW.id_formule) - 1) DAY;
  IF NEW.id_abonnement_precedent IS NOT NULL THEN
    SELECT id_utilisateur, date_fin INTO v_utilisateur_prec, v_fin_prec
      FROM abonnement WHERE id_abonnement = NEW.id_abonnement_precedent;
    IF v_utilisateur_prec <> NEW.id_utilisateur THEN
      CALL lever_erreur('Un renouvellement appartient au même usager que l''abonnement précédent.');
    ELSEIF NEW.date_debut <= v_fin_prec THEN
      CALL lever_erreur('Le renouvellement doit commencer après la fin de l''abonnement précédent.');
    END IF;
  END IF;
  CALL verifier_abonnement_unique(NEW.id_utilisateur, NULL, NEW.date_debut, NEW.date_fin);
END$$

-- Facturation automatique de la souscription (prix de la formule).
CREATE TRIGGER trg_abonnement_ai AFTER INSERT ON abonnement FOR EACH ROW
BEGIN
  INSERT INTO facture (date_emission, montant, id_abonnement)
  SELECT NOW(), prix, NEW.id_abonnement FROM formule WHERE id_formule = NEW.id_formule;
END$$

CREATE TRIGGER trg_abonnement_bu BEFORE UPDATE ON abonnement FOR EACH ROW
BEGIN
  IF NEW.id_utilisateur <> OLD.id_utilisateur THEN
    CALL lever_erreur('Un abonnement ne change pas de titulaire.');
  ELSEIF NOT (NEW.id_abonnement_precedent <=> OLD.id_abonnement_precedent) THEN
    -- fixé à la création (R11) : empêche aussi un abonnement de se renouveler lui-même
    CALL lever_erreur('Le lien de renouvellement d''un abonnement ne se modifie pas.');
  END IF;
  SET NEW.date_fin = NEW.date_debut + INTERVAL
      ((SELECT duree_validite_jours FROM formule WHERE id_formule = NEW.id_formule) - 1) DAY;
  CALL verifier_abonnement_unique(NEW.id_utilisateur, NEW.id_abonnement, NEW.date_debut, NEW.date_fin);
END$$

-- ---------------------------------------------------------------- facture

CREATE TRIGGER trg_facture_bi BEFORE INSERT ON facture FOR EACH ROW
BEGIN
  SET NEW.date_emission = COALESCE(NEW.date_emission, NOW());
END$$

-- Une facture réglée est figée.
CREATE TRIGGER trg_facture_bu BEFORE UPDATE ON facture FOR EACH ROW
BEGIN
  IF OLD.date_reglement IS NOT NULL
     AND (NEW.montant <> OLD.montant
          OR NEW.date_emission <> OLD.date_emission
          OR NOT (NEW.date_reglement <=> OLD.date_reglement)
          OR NOT (NEW.id_abonnement <=> OLD.id_abonnement)
          OR NOT (NEW.id_location <=> OLD.id_location)) THEN
    CALL lever_erreur('Une facture réglée ne peut plus être modifiée.');
  END IF;
END$$

-- ---------------------------------------------------------------- borne

-- R21 : une station garde au moins une borne. (La suppression d'une station
-- supprime ses bornes en cascade, sans déclencher ce trigger.)
CREATE TRIGGER trg_borne_bd BEFORE DELETE ON borne FOR EACH ROW
BEGIN
  IF (SELECT COUNT(*) FROM borne WHERE id_station = OLD.id_station) <= 1 THEN
    CALL lever_erreur('Une station doit garder au moins une borne.');
  END IF;
END$$

-- ---------------------------------------------------------------- velo

CREATE TRIGGER trg_velo_bi BEFORE INSERT ON velo FOR EACH ROW
BEGIN
  SET NEW.date_mise_service = COALESCE(NEW.date_mise_service, NOW());
  IF NEW.id_station IS NOT NULL THEN
    CALL verifier_borne_accueil(NEW.id_station, NEW.numero_borne, 0);
  END IF;
END$$

-- Historisation : un vélo neuf commence EN_SERVICE.
CREATE TRIGGER trg_velo_ai AFTER INSERT ON velo FOR EACH ROW
BEGIN
  INSERT INTO changement_etat (date_heure_changement, etat, id_velo)
  VALUES (NEW.date_mise_service, 'EN_SERVICE', NEW.id_velo);
END$$

-- R5 : un vélo n'est qu'à un seul endroit. Dès qu'il a un historique, sa
-- position est celle que donne son dernier mouvement (NULL pendant le
-- mouvement, borne d'arrivée ensuite) : elle ne se modifie pas à la main.
CREATE TRIGGER trg_velo_bu BEFORE UPDATE ON velo FOR EACH ROW
BEGIN
  DECLARE v_station INT UNSIGNED;
  DECLARE v_numero SMALLINT UNSIGNED;
  IF NOT (NEW.id_station <=> OLD.id_station AND NEW.numero_borne <=> OLD.numero_borne) THEN
    IF EXISTS (SELECT 1 FROM mouvement WHERE id_velo = NEW.id_velo) THEN
      SELECT id_station_arrivee, numero_borne_arrivee INTO v_station, v_numero
        FROM mouvement
       WHERE id_velo = NEW.id_velo
       ORDER BY date_heure_depart DESC, id_mouvement DESC
       LIMIT 1;
      IF NOT (NEW.id_station <=> v_station AND NEW.numero_borne <=> v_numero) THEN
        CALL lever_erreur('La position d''un vélo ne change que par un mouvement.');
      END IF;
    END IF;
    IF NEW.id_station IS NOT NULL THEN
      IF fn_etat_velo(NEW.id_velo) = 'REFORME' THEN
        CALL lever_erreur('Un vélo réformé ne retourne pas sur une borne.');
      END IF;
      CALL verifier_borne_accueil(NEW.id_station, NEW.numero_borne, NEW.id_velo);
    END IF;
  END IF;
END$$

-- ---------------------------------------------------------------- changement_etat

CREATE TRIGGER trg_changement_etat_bi BEFORE INSERT ON changement_etat FOR EACH ROW
BEGIN
  SET NEW.date_heure_changement = COALESCE(NEW.date_heure_changement, NOW());
  IF fn_etat_velo(NEW.id_velo) = 'REFORME' THEN
    CALL lever_erreur('Un vélo réformé ne change plus d''état.');
  ELSEIF NEW.date_heure_changement < (SELECT date_mise_service FROM velo
                                       WHERE id_velo = NEW.id_velo) THEN
    CALL lever_erreur('Changement d''état antérieur à la mise en service du vélo.');
  ELSEIF NEW.date_heure_changement < (SELECT MAX(date_heure_changement)
                                        FROM changement_etat
                                       WHERE id_velo = NEW.id_velo) THEN
    CALL lever_erreur('Changement d''état antérieur au précédent.');
  ELSEIF NEW.etat = 'REFORME'
     AND (SELECT id_station FROM velo WHERE id_velo = NEW.id_velo) IS NOT NULL THEN
    CALL lever_erreur('Un vélo doit être retiré de sa borne avant d''être réformé.');
  END IF;
END$$

-- ---------------------------------------------------------------- mouvement

-- Un mouvement est créé au départ : la borne de départ est celle où se
-- trouve le vélo (R6, R7). L'arrivée s'enregistre ensuite, par UPDATE.
CREATE TRIGGER trg_mouvement_bi BEFORE INSERT ON mouvement FOR EACH ROW
BEGIN
  DECLARE v_station INT UNSIGNED;
  DECLARE v_numero SMALLINT UNSIGNED;
  IF NEW.date_heure_arrivee IS NOT NULL OR NEW.id_station_arrivee IS NOT NULL THEN
    CALL lever_erreur('Un mouvement se crée au départ ; l''arrivée s''enregistre ensuite.');
  END IF;
  SELECT id_station, numero_borne INTO v_station, v_numero
    FROM velo WHERE id_velo = NEW.id_velo;
  IF v_station IS NULL THEN
    CALL lever_erreur('Ce vélo n''est sur aucune borne (en location, en atelier, en tournée ou réformé).');
  END IF;
  -- borne de départ déduite de la position du vélo si elle n'est pas fournie
  SET NEW.id_station_depart   = COALESCE(NEW.id_station_depart, v_station);
  SET NEW.numero_borne_depart = COALESCE(NEW.numero_borne_depart, v_numero);
  SET NEW.date_heure_depart   = COALESCE(NEW.date_heure_depart, NOW());
  IF NOT (NEW.id_station_depart = v_station AND NEW.numero_borne_depart = v_numero) THEN
    CALL lever_erreur('Le vélo ne se trouve pas sur la borne de départ indiquée.');
  ELSEIF NEW.date_heure_depart < (SELECT date_mise_service FROM velo
                                   WHERE id_velo = NEW.id_velo)
      OR NEW.date_heure_depart < (SELECT MAX(date_heure_arrivee) FROM mouvement
                                   WHERE id_velo = NEW.id_velo) THEN
    CALL lever_erreur('Départ antérieur à la dernière arrivée du vélo.');
  END IF;
END$$

-- Historisation : le vélo quitte sa borne.
CREATE TRIGGER trg_mouvement_ai AFTER INSERT ON mouvement FOR EACH ROW
BEGIN
  UPDATE velo SET id_station = NULL, numero_borne = NULL WHERE id_velo = NEW.id_velo;
END$$

-- Enregistrement de l'arrivée : contrôles (R6, R14).
CREATE TRIGGER trg_mouvement_bu BEFORE UPDATE ON mouvement FOR EACH ROW
BEGIN
  IF OLD.date_heure_arrivee IS NOT NULL THEN
    CALL lever_erreur('Un mouvement terminé ne peut plus être modifié.');
  END IF;
  IF NEW.id_velo <> OLD.id_velo
     OR NEW.date_heure_depart <> OLD.date_heure_depart
     OR NEW.id_station_depart <> OLD.id_station_depart
     OR NEW.numero_borne_depart <> OLD.numero_borne_depart THEN
    CALL lever_erreur('Le départ d''un mouvement ne se modifie pas.');
  END IF;
  IF NEW.id_station_arrivee IS NOT NULL OR NEW.date_heure_arrivee IS NOT NULL THEN
    SET NEW.date_heure_arrivee = COALESCE(NEW.date_heure_arrivee, NOW());
    IF NEW.id_station_arrivee IS NULL THEN
      -- seule une maintenance se termine sans borne : le vélo est réformé
      IF NOT EXISTS (SELECT 1 FROM intervention_velo WHERE id_mouvement = NEW.id_mouvement) THEN
        CALL lever_erreur('Seul un vélo réformé (maintenance) arrive sans borne.');
      END IF;
    ELSE
      CALL verifier_borne_accueil(NEW.id_station_arrivee, NEW.numero_borne_arrivee, NEW.id_velo);
    END IF;
    IF EXISTS (SELECT 1 FROM transfert t
                 JOIN tournee tr ON tr.id_tournee = t.id_tournee
                WHERE t.id_mouvement = NEW.id_mouvement
                  AND tr.date_heure_fin IS NOT NULL) THEN
      CALL lever_erreur('La tournée de ce transfert est déjà clôturée.');
    END IF;
  END IF;
END$$

-- Arrivée enregistrée : position, facturation, fin de maintenance.
CREATE TRIGGER trg_mouvement_au AFTER UPDATE ON mouvement FOR EACH ROW
BEGIN
  DECLARE v_intervention INT UNSIGNED;
  DECLARE v_montant DECIMAL(8,2);
  IF OLD.date_heure_arrivee IS NULL AND NEW.date_heure_arrivee IS NOT NULL THEN

    -- 1. R5 : le vélo prend la borne d'arrivée (aucune s'il est réformé)
    UPDATE velo
       SET id_station = NEW.id_station_arrivee, numero_borne = NEW.numero_borne_arrivee
     WHERE id_velo = NEW.id_velo;

    -- 2. Location (R4, R18) : durée et coût calculés (casque choisi à
    --    l'emprunt), puis facture du trajet, même à 0 €.
    SET v_montant = (SELECT fn_cout_trajet(a.id_formule,
                                           fn_duree_minutes(NEW.date_heure_depart, NEW.date_heure_arrivee),
                                           EXISTS (SELECT 1 FROM velo_electrique WHERE id_velo = NEW.id_velo),
                                           l.avec_casque)
                       FROM location l
                       JOIN abonnement a ON a.id_abonnement = l.id_abonnement
                      WHERE l.id_mouvement = NEW.id_mouvement);
    IF v_montant IS NOT NULL THEN
      INSERT INTO facture (date_emission, montant, id_location)
      VALUES (NEW.date_heure_arrivee, v_montant, NEW.id_mouvement);
    END IF;

    -- 3. Maintenance : remise en circulation (borne) ou réforme (pas de borne),
    --    puis clôture des signalements traités par l'intervention.
    SET v_intervention = (SELECT id_intervention FROM intervention_velo
                           WHERE id_mouvement = NEW.id_mouvement);
    IF v_intervention IS NOT NULL THEN
      INSERT INTO changement_etat (date_heure_changement, etat, id_velo)
      VALUES (NEW.date_heure_arrivee,
              IF(NEW.id_station_arrivee IS NULL, 'REFORME', 'EN_SERVICE'),
              NEW.id_velo);
      UPDATE signalement s
        JOIN signalement_velo sv ON sv.id_signalement = s.id_signalement
         SET s.date_heure_cloture = NEW.date_heure_arrivee
       WHERE sv.id_intervention_velo = v_intervention
         AND s.date_heure_cloture IS NULL;
    END IF;
  END IF;
END$$

-- ---------------------------------------------------------------- location

-- R1 à R3 et R8 : abonnement valide, une seule location en cours par usager,
-- vélo en état de marche, station et borne de départ en service.
CREATE TRIGGER trg_location_bi BEFORE INSERT ON location FOR EACH ROW
BEGIN
  DECLARE v_velo, v_station, v_utilisateur INT UNSIGNED;
  DECLARE v_numero SMALLINT UNSIGNED;
  DECLARE v_depart DATETIME;
  DECLARE v_debut, v_fin DATE;
  CALL verifier_mouvement_libre(NEW.id_mouvement);
  SELECT id_velo, date_heure_depart, id_station_depart, numero_borne_depart
    INTO v_velo, v_depart, v_station, v_numero
    FROM mouvement WHERE id_mouvement = NEW.id_mouvement;
  SELECT id_utilisateur, date_debut, date_fin INTO v_utilisateur, v_debut, v_fin
    FROM abonnement WHERE id_abonnement = NEW.id_abonnement;
  IF DATE(v_depart) NOT BETWEEN v_debut AND v_fin THEN
    CALL lever_erreur('Abonnement non valable à la date de l''emprunt.');
  ELSEIF EXISTS (SELECT 1
                   FROM location l
                   JOIN mouvement m  ON m.id_mouvement = l.id_mouvement
                   JOIN abonnement a ON a.id_abonnement = l.id_abonnement
                  WHERE a.id_utilisateur = v_utilisateur
                    AND m.date_heure_arrivee IS NULL) THEN
    CALL lever_erreur('Cet usager a déjà une location en cours.');
  ELSEIF COALESCE(fn_etat_velo(v_velo), '') <> 'EN_SERVICE' THEN
    CALL lever_erreur('Ce vélo est signalé défectueux ou réformé : emprunt impossible.');
  ELSEIF (SELECT etat FROM station WHERE id_station = v_station) <> 'EN_SERVICE'
      OR (SELECT etat FROM borne WHERE id_station = v_station AND numero = v_numero) <> 'EN_SERVICE' THEN
    CALL lever_erreur('La station ou la borne de départ n''est pas en service.');
  END IF;
END$$

-- ---------------------------------------------------------------- tournee / transfert

-- R12 : une tournée est faite par un opérateur de régulation (ou un
-- administrateur). R16 : l'opérateur et le véhicule n'ont qu'une tournée en
-- cours à la fois.
CREATE TRIGGER trg_tournee_bi BEFORE INSERT ON tournee FOR EACH ROW
BEGIN
  IF (SELECT role FROM utilisateur WHERE id_utilisateur = NEW.id_utilisateur)
     NOT IN ('OPERATEUR_REGULATION', 'ADMINISTRATEUR') THEN
    CALL lever_erreur('Une tournée est effectuée par un opérateur de régulation.');
  ELSEIF NEW.date_heure_fin IS NOT NULL THEN
    CALL lever_erreur('Une tournée se crée au démarrage et se clôture ensuite.');
  ELSEIF EXISTS (SELECT 1 FROM tournee
                  WHERE id_utilisateur = NEW.id_utilisateur AND date_heure_fin IS NULL) THEN
    CALL lever_erreur('Cet opérateur a déjà une tournée en cours.');
  ELSEIF EXISTS (SELECT 1 FROM tournee
                  WHERE id_vehicule = NEW.id_vehicule AND date_heure_fin IS NULL) THEN
    CALL lever_erreur('Ce véhicule est déjà engagé dans une tournée en cours.');
  END IF;
  SET NEW.date_heure_debut = COALESCE(NEW.date_heure_debut, NOW());
END$$

-- R17 : clôture seulement quand tous les vélos chargés sont déposés (R14).
-- Une tournée peut être clôturée sans transfert (multiplicité 0..*).
CREATE TRIGGER trg_tournee_bu BEFORE UPDATE ON tournee FOR EACH ROW
BEGIN
  IF OLD.date_heure_fin IS NOT NULL THEN
    CALL lever_erreur('Une tournée clôturée ne se modifie plus.');
  END IF;
  IF NEW.id_vehicule <> OLD.id_vehicule THEN
    CALL lever_erreur('Le véhicule d''une tournée se choisit au démarrage.');
  END IF;
  IF NEW.id_utilisateur <> OLD.id_utilisateur
     AND (SELECT role FROM utilisateur WHERE id_utilisateur = NEW.id_utilisateur)
         NOT IN ('OPERATEUR_REGULATION', 'ADMINISTRATEUR') THEN
    CALL lever_erreur('Une tournée est effectuée par un opérateur de régulation.');
  END IF;
  IF NEW.date_heure_fin IS NOT NULL
     AND EXISTS (SELECT 1 FROM transfert t
                   JOIN mouvement m ON m.id_mouvement = t.id_mouvement
                  WHERE t.id_tournee = NEW.id_tournee
                    AND (m.date_heure_arrivee IS NULL OR m.date_heure_arrivee > NEW.date_heure_fin)) THEN
    CALL lever_erreur('Tous les vélos chargés doivent être déposés avant la clôture.');
  END IF;
END$$

-- R8, R14 et R15 : le véhicule ne charge pas plus de vélos que sa capacité.
CREATE TRIGGER trg_transfert_bi BEFORE INSERT ON transfert FOR EACH ROW
BEGIN
  DECLARE v_debut, v_fin DATETIME;
  DECLARE v_capacite TINYINT UNSIGNED;
  CALL verifier_mouvement_libre(NEW.id_mouvement);
  SELECT t.date_heure_debut, t.date_heure_fin, v.capacite INTO v_debut, v_fin, v_capacite
    FROM tournee t
    JOIN vehicule v ON v.id_vehicule = t.id_vehicule
   WHERE t.id_tournee = NEW.id_tournee;
  IF v_fin IS NOT NULL THEN
    CALL lever_erreur('Cette tournée est déjà clôturée.');
  ELSEIF (SELECT date_heure_depart FROM mouvement
           WHERE id_mouvement = NEW.id_mouvement) < v_debut THEN
    CALL lever_erreur('Ce transfert commence avant la tournée.');
  ELSEIF (SELECT COUNT(*) FROM transfert t
            JOIN mouvement m ON m.id_mouvement = t.id_mouvement
           WHERE t.id_tournee = NEW.id_tournee
             AND m.date_heure_arrivee IS NULL) >= v_capacite THEN
    CALL lever_erreur('Le véhicule est plein : déposez un vélo avant d''en charger un autre.');
  END IF;
END$$

-- ---------------------------------------------------------------- interventions

-- R12 : une intervention est réalisée par un opérateur de maintenance (ou
-- un administrateur).
CREATE TRIGGER trg_intervention_bi BEFORE INSERT ON intervention FOR EACH ROW
BEGIN
  IF (SELECT role FROM utilisateur WHERE id_utilisateur = NEW.id_utilisateur)
     NOT IN ('OPERATEUR_MAINTENANCE', 'ADMINISTRATEUR') THEN
    CALL lever_erreur('Une intervention est réalisée par un opérateur de maintenance.');
  END IF;
END$$

CREATE TRIGGER trg_intervention_bu BEFORE UPDATE ON intervention FOR EACH ROW
BEGIN
  IF NEW.id_utilisateur <> OLD.id_utilisateur
     AND (SELECT role FROM utilisateur WHERE id_utilisateur = NEW.id_utilisateur)
         NOT IN ('OPERATEUR_MAINTENANCE', 'ADMINISTRATEUR') THEN
    CALL lever_erreur('Une intervention est réalisée par un opérateur de maintenance.');
  END IF;
END$$

-- R8, R10 : le mouvement est libre et l'intervention ne porte pas déjà sur
-- une station.
CREATE TRIGGER trg_intervention_velo_bi BEFORE INSERT ON intervention_velo FOR EACH ROW
BEGIN
  IF EXISTS (SELECT 1 FROM intervention_station WHERE id_intervention = NEW.id_intervention) THEN
    CALL lever_erreur('Cette intervention porte déjà sur une station.');
  END IF;
  CALL verifier_mouvement_libre(NEW.id_mouvement);
END$$

-- Retrait pour maintenance : le vélo passe DEFECTUEUX (historisation) et les
-- signalements ouverts sur ce vélo sont rattachés à l'intervention.
CREATE TRIGGER trg_intervention_velo_ai AFTER INSERT ON intervention_velo FOR EACH ROW
BEGIN
  DECLARE v_velo INT UNSIGNED;
  DECLARE v_depart DATETIME;
  SELECT id_velo, date_heure_depart INTO v_velo, v_depart
    FROM mouvement WHERE id_mouvement = NEW.id_mouvement;
  IF COALESCE(fn_etat_velo(v_velo), '') <> 'DEFECTUEUX' THEN
    INSERT INTO changement_etat (date_heure_changement, etat, id_velo)
    VALUES (v_depart, 'DEFECTUEUX', v_velo);
  END IF;
  UPDATE signalement_velo sv
    JOIN signalement s ON s.id_signalement = sv.id_signalement
     SET sv.id_intervention_velo = NEW.id_intervention
   WHERE sv.id_velo = v_velo
     AND sv.id_intervention_velo IS NULL
     AND s.date_heure_cloture IS NULL
     AND s.date_heure_signalement <= v_depart;
END$$

-- R10, R14 : l'intervention traite un signalement de station encore ouvert
-- et commence après lui.
CREATE TRIGGER trg_intervention_station_bi BEFORE INSERT ON intervention_station FOR EACH ROW
BEGIN
  DECLARE v_signalement, v_cloture DATETIME;
  IF EXISTS (SELECT 1 FROM intervention_velo WHERE id_intervention = NEW.id_intervention) THEN
    CALL lever_erreur('Cette intervention porte déjà sur un vélo.');
  END IF;
  SET NEW.date_heure_debut = COALESCE(NEW.date_heure_debut, NOW());
  SELECT date_heure_signalement, date_heure_cloture INTO v_signalement, v_cloture
    FROM signalement WHERE id_signalement = NEW.id_signalement_station;
  IF v_cloture IS NOT NULL THEN
    CALL lever_erreur('Ce signalement est déjà clos.');
  ELSEIF NEW.date_heure_debut < v_signalement THEN
    CALL lever_erreur('L''intervention commence avant le signalement.');
  END IF;
END$$

CREATE TRIGGER trg_intervention_station_bu BEFORE UPDATE ON intervention_station FOR EACH ROW
BEGIN
  IF OLD.date_heure_fin IS NOT NULL THEN
    CALL lever_erreur('Une intervention terminée ne se modifie plus.');
  END IF;
END$$

-- ---------------------------------------------------------------- signalements

-- R12 : seul un usager signale un problème (cas d'utilisation UC10, UC11).
CREATE TRIGGER trg_signalement_bi BEFORE INSERT ON signalement FOR EACH ROW
BEGIN
  IF (SELECT role FROM utilisateur WHERE id_utilisateur = NEW.id_utilisateur) <> 'USAGER' THEN
    CALL lever_erreur('Seul un usager peut émettre un signalement.');
  END IF;
END$$

-- R9 : un signalement porte sur un vélo OU une station ; R13 / R14.
CREATE TRIGGER trg_signalement_velo_bi BEFORE INSERT ON signalement_velo FOR EACH ROW
BEGIN
  IF EXISTS (SELECT 1 FROM signalement_station WHERE id_signalement = NEW.id_signalement) THEN
    CALL lever_erreur('Ce signalement porte déjà sur une station.');
  END IF;
  IF NEW.id_intervention_velo IS NOT NULL THEN
    CALL verifier_traitement(NEW.id_signalement, NEW.id_velo, NEW.id_intervention_velo);
  END IF;
END$$

-- R20 (et R3) : un vélo signalé passe DEFECTUEUX, il n'est plus empruntable
-- jusqu'à sa réparation ou la clôture d'une fausse alerte.
CREATE TRIGGER trg_signalement_velo_ai AFTER INSERT ON signalement_velo FOR EACH ROW
BEGIN
  DECLARE v_quand, v_dernier DATETIME;
  IF fn_etat_velo(NEW.id_velo) = 'EN_SERVICE' THEN
    SET v_quand = (SELECT date_heure_signalement FROM signalement
                    WHERE id_signalement = NEW.id_signalement);
    SET v_dernier = (SELECT MAX(date_heure_changement) FROM changement_etat
                      WHERE id_velo = NEW.id_velo);
    -- jamais avant (ni au même instant que) le dernier changement d'état
    INSERT INTO changement_etat (date_heure_changement, etat, id_velo)
    VALUES (GREATEST(v_quand, v_dernier + INTERVAL 1 SECOND), 'DEFECTUEUX', NEW.id_velo);
  END IF;
END$$

CREATE TRIGGER trg_signalement_velo_bu BEFORE UPDATE ON signalement_velo FOR EACH ROW
BEGIN
  IF NEW.id_velo <> OLD.id_velo THEN
    CALL lever_erreur('Un signalement ne change pas de vélo.');
  END IF;
  IF NEW.id_intervention_velo IS NOT NULL
     AND NOT (NEW.id_intervention_velo <=> OLD.id_intervention_velo) THEN
    CALL verifier_traitement(NEW.id_signalement, NEW.id_velo, NEW.id_intervention_velo);
  END IF;
END$$

CREATE TRIGGER trg_signalement_station_bi BEFORE INSERT ON signalement_station FOR EACH ROW
BEGIN
  IF EXISTS (SELECT 1 FROM signalement_velo WHERE id_signalement = NEW.id_signalement) THEN
    CALL lever_erreur('Ce signalement porte déjà sur un vélo.');
  END IF;
END$$


-- =============================================================================
--  4. Procédures : une par cas d'utilisation
-- =============================================================================
--  Chaque procédure est une transaction : en cas d'erreur, tout est annulé et
--  l'erreur est renvoyée à l'appelant (RESIGNAL).

-- ---------------------------------------------------------------- stations

-- Créer une station avec ses p_nb_bornes bornes (numérotées 1, 2, ...) dans
-- la même transaction : une station a toujours au moins une borne (R21).
CREATE PROCEDURE creer_station(IN p_nom VARCHAR(100), IN p_adresse VARCHAR(255),
                               IN p_code_postal CHAR(5), IN p_latitude DECIMAL(8,6),
                               IN p_longitude DECIMAL(9,6), IN p_nb_bornes SMALLINT UNSIGNED,
                               OUT p_station INT UNSIGNED)
BEGIN
  DECLARE v_numero SMALLINT UNSIGNED DEFAULT 1;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  IF COALESCE(p_nb_bornes, 0) < 1 THEN
    CALL lever_erreur('Une station a au moins une borne.');
  END IF;
  INSERT INTO station (nom, adresse, code_postal, latitude, longitude)
  VALUES (p_nom, p_adresse, p_code_postal, p_latitude, p_longitude);
  SET p_station = LAST_INSERT_ID();
  WHILE v_numero <= p_nb_bornes DO
    INSERT INTO borne (id_station, numero) VALUES (p_station, v_numero);
    SET v_numero = v_numero + 1;
  END WHILE;
  COMMIT;
END$$

-- ---------------------------------------------------------------- abonnements

-- Souscrire un abonnement. La date de fin et la facture sont produites par
-- les triggers. p_date_debut NULL = au plus tôt : aujourd'hui, ou, si
-- l'usager a déjà un abonnement en cours ou à venir, le lendemain de la fin
-- du dernier (R22 : changer de formule programme le nouvel abonnement à la
-- suite de l'actuel, sans l'écourter). Une date imposée qui chevauche un
-- abonnement existant est refusée par le trigger.
CREATE PROCEDURE souscrire_abonnement(IN p_utilisateur INT UNSIGNED,
                                      IN p_formule INT UNSIGNED,
                                      IN p_date_debut DATE,
                                      OUT p_abonnement INT UNSIGNED)
BEGIN
  DECLARE v_debut DATE;
  DECLARE v_verrou INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  -- verrou sur l'usager : deux souscriptions simultanées ne passent pas toutes
  -- les deux le contrôle de chevauchement (R22)
  SELECT id_utilisateur INTO v_verrou FROM utilisateur
   WHERE id_utilisateur = p_utilisateur FOR UPDATE;
  SET v_debut = COALESCE(p_date_debut,
                         GREATEST(CURDATE(),
                                  COALESCE((SELECT MAX(date_fin) FROM abonnement
                                             WHERE id_utilisateur = p_utilisateur)
                                           + INTERVAL 1 DAY, CURDATE())));
  INSERT INTO abonnement (date_debut, date_fin, id_utilisateur, id_formule)
  VALUES (v_debut, v_debut, p_utilisateur, p_formule);
  SET p_abonnement = LAST_INSERT_ID();
  COMMIT;
END$$

-- Renouveler : même usager, même formule, à partir du lendemain de la fin
-- (ou d'aujourd'hui si l'abonnement a déjà expiré).
CREATE PROCEDURE renouveler_abonnement(IN p_abonnement INT UNSIGNED,
                                       OUT p_nouvel_abonnement INT UNSIGNED)
BEGIN
  DECLARE v_utilisateur, v_formule INT UNSIGNED;
  DECLARE v_debut DATE;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SELECT id_utilisateur, id_formule, GREATEST(date_fin + INTERVAL 1 DAY, CURDATE())
    INTO v_utilisateur, v_formule, v_debut
    FROM abonnement WHERE id_abonnement = p_abonnement FOR UPDATE;
  IF v_utilisateur IS NULL THEN
    CALL lever_erreur('Abonnement inconnu.');
  ELSEIF EXISTS (SELECT 1 FROM abonnement WHERE id_abonnement_precedent = p_abonnement) THEN
    CALL lever_erreur('Cet abonnement a déjà été renouvelé.');
  END IF;
  -- verrou sur l'usager (R22, comme pour une souscription)
  SELECT id_utilisateur INTO v_utilisateur FROM utilisateur
   WHERE id_utilisateur = v_utilisateur FOR UPDATE;
  IF EXISTS (SELECT 1 FROM abonnement
              WHERE id_utilisateur = v_utilisateur AND date_debut >= v_debut) THEN
    CALL lever_erreur('Un autre abonnement est déjà programmé après celui-ci.');
  END IF;
  INSERT INTO abonnement (date_debut, date_fin, id_utilisateur, id_formule, id_abonnement_precedent)
  VALUES (v_debut, v_debut, v_utilisateur, v_formule, p_abonnement);
  SET p_nouvel_abonnement = LAST_INSERT_ID();
  COMMIT;
END$$

-- Payer une facture (seulement si son montant est supérieur à 0).
CREATE PROCEDURE regler_facture(IN p_facture INT UNSIGNED)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  IF (SELECT montant FROM facture WHERE id_facture = p_facture) = 0 THEN
    CALL lever_erreur('Facture à 0 € : rien à régler.');
  END IF;
  UPDATE facture SET date_reglement = NOW()
   WHERE id_facture = p_facture AND date_reglement IS NULL;
  IF ROW_COUNT() = 0 THEN
    CALL lever_erreur('Facture inconnue ou déjà réglée.');
  END IF;
  COMMIT;
END$$

-- ---------------------------------------------------------------- locations

-- Emprunter un vélo (p_avec_casque : l'usager récupère un casque, facturé
-- à la restitution). Verrouille l'usager (R1) et le vélo (deux emprunts
-- simultanés du même vélo sont impossibles) ; les règles sont vérifiées par
-- les triggers de mouvement et de location.
CREATE PROCEDURE emprunter_velo(IN p_utilisateur INT UNSIGNED,
                                IN p_velo INT UNSIGNED,
                                IN p_avec_casque BOOLEAN,
                                OUT p_location INT UNSIGNED)
BEGIN
  DECLARE v_abonnement, v_verrou INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SELECT id_utilisateur INTO v_verrou FROM utilisateur
   WHERE id_utilisateur = p_utilisateur FOR UPDATE;
  SELECT id_velo INTO v_verrou FROM velo WHERE id_velo = p_velo FOR UPDATE;
  SET v_abonnement = fn_abonnement_valide(p_utilisateur, CURDATE());
  IF v_abonnement IS NULL THEN
    CALL lever_erreur('Aucun abonnement valide pour cet usager.');
  END IF;
  INSERT INTO mouvement (id_velo) VALUES (p_velo);
  SET p_location = LAST_INSERT_ID();
  INSERT INTO location (id_mouvement, avec_casque, id_abonnement)
  VALUES (p_location, COALESCE(p_avec_casque, FALSE), v_abonnement);
  COMMIT;
END$$

-- Arrivée d'un mouvement sur une borne (choisie automatiquement si
-- p_numero_borne est NULL). La station est verrouillée pour que deux
-- arrivées simultanées ne prennent pas la même borne. Sans transaction :
-- appelée par les procédures ci-dessous.
CREATE PROCEDURE enregistrer_arrivee(IN p_mouvement INT UNSIGNED,
                                     IN p_station INT UNSIGNED,
                                     IN p_numero_borne SMALLINT UNSIGNED)
BEGIN
  DECLARE v_verrou INT UNSIGNED;
  DECLARE v_numero SMALLINT UNSIGNED;
  SELECT id_station INTO v_verrou FROM station WHERE id_station = p_station FOR UPDATE;
  IF v_verrou IS NULL THEN
    CALL lever_erreur('Station inconnue.');
  ELSEIF (SELECT etat FROM station WHERE id_station = p_station) <> 'EN_SERVICE' THEN
    CALL lever_erreur('Cette station n''est pas en service.');
  END IF;
  SET v_numero = COALESCE(p_numero_borne, fn_borne_libre(p_station));
  IF v_numero IS NULL THEN
    CALL lever_erreur('Aucune borne libre dans cette station.');
  END IF;
  UPDATE mouvement
     SET date_heure_arrivee = NOW(), id_station_arrivee = p_station, numero_borne_arrivee = v_numero
   WHERE id_mouvement = p_mouvement;
END$$

-- Restituer un vélo (et le casque éventuel). La durée, le coût et la
-- facture sont calculés par trigger.
CREATE PROCEDURE restituer_velo(IN p_location INT UNSIGNED,
                                IN p_station INT UNSIGNED,
                                IN p_numero_borne SMALLINT UNSIGNED)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  IF NOT EXISTS (SELECT 1 FROM location WHERE id_mouvement = p_location) THEN
    CALL lever_erreur('Location inconnue.');
  END IF;
  CALL enregistrer_arrivee(p_location, p_station, p_numero_borne);
  COMMIT;
END$$

-- ---------------------------------------------------------------- régulation

-- Démarrer une tournée avec le véhicule choisi par l'opérateur (UC31).
CREATE PROCEDURE demarrer_tournee(IN p_operateur INT UNSIGNED, IN p_vehicule INT UNSIGNED,
                                  OUT p_tournee INT UNSIGNED)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  INSERT INTO tournee (date_heure_debut, id_utilisateur, id_vehicule)
  VALUES (NOW(), p_operateur, p_vehicule);
  SET p_tournee = LAST_INSERT_ID();
  COMMIT;
END$$

-- Charger un vélo dans le véhicule : le vélo quitte sa borne (transfert).
CREATE PROCEDURE charger_velo(IN p_tournee INT UNSIGNED, IN p_velo INT UNSIGNED,
                              OUT p_transfert INT UNSIGNED)
BEGIN
  DECLARE v_verrou INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SELECT id_velo INTO v_verrou FROM velo WHERE id_velo = p_velo FOR UPDATE;
  INSERT INTO mouvement (id_velo) VALUES (p_velo);
  SET p_transfert = LAST_INSERT_ID();
  INSERT INTO transfert (id_mouvement, id_tournee) VALUES (p_transfert, p_tournee);
  COMMIT;
END$$

-- Déposer un vélo chargé sur une borne (p_numero_borne NULL = automatique).
CREATE PROCEDURE deposer_velo(IN p_transfert INT UNSIGNED, IN p_station INT UNSIGNED,
                              IN p_numero_borne SMALLINT UNSIGNED)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  IF NOT EXISTS (SELECT 1 FROM transfert WHERE id_mouvement = p_transfert) THEN
    CALL lever_erreur('Transfert inconnu.');
  END IF;
  CALL enregistrer_arrivee(p_transfert, p_station, p_numero_borne);
  COMMIT;
END$$

CREATE PROCEDURE cloturer_tournee(IN p_tournee INT UNSIGNED)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  UPDATE tournee SET date_heure_fin = NOW()
   WHERE id_tournee = p_tournee AND date_heure_fin IS NULL;
  IF ROW_COUNT() = 0 THEN
    CALL lever_erreur('Tournée inconnue ou déjà clôturée.');
  END IF;
  COMMIT;
END$$

-- ---------------------------------------------------------------- signalements

CREATE PROCEDURE signaler_velo(IN p_utilisateur INT UNSIGNED, IN p_velo INT UNSIGNED,
                               IN p_description VARCHAR(500), OUT p_signalement INT UNSIGNED)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  INSERT INTO signalement (date_heure_signalement, description, id_utilisateur)
  VALUES (NOW(), p_description, p_utilisateur);
  SET p_signalement = LAST_INSERT_ID();
  INSERT INTO signalement_velo (id_signalement, id_velo) VALUES (p_signalement, p_velo);
  COMMIT;
END$$

CREATE PROCEDURE signaler_station(IN p_utilisateur INT UNSIGNED, IN p_station INT UNSIGNED,
                                  IN p_description VARCHAR(500), OUT p_signalement INT UNSIGNED)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  INSERT INTO signalement (date_heure_signalement, description, id_utilisateur)
  VALUES (NOW(), p_description, p_utilisateur);
  SET p_signalement = LAST_INSERT_ID();
  INSERT INTO signalement_station (id_signalement, id_station) VALUES (p_signalement, p_station);
  COMMIT;
END$$

-- Clore un signalement sans intervention (problème inexistant ou résolu).
-- R20 : un vélo passé DEFECTUEUX par une fausse alerte redevient EN_SERVICE,
-- sauf s'il est en atelier ou qu'un autre signalement reste ouvert.
CREATE PROCEDURE cloturer_signalement(IN p_signalement INT UNSIGNED)
BEGIN
  DECLARE v_velo INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  UPDATE signalement SET date_heure_cloture = NOW()
   WHERE id_signalement = p_signalement AND date_heure_cloture IS NULL;
  IF ROW_COUNT() = 0 THEN
    CALL lever_erreur('Signalement inconnu ou déjà clos.');
  END IF;
  SET v_velo = (SELECT id_velo FROM signalement_velo WHERE id_signalement = p_signalement);
  IF v_velo IS NOT NULL
     AND fn_etat_velo(v_velo) = 'DEFECTUEUX'
     AND NOT EXISTS (SELECT 1 FROM mouvement m
                       JOIN intervention_velo iv ON iv.id_mouvement = m.id_mouvement
                      WHERE m.id_velo = v_velo AND m.date_heure_arrivee IS NULL)
     AND NOT EXISTS (SELECT 1 FROM signalement_velo sv
                       JOIN signalement s ON s.id_signalement = sv.id_signalement
                      WHERE sv.id_velo = v_velo AND s.date_heure_cloture IS NULL) THEN
    INSERT INTO changement_etat (date_heure_changement, etat, id_velo)
    VALUES (NOW(), 'EN_SERVICE', v_velo);
  END IF;
  COMMIT;
END$$

-- ---------------------------------------------------------------- maintenance

-- Retirer un vélo pour maintenance : intervention + mouvement vers l'atelier.
-- Les triggers passent le vélo DEFECTUEUX et rattachent ses signalements.
CREATE PROCEDURE retirer_velo(IN p_operateur INT UNSIGNED, IN p_velo INT UNSIGNED,
                              IN p_description VARCHAR(500), OUT p_intervention INT UNSIGNED)
BEGIN
  DECLARE v_mouvement, v_verrou INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SELECT id_velo INTO v_verrou FROM velo WHERE id_velo = p_velo FOR UPDATE;
  INSERT INTO intervention (description, id_utilisateur) VALUES (p_description, p_operateur);
  SET p_intervention = LAST_INSERT_ID();
  INSERT INTO mouvement (id_velo) VALUES (p_velo);
  SET v_mouvement = LAST_INSERT_ID();
  INSERT INTO intervention_velo (id_intervention, id_mouvement) VALUES (p_intervention, v_mouvement);
  COMMIT;
END$$

-- Remettre en circulation : le vélo revient sur une borne ; les triggers le
-- repassent EN_SERVICE et closent les signalements traités.
CREATE PROCEDURE remettre_en_circulation(IN p_intervention INT UNSIGNED,
                                         IN p_station INT UNSIGNED,
                                         IN p_numero_borne SMALLINT UNSIGNED)
BEGIN
  DECLARE v_mouvement INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SET v_mouvement = (SELECT id_mouvement FROM intervention_velo WHERE id_intervention = p_intervention);
  IF v_mouvement IS NULL THEN
    CALL lever_erreur('Intervention sur vélo inconnue.');
  END IF;
  CALL enregistrer_arrivee(v_mouvement, p_station, p_numero_borne);
  COMMIT;
END$$

-- Réformer : le vélo arrive à l'atelier sans borne ; les triggers le
-- passent REFORME et closent les signalements traités.
CREATE PROCEDURE reformer_velo(IN p_intervention INT UNSIGNED)
BEGIN
  DECLARE v_mouvement INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SET v_mouvement = (SELECT id_mouvement FROM intervention_velo WHERE id_intervention = p_intervention);
  IF v_mouvement IS NULL THEN
    CALL lever_erreur('Intervention sur vélo inconnue.');
  END IF;
  UPDATE mouvement SET date_heure_arrivee = NOW() WHERE id_mouvement = v_mouvement;
  COMMIT;
END$$

CREATE PROCEDURE demarrer_intervention_station(IN p_operateur INT UNSIGNED,
                                               IN p_signalement INT UNSIGNED,
                                               IN p_description VARCHAR(500),
                                               OUT p_intervention INT UNSIGNED)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  INSERT INTO intervention (description, id_utilisateur) VALUES (p_description, p_operateur);
  SET p_intervention = LAST_INSERT_ID();
  INSERT INTO intervention_station (id_intervention, date_heure_debut, id_signalement_station)
  VALUES (p_intervention, NOW(), p_signalement);
  COMMIT;
END$$

-- Terminer une intervention sur station ; p_resolu clôt aussi le signalement
-- (sinon une autre intervention pourra suivre).
CREATE PROCEDURE terminer_intervention_station(IN p_intervention INT UNSIGNED,
                                               IN p_resolu BOOLEAN)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  UPDATE intervention_station SET date_heure_fin = NOW()
   WHERE id_intervention = p_intervention AND date_heure_fin IS NULL;
  IF ROW_COUNT() = 0 THEN
    CALL lever_erreur('Intervention sur station inconnue ou déjà terminée.');
  END IF;
  IF p_resolu THEN
    UPDATE signalement s
      JOIN intervention_station i ON i.id_signalement_station = s.id_signalement
       SET s.date_heure_cloture = NOW()
     WHERE i.id_intervention = p_intervention AND s.date_heure_cloture IS NULL;
  END IF;
  COMMIT;
END$$

DELIMITER ;


-- =============================================================================
--  5. Vues
-- =============================================================================

-- ---------------------------------------------------------------- flotte

-- État actuel de chaque vélo (dernier changement d'état).
CREATE VIEW v_etat_actuel_velo AS
SELECT id_velo, etat, date_heure_changement AS etat_depuis
  FROM (SELECT id_velo, etat, date_heure_changement,
               ROW_NUMBER() OVER (PARTITION BY id_velo
                                  ORDER BY date_heure_changement DESC, id_changement DESC) AS rang
          FROM changement_etat) e
 WHERE rang = 1;

-- Fiche de chaque vélo : type, batterie, état et situation actuelle
-- (sur une borne, en location, en tournée, en atelier ou réformé).
CREATE VIEW v_velo AS
SELECT v.id_velo,
       IF(ve.id_velo IS NULL, 'MECANIQUE', 'ELECTRIQUE') AS type_velo,
       ve.niveau_batterie,
       e.etat,
       e.etat_depuis,
       CASE
         WHEN e.etat = 'REFORME'             THEN 'REFORME'
         WHEN v.id_station IS NOT NULL       THEN 'SUR_BORNE'
         WHEN l.id_mouvement IS NOT NULL     THEN 'EN_LOCATION'
         WHEN t.id_mouvement IS NOT NULL     THEN 'EN_TOURNEE'
         WHEN iv.id_mouvement IS NOT NULL    THEN 'EN_ATELIER'
         ELSE 'INCONNUE'
       END AS situation,
       v.id_station,
       s.nom AS station,
       v.numero_borne,
       mc.id_mouvement AS id_mouvement_en_cours,
       v.date_mise_service
  FROM velo v
  LEFT JOIN velo_electrique ve    ON ve.id_velo = v.id_velo
  LEFT JOIN v_etat_actuel_velo e  ON e.id_velo = v.id_velo
  LEFT JOIN station s             ON s.id_station = v.id_station
  LEFT JOIN mouvement mc          ON mc.id_velo = v.id_velo AND mc.date_heure_arrivee IS NULL
  LEFT JOIN location l            ON l.id_mouvement = mc.id_mouvement
  LEFT JOIN transfert t           ON t.id_mouvement = mc.id_mouvement
  LEFT JOIN intervention_velo iv  ON iv.id_mouvement = mc.id_mouvement;

-- ---------------------------------------------------------------- stations (temps réel)

-- Vélos disponibles par type et bornes libres dans chaque station.
-- Disponible = sur une borne, EN_SERVICE, dans une station EN_SERVICE.
CREATE VIEW v_disponibilite_station AS
SELECT s.id_station,
       s.nom,
       s.etat,
       COUNT(b.numero) AS nb_bornes,
       COALESCE(SUM(b.etat = 'EN_SERVICE'), 0) AS bornes_en_service,
       COUNT(v.id_velo) AS velos_presents,
       COALESCE(SUM(s.etat = 'EN_SERVICE' AND e.etat = 'EN_SERVICE' AND ve.id_velo IS NULL), 0)
         AS velos_mecaniques_disponibles,
       COALESCE(SUM(s.etat = 'EN_SERVICE' AND e.etat = 'EN_SERVICE' AND ve.id_velo IS NOT NULL), 0)
         AS velos_electriques_disponibles,
       COALESCE(SUM(s.etat = 'EN_SERVICE' AND b.etat = 'EN_SERVICE' AND v.id_velo IS NULL), 0)
         AS bornes_libres,
       ROUND(100 * COUNT(v.id_velo) / NULLIF(SUM(b.etat = 'EN_SERVICE'), 0), 1)
         AS taux_remplissage_pct
  FROM station s
  LEFT JOIN borne b               ON b.id_station = s.id_station
  LEFT JOIN velo v                ON v.id_station = b.id_station AND v.numero_borne = b.numero
  LEFT JOIN velo_electrique ve    ON ve.id_velo = v.id_velo
  LEFT JOIN v_etat_actuel_velo e  ON e.id_velo = v.id_velo
 GROUP BY s.id_station, s.nom, s.etat;

-- Stations pleines ou vides (stations en service). ecart_equilibre : vélos
-- en trop (> 0) ou manquants (< 0) par rapport à une station à moitié pleine.
CREATE VIEW v_regulation AS
SELECT d.id_station,
       d.nom,
       d.bornes_en_service,
       d.velos_presents,
       d.velos_mecaniques_disponibles + d.velos_electriques_disponibles AS velos_disponibles,
       d.bornes_libres,
       d.taux_remplissage_pct,
       d.velos_presents - ROUND(d.bornes_en_service / 2) AS ecart_equilibre,
       CASE
         WHEN d.velos_mecaniques_disponibles + d.velos_electriques_disponibles = 0 THEN 'VIDE'
         WHEN d.bornes_libres = 0               THEN 'PLEINE'
         WHEN d.taux_remplissage_pct <= 20      THEN 'PRESQUE_VIDE'
         WHEN d.taux_remplissage_pct >= 80      THEN 'PRESQUE_PLEINE'
         ELSE 'EQUILIBREE'
       END AS statut
  FROM v_disponibilite_station d
 WHERE d.etat = 'EN_SERVICE';

-- Proposition de déplacements : chaque station pleine ou presque pleine
-- envoie ses vélos en trop vers la station vide ou presque vide la plus
-- proche (distance à vol d'oiseau).
CREATE VIEW v_proposition_deplacement AS
SELECT id_station_source, station_source, id_station_destination, station_destination,
       nb_velos_a_deplacer, distance_km
  FROM (SELECT src.id_station AS id_station_source,
               src.nom        AS station_source,
               dst.id_station AS id_station_destination,
               dst.nom        AS station_destination,
               LEAST(src.ecart_equilibre, -dst.ecart_equilibre) AS nb_velos_a_deplacer,
               ROUND(ST_Distance_Sphere(POINT(ss.longitude, ss.latitude),
                                        POINT(sd.longitude, sd.latitude)) / 1000, 2) AS distance_km,
               ROW_NUMBER() OVER (PARTITION BY src.id_station
                                  ORDER BY ST_Distance_Sphere(POINT(ss.longitude, ss.latitude),
                                                              POINT(sd.longitude, sd.latitude))) AS rang
          FROM v_regulation src
          JOIN v_regulation dst ON dst.statut IN ('VIDE', 'PRESQUE_VIDE') AND dst.ecart_equilibre < 0
          JOIN station ss ON ss.id_station = src.id_station
          JOIN station sd ON sd.id_station = dst.id_station
         WHERE src.statut IN ('PLEINE', 'PRESQUE_PLEINE') AND src.ecart_equilibre > 0) p
 WHERE rang = 1;

-- ---------------------------------------------------------------- consultation

-- Locations avec durée, statut et montant (coût actuel pour une location en cours).
CREATE VIEW v_location AS
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

-- Abonnements et leur statut (l'expiration se déduit de date_fin).
CREATE VIEW v_abonnement AS
SELECT a.id_abonnement,
       a.id_utilisateur,
       CONCAT(u.prenom, ' ', u.nom) AS usager,
       f.libelle AS formule,
       a.date_debut,
       a.date_fin,
       CASE
         WHEN CURDATE() < a.date_debut THEN 'A_VENIR'
         WHEN CURDATE() > a.date_fin   THEN 'EXPIRE'
         ELSE 'ACTIF'
       END AS statut,
       GREATEST(DATEDIFF(a.date_fin, GREATEST(CURDATE(), a.date_debut)) + 1, 0) AS jours_restants,
       a.id_abonnement_precedent,
       r.id_abonnement AS id_renouvellement
  FROM abonnement a
  JOIN utilisateur u      ON u.id_utilisateur = a.id_utilisateur
  JOIN formule f          ON f.id_formule = a.id_formule
  LEFT JOIN abonnement r  ON r.id_abonnement_precedent = a.id_abonnement;

-- Signalements avec leur cible et leur statut de traitement.
CREATE VIEW v_signalement AS
SELECT s.id_signalement,
       IF(sv.id_signalement IS NOT NULL, 'VELO', 'STATION') AS cible,
       sv.id_velo,
       ss.id_station,
       st.nom AS station,
       s.description,
       s.date_heure_signalement,
       s.date_heure_cloture,
       CASE
         WHEN s.date_heure_cloture IS NOT NULL THEN 'CLOS'
         WHEN sv.id_intervention_velo IS NOT NULL
           OR EXISTS (SELECT 1 FROM intervention_station i
                       WHERE i.id_signalement_station = s.id_signalement
                         AND i.date_heure_fin IS NULL) THEN 'EN_TRAITEMENT'
         ELSE 'OUVERT'
       END AS statut,
       sv.id_intervention_velo,
       s.id_utilisateur,
       CONCAT(u.prenom, ' ', u.nom) AS auteur
  FROM signalement s
  JOIN utilisateur u              ON u.id_utilisateur = s.id_utilisateur
  LEFT JOIN signalement_velo sv   ON sv.id_signalement = s.id_signalement
  LEFT JOIN signalement_station ss ON ss.id_signalement = s.id_signalement
  LEFT JOIN station st            ON st.id_station = ss.id_station;

-- ---------------------------------------------------------------- statistiques

-- Nombre de trajets (locations) par jour et durée moyenne.
CREATE VIEW v_stat_trajets_par_jour AS
SELECT DATE(m.date_heure_depart) AS jour,
       COUNT(*) AS nb_trajets,
       ROUND(AVG(fn_duree_minutes(m.date_heure_depart, m.date_heure_arrivee)), 1) AS duree_moyenne_min
  FROM location l
  JOIN mouvement m ON m.id_mouvement = l.id_mouvement
 GROUP BY DATE(m.date_heure_depart);

-- Heures de pointe : départs de location par heure de la journée.
CREATE VIEW v_stat_heures_pointe AS
SELECT HOUR(m.date_heure_depart) AS heure,
       COUNT(*) AS nb_departs,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS part_pct
  FROM location l
  JOIN mouvement m ON m.id_mouvement = l.id_mouvement
 GROUP BY HOUR(m.date_heure_depart);

-- Trajets origine -> destination, du plus fréquent au moins fréquent (rang).
CREATE VIEW v_stat_origine_destination AS
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

-- Recettes par formule : abonnements + locations, facturé et encaissé.
CREATE VIEW v_stat_recettes_formule AS
SELECT f.id_formule,
       f.libelle AS formule,
       COUNT(r.id_facture) AS nb_factures,
       COALESCE(SUM(IF(r.origine = 'ABONNEMENT', r.montant, 0)), 0) AS recettes_abonnements,
       COALESCE(SUM(IF(r.origine = 'LOCATION', r.montant, 0)), 0)   AS recettes_locations,
       COALESCE(SUM(r.montant), 0) AS recettes_totales,
       COALESCE(SUM(IF(r.date_reglement IS NOT NULL, r.montant, 0)), 0) AS montant_encaisse
  FROM formule f
  LEFT JOIN (SELECT fa.id_facture, fa.montant, fa.date_reglement, a.id_formule,
                    'ABONNEMENT' AS origine
               FROM facture fa
               JOIN abonnement a ON a.id_abonnement = fa.id_abonnement
             UNION ALL
             SELECT fa.id_facture, fa.montant, fa.date_reglement, a.id_formule,
                    'LOCATION'
               FROM facture fa
               JOIN location l   ON l.id_mouvement = fa.id_location
               JOIN abonnement a ON a.id_abonnement = l.id_abonnement) r
         ON r.id_formule = f.id_formule
 GROUP BY f.id_formule, f.libelle;

-- Indisponibilité de la flotte, par type et au total (ligne 'TOUS') :
-- situation actuelle et part du temps passé DEFECTUEUX sur 30 jours
-- (les vélos réformés sortent de la flotte).
CREATE VIEW v_stat_indisponibilite_flotte AS
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

-- Taux de remplissage moyen des stations par tranche horaire, sur les 30
-- derniers jours. Reconstitué depuis l'historique : un vélo occupe une
-- station de son arrivée à son départ suivant. Mesure à la demi-heure de
-- chaque tranche ; base = bornes actuellement en service.
CREATE VIEW v_stat_remplissage_horaire AS
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
