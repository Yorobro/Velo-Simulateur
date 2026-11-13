-- =============================================================================
--  Réseau de vélos en libre-service — STRUCTURE DE LA BASE
-- =============================================================================
--  Traduction en SQL du MLD (mld.md), lui-même issu du MCD (mcd.mmd).
--  SGBD cible : MySQL 8.4 LTS et MySQL 9.x (testé sur MySQL 9.0).
--  Moteur InnoDB, jeu de caractères utf8mb4.
--
--  Ce script ne contient que la structure et les contraintes déclaratives :
--  clés primaires et étrangères, NOT NULL, UNIQUE, CHECK, types ENUM.
--  Les règles qui portent sur plusieurs tables (triggers) et les index
--  d'optimisation viendront plus tard ; elles sont listées à la fin du fichier.
--
--  Conventions :
--    - noms de tables et de colonnes en minuscules (portable Windows / Linux) ;
--    - pk_ / fk_ / uq_ / ck_ : préfixes des noms de contraintes ;
--    - énumérations du MCD -> type ENUM (refusé hors liste en mode strict,
--      mode par défaut de MySQL 8 et 9) ;
--    - clé étrangère sans action : la suppression d'une ligne référencée est
--      refusée (historique protégé). ON DELETE CASCADE n'est utilisé que pour
--      les sous-classes (une ligne fille n'existe pas sans sa ligne mère) et
--      pour les bornes d'une station.
--
--  Remarque MySQL : une colonne utilisée dans un CHECK ne peut pas porter
--  d'action ON DELETE / ON UPDATE. Les clés étrangères concernées (facture,
--  vélo, mouvement) restent donc sans action.
-- =============================================================================

-- Attention : recrée la base de zéro (toutes les données sont supprimées).
DROP DATABASE IF EXISTS velo_libre_service;
CREATE DATABASE velo_libre_service
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE velo_libre_service;


-- =============================================================================
--  1. Utilisateurs, formules, abonnements
-- =============================================================================

CREATE TABLE utilisateur (
  id_utilisateur     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  nom                VARCHAR(50)   NOT NULL,
  prenom             VARCHAR(50)   NOT NULL,
  email              VARCHAR(254)  NOT NULL,
  mot_de_passe_hash  VARCHAR(255)  NOT NULL,
  telephone          VARCHAR(16)   NOT NULL,
  date_inscription   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  role               ENUM('USAGER', 'OPERATEUR_REGULATION',
                          'OPERATEUR_MAINTENANCE', 'ADMINISTRATEUR')
                                   NOT NULL DEFAULT 'USAGER',
  CONSTRAINT pk_utilisateur PRIMARY KEY (id_utilisateur),
  -- une adresse e-mail = un compte (comparaison insensible à la casse)
  CONSTRAINT uq_utilisateur_email UNIQUE (email),
  CONSTRAINT ck_utilisateur_nom    CHECK (CHAR_LENGTH(TRIM(nom)) > 0),
  CONSTRAINT ck_utilisateur_prenom CHECK (CHAR_LENGTH(TRIM(prenom)) > 0),
  CONSTRAINT ck_utilisateur_email
    CHECK (email REGEXP '^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$'),
  -- jamais de mot de passe en clair : on attend une empreinte (bcrypt = 60 car.)
  CONSTRAINT ck_utilisateur_mdp    CHECK (CHAR_LENGTH(mot_de_passe_hash) >= 60),
  -- chiffres uniquement, avec + facultatif pour l'indicatif international
  CONSTRAINT ck_utilisateur_telephone CHECK (telephone REGEXP '^\\+?[0-9]{10,15}$')
) ENGINE = InnoDB
  COMMENT = 'Comptes : usagers, opérateurs (régulation, maintenance), administrateurs';


