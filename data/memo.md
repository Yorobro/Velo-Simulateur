# Mémo de la base `velo_libre_service`

Ce mémo résume tout ce que contiennent les scripts SQL de ce dossier. Il présente :

1. les contraintes de structure, table par table ;
2. les règles métier R1 à R14, et l'objet qui fait respecter chacune ;
3. les fonctions, procédures, triggers, l'événement et les vues, avec leur rôle.

| Fichier | Contenu | Ordre d'exécution |
|---|---|---|
| `structure.sql` | Base, tables, clés, contraintes `UNIQUE` et `CHECK`, types `ENUM` | 1 |
| `../peuplement_velo.py` | Données factices en grand volume (Faker) : un an d'activité simulée, voir § 11 | 2 |
| `donnes.sql` | Petit jeu de données écrit à la main, à utiliser **à la place** du script Python | 2 |
| `automatisation.sql` | Fonctions, procédures, triggers, vues | 3 |
| `optimisation.sql` | Index, vues réécrites plus rapides, statistiques, événement planifié | 4 |

> Les données (script Python ou `donnes.sql`) se chargent **avant** `automatisation.sql` : ses triggers créent eux-mêmes des factures et des changements d'état. S'il était chargé avant, il créerait des doublons. Le script Python refuse d'ailleurs de s'exécuter si les triggers sont déjà présents.
> `optimisation.sql` remplace six vues de `automatisation.sql`. Si on rejoue `automatisation.sql`, il faut rejouer `optimisation.sql` ensuite.
> Ces deux scripts peuvent être rejoués : ils suppriment puis recréent leurs objets.

---

## 1. Contraintes de structure (`structure.sql`)

### Règles générales

- **SGBD** : MySQL 8.4 LTS et 9.x (testé sur 9.0). Moteur InnoDB, jeu de caractères `utf8mb4`.
- **Collation** : `utf8mb4_0900_ai_ci`, qui ne tient compte ni des majuscules ni des accents dans les comparaisons. Elle n'existe que sous MySQL ; sous MariaDB 10.11, il faudrait `utf8mb4_unicode_ci`.
- **Noms des contraintes** : préfixes `pk_` (clé primaire), `fk_` (clé étrangère), `uq_` (unicité) et `ck_` (vérification).
- **Énumérations** : les énumérations du MCD deviennent des colonnes `ENUM`. Le mode strict, actif par défaut sous MySQL 8 et 9, refuse toute valeur hors de la liste.
- **Clé étrangère sans action** : on ne peut pas supprimer une ligne encore référencée, ce qui protège l'historique.
- **`ON DELETE CASCADE`** : seulement pour les sous-classes, qui n'existent pas sans leur ligne mère, et pour les bornes d'une station.
- **Limite MySQL** : une colonne utilisée dans un `CHECK` ne peut pas porter d'action `ON DELETE` ou `ON UPDATE`. Les clés étrangères de `facture`, `velo` et `mouvement` restent donc sans action.
- **Identifiants** : `INT UNSIGNED AUTO_INCREMENT`. Les sous-classes réutilisent l'identifiant de leur super-classe, qui leur sert à la fois de clé primaire et de clé étrangère.

### `utilisateur` — comptes

| Contrainte | Type | Règle |
|---|---|---|
| `pk_utilisateur` | PRIMARY KEY | `id_utilisateur` |
| `uq_utilisateur_email` | UNIQUE | Une adresse e-mail = un seul compte (comparaison insensible à la casse) |
| `ck_utilisateur_nom`, `ck_utilisateur_prenom` | CHECK | Nom et prénom non vides, espaces exclus |
| `ck_utilisateur_email` | CHECK | Format `texte@texte.texte`, sans espace |
| `ck_utilisateur_mdp` | CHECK | Au moins 60 caractères : on stocke une empreinte bcrypt, jamais le mot de passe en clair |
| `ck_utilisateur_telephone` | CHECK | 10 à 15 chiffres, précédés d'un `+` facultatif |
| `role` | ENUM | `USAGER`, `OPERATEUR_REGULATION`, `OPERATEUR_MAINTENANCE`, `ADMINISTRATEUR` ; `USAGER` par défaut |
| `date_inscription` | DEFAULT | Date et heure courantes |

### `formule` — formules tarifaires

| Contrainte | Type | Règle |
|---|---|---|
| `pk_formule` | PRIMARY KEY | `id_formule` |
| `type` | ENUM | `TICKET_JOURNEE`, `MENSUEL`, `ANNUEL`, `TARIF_REDUIT` |
| `ck_formule_prix` | CHECK | `prix >= 0` |
| `ck_formule_validite` | CHECK | `duree_validite_jours > 0` |
| `ck_formule_tranche` | CHECK | `duree_tranche_min > 0` (évite une division par zéro dans le calcul du coût) |
| `ck_formule_prix_tranche` | CHECK | `prix_tranche >= 0` |
| `ck_formule_supp_electrique`, `ck_formule_supp_casque` | CHECK | Suppléments `>= 0` ; valeur par défaut 0 |
| `duree_gratuite_min` | UNSIGNED | Peut valoir 0 (aucune minute offerte) |

### `abonnement` — souscriptions

| Contrainte | Type | Règle |
|---|---|---|
| `pk_abonnement` | PRIMARY KEY | `id_abonnement` |
| `uq_abonnement_precedent` | UNIQUE | Un abonnement n'est renouvelé qu'une fois au plus |
| `ck_abonnement_dates` | CHECK | `date_fin >= date_debut` |
| `fk_abonnement_utilisateur` | FOREIGN KEY | Vers `utilisateur` |
| `fk_abonnement_formule` | FOREIGN KEY | Vers `formule` |
| `fk_abonnement_precedent` | FOREIGN KEY | Vers `abonnement` (lien réflexif « renouvelle ») ; NULL = premier abonnement |

