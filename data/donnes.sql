-- =============================================================================
--  Réseau de vélos en libre-service — DONNÉES DE TEST
-- =============================================================================
--  À exécuter après structure.sql. MySQL 8.4 LTS / 9.x.
--  Période simulée : septembre à novembre 2026 (dernières données : 4 novembre).
--  Les données respectent les règles du sujet, y compris celles qui seront
--  imposées plus tard par triggers (voir la fin de structure.sql) :
--  un vélo à un seul endroit, une borne = un vélo, une location à la fois,
--  abonnement valide, pas d'emprunt d'un vélo défectueux, montants calculés
--  selon la formule, rôles des opérateurs.
--
--  Mots de passe : les empreintes sont FICTIVES (format bcrypt, mais elles ne
--  correspondent à aucun mot de passe). Elles seront remplacées par de vraies
--  empreintes générées par l'interface.
-- =============================================================================

SET NAMES utf8mb4;
USE velo_libre_service;
START TRANSACTION;

-- -----------------------------------------------------------------------------
--  Utilisateurs (26) : 2 administrateurs, 3 opérateurs de régulation, 3 opérateurs de maintenance, 18 usagers
-- -----------------------------------------------------------------------------
INSERT INTO utilisateur (id_utilisateur, nom, prenom, email, mot_de_passe_hash, telephone, date_inscription, role) VALUES
  (1, 'Martin', 'Claire', 'claire.martin@velo.example.org', '$2y$12$AfJnWmLcy6vlvlMIJtCrY7tu6DMpv/SMYk/GmDmGJ9nay2KQpOwul', '0601282838', '2025-01-06 09:00:00', 'ADMINISTRATEUR'),
  (2, 'Bernard', 'Julien', 'julien.bernard@velo.example.org', '$2y$12$5Nj6ERDepm9KO4mLRQv9B3ySOGgOx091ESbDTxWtW6PYwq38D.jgw', '0701331109', '2025-01-06 09:15:00', 'ADMINISTRATEUR'),
  (3, 'Petit', 'Sophie', 'sophie.petit@velo.example.org', '$2y$12$q7qTXedhoIE4J9QK4dl3RUKOC0bN.9muGb1CyZUQD5cvoKqajNWXU', '0601379380', '2025-02-03 08:30:00', 'OPERATEUR_REGULATION'),
  (4, 'Benali', 'Karim', 'karim.benali@velo.example.org', '$2y$12$FTddtYo1RtStxGc7iz19Iub5Wmi2DbJzq03n4t.Z.rMZE.2YtJ55T', '0701427651', '2025-02-03 08:45:00', 'OPERATEUR_REGULATION'),
  (5, 'Moreau', 'Lucas', 'lucas.moreau@velo.example.org', '$2y$12$ImvcgujWH6mgKPHQMj3.JH0cho2Inf2MJnZxbDJkBJsifsWDR4zEW', '0601475922', '2025-09-01 08:30:00', 'OPERATEUR_REGULATION'),
  (6, 'Girard', 'Thomas', 'thomas.girard@velo.example.org', '$2y$12$Z6a9Ansxy4yN0qTyEPOKwz3jM6A349LuGVoVgwt0/HV6d28Iaf1u3', '0701524193', '2025-02-10 08:30:00', 'OPERATEUR_MAINTENANCE'),
  (7, 'Haddad', 'Nadia', 'nadia.haddad@velo.example.org', '$2y$12$U4W/skUjliUrZd9dR0VUZ3pVnnM8VW6l2c1LO3ha0zmvBnj8ozOuK', '0601572464', '2025-02-10 08:45:00', 'OPERATEUR_MAINTENANCE'),
  (8, 'Lambert', 'Hugo', 'hugo.lambert@velo.example.org', '$2y$12$UlP3dW65Q0JnX3lrV2OzK7yKE.AYvOw8Pn2dSDxdZj90Fc4Vq5IMx', '0701620735', '2025-09-01 09:00:00', 'OPERATEUR_MAINTENANCE'),
  (9, 'Laurent', 'Emma', 'emma.laurent@example.org', '$2y$12$KCxJjZxKsh.LAKOxPvCWEOKdAmWJjiOtgqe.uP3p9tJtB9wGk3DAg', '0601669006', '2026-01-13 19:27:00', 'USAGER'),
  (10, 'Fontaine', 'Léo', 'leo.fontaine@example.org', '$2y$12$TQT2efkrzZe5CN6mOKwpUlaSYBaMhyr0fYiIUIyEOKy30wkoDGrc1', '0701717277', '2026-08-29 19:20:00', 'USAGER'),
  (11, 'Rousseau', 'Chloé', 'chloe.rousseau@example.org', '$2y$12$f8EWYQ3bzFShHbK8uiGaso0/zzDcSjAQBc4fIuynIxv7WI.UQ.NzE', '0601765548', '2026-09-06 19:13:00', 'USAGER'),
  (12, 'Mercier', 'Nathan', 'nathan.mercier@example.org', '$2y$12$bGOksy.6EEp2ivZP0luWHWXqSk19pq16JgKtBqRf0nDbOePT5tKdS', '0701813819', '2025-10-31 19:06:00', 'USAGER'),
  (13, 'Garnier', 'Inès', 'ines.garnier@example.org', '$2y$12$Jtp90.Ky1kW5WUnqh87qoXsPUOo5T1QlPsOWCm5DE46xePDHW7jEc', '0601862090', '2026-10-01 18:59:00', 'USAGER'),
  (14, 'Faure', 'Louis', 'louis.faure@example.org', '$2y$12$PtfssL1Ub5bwjVIgNI7jy5KuOA76zGttJ0sqWcBjt5OW/ko/ePK.7', '0701910361', '2026-10-08 18:52:00', 'USAGER'),
  (15, 'Chevalier', 'Manon', 'manon.chevalier@example.org', '$2y$12$U3PKvg4/OrahZTJsZFCSyu5zGRTpKvw6JeefRM1pSkDlq6EKlh4kc', '0601958632', '2026-02-25 18:45:00', 'USAGER'),
  (16, 'Robin', 'Gabriel', 'gabriel.robin@example.org', '$2y$12$z1PLl866ihjVar68ND28LAD7wYVvu31TsdA6IozyG1sma8O7lzTwV', '0702006903', '2026-09-14 18:38:00', 'USAGER'),
  (17, 'Blanc', 'Léa', 'lea.blanc@example.org', '$2y$12$m/cERD8et16paB740ol9s.l7n0qVps/WWYyHFOqJXBb9eUS7zbYxA', '0602055174', '2026-10-10 18:31:00', 'USAGER'),
  (18, 'Guérin', 'Arthur', 'arthur.guerin@example.org', '$2y$12$q7gHtbGW3moQvIXRFKpJx9z.YjVWn55961Z74lYdHy4SVhSYIE2TM', '0702103445', '2026-10-15 18:24:00', 'USAGER'),
  (19, 'Muller', 'Jade', 'jade.muller@example.org', '$2y$12$7R79KjjSRq28chwJHJXs600VShB.OjIJNnVrs5Q41T5BgkEqPplhX', '0602151716', '2026-06-16 18:17:00', 'USAGER'),
  (20, 'Henry', 'Raphaël', 'raphael.henry@example.org', '$2y$12$CfanLZPTR/cya.217xbW/N98XyEBYkRI5xjFWoHYHk9uqIj6oE1vd', '0702199987', '2026-10-19 18:10:00', 'USAGER'),
  (21, 'Roux', 'Camille', 'camille.roux@example.org', '$2y$12$7z5o8GcVvbPchxOWLh7CRC.l.QPcJ9Rwt1avWV/2SfhSx6FVWUqaF', '0602248258', '2026-08-28 18:03:00', 'USAGER'),
  (22, 'Lefebvre', 'Adam', 'adam.lefebvre@example.org', '$2y$12$wiZI1xA.7SyLNkHBjPmtCygfOXzuTI7lMdcF7y.7FC06z9el65AI3', '0702296529', '2026-09-22 17:56:00', 'USAGER'),
  (23, 'Dupont', 'Sarah', 'sarah.dupont@example.org', '$2y$12$h6/OHxCC5Z7eaRP1WjeVrV6Qw0.t5F9mYDmCOts9owaxWTNzeb8On', '0602344800', '2026-10-29 17:49:00', 'USAGER'),
  (24, 'Perrin', 'Enzo', 'enzo.perrin@example.org', '$2y$12$YHeX9k69/rir1mwqp6CADdWFkN359MxMPUvf7DpfHgrUNORej38ot', '0702393071', '2026-02-09 17:42:00', 'USAGER'),
  (25, 'Marchand', 'Zoé', 'zoe.marchand@example.org', '$2y$12$A45/O/AvM1mhuFN3/CuTXjDBZ3BJB/zBwrn.GlxWPYqIDyKTx5S/t', '0602441342', '2026-10-13 17:35:00', 'USAGER'),
  (26, 'Lopez', 'Mathis', 'mathis.lopez@example.org', '$2y$12$Oj.etLM/vAALdJq7a770n1Edlsao8hrbuezmItTBtGqbWuGikMQ60', '0702489613', '2026-09-28 17:28:00', 'USAGER');