CREATE TABLE formule (
  id_formule             INT UNSIGNED       NOT NULL AUTO_INCREMENT,
  libelle                VARCHAR(50)        NOT NULL,
  prix                   DECIMAL(7,2)       NOT NULL,
  duree_validite_jours   SMALLINT UNSIGNED  NOT NULL,
  duree_gratuite_min     SMALLINT UNSIGNED  NOT NULL,
  duree_tranche_min      SMALLINT UNSIGNED  NOT NULL,
  prix_tranche           DECIMAL(5,2)       NOT NULL,
  supplement_electrique  DECIMAL(5,2)       NOT NULL DEFAULT 0.00,
  supplement_casque      DECIMAL(5,2)       NOT NULL DEFAULT 0.00,
  CONSTRAINT pk_formule PRIMARY KEY (id_formule),
  -- les formules du sujet (ticket journée, mensuel, annuel, tarif réduit) sont
  -- des lignes de la table : leur libellé est une clé candidate
  CONSTRAINT uq_formule_libelle         UNIQUE (libelle),
  CONSTRAINT ck_formule_libelle         CHECK (CHAR_LENGTH(TRIM(libelle)) > 0),
  CONSTRAINT ck_formule_prix            CHECK (prix >= 0),
  CONSTRAINT ck_formule_validite        CHECK (duree_validite_jours > 0),
  -- duree_gratuite_min peut valoir 0 (aucune minute offerte) : UNSIGNED suffit
  CONSTRAINT ck_formule_tranche         CHECK (duree_tranche_min > 0),
  CONSTRAINT ck_formule_prix_tranche    CHECK (prix_tranche >= 0),
  CONSTRAINT ck_formule_supp_electrique CHECK (supplement_electrique >= 0),
  CONSTRAINT ck_formule_supp_casque     CHECK (supplement_casque >= 0)
) ENGINE = InnoDB
  COMMENT = 'Formules tarifaires et leurs conditions';


CREATE TABLE abonnement (
  id_abonnement            INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  date_debut               DATE          NOT NULL,
  date_fin                 DATE          NOT NULL,
  id_utilisateur           INT UNSIGNED  NOT NULL,
  id_formule               INT UNSIGNED  NOT NULL,
  id_abonnement_precedent  INT UNSIGNED  NULL,
  CONSTRAINT pk_abonnement PRIMARY KEY (id_abonnement),
  -- un abonnement est renouvelé au plus une fois. (Qu'il ne se renouvelle pas
  -- lui-même est vérifié par trigger : MySQL refuse un CHECK sur une colonne
  -- AUTO_INCREMENT.)
  CONSTRAINT uq_abonnement_precedent UNIQUE (id_abonnement_precedent),
  CONSTRAINT ck_abonnement_dates CHECK (date_fin >= date_debut),
  CONSTRAINT fk_abonnement_utilisateur FOREIGN KEY (id_utilisateur)
    REFERENCES utilisateur (id_utilisateur),
  CONSTRAINT fk_abonnement_formule FOREIGN KEY (id_formule)
    REFERENCES formule (id_formule),
  CONSTRAINT fk_abonnement_precedent FOREIGN KEY (id_abonnement_precedent)
    REFERENCES abonnement (id_abonnement)
) ENGINE = InnoDB
  COMMENT = 'Souscriptions ; expiré dès que date_fin est passée';


-- =============================================================================
--  2. Réseau : stations et bornes
-- =============================================================================

CREATE TABLE station (
  id_station   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  nom          VARCHAR(100)  NOT NULL,
  adresse      VARCHAR(255)  NOT NULL,
  code_postal  CHAR(5)       NOT NULL,
  latitude     DECIMAL(8,6)  NOT NULL,
  longitude    DECIMAL(9,6)  NOT NULL,
  etat         ENUM('EN_SERVICE', 'HORS_SERVICE', 'EN_TRAVAUX')
                             NOT NULL DEFAULT 'EN_SERVICE',
  CONSTRAINT pk_station PRIMARY KEY (id_station),
  CONSTRAINT uq_station_adresse     UNIQUE (adresse, code_postal),
  CONSTRAINT uq_station_coordonnees UNIQUE (latitude, longitude),
  CONSTRAINT ck_station_nom         CHECK (CHAR_LENGTH(TRIM(nom)) > 0),
  CONSTRAINT ck_station_code_postal CHECK (code_postal REGEXP '^[0-9]{5}$'),
  CONSTRAINT ck_station_latitude    CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT ck_station_longitude   CHECK (longitude BETWEEN -180 AND 180)
) ENGINE = InnoDB
  COMMENT = 'Stations ; le nombre de bornes se calcule (COUNT sur borne)';