L'abonnement est expiré dès que `date_fin` est passée. Ce statut n'est pas stocké.

### `station`

| Contrainte | Type | Règle |
|---|---|---|
| `pk_station` | PRIMARY KEY | `id_station` |
| `uq_station_adresse` | UNIQUE | Deux stations n'ont pas la même adresse (`adresse`, `code_postal`) |
| `uq_station_coordonnees` | UNIQUE | Deux stations n'ont pas les mêmes coordonnées GPS |
| `ck_station_nom` | CHECK | Nom non vide |
| `ck_station_code_postal` | CHECK | Exactement 5 chiffres |
| `ck_station_latitude` / `ck_station_longitude` | CHECK | Latitude entre -90 et 90, longitude entre -180 et 180 |
| `etat` | ENUM | `EN_SERVICE` (par défaut), `HORS_SERVICE`, `EN_TRAVAUX` |

Le nombre de bornes d'une station n'est pas stocké : il se calcule (`COUNT` sur `borne`).

### `borne`

| Contrainte | Type | Règle |
|---|---|---|
| `pk_borne` | PRIMARY KEY | (`id_station`, `numero`) : identifiant relatif, le numéro n'est unique que dans sa station |
| `ck_borne_numero` | CHECK | `numero > 0` |
| `fk_borne_station` | FOREIGN KEY | Vers `station`, **ON DELETE CASCADE** (supprimer une station supprime ses bornes) |
| `etat` | ENUM | `EN_SERVICE` (par défaut), `HORS_SERVICE` |

### `velo`

| Contrainte | Type | Règle |
|---|---|---|
| `pk_velo` | PRIMARY KEY | `id_velo` |
| `uq_velo_borne` | UNIQUE | (`id_station`, `numero_borne`) : **une borne accueille au plus un vélo** (exigé par le sujet). Plusieurs vélos peuvent avoir une position NULL. |
| `ck_velo_position` | CHECK | Station et borne sont renseignées ensemble ou NULL ensemble |
| `fk_velo_borne` | FOREIGN KEY | (`id_station`, `numero_borne`) vers `borne` |

Une position NULL signifie que le vélo est en location, en tournée, en atelier ou réformé.

### `velo_electrique` — sous-classe de `velo`

| Contrainte | Type | Règle |
|---|---|---|
| `pk_velo_electrique` | PRIMARY KEY | `id_velo` |
| `ck_velo_electrique_batterie` | CHECK | Batterie entre 0 et 100 % |
| `fk_velo_electrique_velo` | FOREIGN KEY | Vers `velo`, **ON DELETE CASCADE** |

Un vélo sans ligne dans cette table est mécanique.

### `changement_etat` — historique des états d'un vélo

| Contrainte | Type | Règle |
|---|---|---|
| `pk_changement_etat` | PRIMARY KEY | `id_changement` |
| `uq_changement_etat` | UNIQUE | (`id_velo`, `date_heure_changement`) : pas deux changements au même instant pour un vélo |
| `etat` | ENUM | `EN_SERVICE`, `DEFECTUEUX`, `REFORME` |
| `fk_changement_etat_velo` | FOREIGN KEY | Vers `velo` |

L'état actuel d'un vélo est celui de son dernier changement.

### `tournee` — tournées de rééquilibrage