-- -----------------------------------------------------------------------------
--  Formules (4)
-- -----------------------------------------------------------------------------
INSERT INTO formule (id_formule, type, prix, duree_validite_jours, duree_gratuite_min, duree_tranche_min, prix_tranche, supplement_electrique, supplement_casque) VALUES
  (1, 'TICKET_JOURNEE', 5.00, 1, 30, 30, 1.00, 1.00, 1.00),
  (2, 'MENSUEL', 15.00, 30, 45, 30, 1.00, 0.50, 0.50),
  (3, 'ANNUEL', 120.00, 365, 45, 30, 0.75, 0.50, 0.50),
  (4, 'TARIF_REDUIT', 60.00, 365, 45, 30, 0.50, 0.25, 0.25);

-- -----------------------------------------------------------------------------
--  Abonnements (23) — date_fin = date_debut + durée de validité - 1 jour
-- -----------------------------------------------------------------------------
INSERT INTO abonnement (id_abonnement, date_debut, date_fin, id_utilisateur, id_formule, id_abonnement_precedent) VALUES
  (1, '2026-01-15', '2027-01-14', 9, 3, NULL),  -- Emma Laurent, annuel
  (2, '2026-09-01', '2026-09-30', 10, 2, NULL),  -- Léo Fontaine, mensuel (expiré)
  (3, '2026-10-01', '2026-10-30', 10, 2, 2),  -- Léo Fontaine, mensuel, renouvelle 2 (expiré)
  (4, '2026-10-31', '2026-11-29', 10, 2, 3),  -- Léo Fontaine, mensuel, renouvelle 3
  (5, '2026-09-10', '2027-09-09', 11, 4, NULL),  -- Chloé Rousseau, tarif_reduit
  (6, '2025-11-01', '2026-10-31', 12, 3, NULL),  -- Nathan Mercier, annuel (expiré)
  (7, '2026-11-01', '2027-10-31', 12, 3, 6),  -- Nathan Mercier, annuel, renouvelle 6
  (8, '2026-10-03', '2026-11-01', 13, 2, NULL),  -- Inès Garnier, mensuel (expiré)
  (9, '2026-10-11', '2026-10-11', 14, 1, NULL),  -- Louis Faure, ticket_journee (expiré)
  (10, '2026-10-25', '2026-10-25', 14, 1, NULL),  -- Louis Faure, ticket_journee (expiré)
  (11, '2026-03-01', '2027-02-28', 15, 3, NULL),  -- Manon Chevalier, annuel
  (12, '2026-09-15', '2027-09-14', 16, 4, NULL),  -- Gabriel Robin, tarif_reduit
  (13, '2026-10-12', '2026-11-10', 17, 2, NULL),  -- Léa Blanc, mensuel
  (14, '2026-10-18', '2026-10-18', 18, 1, NULL),  -- Arthur Guérin, ticket_journee (expiré)
  (15, '2026-06-20', '2027-06-19', 19, 3, NULL),  -- Jade Muller, annuel
  (16, '2026-10-20', '2026-11-18', 20, 2, NULL),  -- Raphaël Henry, mensuel
  (17, '2026-08-30', '2027-08-29', 21, 4, NULL),  -- Camille Roux, tarif_reduit
  (18, '2026-09-25', '2026-10-24', 22, 2, NULL),  -- Adam Lefebvre, mensuel (expiré)
  (19, '2026-10-25', '2026-11-23', 22, 2, 18),  -- Adam Lefebvre, mensuel, renouvelle 18
  (20, '2026-11-02', '2026-11-02', 23, 1, NULL),  -- Sarah Dupont, ticket_journee (expiré)
  (21, '2026-02-10', '2027-02-09', 24, 3, NULL),  -- Enzo Perrin, annuel
  (22, '2026-10-15', '2026-11-13', 25, 2, NULL),  -- Zoé Marchand, mensuel
  (23, '2026-10-01', '2027-09-30', 26, 4, NULL);  -- Mathis Lopez, tarif_reduit