CREATE TABLE borne (
  id_station  INT UNSIGNED       NOT NULL,
  numero      SMALLINT UNSIGNED  NOT NULL,
  etat        ENUM('EN_SERVICE', 'HORS_SERVICE') NOT NULL DEFAULT 'EN_SERVICE',
  -- identifiant relatif : le numéro n'est unique que dans sa station
  CONSTRAINT pk_borne PRIMARY KEY (id_station, numero),
  CONSTRAINT ck_borne_numero CHECK (numero > 0),
  CONSTRAINT fk_borne_station FOREIGN KEY (id_station)
    REFERENCES station (id_station) ON DELETE CASCADE
) ENGINE = InnoDB
  COMMENT = 'Points d''attache d''une station';


-- =============================================================================
--  3. Flotte : vélos, états, mouvements
-- =============================================================================

CREATE TABLE velo (
  id_velo            INT UNSIGNED       NOT NULL AUTO_INCREMENT,
  date_mise_service  DATETIME           NOT NULL,
  -- position actuelle : NULL = en location, en atelier, en tournée ou réformé
  id_station         INT UNSIGNED       NULL,
  numero_borne       SMALLINT UNSIGNED  NULL,
  CONSTRAINT pk_velo PRIMARY KEY (id_velo),
  -- une borne accueille au plus un vélo (le sujet l'impose)
  CONSTRAINT uq_velo_borne UNIQUE (id_station, numero_borne),
  -- une position est complète (station ET borne) ou absente
  CONSTRAINT ck_velo_position
    CHECK ((id_station IS NULL) = (numero_borne IS NULL)),
  CONSTRAINT fk_velo_borne FOREIGN KEY (id_station, numero_borne)
    REFERENCES borne (id_station, numero)
) ENGINE = InnoDB
  COMMENT = 'Vélos (mécaniques ; électriques si une ligne existe dans velo_electrique)';


CREATE TABLE velo_electrique (
  id_velo          INT UNSIGNED      NOT NULL,
  niveau_batterie  TINYINT UNSIGNED  NOT NULL,
  CONSTRAINT pk_velo_electrique PRIMARY KEY (id_velo),
  CONSTRAINT ck_velo_electrique_batterie CHECK (niveau_batterie BETWEEN 0 AND 100),
  CONSTRAINT fk_velo_electrique_velo FOREIGN KEY (id_velo)
    REFERENCES velo (id_velo) ON DELETE CASCADE
) ENGINE = InnoDB
  COMMENT = 'Sous-classe de velo : niveau de batterie en %';


CREATE TABLE changement_etat (
  id_changement          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  date_heure_changement  DATETIME      NOT NULL,
  etat                   ENUM('EN_SERVICE', 'DEFECTUEUX', 'REFORME') NOT NULL,
  id_velo                INT UNSIGNED  NOT NULL,
  CONSTRAINT pk_changement_etat PRIMARY KEY (id_changement),
  -- un vélo ne change pas deux fois d'état au même instant
  CONSTRAINT uq_changement_etat UNIQUE (id_velo, date_heure_changement),
  CONSTRAINT fk_changement_etat_velo FOREIGN KEY (id_velo)
    REFERENCES velo (id_velo)
) ENGINE = InnoDB
  COMMENT = 'Historique des états ; état actuel = dernier changement';


CREATE TABLE vehicule (
  id_vehicule      INT UNSIGNED      NOT NULL AUTO_INCREMENT,
  immatriculation  VARCHAR(10)       NOT NULL,
  capacite         TINYINT UNSIGNED  NOT NULL,
  CONSTRAINT pk_vehicule PRIMARY KEY (id_vehicule),
  CONSTRAINT uq_vehicule_immatriculation UNIQUE (immatriculation),
  CONSTRAINT ck_vehicule_immatriculation CHECK (CHAR_LENGTH(TRIM(immatriculation)) > 0),
  -- nombre de vélos que le véhicule peut transporter à la fois
  CONSTRAINT ck_vehicule_capacite CHECK (capacite > 0)
) ENGINE = InnoDB
  COMMENT = 'Véhicules de régulation utilisés pour les tournées';


CREATE TABLE tournee (
  id_tournee        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  date_heure_debut  DATETIME      NOT NULL,
  date_heure_fin    DATETIME      NULL,
  id_utilisateur    INT UNSIGNED  NOT NULL,
  id_vehicule       INT UNSIGNED  NOT NULL,
  CONSTRAINT pk_tournee PRIMARY KEY (id_tournee),
  CONSTRAINT ck_tournee_dates
    CHECK (date_heure_fin IS NULL OR date_heure_fin > date_heure_debut),
  CONSTRAINT fk_tournee_utilisateur FOREIGN KEY (id_utilisateur)
    REFERENCES utilisateur (id_utilisateur),
  CONSTRAINT fk_tournee_vehicule FOREIGN KEY (id_vehicule)
    REFERENCES vehicule (id_vehicule)
) ENGINE = InnoDB
  COMMENT = 'Tournées de rééquilibrage (date_heure_fin NULL = en cours)';


CREATE TABLE mouvement (
  id_mouvement          INT UNSIGNED       NOT NULL AUTO_INCREMENT,
  date_heure_depart     DATETIME           NOT NULL,
  date_heure_arrivee    DATETIME           NULL,
  id_velo               INT UNSIGNED       NOT NULL,
  id_station_depart     INT UNSIGNED       NOT NULL,
  numero_borne_depart   SMALLINT UNSIGNED  NOT NULL,
  id_station_arrivee    INT UNSIGNED       NULL,
  numero_borne_arrivee  SMALLINT UNSIGNED  NULL,
  CONSTRAINT pk_mouvement PRIMARY KEY (id_mouvement),
  CONSTRAINT ck_mouvement_dates
    CHECK (date_heure_arrivee IS NULL OR date_heure_arrivee > date_heure_depart),
  -- borne d'arrivée complète (station ET numéro) ou absente
  CONSTRAINT ck_mouvement_borne_arrivee
    CHECK ((id_station_arrivee IS NULL) = (numero_borne_arrivee IS NULL)),
  -- on ne peut pas être arrivé sur une borne sans date d'arrivée.
  -- (L'inverse n'est pas imposé : un vélo réformé en atelier a une date
  -- d'arrivée mais pas de borne.)
  CONSTRAINT ck_mouvement_arrivee
    CHECK (id_station_arrivee IS NULL OR date_heure_arrivee IS NOT NULL),
  CONSTRAINT fk_mouvement_velo FOREIGN KEY (id_velo)
    REFERENCES velo (id_velo),
  CONSTRAINT fk_mouvement_borne_depart FOREIGN KEY (id_station_depart, numero_borne_depart)
    REFERENCES borne (id_station, numero),
  CONSTRAINT fk_mouvement_borne_arrivee FOREIGN KEY (id_station_arrivee, numero_borne_arrivee)
    REFERENCES borne (id_station, numero)
) ENGINE = InnoDB
  COMMENT = 'Déplacements des vélos : location, transfert ou maintenance';


CREATE TABLE location (
  id_mouvement   INT UNSIGNED  NOT NULL,
  -- casque récupéré à l'emprunt (supplément casque de la formule)
  avec_casque    BOOLEAN       NOT NULL DEFAULT FALSE,
  id_abonnement  INT UNSIGNED  NOT NULL,
  CONSTRAINT pk_location PRIMARY KEY (id_mouvement),
  CONSTRAINT fk_location_mouvement FOREIGN KEY (id_mouvement)
    REFERENCES mouvement (id_mouvement) ON DELETE CASCADE,
  CONSTRAINT fk_location_abonnement FOREIGN KEY (id_abonnement)
    REFERENCES abonnement (id_abonnement)
) ENGINE = InnoDB
  COMMENT = 'Sous-classe de mouvement : emprunt par un usager';


CREATE TABLE transfert (
  id_mouvement  INT UNSIGNED  NOT NULL,
  id_tournee    INT UNSIGNED  NOT NULL,
  CONSTRAINT pk_transfert PRIMARY KEY (id_mouvement),
  CONSTRAINT fk_transfert_mouvement FOREIGN KEY (id_mouvement)
    REFERENCES mouvement (id_mouvement) ON DELETE CASCADE,
  CONSTRAINT fk_transfert_tournee FOREIGN KEY (id_tournee)
    REFERENCES tournee (id_tournee)
) ENGINE = InnoDB
  COMMENT = 'Sous-classe de mouvement : vélo déplacé pendant une tournée';


-- =============================================================================
--  4. Facturation
-- =============================================================================

CREATE TABLE facture (
  id_facture      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  date_emission   DATETIME      NOT NULL,
  montant         DECIMAL(8,2)  NOT NULL,
  date_reglement  DATETIME      NULL,
  id_abonnement   INT UNSIGNED  NULL,
  id_location     INT UNSIGNED  NULL,
  CONSTRAINT pk_facture PRIMARY KEY (id_facture),
  -- un abonnement ou une location est facturé au plus une fois
  CONSTRAINT uq_facture_abonnement UNIQUE (id_abonnement),
  CONSTRAINT uq_facture_location   UNIQUE (id_location),
  -- une facture porte sur exactement une cible : un abonnement OU une location
  CONSTRAINT ck_facture_cible
    CHECK ((id_abonnement IS NULL) <> (id_location IS NULL)),
  CONSTRAINT ck_facture_montant CHECK (montant >= 0),
  CONSTRAINT ck_facture_reglement
    CHECK (date_reglement IS NULL OR date_reglement >= date_emission),
  -- une facture à 0 € n'est pas à payer (on ne paie que si montant > 0)
  CONSTRAINT ck_facture_paiement
    CHECK (date_reglement IS NULL OR montant > 0),
  CONSTRAINT fk_facture_abonnement FOREIGN KEY (id_abonnement)
    REFERENCES abonnement (id_abonnement),
  CONSTRAINT fk_facture_location FOREIGN KEY (id_location)
    REFERENCES location (id_mouvement)
) ENGINE = InnoDB
  COMMENT = 'Factures ; date_reglement NULL = non réglée (ou rien à régler si montant = 0)';


-- =============================================================================
--  5. Interventions de maintenance et signalements
-- =============================================================================

CREATE TABLE intervention (
  id_intervention  INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  description      VARCHAR(500)  NOT NULL,
  id_utilisateur   INT UNSIGNED  NOT NULL,
  CONSTRAINT pk_intervention PRIMARY KEY (id_intervention),
  CONSTRAINT ck_intervention_description CHECK (CHAR_LENGTH(TRIM(description)) > 0),
  CONSTRAINT fk_intervention_utilisateur FOREIGN KEY (id_utilisateur)
    REFERENCES utilisateur (id_utilisateur)
) ENGINE = InnoDB
  COMMENT = 'Interventions de maintenance (sur un vélo ou une station)';


CREATE TABLE intervention_velo (
  id_intervention  INT UNSIGNED  NOT NULL,
  id_mouvement     INT UNSIGNED  NOT NULL,
  CONSTRAINT pk_intervention_velo PRIMARY KEY (id_intervention),
  -- un mouvement donne lieu à au plus une intervention
  CONSTRAINT uq_intervention_velo_mouvement UNIQUE (id_mouvement),
  CONSTRAINT fk_intervention_velo_intervention FOREIGN KEY (id_intervention)
    REFERENCES intervention (id_intervention) ON DELETE CASCADE,
  CONSTRAINT fk_intervention_velo_mouvement FOREIGN KEY (id_mouvement)
    REFERENCES mouvement (id_mouvement)
) ENGINE = InnoDB
  COMMENT = 'Sous-classe d''intervention : retrait, réparation, remise en circulation';


CREATE TABLE signalement (
  id_signalement          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  date_heure_signalement  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  description             VARCHAR(500)  NOT NULL,
  date_heure_cloture      DATETIME      NULL,
  id_utilisateur          INT UNSIGNED  NOT NULL,
  CONSTRAINT pk_signalement PRIMARY KEY (id_signalement),
  CONSTRAINT ck_signalement_description CHECK (CHAR_LENGTH(TRIM(description)) > 0),
  CONSTRAINT ck_signalement_dates
    CHECK (date_heure_cloture IS NULL OR date_heure_cloture >= date_heure_signalement),
  CONSTRAINT fk_signalement_utilisateur FOREIGN KEY (id_utilisateur)
    REFERENCES utilisateur (id_utilisateur)
) ENGINE = InnoDB
  COMMENT = 'Signalements (date_heure_cloture NULL = ouvert)';


CREATE TABLE signalement_velo (
  id_signalement        INT UNSIGNED  NOT NULL,
  id_velo               INT UNSIGNED  NOT NULL,
  id_intervention_velo  INT UNSIGNED  NULL,
  CONSTRAINT pk_signalement_velo PRIMARY KEY (id_signalement),
  CONSTRAINT fk_signalement_velo_signalement FOREIGN KEY (id_signalement)
    REFERENCES signalement (id_signalement) ON DELETE CASCADE,
  CONSTRAINT fk_signalement_velo_velo FOREIGN KEY (id_velo)
    REFERENCES velo (id_velo),
  CONSTRAINT fk_signalement_velo_intervention FOREIGN KEY (id_intervention_velo)
    REFERENCES intervention_velo (id_intervention)
) ENGINE = InnoDB
  COMMENT = 'Sous-classe de signalement : problème sur un vélo';


CREATE TABLE signalement_station (
  id_signalement  INT UNSIGNED  NOT NULL,
  id_station      INT UNSIGNED  NOT NULL,
  CONSTRAINT pk_signalement_station PRIMARY KEY (id_signalement),
  CONSTRAINT fk_signalement_station_signalement FOREIGN KEY (id_signalement)
    REFERENCES signalement (id_signalement) ON DELETE CASCADE,
  CONSTRAINT fk_signalement_station_station FOREIGN KEY (id_station)
    REFERENCES station (id_station)
) ENGINE = InnoDB
  COMMENT = 'Sous-classe de signalement : problème sur une station';


CREATE TABLE intervention_station (
  id_intervention         INT UNSIGNED  NOT NULL,
  date_heure_debut        DATETIME      NOT NULL,
  date_heure_fin          DATETIME      NULL,
  id_signalement_station  INT UNSIGNED  NOT NULL,
  CONSTRAINT pk_intervention_station PRIMARY KEY (id_intervention),
  CONSTRAINT ck_intervention_station_dates
    CHECK (date_heure_fin IS NULL OR date_heure_fin > date_heure_debut),
  CONSTRAINT fk_intervention_station_intervention FOREIGN KEY (id_intervention)
    REFERENCES intervention (id_intervention) ON DELETE CASCADE,
  CONSTRAINT fk_intervention_station_signalement FOREIGN KEY (id_signalement_station)
    REFERENCES signalement_station (id_signalement)
) ENGINE = InnoDB
  COMMENT = 'Sous-classe d''intervention : travaux sur une station (date_heure_fin NULL = en cours)';


-- =============================================================================
--  Règles du sujet et du MLD (V2/mld.md, § 4) qui ne peuvent pas s'écrire en
--  contrainte déclarative. Elles sont implémentées par les triggers et les
--  procédures de automatisation.sql ; les jeux de données (donnes.sql,
--  peuplement_velo.py) les respectent déjà.
-- =============================================================================
--  Locations
--    R1  un usager n'a qu'une location en cours à la fois ;
--    R2  il faut un abonnement valide (date_debut <= jour du départ <= date_fin),
--        appartenant à l'usager ;
--    R3  un vélo dont le dernier état est DEFECTUEUX ou REFORME ne peut pas
--        être emprunté ;
--    R4  durée et coût calculés à la restitution ; facture.montant = coût du
--        trajet (tranches au-delà de la durée gratuite + suppléments électrique
--        et casque).
--  Flotte
--    R5  un vélo n'est qu'à un seul endroit : velo.(id_station, numero_borne)
--        = borne d'arrivée de son dernier mouvement, NULL pendant un mouvement ;
--    R6  un vélo ne part que de la borne où il se trouve, et n'arrive que sur
--        une borne libre et EN_SERVICE d'une station EN_SERVICE ; une location
--        part d'une borne et d'une station en service ;
--    R7  un vélo n'a qu'un mouvement en cours à la fois.
--  Généralisations
--    R8  un mouvement est une location, un transfert OU le mouvement d'une
--        intervention sur vélo, jamais deux à la fois ;
--    R9  un signalement est dans signalement_velo OU signalement_station
--        (exactement une des deux) ;
--    R10 une intervention est dans intervention_velo OU intervention_station
--        (exactement une des deux).
--  Cohérence entre tables
--    R11 abonnement.date_fin = date_debut + formule.duree_validite_jours - 1 ;
--        un renouvellement appartient au même usager et commence après la fin
--        du précédent ;
--    R12 tournée effectuée par un OPERATEUR_REGULATION ou un ADMINISTRATEUR,
--        intervention par un OPERATEUR_MAINTENANCE ou un ADMINISTRATEUR ;
--        seul un USAGER s'abonne et émet un signalement ;
--    R13 un signalement de vélo et l'intervention qui le traite concernent le
--        même vélo (via intervention_velo -> mouvement) ;
--    R14 une intervention commence après le signalement qu'elle traite ;
--        les transferts d'une tournée ont lieu pendant la tournée.
--  Régulation
--    R15 les vélos chargés (transferts en cours) ne dépassent pas la capacité
--        du véhicule de la tournée ;
--    R16 un véhicule et un opérateur n'ont qu'une tournée en cours à la fois ;
--    R17 une tournée n'est clôturée qu'une fois tous ses vélos déposés.
--  Facturation, maintenance, historisation
--    R18 tout abonnement a sa facture (créée avec lui) ; toute location
--        terminée a sa facture, même à 0 € ;
--    R19 fin d'une intervention sur vélo : EN_SERVICE s'il revient sur une
--        borne, REFORME sinon ; les signalements traités sont clos ;
--    R20 mise en service -> premier état EN_SERVICE ; un signalement de vélo
--        le passe DEFECTUEUX ; un signalement clos sans intervention (fausse
--        alerte) le remet EN_SERVICE s'il n'en reste pas d'autre ouvert ;
--    R21 une station a au moins une borne.
--  Abonnements
--    R22 un usager n'a qu'un abonnement à la fois : les périodes
--        [date_debut, date_fin] de ses abonnements ne se chevauchent pas.
--        Renouveler reste possible (le renouvellement commence après la fin
--        du précédent) ; changer de formule programme le nouvel abonnement
--        au lendemain de la fin de l'actuel.
-- =============================================================================