| Contrainte | Type | Règle |
|---|---|---|
| `pk_tournee` | PRIMARY KEY | `id_tournee` |
| `ck_tournee_dates` | CHECK | `date_heure_fin` est NULL (tournée en cours) ou postérieure au début |
| `fk_tournee_utilisateur` | FOREIGN KEY | Vers `utilisateur` (l'opérateur) |

### `mouvement` — déplacements d'un vélo

| Contrainte | Type | Règle |
|---|---|---|
| `pk_mouvement` | PRIMARY KEY | `id_mouvement` |
| `ck_mouvement_dates` | CHECK | `date_heure_arrivee` est NULL (mouvement en cours) ou postérieure au départ |
| `ck_mouvement_borne_arrivee` | CHECK | Station et numéro de la borne d'arrivée sont renseignés ensemble ou NULL ensemble |
| `ck_mouvement_arrivee` | CHECK | Pas de borne d'arrivée sans date d'arrivée. L'inverse est permis : un vélo réformé a une date d'arrivée mais pas de borne. |
| `fk_mouvement_velo` | FOREIGN KEY | Vers `velo` |
| `fk_mouvement_borne_depart` | FOREIGN KEY | Vers `borne` ; obligatoire |
| `fk_mouvement_borne_arrivee` | FOREIGN KEY | Vers `borne` ; facultative |

### `location` et `transfert` — sous-classes de `mouvement`

| Table | Contrainte | Règle |
|---|---|---|
| `location` | `pk_location` + `fk_location_mouvement` | `id_mouvement`, vers `mouvement`, **ON DELETE CASCADE** |
| `location` | `fk_location_abonnement` | Vers l'abonnement utilisé ; l'usager se déduit de l'abonnement |
| `transfert` | `pk_transfert` + `fk_transfert_mouvement` | `id_mouvement`, vers `mouvement`, **ON DELETE CASCADE** |
| `transfert` | `fk_transfert_tournee` | Vers la tournée qui déplace le vélo |

### `facture`

| Contrainte | Type | Règle |
|---|---|---|
| `pk_facture` | PRIMARY KEY | `id_facture` |
| `uq_facture_abonnement` / `uq_facture_location` | UNIQUE | Un abonnement ou une location n'est facturé qu'une fois au plus |
| `ck_facture_cible` | CHECK | Une facture porte sur un abonnement **ou** sur une location : exactement l'un des deux |
| `ck_facture_montant` | CHECK | `montant >= 0` |
| `ck_facture_reglement` | CHECK | `date_reglement` est NULL (non réglée) ou postérieure ou égale à l'émission |
| `fk_facture_abonnement` / `fk_facture_location` | FOREIGN KEY | Vers `abonnement` et vers `location` |

### `intervention` et ses sous-classes

| Table | Contrainte | Règle |
|---|---|---|
| `intervention` | `pk_intervention` | `id_intervention` |
| `intervention` | `ck_intervention_description` | Description non vide |
| `intervention` | `fk_intervention_utilisateur` | Vers l'opérateur qui réalise l'intervention |
| `intervention_velo` | `pk_intervention_velo` + `fk_intervention_velo_intervention` | `id_intervention`, vers `intervention`, **ON DELETE CASCADE** |
| `intervention_velo` | `uq_intervention_velo_mouvement` | Un mouvement donne lieu à une intervention au plus |
| `intervention_velo` | `fk_intervention_velo_mouvement` | Vers le mouvement de retrait du vélo |
| `intervention_station` | `pk_intervention_station` + `fk_intervention_station_intervention` | `id_intervention`, vers `intervention`, **ON DELETE CASCADE** |
| `intervention_station` | `ck_intervention_station_dates` | `date_heure_fin` est NULL (en cours) ou postérieure au début |
| `intervention_station` | `fk_intervention_station_signalement` | Vers le signalement de station traité |

### `signalement` et ses sous-classes

| Table | Contrainte | Règle |
|---|---|---|
| `signalement` | `pk_signalement` | `id_signalement` ; `date_heure_signalement` vaut la date et l'heure courantes par défaut |
| `signalement` | `ck_signalement_description` | Description non vide |
| `signalement` | `ck_signalement_dates` | `date_heure_cloture` est NULL (ouvert) ou postérieure ou égale au signalement |
| `signalement` | `fk_signalement_utilisateur` | Vers l'auteur |
| `signalement_velo` | `pk_signalement_velo` + `fk_signalement_velo_signalement` | `id_signalement`, vers `signalement`, **ON DELETE CASCADE** |
| `signalement_velo` | `fk_signalement_velo_velo` | Vers le vélo signalé |
| `signalement_velo` | `fk_signalement_velo_intervention` | Vers `intervention_velo` ; NULL = pas encore pris en charge |
| `signalement_station` | `pk_signalement_station` + `fk_signalement_station_signalement` | `id_signalement`, vers `signalement`, **ON DELETE CASCADE** |
| `signalement_station` | `fk_signalement_station_station` | Vers la station signalée |

---

## 2. Règles qui ne s'écrivent pas en contrainte déclarative

Ces règles portent sur plusieurs tables. `structure.sql` les liste en fin de fichier, et `automatisation.sql` les fait respecter.

| N° | Règle | Où elle est garantie |
|---|---|---|
| R1 | Un usager n'a qu'une location en cours à la fois | `trg_location_bi` ; verrou sur l'usager dans `emprunter_velo` |
| R2 | Il faut un abonnement valide le jour de l'emprunt | `trg_location_bi` ; recherche par `fn_abonnement_valide` dans `emprunter_velo` |
| R3 | Un vélo défectueux ou réformé ne peut pas être emprunté | `trg_location_bi` (avec `fn_etat_velo`) |
| R4 | Durée et coût calculés à la restitution ; facture du trajet | `trg_mouvement_au` (avec `fn_duree_minutes` et `fn_cout_trajet`) |
| R5 | Un vélo n'est qu'à un seul endroit ; sa position suit ses mouvements | `trg_mouvement_ai`, `trg_mouvement_au`, `trg_velo_bu` |
| R6 | Un vélo part de la borne où il se trouve, et arrive sur une borne libre et en service d'une station en service | `trg_mouvement_bi` (départ) ; `trg_mouvement_bu` et `trg_velo_bi`, avec `verifier_borne_accueil` (arrivée) |
| R7 | Un vélo n'a qu'un mouvement en cours | `trg_mouvement_bi` : le vélo doit être sur une borne, or sa position est NULL pendant un mouvement ; verrous `FOR UPDATE` |
| R8 | Un mouvement est une location, un transfert **ou** une maintenance | `verifier_mouvement_libre` (appelée par trois triggers) ; les procédures créent toujours le mouvement avec son type |
| R9 | Un signalement porte sur un vélo **ou** sur une station | `trg_signalement_velo_bi` et `trg_signalement_station_bi` (exclusion) ; `signaler_velo` et `signaler_station` (existence) |
| R10 | Une intervention porte sur un vélo **ou** sur une station | `trg_intervention_velo_bi` et `trg_intervention_station_bi` (exclusion) ; `retirer_velo` et `demarrer_intervention_station` (existence) |
| R11 | Date de fin d'abonnement = début + durée de validité - 1 ; un renouvellement appartient au même usager et commence après la fin du précédent | `trg_abonnement_bi`, `trg_abonnement_bu` |
| R12 | Tournée faite par un opérateur de régulation, intervention par un opérateur de maintenance (ou un administrateur) ; seul un usager s'abonne | `trg_tournee_bi`/`bu`, `trg_intervention_bi`/`bu`, `trg_abonnement_bi` |
| R13 | Un signalement de vélo et l'intervention qui le traite concernent le même vélo | `verifier_traitement` ; rattachement automatique par `trg_intervention_velo_ai` |
| R14 | Une intervention commence après son signalement ; les transferts d'une tournée ont lieu pendant la tournée | `verifier_traitement`, `trg_intervention_station_bi`, `trg_transfert_bi`, `trg_tournee_bu`, `trg_mouvement_bu` |

> **Exclusion et existence.** Les triggers interdisent qu'un objet appartienne à deux sous-classes à la fois. En revanche, un trigger ne peut pas exiger qu'une sous-classe existe : la ligne mère est insérée avant la ligne fille. Ce sont donc les procédures qui garantissent qu'un signalement, une intervention ou un mouvement est toujours créé avec son type, dans la même transaction.

---

## 3. Fonctions (`automatisation.sql`)

| Fonction | Renvoie | Rôle | Utilisée par |
|---|---|---|---|
| `fn_etat_velo(p_velo)` | `VARCHAR(12)` | État actuel d'un vélo, c'est-à-dire son dernier changement d'état ; NULL s'il n'en a aucun | `trg_velo_bu`, `trg_changement_etat_bi`, `trg_location_bi`, `trg_intervention_velo_ai` |
| `fn_abonnement_valide(p_utilisateur, p_jour)` | `INT` | Abonnement de l'usager valable ce jour-là (le plus récent s'il y en a plusieurs), ou NULL | `emprunter_velo` |
| `fn_duree_minutes(p_debut, p_fin)` | `INT` | Durée en minutes ; toute minute commencée compte (arrondi au-dessus) | `fn_cout_location`, `trg_mouvement_au`. Après `optimisation.sql`, les vues n'y font plus appel : elles écrivent le calcul directement. |
| `fn_cout_trajet(p_formule, p_minutes, p_electrique, p_casque)` | `DECIMAL(8,2)` | Coût d'un trajet : nombre de tranches entamées au-delà de la durée gratuite × prix d'une tranche, plus le supplément électrique, plus le supplément casque. NULL si la formule ou la durée est inconnue. | `trg_mouvement_au` (facture), `fn_cout_location`, vue `v_location` (coût en cours) |
| `fn_cout_location(p_location, p_casque)` | `DECIMAL(8,2)` | Coût d'une location terminée, à partir de sa formule, de sa durée et du type de vélo ; NULL si elle est en cours | Aucun objet de la base ne l'appelle ; elle est disponible pour l'interface |
| `fn_borne_libre(p_station)` | `SMALLINT` | Plus petit numéro de borne libre et en service, dans une station en service ; NULL s'il n'y en a pas | `enregistrer_arrivee` (choix automatique de la borne) |