-- -----------------------------------------------------------------------------
--  Stations (8)
-- -----------------------------------------------------------------------------
INSERT INTO station (id_station, nom, adresse, code_postal, latitude, longitude, etat) VALUES
  (1, 'Gare de Belfort', '2 avenue Wilson, Belfort', '90000', 47.633900, 6.854600, 'EN_SERVICE'),
  (2, 'Place d''Armes', '1 place d''Armes, Belfort', '90000', 47.638000, 6.863500, 'EN_SERVICE'),
  (3, 'République', 'place de la République, Belfort', '90000', 47.637200, 6.858900, 'EN_SERVICE'),
  (4, 'Techn''Hom – UTBM', 'rue Ernest-Thierry-Mieg, Belfort', '90010', 47.644100, 6.843500, 'EN_SERVICE'),
  (5, 'Atria', 'avenue de l''Espérance, Belfort', '90000', 47.641000, 6.856800, 'EN_SERVICE'),
  (6, 'Hôpital Nord Franche-Comté', '100 route de Moval, Trévenans', '90400', 47.565800, 6.865000, 'EN_TRAVAUX'),
  (7, 'Glacis du Château', 'boulevard Carnot, Belfort', '90000', 47.636000, 6.866500, 'HORS_SERVICE'),
  (8, 'Sevenans – UTBM', 'rue de Leupe, Sevenans', '90400', 47.587400, 6.862800, 'EN_SERVICE');

-- -----------------------------------------------------------------------------
--  Bornes (40)
-- -----------------------------------------------------------------------------
INSERT INTO borne (id_station, numero, etat) VALUES
  (1, 1, 'EN_SERVICE'),
  (1, 2, 'EN_SERVICE'),
  (1, 3, 'EN_SERVICE'),
  (1, 4, 'EN_SERVICE'),
  (1, 5, 'EN_SERVICE'),
  (1, 6, 'HORS_SERVICE'),
  (2, 1, 'EN_SERVICE'),
  (2, 2, 'EN_SERVICE'),
  (2, 3, 'EN_SERVICE'),
  (2, 4, 'EN_SERVICE'),
  (2, 5, 'EN_SERVICE'),
  (3, 1, 'EN_SERVICE'),
  (3, 2, 'EN_SERVICE'),
  (3, 3, 'EN_SERVICE'),
  (3, 4, 'EN_SERVICE'),
  (3, 5, 'EN_SERVICE'),
  (4, 1, 'EN_SERVICE'),
  (4, 2, 'EN_SERVICE'),
  (4, 3, 'EN_SERVICE'),
  (4, 4, 'EN_SERVICE'),
  (4, 5, 'EN_SERVICE'),
  (4, 6, 'HORS_SERVICE'),
  (5, 1, 'EN_SERVICE'),
  (5, 2, 'EN_SERVICE'),
  (5, 3, 'EN_SERVICE'),
  (5, 4, 'EN_SERVICE'),
  (5, 5, 'EN_SERVICE'),
  (6, 1, 'HORS_SERVICE'),
  (6, 2, 'HORS_SERVICE'),
  (6, 3, 'HORS_SERVICE'),
  (6, 4, 'HORS_SERVICE'),
  (7, 1, 'HORS_SERVICE'),
  (7, 2, 'HORS_SERVICE'),
  (7, 3, 'HORS_SERVICE'),
  (8, 1, 'EN_SERVICE'),
  (8, 2, 'EN_SERVICE'),
  (8, 3, 'EN_SERVICE'),
  (8, 4, 'EN_SERVICE'),
  (8, 5, 'EN_SERVICE'),
  (8, 6, 'EN_SERVICE');

-- -----------------------------------------------------------------------------
--  Vélos (25) : 1 à 15 mécaniques, 16 à 25 électriques — position actuelle
-- -----------------------------------------------------------------------------
INSERT INTO velo (id_velo, date_mise_service, id_station, numero_borne) VALUES
  (1, '2025-03-17 08:30:00', NULL, NULL),  -- en location
  (2, '2025-03-20 08:30:00', 2, 3),
  (3, '2025-03-23 08:30:00', NULL, NULL),  -- en location
  (4, '2025-03-26 08:30:00', 3, 2),
  (5, '2025-03-29 08:30:00', 1, 1),
  (6, '2025-04-01 08:30:00', 8, 4),
  (7, '2025-04-04 08:30:00', 5, 4),
  (8, '2025-04-07 08:30:00', 2, 2),
  (9, '2025-04-10 08:30:00', 2, 4),
  (10, '2025-04-13 08:30:00', 5, 3),
  (11, '2025-04-16 08:30:00', 1, 4),
  (12, '2025-04-19 08:30:00', NULL, NULL),  -- réformé
  (13, '2025-04-22 08:30:00', 3, 1),
  (14, '2025-04-25 08:30:00', 8, 2),
  (15, '2025-04-28 08:30:00', 4, 2),
  (16, '2025-09-01 09:00:00', 1, 3),
  (17, '2025-09-08 09:00:00', 1, 2),
  (18, '2025-09-15 09:00:00', 3, 5),
  (19, '2025-09-22 09:00:00', 5, 2),
  (20, '2025-09-29 09:00:00', 8, 3),
  (21, '2025-10-06 09:00:00', 8, 1),
  (22, '2025-10-13 09:00:00', NULL, NULL),  -- en atelier
  (23, '2025-10-20 09:00:00', NULL, NULL),  -- dans le camion de la tournée
  (24, '2025-10-27 09:00:00', 4, 3),
  (25, '2025-11-03 09:00:00', 4, 1);

-- -----------------------------------------------------------------------------
--  Vélos électriques (10) — niveau de batterie en %
-- -----------------------------------------------------------------------------
INSERT INTO velo_electrique (id_velo, niveau_batterie) VALUES
  (16, 82),
  (17, 100),
  (18, 64),
  (19, 45),
  (20, 71),
  (21, 90),
  (22, 12),
  (23, 58),
  (24, 77),
  (25, 33);

-- -----------------------------------------------------------------------------
--  Changements d'état (34) — mise en service, pannes, réparations, réforme
-- -----------------------------------------------------------------------------
INSERT INTO changement_etat (id_changement, date_heure_changement, etat, id_velo) VALUES
  (1, '2025-03-17 08:30:00', 'EN_SERVICE', 1),
  (2, '2025-03-20 08:30:00', 'EN_SERVICE', 2),
  (3, '2025-03-23 08:30:00', 'EN_SERVICE', 3),
  (4, '2025-03-26 08:30:00', 'EN_SERVICE', 4),
  (5, '2025-03-29 08:30:00', 'EN_SERVICE', 5),
  (6, '2025-04-01 08:30:00', 'EN_SERVICE', 6),
  (7, '2025-04-04 08:30:00', 'EN_SERVICE', 7),
  (8, '2025-04-07 08:30:00', 'EN_SERVICE', 8),
  (9, '2025-04-10 08:30:00', 'EN_SERVICE', 9),
  (10, '2025-04-13 08:30:00', 'EN_SERVICE', 10),
  (11, '2025-04-16 08:30:00', 'EN_SERVICE', 11),
  (12, '2025-04-19 08:30:00', 'EN_SERVICE', 12),
  (13, '2025-04-22 08:30:00', 'EN_SERVICE', 13),
  (14, '2025-04-25 08:30:00', 'EN_SERVICE', 14),
  (15, '2025-04-28 08:30:00', 'EN_SERVICE', 15),
  (16, '2025-09-01 09:00:00', 'EN_SERVICE', 16),
  (17, '2025-09-08 09:00:00', 'EN_SERVICE', 17),
  (18, '2025-09-15 09:00:00', 'EN_SERVICE', 18),
  (19, '2025-09-22 09:00:00', 'EN_SERVICE', 19),
  (20, '2025-09-29 09:00:00', 'EN_SERVICE', 20),
  (21, '2025-10-06 09:00:00', 'EN_SERVICE', 21),
  (22, '2025-10-13 09:00:00', 'EN_SERVICE', 22),
  (23, '2025-10-20 09:00:00', 'EN_SERVICE', 23),
  (24, '2025-10-27 09:00:00', 'EN_SERVICE', 24),
  (25, '2025-11-03 09:00:00', 'EN_SERVICE', 25),
  (26, '2026-10-06 09:30:00', 'DEFECTUEUX', 3),
  (27, '2026-10-07 14:00:00', 'EN_SERVICE', 3),
  (28, '2026-10-10 08:15:00', 'DEFECTUEUX', 17),
  (29, '2026-10-13 10:30:00', 'EN_SERVICE', 17),
  (30, '2026-10-19 10:00:00', 'DEFECTUEUX', 8),
  (31, '2026-10-19 11:30:00', 'EN_SERVICE', 8),
  (32, '2026-10-27 09:00:00', 'DEFECTUEUX', 12),
  (33, '2026-10-28 16:00:00', 'REFORME', 12),
  (34, '2026-11-03 11:00:00', 'DEFECTUEUX', 22);