## 4. Procédures de contrôle (`automatisation.sql`)

Ces procédures ne s'appellent pas directement : elles regroupent des vérifications partagées par les triggers.

| Procédure | Rôle | Appelée par |
|---|---|---|
| `lever_erreur(p_message)` | Lève une erreur métier (`SIGNAL SQLSTATE '45000'`) avec un message lisible, qui annule l'instruction en cours | Tous les triggers et toutes les procédures |
| `verifier_borne_accueil(p_station, p_numero, p_velo)` | R6 : la borne existe, la station et la borne sont en service, et aucun autre vélo n'occupe la borne | `trg_velo_bi`, `trg_velo_bu`, `trg_mouvement_bu` |
| `verifier_mouvement_libre(p_mouvement)` | R8 : le mouvement est encore en cours, et n'est pas déjà une location, un transfert ou une maintenance | `trg_location_bi`, `trg_transfert_bi`, `trg_intervention_velo_bi` |
| `verifier_traitement(p_signalement, p_velo, p_intervention)` | R13 et R14 : l'intervention porte sur le vélo signalé et a commencé après le signalement | `trg_signalement_velo_bi`, `trg_signalement_velo_bu` |

---

## 5. Triggers (`automatisation.sql`)

Il y a 28 triggers. Nom : `trg_<table>_<moment>`, où `b` signifie `BEFORE`, `a` `AFTER`, `i` `INSERT` et `u` `UPDATE`. Ils servent de filet de sécurité pour les écritures faites directement dans les tables ; la voie normale reste les procédures (§ 6).

### `utilisateur`

| Trigger | Quand | Ce qu'il fait |
|---|---|---|
| `trg_utilisateur_bi` | Avant insertion | Met l'e-mail en minuscules sans espaces autour ; refuse une date d'inscription dans le futur |
| `trg_utilisateur_bu` | Avant modification | Normalise l'e-mail de la même façon |

### `abonnement`

| Trigger | Quand | Ce qu'il fait |
|---|---|---|
| `trg_abonnement_bi` | Avant insertion | Refuse un titulaire qui n'est pas `USAGER` (R12). Prend la date du jour comme début si aucune n'est donnée. **Calcule `date_fin`** à partir de la durée de la formule (R11). Pour un renouvellement : même usager, et début après la fin de l'abonnement précédent. |
| `trg_abonnement_ai` | Après insertion | **Crée la facture de souscription** au prix de la formule |
| `trg_abonnement_bu` | Avant modification | Interdit de changer de titulaire ; recalcule `date_fin` |

### `facture`

| Trigger | Quand | Ce qu'il fait |
|---|---|---|
| `trg_facture_bi` | Avant insertion | Prend la date et l'heure courantes comme `date_emission` si aucune n'est donnée |
| `trg_facture_bu` | Avant modification | **Fige une facture réglée** : montant, dates et cible ne changent plus |