-- -----------------------------------------------------------------------------
--  Tournées de rééquilibrage (4)
-- -----------------------------------------------------------------------------
INSERT INTO tournee (id_tournee, date_heure_debut, date_heure_fin, id_utilisateur) VALUES
  (1, '2026-10-06 06:00:00', '2026-10-06 07:30:00', 3),  -- Sophie Petit
  (2, '2026-10-15 05:45:00', '2026-10-15 07:00:00', 4),  -- Karim Benali
  (3, '2026-10-23 06:00:00', '2026-10-23 07:15:00', 5),  -- Lucas Moreau
  (4, '2026-11-04 13:30:00', NULL, 3);  -- Sophie Petit, en cours

-- -----------------------------------------------------------------------------
--  Mouvements (38) — locations, transferts et retraits pour maintenance
-- -----------------------------------------------------------------------------
INSERT INTO mouvement (id_mouvement, date_heure_depart, date_heure_arrivee, id_velo, id_station_depart, numero_borne_depart, id_station_arrivee, numero_borne_arrivee) VALUES
  (1, '2026-10-01 08:12:00', '2026-10-01 08:30:00', 1, 1, 1, 4, 4),  -- L1 location : Gare de Belfort -> Techn'Hom – UTBM
  (2, '2026-10-01 08:25:00', '2026-10-01 08:47:00', 16, 1, 3, 4, 5),  -- L2 location : Gare de Belfort -> Techn'Hom – UTBM
  (3, '2026-10-02 17:40:00', '2026-10-02 18:15:00', 5, 3, 1, 1, 1),  -- L3 location : République -> Gare de Belfort
  (4, '2026-10-03 12:05:00', '2026-10-03 12:57:00', 10, 5, 1, 2, 5),  -- L4 location : Atria -> Place d'Armes
  (5, '2026-10-05 07:50:00', '2026-10-05 08:15:00', 13, 8, 1, 5, 1),  -- L5 location : Sevenans – UTBM -> Atria
  (6, '2026-10-06 06:10:00', '2026-10-06 06:40:00', 1, 4, 4, 5, 1),  -- T1-1 transfert (tournée 1) : Techn'Hom – UTBM -> Atria
  (7, '2026-10-06 06:12:00', '2026-10-06 06:40:00', 16, 4, 5, 1, 3),  -- T1-16 transfert (tournée 1) : Techn'Hom – UTBM -> Gare de Belfort
  (8, '2026-10-06 06:15:00', '2026-10-06 06:55:00', 13, 5, 1, 3, 1),  -- T1-13 transfert (tournée 1) : Atria -> République
  (9, '2026-10-06 09:30:00', '2026-10-07 14:00:00', 3, 2, 1, 2, 1),  -- IV1 maintenance : Place d'Armes -> Place d'Armes
  (10, '2026-10-07 18:10:00', '2026-10-07 18:25:00', 18, 2, 3, 3, 5),  -- L6 location : Place d'Armes -> République
  (11, '2026-10-09 08:30:00', '2026-10-09 09:10:00', 21, 4, 3, 8, 1),  -- L7 location : Techn'Hom – UTBM -> Sevenans – UTBM
  (12, '2026-10-10 08:15:00', '2026-10-13 10:30:00', 17, 1, 4, 1, 2),  -- IV2 maintenance : Gare de Belfort -> Gare de Belfort
  (13, '2026-10-11 10:00:00', '2026-10-11 11:35:00', 6, 3, 2, 5, 5),  -- L8 location : République -> Atria
  (14, '2026-10-12 19:20:00', '2026-10-12 19:32:00', 2, 1, 2, 2, 3),  -- L9 location : Gare de Belfort -> Place d'Armes
  (15, '2026-10-14 08:05:00', '2026-10-14 08:33:00', 24, 8, 4, 4, 3),  -- L10 location : Sevenans – UTBM -> Techn'Hom – UTBM
  (16, '2026-10-15 06:00:00', '2026-10-15 06:30:00', 10, 2, 5, 4, 4),  -- T2-10 transfert (tournée 2) : Place d'Armes -> Techn'Hom – UTBM
  (17, '2026-10-15 06:05:00', '2026-10-15 06:40:00', 6, 5, 5, 8, 4),  -- T2-6 transfert (tournée 2) : Atria -> Sevenans – UTBM
  (18, '2026-10-16 12:30:00', '2026-10-16 12:50:00', 11, 5, 2, 1, 4),  -- L11 location : Atria -> Gare de Belfort
  (19, '2026-10-18 14:00:00', '2026-10-18 15:10:00', 19, 2, 4, 5, 2),  -- L12 location : Place d'Armes -> Atria
  (20, '2026-10-19 10:00:00', '2026-10-19 11:30:00', 8, 4, 1, 4, 1),  -- IV3 maintenance : Techn'Hom – UTBM -> Techn'Hom – UTBM
  (21, '2026-10-20 08:15:00', '2026-10-20 08:48:00', 14, 8, 2, 4, 5),  -- L13 location : Sevenans – UTBM -> Techn'Hom – UTBM
  (22, '2026-10-22 17:45:00', '2026-10-22 18:33:00', 9, 4, 2, 3, 2),  -- L14 location : Techn'Hom – UTBM -> République
  (23, '2026-10-23 06:10:00', '2026-10-23 06:50:00', 14, 4, 5, 8, 2),  -- T3-14 transfert (tournée 3) : Techn'Hom – UTBM -> Sevenans – UTBM
  (24, '2026-10-23 06:20:00', '2026-10-23 06:45:00', 9, 3, 2, 2, 4),  -- T3-9 transfert (tournée 3) : République -> Place d'Armes
  (25, '2026-10-24 09:10:00', '2026-10-24 09:36:00', 23, 5, 4, 2, 5),  -- L15 location : Atria -> Place d'Armes
  (26, '2026-10-25 15:00:00', '2026-10-25 15:41:00', 4, 2, 2, 1, 5),  -- L16 location : Place d'Armes -> Gare de Belfort
  (27, '2026-10-27 08:00:00', '2026-10-27 08:30:00', 15, 8, 3, 4, 2),  -- L17 location : Sevenans – UTBM -> Techn'Hom – UTBM
  (28, '2026-10-27 09:00:00', '2026-10-27 09:40:00', 12, 5, 3, NULL, NULL),  -- IV4 maintenance : Atria -> atelier (réformé)
  (29, '2026-10-28 12:15:00', '2026-10-28 13:19:00', 10, 4, 4, 5, 3),  -- L18 location : Techn'Hom – UTBM -> Atria
  (30, '2026-10-29 18:30:00', '2026-10-29 18:46:00', 7, 3, 3, 5, 4),  -- L19 location : République -> Atria
  (31, '2026-10-30 07:40:00', '2026-10-30 08:02:00', 8, 4, 1, 2, 2),  -- L20 location : Techn'Hom – UTBM -> Place d'Armes
  (32, '2026-11-01 11:20:00', '2026-11-01 12:15:00', 20, 3, 4, 8, 3),  -- L21 location : République -> Sevenans – UTBM
  (33, '2026-11-02 10:45:00', '2026-11-02 11:23:00', 25, 8, 5, 4, 1),  -- L22 location : Sevenans – UTBM -> Techn'Hom – UTBM
  (34, '2026-11-03 11:00:00', NULL, 22, 8, 6, NULL, NULL),  -- IV5 maintenance : Sevenans – UTBM -> atelier
  (35, '2026-11-04 13:45:00', '2026-11-04 14:10:00', 4, 1, 5, 3, 2),  -- T4-4 transfert (tournée 4) : Gare de Belfort -> République
  (36, '2026-11-04 14:05:00', NULL, 1, 5, 1, NULL, NULL),  -- L23 location : Atria -> en cours
  (37, '2026-11-04 14:20:00', NULL, 23, 2, 5, NULL, NULL),  -- T4-23 transfert (tournée 4) : Place d'Armes -> en cours
  (38, '2026-11-04 14:40:00', NULL, 3, 2, 1, NULL, NULL);  -- L24 location : Place d'Armes -> en cours

-- -----------------------------------------------------------------------------
--  Locations (24)
-- -----------------------------------------------------------------------------
INSERT INTO location (id_mouvement, id_abonnement) VALUES
  (1, 1),  -- L1 : Emma Laurent, 18 min
  (2, 3),  -- L2 : Léo Fontaine, 22 min
  (3, 5),  -- L3 : Chloé Rousseau, 35 min
  (4, 8),  -- L4 : Inès Garnier, 52 min
  (5, 6),  -- L5 : Nathan Mercier, 25 min
  (10, 11),  -- L6 : Manon Chevalier, 15 min
  (11, 12),  -- L7 : Gabriel Robin, 40 min
  (13, 9),  -- L8 : Louis Faure, 95 min, avec casque
  (14, 13),  -- L9 : Léa Blanc, 12 min
  (15, 15),  -- L10 : Jade Muller, 28 min
  (18, 17),  -- L11 : Camille Roux, 20 min
  (19, 14),  -- L12 : Arthur Guérin, 70 min, avec casque
  (21, 16),  -- L13 : Raphaël Henry, 33 min
  (22, 18),  -- L14 : Adam Lefebvre, 48 min
  (25, 22),  -- L15 : Zoé Marchand, 26 min
  (26, 10),  -- L16 : Louis Faure, 41 min
  (27, 23),  -- L17 : Mathis Lopez, 30 min
  (29, 8),  -- L18 : Inès Garnier, 64 min
  (30, 3),  -- L19 : Léo Fontaine, 16 min
  (31, 21),  -- L20 : Enzo Perrin, 22 min
  (32, 7),  -- L21 : Nathan Mercier, 55 min
  (33, 20),  -- L22 : Sarah Dupont, 38 min, avec casque
  (36, 11),  -- L23 : Manon Chevalier, en cours
  (38, 17);  -- L24 : Camille Roux, en cours

-- -----------------------------------------------------------------------------
--  Transferts (9)
-- -----------------------------------------------------------------------------
INSERT INTO transfert (id_mouvement, id_tournee) VALUES
  (6, 1),
  (7, 1),
  (8, 1),
  (16, 2),
  (17, 2),
  (23, 3),
  (24, 3),
  (35, 4),
  (37, 4);