### `velo` et `changement_etat`

| Trigger | Quand | Ce qu'il fait |
|---|---|---|
| `trg_velo_bi` | Avant insertion | Prend la date courante comme mise en service si aucune n'est donnée ; si le vélo est posé sur une borne, vérifie que cette borne peut l'accueillir (R6) |
| `trg_velo_ai` | Après insertion | **Historisation** : enregistre l'état `EN_SERVICE` à la date de mise en service |
| `trg_velo_bu` | Avant modification | R5 : un vélo qui a déjà un mouvement ne change de position que pour celle de son dernier mouvement ; impossible de le déplacer à la main. Un vélo réformé ne revient pas sur une borne. Vérifie la borne d'accueil. |
| `trg_changement_etat_bi` | Avant insertion | Prend la date courante si aucune n'est donnée. Refuse : un nouvel état pour un vélo réformé, un changement antérieur à la mise en service ou au changement précédent, une réforme d'un vélo encore sur sa borne. |

### `mouvement`

| Trigger | Quand | Ce qu'il fait |
|---|---|---|
| `trg_mouvement_bi` | Avant insertion | Un mouvement se crée **au départ, sans arrivée**. Le vélo doit être sur une borne (R7). La borne de départ se déduit de la position du vélo, ou doit lui correspondre (R6). Le départ ne peut pas précéder la mise en service ni la dernière arrivée. |
| `trg_mouvement_ai` | Après insertion | **Historisation** : le vélo quitte sa borne (position NULL) |
| `trg_mouvement_bu` | Avant modification | Un mouvement terminé est figé, et le départ ne se modifie jamais. À l'arrivée : prend la date courante si aucune n'est donnée. Seule une maintenance peut se terminer sans borne (le vélo est alors réformé) ; sinon, la borne d'arrivée est vérifiée (R6). Refuse l'arrivée d'un transfert dont la tournée est déjà clôturée (R14). |
| `trg_mouvement_au` | Après modification (à l'arrivée) | 1. **Position** : le vélo prend la borne d'arrivée, ou aucune s'il est réformé (R5). 2. **Location** : calcule la durée et le coût, et crée la facture si le trajet est payant (R4) ; le choix du casque arrive par la variable de session `@casque`. 3. **Maintenance** : enregistre l'état `EN_SERVICE` (retour sur une borne) ou `REFORME` (pas de borne), puis clôt les signalements traités par l'intervention. |

### `location`, `tournee`, `transfert`

| Trigger | Quand | Ce qu'il fait |
|---|---|---|
| `trg_location_bi` | Avant insertion | Le mouvement doit être libre (R8). L'abonnement doit être valable à la date du départ (R2). L'usager ne doit pas avoir d'autre location en cours (R1). Le vélo doit être `EN_SERVICE` (R3). La station et la borne de départ doivent être en service. |
| `trg_tournee_bi` | Avant insertion | L'opérateur doit être de régulation ou administrateur (R12). La tournée se crée sans date de fin, et un opérateur n'a qu'une tournée en cours. Prend la date courante comme début si aucune n'est donnée. |
| `trg_tournee_bu` | Avant modification | Une tournée clôturée est figée ; le nouvel opérateur éventuel doit avoir le bon rôle. Pour la clôturer, il faut au moins un transfert et tous les vélos déposés avant la fin (R14). |
| `trg_transfert_bi` | Avant insertion | Le mouvement doit être libre (R8), la tournée non clôturée, et le transfert ne peut pas commencer avant la tournée (R14) |

### Interventions

| Trigger | Quand | Ce qu'il fait |
|---|---|---|
| `trg_intervention_bi` | Avant insertion | L'auteur doit être opérateur de maintenance ou administrateur (R12) |
| `trg_intervention_bu` | Avant modification | Même contrôle si on change d'opérateur |
| `trg_intervention_velo_bi` | Avant insertion | L'intervention ne doit pas déjà porter sur une station (R10), et le mouvement doit être libre (R8) |
| `trg_intervention_velo_ai` | Après insertion | **Retrait pour maintenance** : passe le vélo `DEFECTUEUX` s'il ne l'est pas déjà (historisation). **Rattache à l'intervention** les signalements ouverts sur ce vélo, faits avant le retrait. |
| `trg_intervention_station_bi` | Avant insertion | L'intervention ne doit pas déjà porter sur un vélo (R10). Prend la date courante comme début si aucune n'est donnée. Le signalement doit être encore ouvert, et l'intervention ne peut pas commencer avant lui (R14). |
| `trg_intervention_station_bu` | Avant modification | Une intervention terminée est figée |

### Signalements

| Trigger | Quand | Ce qu'il fait |
|---|---|---|
| `trg_signalement_velo_bi` | Avant insertion | Le signalement ne doit pas déjà porter sur une station (R9). Si une intervention est indiquée, elle doit concerner le même vélo et avoir commencé après le signalement (R13, R14). |
| `trg_signalement_velo_bu` | Avant modification | Un signalement ne change pas de vélo ; le rattachement à une intervention est vérifié (R13, R14) |
| `trg_signalement_station_bi` | Avant insertion | Le signalement ne doit pas déjà porter sur un vélo (R9) |

---

## 6. Procédures : une par cas d'utilisation (`automatisation.sql`)

C'est par elles qu'il faut passer pour écrire dans la base. Chaque procédure est une transaction complète : en cas d'erreur, tout est annulé (`ROLLBACK`) et l'erreur est renvoyée à l'appelant (`RESIGNAL`). Les verrous `SELECT … FOR UPDATE` empêchent par exemple deux usagers d'emprunter le même vélo au même instant.

> Une procédure ouvre sa propre transaction. L'appeler au milieu d'une transaction déjà ouverte valide cette dernière.

### Abonnements et factures

| Procédure | Paramètres | Ce qu'elle fait |
|---|---|---|
| `souscrire_abonnement` | `p_utilisateur`, `p_formule`, `p_date_debut` (NULL = aujourd'hui) → `p_abonnement` | Crée l'abonnement. Les triggers calculent la date de fin et créent la facture. |
| `renouveler_abonnement` | `p_abonnement` → `p_nouvel_abonnement` | Crée l'abonnement suivant pour le même usager, avec la même formule. Il commence le lendemain de la fin, ou aujourd'hui si l'ancien a expiré. Refuse un abonnement inconnu ou déjà renouvelé. |
| `regler_facture` | `p_facture` | Enregistre le paiement (`date_reglement` = maintenant). Refuse une facture inconnue ou déjà réglée. |

### Locations

| Procédure | Paramètres | Ce qu'elle fait |
|---|---|---|
| `emprunter_velo` | `p_utilisateur`, `p_velo` → `p_location` | Verrouille l'usager et le vélo, puis cherche son abonnement valide. Crée le mouvement (le vélo quitte sa borne) et la location. Les triggers vérifient R1 à R3, R6 et R7. |
| `restituer_velo` | `p_location`, `p_station`, `p_numero_borne` (NULL = automatique), `p_avec_casque` | Enregistre l'arrivée de la location. Le trigger replace le vélo sur la borne, calcule la durée et le coût, et crée la facture. `p_avec_casque` passe par `@casque` pour ajouter le supplément casque. |
| `enregistrer_arrivee` | `p_mouvement`, `p_station`, `p_numero_borne` | Procédure interne, **sans transaction** : elle est appelée par `restituer_velo`, `deposer_velo` et `remettre_en_circulation`. Elle verrouille la station pour que deux arrivées simultanées ne prennent pas la même borne. Elle refuse une station inconnue ou hors service, choisit une borne libre si aucune n'est donnée (`fn_borne_libre`), puis enregistre l'arrivée. |

### Régulation

| Procédure | Paramètres | Ce qu'elle fait |
|---|---|---|
| `demarrer_tournee` | `p_operateur` → `p_tournee` | Ouvre une tournée de rééquilibrage |
| `charger_velo` | `p_tournee`, `p_velo` → `p_transfert` | Charge un vélo dans le véhicule : crée le mouvement et le transfert ; le vélo quitte sa borne |
| `deposer_velo` | `p_transfert`, `p_station`, `p_numero_borne` (NULL = automatique) | Dépose un vélo chargé sur une borne |
| `cloturer_tournee` | `p_tournee` | Clôt la tournée. Le trigger exige au moins un transfert et tous les vélos déposés. |

### Signalements et maintenance

| Procédure | Paramètres | Ce qu'elle fait |
|---|---|---|
| `signaler_velo` | `p_utilisateur`, `p_velo`, `p_description` → `p_signalement` | Crée le signalement et sa ligne `signalement_velo` dans la même transaction |
| `signaler_station` | `p_utilisateur`, `p_station`, `p_description` → `p_signalement` | Crée le signalement et sa ligne `signalement_station` |
| `cloturer_signalement` | `p_signalement` | Clôt un signalement sans intervention, par exemple un problème inexistant ou déjà résolu |
| `retirer_velo` | `p_operateur`, `p_velo`, `p_description` → `p_intervention` | Crée l'intervention et le mouvement vers l'atelier. Les triggers passent le vélo `DEFECTUEUX` et rattachent ses signalements ouverts. |
| `remettre_en_circulation` | `p_intervention`, `p_station`, `p_numero_borne` (NULL = automatique) | Le vélo réparé revient sur une borne. Les triggers le repassent `EN_SERVICE` et closent les signalements traités. |
| `reformer_velo` | `p_intervention` | Le mouvement de maintenance se termine sans borne. Les triggers passent le vélo `REFORME` et closent les signalements. |
| `demarrer_intervention_station` | `p_operateur`, `p_signalement`, `p_description` → `p_intervention` | Ouvre une intervention de travaux sur le signalement d'une station |
| `terminer_intervention_station` | `p_intervention`, `p_resolu` | Termine l'intervention. Si `p_resolu` est vrai, clôt aussi le signalement ; sinon, une autre intervention pourra suivre. |

### Procédures de `optimisation.sql`

| Procédure | Rôle |
|---|---|
| `executer_sql(p_sql)` | Exécute une instruction écrite dans une chaîne (`PREPARE`). Sert aux syntaxes propres à un seul SGBD : écrites en clair, elles empêcheraient l'autre SGBD de créer la procédure. |
| `rafraichir_statistiques()` | Recalcule les statistiques de l'optimiseur (`ANALYZE TABLE` sur toutes les tables), puis les histogrammes des colonnes filtrées sans index : `role`, `type` de formule, états de station, de borne et de vélo. La syntaxe MySQL ou MariaDB est choisie à l'exécution. |
| `opt_creer_index`, `opt_supprimer_index` | Outils **temporaires** : ils créent ou suppriment un index seulement s'il n'existe pas ou existe encore. Ils sont supprimés à la fin du script. |

---

## 7. Événement planifié (`optimisation.sql`)

| Événement | Fréquence | Rôle |
|---|---|---|
| `evt_rafraichir_statistiques` | Chaque semaine, le lundi à 3 h | Appelle `rafraichir_statistiques()` pour que l'optimiseur garde une image juste de la répartition des données. Les histogrammes ne se mettent pas à jour seuls. |

Il faut que le planificateur soit actif : c'est le cas par défaut sous MySQL 8 et 9. Sous MariaDB, il faut régler `event_scheduler = ON`.

---

## 8. Vues (`automatisation.sql`, six réécrites par `optimisation.sql`)

Les vues réécrites gardent exactement les mêmes colonnes et donnent le même résultat ; seule la façon de le calculer change, pour aller plus vite.

### Flotte et stations (temps réel)

| Vue | Ce qu'elle donne | Réécrite ? |
|---|---|---|
| `v_etat_actuel_velo` | Pour chaque vélo, son état actuel (`etat`) et depuis quand (`etat_depuis`) | Oui : `GROUP BY` + `MAX` sur l'index unique, au lieu de numéroter tout l'historique |
| `v_velo` | Fiche de chaque vélo : type (mécanique ou électrique), batterie, état, **situation** (`SUR_BORNE`, `EN_LOCATION`, `EN_TOURNEE`, `EN_ATELIER`, `REFORME`), station et borne, mouvement en cours, mise en service | Non |
| `v_disponibilite_station` | Pour chaque station : bornes, bornes en service, vélos présents, **vélos disponibles par type** (sur une borne, `EN_SERVICE`, dans une station en service), **bornes libres**, taux de remplissage. Répond au besoin « temps réel » du sujet. | Non |

### Régulation

| Vue | Ce qu'elle donne | Réécrite ? |
|---|---|---|
| `v_regulation` | Stations en service avec leur statut : `VIDE` (aucun vélo disponible), `PLEINE` (aucune borne libre), `PRESQUE_VIDE` (≤ 20 %), `PRESQUE_PLEINE` (≥ 80 %) ou `EQUILIBREE`. `ecart_equilibre` donne les vélos en trop (positif) ou manquants (négatif) par rapport à une station à moitié pleine. | Non |
| `v_proposition_deplacement` | Pour chaque station pleine ou presque pleine qui a des vélos en trop : la station vide ou presque vide la plus proche à vol d'oiseau (`ST_Distance_Sphere`), le nombre de vélos à déplacer et la distance en km | Non |

### Consultation

| Vue | Ce qu'elle donne | Réécrite ? |
|---|---|---|
| `v_location` | Chaque location : usager, formule, vélo et type, stations et dates de départ et d'arrivée, statut (`EN_COURS` ou `TERMINEE`), durée, montant (coût actuel si la location est en cours, sans casque), facture et règlement | Oui : durée calculée directement, sans appel de fonction par ligne |
| `v_abonnement` | Chaque abonnement : usager, formule, dates, **statut** (`A_VENIR`, `ACTIF`, `EXPIRE`, déduit des dates), jours restants, abonnement précédent et renouvellement | Non |
| `v_signalement` | Chaque signalement : cible (`VELO` ou `STATION`), vélo ou station, description, dates, **statut** (`OUVERT`, `EN_TRAITEMENT`, `CLOS`), intervention, auteur | Non |

### Statistiques demandées par le sujet

| Vue | Ce qu'elle donne | Réécrite ? |
|---|---|---|
| `v_stat_trajets_par_jour` | Nombre de trajets par jour et durée moyenne | Oui : durée calculée directement |
| `v_stat_heures_pointe` | Départs de location par heure de la journée, et part de chaque heure en % | Non |
| `v_stat_origine_destination` | Couples station de départ → station d'arrivée, classés du plus fréquent au moins fréquent (rang, nombre de trajets, durée moyenne) | Oui : regroupement sur les identifiants avant la jointure aux stations |
| `v_stat_recettes_formule` | Pour chaque formule : nombre de factures, recettes des abonnements, recettes des locations, total facturé, montant encaissé | Non |
| `v_stat_indisponibilite_flotte` | Par type de vélo et au total (ligne `TOUS`) : vélos en flotte, en service, défectueux, réformés ; taux d'indisponibilité actuel et sur 30 jours (part du temps passé `DEFECTUEUX`) | Oui : ne lit que les changements des 30 derniers jours, plus l'état de chaque vélo au début de la fenêtre |
| `v_stat_remplissage_horaire` | Pour chaque station et chaque heure de la journée : nombre moyen de vélos et taux de remplissage sur les 30 derniers jours. Reconstitué depuis l'historique des mouvements : un vélo occupe une station de son arrivée à son départ suivant, et la mesure se fait à la demi-heure. | Oui : séjours limités à la fenêtre, une seule jointure séjours × instants |

---

## 9. Pour mémoire : index ajoutés par `optimisation.sql`

| Index | Table (colonnes) | Requête servie |
|---|---|---|
| `idx_mouvement_velo_depart` | `mouvement` (`id_velo`, `date_heure_depart`) | Historique et dernier mouvement d'un vélo ; remplace l'index de `fk_mouvement_velo` |
| `idx_mouvement_velo_arrivee` | `mouvement` (`id_velo`, `date_heure_arrivee`) | Mouvement en cours d'un vélo, dernière arrivée |
| `idx_mouvement_depart` | `mouvement` (`date_heure_depart`) | Statistiques et recherches par période |
| `idx_abonnement_utilisateur_fin` | `abonnement` (`id_utilisateur`, `date_fin`) | Abonnement valide à l'emprunt ; remplace l'index de la clé étrangère |
| `idx_facture_emission` | `facture` (`date_emission`) | Recettes par période |
| `idx_facture_reglement` | `facture` (`date_reglement`) | Factures impayées |
| `idx_signalement_ouvert` | `signalement` (`date_heure_cloture`, `date_heure_signalement`) | Signalements ouverts, du plus ancien au plus récent |
| `idx_signalement_velo_traitement` | `signalement_velo` (`id_velo`, `id_intervention_velo`) | Signalements non traités d'un vélo ; remplace l'index de la clé étrangère |
| `idx_intervention_station_signalement` | `intervention_station` (`id_signalement_station`, `date_heure_fin`) | Intervention en cours sur un signalement ; remplace l'index de la clé étrangère |
| `idx_tournee_operateur_fin` | `tournee` (`id_utilisateur`, `date_heure_fin`) | Tournée en cours d'un opérateur ; remplace l'index de la clé étrangère |
| `idx_utilisateur_nom` | `utilisateur` (`nom`, `prenom`) | Recherche d'un utilisateur par nom |

Les index qui existent déjà grâce aux contraintes de `structure.sql` (clés primaires, `UNIQUE`, index des clés étrangères) ne sont pas recréés.

---

## 10. Limites connues

- Les suppressions en cascade (`ON DELETE CASCADE`) ne déclenchent pas les triggers : c'est une limite de MySQL et de MariaDB.
- Le supplément casque n'est stocké nulle part. `restituer_velo` le transmet au trigger par la variable de session `@casque`, puis la remet à NULL.
- Les généralisations `{complete}` (tout mouvement, signalement ou intervention a son type) ne sont garanties que si l'on passe par les procédures (voir § 2).
- La collation `utf8mb4_0900_ai_ci` de `structure.sql` est propre à MySQL. Le `docker-compose.yml` utilise MariaDB 10.11 : il faudra la remplacer par `utf8mb4_unicode_ci` si la base tourne sous MariaDB.

---

## 11. Données factices : `peuplement_velo.py`

Le script, à la racine du dépôt, simule l'activité du réseau puis insère le résultat dans la base. Il remplace `donnes.sql` quand on veut beaucoup de données, par exemple pour les statistiques ou le rapport de performances. Les noms, prénoms et adresses viennent de Faker, en français.

```bash
pip install -r requirements.txt
python peuplement_velo.py --mot-de-passe secret            # volumes par défaut
python peuplement_velo.py --usagers 5000 --jours 730 --vider
```

| Option | Défaut | Rôle |
|---|---|---|
| `--hote`, `--port`, `--utilisateur`, `--mot-de-passe`, `--base` | `127.0.0.1`, `3306`, `root`, vide, `velo_libre_service` | Connexion ; aussi lisibles dans `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` |
| `--usagers` | 3000 | Nombre d'usagers |
| `--stations` | 40 | Nombre de stations (10 au minimum) |
| `--velos` | 55 % des bornes en service | Taille de la flotte |
| `--jours` | 365 | Durée de l'historique |
| `--trajets-par-jour` | 300 | Nombre moyen de trajets par jour |
| `--graine` | 2026 | Graine aléatoire : les mêmes options redonnent les mêmes données |
| `--maintenant` | date courante | Fin de la simulation (`"AAAA-MM-JJ HH:MM"`) |
| `--vider` | non | Vide les tables avant l'insertion |

**Ce qui est simulé**, dans l'ordre chronologique :

- **Personnes et abonnements** : 4 comptes de démonstration, 2 administrateurs, 5 opérateurs de régulation et 5 de maintenance, puis les usagers. Chaque usager a un profil (annuel, mensuel, tarif réduit ou tickets journée), des renouvellements, des pauses et des abandons. Chaque abonnement a sa facture de souscription.
- **Réseau** : stations de l'agglomération de Belfort, bornes et flotte (35 % de vélos électriques). Une station est en travaux et une autre hors service, chacune avec son signalement.
- **Trajets** : demande selon la saison, le jour de la semaine et l'heure (pointes vers 8 h et 17-18 h). Trajets domicile-travail le matin et le soir, balades le week-end. Un trajet n'a lieu que si un vélo est disponible ; à l'arrivée dans une station pleine, l'usager va à la station libre la plus proche. Durée et coût sont calculés comme `fn_cout_trajet`, et la facture est créée si le trajet est payant.
- **Régulation** : tournées plusieurs fois par jour, des stations pleines vers les stations vides.
- **Maintenance** : signalements après certains trajets (vraies pannes ou fausses alertes), blocage à distance de vélos défectueux, retrait, réparation, remise en circulation ou réforme ; révisions périodiques ; signalements et interventions sur les stations.

À la fin de la simulation, la base contient aussi des **situations en cours** : locations, une tournée, des vélos en atelier, des signalements ouverts et des interventions de station en cours.

**Comptes de démonstration** : `admin@velo.example.org`, `regulation@velo.example.org`, `maintenance@velo.example.org` et `usager@velo.example.org`, ce dernier avec un abonnement annuel en cours. Le mot de passe est `velo2026` ; c'est le même pour tous les comptes générés (vraie empreinte bcrypt, vérifiable par `password_verify` en PHP).

**Volumes obtenus avec les options par défaut** : environ 3 000 utilisateurs, 11 700 abonnements, 108 000 mouvements dont 93 000 locations, 13 500 transferts, 67 000 factures, 1 300 tournées et 800 signalements. La génération et l'insertion prennent une trentaine de secondes.

**Vérification** : sur ce volume, toutes les règles R1 à R14 sont respectées (positions, bornes jamais partagées, une location à la fois, abonnement valide, états, rôles, dates, montants). Les procédures de `automatisation.sql` fonctionnent sur la base générée : emprunt, restitution, maintenance, tournée et abonnement.