-- -----------------------------------------------------------------------------
--  Factures (36) — abonnements et locations payantes (montant = tranches au-delà du temps gratuit + suppléments)
-- -----------------------------------------------------------------------------
INSERT INTO facture (id_facture, date_emission, montant, date_reglement, id_abonnement, id_location) VALUES
  (1, '2025-11-01 07:06:00', 120.00, '2025-11-01 07:07:00', 6, NULL),  -- abonnement 6 (ANNUEL)
  (2, '2026-01-15 07:01:00', 120.00, '2026-01-15 07:02:00', 1, NULL),  -- abonnement 1 (ANNUEL)
  (3, '2026-02-10 07:21:00', 120.00, '2026-02-10 07:22:00', 21, NULL),  -- abonnement 21 (ANNUEL)
  (4, '2026-03-01 07:11:00', 120.00, '2026-03-01 07:12:00', 11, NULL),  -- abonnement 11 (ANNUEL)
  (5, '2026-06-20 07:15:00', 120.00, '2026-06-20 07:16:00', 15, NULL),  -- abonnement 15 (ANNUEL)
  (6, '2026-08-30 07:17:00', 60.00, '2026-08-30 07:18:00', 17, NULL),  -- abonnement 17 (TARIF_REDUIT)
  (7, '2026-09-01 07:02:00', 15.00, '2026-09-01 07:03:00', 2, NULL),  -- abonnement 2 (MENSUEL)
  (8, '2026-09-10 07:05:00', 60.00, '2026-09-10 07:06:00', 5, NULL),  -- abonnement 5 (TARIF_REDUIT)
  (9, '2026-09-15 07:12:00', 60.00, '2026-09-15 07:13:00', 12, NULL),  -- abonnement 12 (TARIF_REDUIT)
  (10, '2026-09-25 07:18:00', 15.00, '2026-09-25 07:19:00', 18, NULL),  -- abonnement 18 (MENSUEL)
  (11, '2026-10-01 07:03:00', 15.00, '2026-10-01 07:04:00', 3, NULL),  -- abonnement 3 (MENSUEL)
  (12, '2026-10-01 07:23:00', 60.00, '2026-10-01 07:24:00', 23, NULL),  -- abonnement 23 (TARIF_REDUIT)
  (13, '2026-10-01 08:47:00', 0.50, '2026-10-01 08:49:00', NULL, 2),  -- L2 : 22 min, vélo électrique
  (14, '2026-10-03 07:08:00', 15.00, '2026-10-03 07:09:00', 8, NULL),  -- abonnement 8 (MENSUEL)
  (15, '2026-10-03 12:57:00', 1.00, '2026-10-03 12:59:00', NULL, 4),  -- L4 : 52 min, 1 tranche(s)
  (16, '2026-10-07 18:25:00', 0.50, '2026-10-07 18:27:00', NULL, 10),  -- L6 : 15 min, vélo électrique
  (17, '2026-10-09 09:10:00', 0.25, '2026-10-09 09:12:00', NULL, 11),  -- L7 : 40 min, vélo électrique
  (18, '2026-10-11 07:09:00', 5.00, '2026-10-11 07:10:00', 9, NULL),  -- abonnement 9 (TICKET_JOURNEE)
  (19, '2026-10-11 11:35:00', 4.00, '2026-10-11 11:37:00', NULL, 13),  -- L8 : 95 min, 3 tranche(s), casque
  (20, '2026-10-12 07:13:00', 15.00, '2026-10-12 07:14:00', 13, NULL),  -- abonnement 13 (MENSUEL)
  (21, '2026-10-14 08:33:00', 0.50, '2026-10-14 08:35:00', NULL, 15),  -- L10 : 28 min, vélo électrique
  (22, '2026-10-15 07:22:00', 15.00, '2026-10-15 07:23:00', 22, NULL),  -- abonnement 22 (MENSUEL)
  (23, '2026-10-18 07:14:00', 5.00, '2026-10-18 07:15:00', 14, NULL),  -- abonnement 14 (TICKET_JOURNEE)
  (24, '2026-10-18 15:10:00', 4.00, '2026-10-18 15:12:00', NULL, 19),  -- L12 : 70 min, 2 tranche(s), vélo électrique, casque
  (25, '2026-10-20 07:16:00', 15.00, '2026-10-20 07:17:00', 16, NULL),  -- abonnement 16 (MENSUEL)
  (26, '2026-10-22 18:33:00', 1.00, '2026-10-22 18:35:00', NULL, 22),  -- L14 : 48 min, 1 tranche(s)
  (27, '2026-10-24 09:36:00', 0.50, '2026-10-24 09:38:00', NULL, 25),  -- L15 : 26 min, vélo électrique
  (28, '2026-10-25 07:10:00', 5.00, '2026-10-25 07:11:00', 10, NULL),  -- abonnement 10 (TICKET_JOURNEE)
  (29, '2026-10-25 07:19:00', 15.00, '2026-10-25 07:20:00', 19, NULL),  -- abonnement 19 (MENSUEL)
  (30, '2026-10-25 15:41:00', 1.00, '2026-10-25 15:43:00', NULL, 26),  -- L16 : 41 min, 1 tranche(s)
  (31, '2026-10-28 13:19:00', 1.00, '2026-10-28 13:21:00', NULL, 29),  -- L18 : 64 min, 1 tranche(s)
  (32, '2026-10-31 07:04:00', 15.00, '2026-10-31 07:05:00', 4, NULL),  -- abonnement 4 (MENSUEL)
  (33, '2026-11-01 07:07:00', 120.00, NULL, 7, NULL),  -- abonnement 7 (ANNUEL), non réglée
  (34, '2026-11-01 12:15:00', 1.25, '2026-11-01 12:17:00', NULL, 32),  -- L21 : 55 min, 1 tranche(s), vélo électrique
  (35, '2026-11-02 07:20:00', 5.00, '2026-11-02 07:21:00', 20, NULL),  -- abonnement 20 (TICKET_JOURNEE)
  (36, '2026-11-02 11:23:00', 3.00, NULL, NULL, 33);  -- L22 : 38 min, 1 tranche(s), vélo électrique, casque, non réglée

-- -----------------------------------------------------------------------------
--  Interventions (9)
-- -----------------------------------------------------------------------------
INSERT INTO intervention (id_intervention, description, id_utilisateur) VALUES
  (1, 'Remplacement des plaquettes de frein arrière.', 6),  -- IV1 : Thomas Girard
  (2, 'Remplacement de la batterie et contrôle du moteur.', 7),  -- IV2 : Nadia Haddad
  (3, 'Réglage du verrou de la borne 2.', 8),  -- IS1 : Hugo Lambert
  (4, 'Réparation de la crevaison, pneu avant changé.', 8),  -- IV3 : Hugo Lambert
  (5, 'Diagnostic du terminal de paiement.', 6),  -- IS2 : Thomas Girard
  (6, 'Remplacement du terminal de paiement.', 6),  -- IS3 : Thomas Girard
  (7, 'Cadre fissuré : vélo retiré puis réformé.', 6),  -- IV4 : Thomas Girard
  (8, 'Remplacement de l''écran de la station.', 8),  -- IS4 : Hugo Lambert
  (9, 'Chaîne et dérailleur à remplacer, vélo en atelier.', 7);  -- IV5 : Nadia Haddad

-- -----------------------------------------------------------------------------
--  Interventions sur vélo (5)
-- -----------------------------------------------------------------------------
INSERT INTO intervention_velo (id_intervention, id_mouvement) VALUES
  (1, 9),  -- IV1 : vélo 3
  (2, 12),  -- IV2 : vélo 17
  (4, 20),  -- IV3 : vélo 8
  (7, 28),  -- IV4 : vélo 12
  (9, 34);  -- IV5 : vélo 22

-- -----------------------------------------------------------------------------
--  Signalements (12)
-- -----------------------------------------------------------------------------
INSERT INTO signalement (id_signalement, date_heure_signalement, description, date_heure_cloture, id_utilisateur) VALUES
  (1, '2026-10-05 19:02:00', 'Le frein arrière ne freine presque plus.', '2026-10-07 14:00:00', 11),  -- S1 : Chloé Rousseau
  (2, '2026-10-09 18:20:00', 'La batterie se vide en quelques minutes.', '2026-10-13 10:30:00', 13),  -- S2 : Inès Garnier
  (3, '2026-10-09 21:05:00', 'L''assistance électrique se coupe en pleine montée.', '2026-10-13 10:30:00', 19),  -- S3 : Jade Muller
  (4, '2026-10-13 07:55:00', 'La borne 2 ne libère pas le vélo.', '2026-10-14 10:45:00', 9),  -- S4 : Emma Laurent
  (5, '2026-10-19 08:40:00', 'Pneu avant crevé.', '2026-10-19 11:30:00', 16),  -- S5 : Gabriel Robin
  (6, '2026-10-20 12:10:00', 'Le terminal de paiement de la station est en panne.', '2026-10-23 10:00:00', 12),  -- S6 : Nathan Mercier
  (7, '2026-10-21 09:10:00', 'Garde-boue arrière qui frotte.', '2026-10-21 15:00:00', 9),  -- S7 : Emma Laurent
  (8, '2026-10-26 17:15:00', 'Fissure sur le cadre, au niveau de la selle.', '2026-10-28 16:00:00', 20),  -- S8 : Raphaël Henry
  (9, '2026-10-28 18:40:00', 'Écran de la station éteint, impossible de rendre un vélo.', NULL, 17),  -- S9 : Léa Blanc, ouvert
  (10, '2026-11-01 09:30:00', 'Station fermée depuis plusieurs semaines, aucune information affichée.', NULL, 24),  -- S10 : Enzo Perrin, ouvert
  (11, '2026-11-02 16:30:00', 'La sonnette est cassée.', NULL, 26),  -- S11 : Mathis Lopez, ouvert
  (12, '2026-11-03 08:50:00', 'La chaîne saute sans arrêt.', NULL, 25);  -- S12 : Zoé Marchand, ouvert

-- -----------------------------------------------------------------------------
--  Signalements de vélo (8)
-- -----------------------------------------------------------------------------
INSERT INTO signalement_velo (id_signalement, id_velo, id_intervention_velo) VALUES
  (1, 3, 1),
  (2, 17, 2),
  (3, 17, 2),
  (5, 8, 4),
  (7, 20, NULL),  -- clos sans intervention
  (8, 12, 7),
  (11, 5, NULL),  -- pas encore traité
  (12, 22, 9);

-- -----------------------------------------------------------------------------
--  Signalements de station (4)
-- -----------------------------------------------------------------------------
INSERT INTO signalement_station (id_signalement, id_station) VALUES
  (4, 3),
  (6, 1),
  (9, 6),
  (10, 7);

-- -----------------------------------------------------------------------------
--  Interventions sur station (4)
-- -----------------------------------------------------------------------------
INSERT INTO intervention_station (id_intervention, date_heure_debut, date_heure_fin, id_signalement_station) VALUES
  (3, '2026-10-14 09:00:00', '2026-10-14 10:45:00', 4),  -- IS1
  (5, '2026-10-21 08:30:00', '2026-10-21 09:15:00', 6),  -- IS2
  (6, '2026-10-23 08:00:00', '2026-10-23 10:00:00', 6),  -- IS3
  (8, '2026-10-29 08:00:00', NULL, 9);  -- IS4, en cours

COMMIT;
