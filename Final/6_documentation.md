# Documentation de conception — Réseau de vélos en libre-service

Ce document justifie la conception de la base de données et présente les fonctionnalités réalisées, au regard du sujet (`A26_Velo_Libre_Service.pdf`). Le détail se trouve dans les autres livrables :

| Livrable | Fichier |
|---|---|
| Diagramme de cas d'utilisation | [1_cas_utilisation](1_cas_utilisation_complet.svg) |
| Modèle conceptuel (MCD) | [2_mcd](2_mcd_uml.svg) |
| Modèle logique (MLD), règles R1 à R22, traçabilité | [3_mld](3_mld.md) |
| Rapport d'analyse des performances | [7_rapport_performances.md](7_rapport_performances.md) |
| Structure, automatisation, optimisation, simulation | `Velo-Simulateur/data/structure.sql`, `automatisation.sql`, `optimisation.sql`, `simulation.sql` |
| Données factices | `Velo-Simulateur/peuplement_velo.py` |
| Interface web | `Velo-Simulateur/web/` |

**SGBD** : MySQL 8.4 (compatible MySQL 9 et MariaDB 10.11), moteur InnoDB, jeu de caractères utf8mb4.

---

## 1. Démarche

1. **Cas d'utilisation** : les fonctionnalités sont réparties entre quatre acteurs (usager, opérateur de régulation, opérateur de maintenance, administrateur). L'administrateur hérite des droits des deux opérateurs.
2. **MCD** : une classe par concept du sujet. Les généralisations servent quand plusieurs objets partagent une partie commune (mouvements, signalements, interventions, vélos).
3. **MLD** : traduction systématique (une relation par classe, une clé étrangère par association), puis vérification de la 3NF.
4. **SQL** : tout ce qui peut être déclaratif l'est (clés, `UNIQUE`, `CHECK`, `ENUM`). Les règles qui portent sur plusieurs tables sont écrites en triggers et en procédures stockées.

La base garantit seule sa cohérence : une écriture faite directement en SQL est soumise aux mêmes règles qu'une action du site.

---

## 2. Conception de la base

### 2.1 Vue d'ensemble : 20 relations

| Domaine | Relations |
|---|---|
| Comptes et tarifs | `utilisateur`, `formule`, `abonnement`, `facture` |
| Réseau | `station`, `borne` |
| Flotte | `velo`, `velo_electrique`, `changement_etat` |
| Déplacements | `mouvement`, `location`, `transfert` |
| Régulation | `vehicule`, `tournee` |
| Signalements et maintenance | `signalement`, `signalement_velo`, `signalement_station`, `intervention`, `intervention_velo`, `intervention_station` |

### 2.2 Choix de modélisation et justification

| Choix | Justification |
|---|---|
| **Un seul `utilisateur`, avec un `role`** (USAGER, OPERATEUR_REGULATION, OPERATEUR_MAINTENANCE, ADMINISTRATEUR) | Tous les acteurs ont les mêmes attributs et se connectent de la même façon. Une table par acteur dupliquerait l'authentification. Les droits propres à chaque rôle sont vérifiés par la base (R12) et par le routeur web. |
| **Les formules sont des lignes de `formule`**, pas une énumération | Le sujet cite quatre formules (ticket journée, mensuel, annuel, tarif réduit), mais l'exploitant doit pouvoir en créer ou en changer les tarifs sans modifier le schéma. `libelle` est une clé candidate (`UNIQUE`). |
| **`abonnement` est réflexif** (`id_abonnement_precedent`, `UNIQUE`) | Un renouvellement est un nouvel abonnement, avec sa propre période et sa propre facture, relié au précédent. L'historique des souscriptions reste complet. L'expiration n'est pas stockée : elle se déduit de `date_fin`. |
| **`borne` a un identifiant relatif** (clé `(id_station, numero)`) | Une borne n'existe que dans sa station, et son numéro n'est unique que dans celle-ci (borne n°3 de la station 12). Le nombre de bornes d'une station se compte, il n'est pas stocké. |
| **La position du vélo est une clé étrangère `UNIQUE (id_station, numero_borne)` dans `velo`** | Un vélo n'a qu'une position (une seule ligne par vélo) et une borne n'accueille qu'un vélo (`UNIQUE`). Un `CHECK` impose que la station et la borne soient renseignées ensemble. NULL signifie que le vélo est en mouvement (location, tournée, atelier) ou réformé. |
| **Le type de vélo vient de la sous-table `velo_electrique`** | Seul un vélo électrique a un niveau de batterie. Une colonne `type` plus une colonne `batterie` souvent NULL serait redondante. Ici, un vélo est électrique si et seulement s'il a une ligne dans `velo_electrique`. |
| **L'état du vélo est historisé** dans `changement_etat` (EN_SERVICE, DEFECTUEUX, REFORME) | L'état actuel est le dernier changement : le stocker aussi dans `velo` créerait une redondance qui pourrait diverger. |
| **Un `mouvement` généralise location, transfert et maintenance** | Tout déplacement d'un vélo (emprunt, tournée de régulation, retrait pour l'atelier) a un départ d'une borne et une arrivée. Une seule table donne l'historique complet des déplacements. Les sous-tables portent ce qui est propre à chaque type : abonnement et casque pour `location`, tournée pour `transfert`. |
| **Une seule table `facture`**, avec deux clés facultatives (`id_abonnement`, `id_location`) et un `CHECK` « exactement une cible » | Toutes les recettes sont au même endroit, ce qui simplifie les statistiques par formule. Les deux clés sont `UNIQUE` : un abonnement ou un trajet n'est jamais facturé deux fois, donc jamais compté deux fois dans les recettes. Le montant est figé dans la facture, car les tarifs de la formule peuvent changer ensuite. |
| **`signalement` et `intervention` sont généralisés** (sur vélo ou sur station) | Les deux cas partagent l'auteur, la date et la description, mais leur cible diffère. Une intervention sur vélo passe par un mouvement (retrait puis remise en circulation), une intervention sur station a ses propres dates. |
| **`vehicule` est une table**, reliée à `tournee` | Le sujet demande d'enregistrer le véhicule d'une tournée. Sa capacité limite le nombre de vélos chargés (R15). |

### 2.3 Intégrité : déclaratif d'abord, triggers ensuite

**Contraintes déclaratives** (`structure.sql`) :
- 20 clés primaires et 29 clés étrangères. La suppression d'une ligne encore référencée est refusée, ce qui protège l'historique. Seules les sous-classes et les bornes d'une station sont supprimées en cascade.
- 34 `CHECK`, par exemple : format de l'e-mail et du téléphone, empreinte de mot de passe d'au moins 60 caractères, prix positifs, dates d'arrivée postérieures au départ, batterie entre 0 et 100, facture à une seule cible, facture à 0 € jamais « réglée ».
- `UNIQUE` sur les clés candidates : e-mail, libellé de formule, immatriculation, adresse et coordonnées d'une station, borne d'un vélo, cibles d'une facture.
- `ENUM` pour les domaines fermés : rôles, états des stations, des bornes et des vélos.

**Règles sur plusieurs tables** (R1 à R22) : elles ne peuvent pas s'écrire en contrainte déclarative et sont garanties par les triggers et les procédures de `automatisation.sql`. Les principales : une seule location en cours par usager, abonnement valide et vélo en état de marche pour emprunter (R1 à R3), durée et coût calculés à la restitution (R4), un vélo à un seul endroit (R5 à R7), un seul abonnement à la fois (R22). Le texte complet de chaque règle et son mécanisme sont au § 4 de [3_mld.md](3_mld.md).

### 2.4 Troisième forme normale

- **1NF** : attributs atomiques. L'adresse et le code postal sont séparés, de même que la latitude et la longitude.
- **2NF** : seule `borne` a une clé composée, et son unique attribut (`etat`) dépend de la borne entière.
- **3NF (et BCNF)** : aucun attribut non clé ne dépend d'un autre attribut non clé. Les seules autres dépendances partent de clés candidates déclarées `UNIQUE`.
- **Rien de calculable n'est stocké** : durée d'un trajet, type et état actuel d'un vélo, position « en location / en tournée / en atelier », nombre de bornes, vélos disponibles, abonnement en cours ou expiré, charge d'un véhicule. Tout se déduit par des vues ou des fonctions. Exception : `facture.montant`, qui fige le prix au moment de la facturation.

---

## 3. Automatisation
 `automatisation.sql` contient :

- **31 triggers** : contrôles des règles R1 à R22, et calculs automatiques (date de fin d'abonnement, position du vélo, facture d'abonnement et de trajet, changements d'état, rattachement des signalements à l'intervention qui les traite, clôture des signalements traités, e-mail en minuscules).
- **6 fonctions** : `fn_etat_velo`, `fn_abonnement_valide`, `fn_duree_minutes`, `fn_cout_trajet`, `fn_cout_location`, `fn_borne_libre`.
- **Une procédure stockée par cas d'utilisation** : `emprunter_velo`, `restituer_velo`, `souscrire_abonnement`, `renouveler_abonnement`, `regler_facture`, `demarrer_tournee`, `charger_velo`, `deposer_velo`, `cloturer_tournee`, `signaler_velo`, `signaler_station`, `retirer_velo`, `remettre_en_circulation`, `reformer_velo`, `creer_station`, etc. Chaque procédure est **une transaction complète** : tout est validé, ou tout est annulé en cas d'erreur. Elle pose des verrous (`SELECT … FOR UPDATE`) qui empêchent, par exemple, deux usagers d'emprunter le même vélo au même instant.

Les procédures sont nécessaires en plus des triggers : une généralisation complète (un signalement porte forcément sur un vélo ou une station) ne peut pas être contrôlée par un trigger, puisque la ligne mère est insérée avant la ligne fille. La procédure crée les deux lignes dans la même transaction ; les triggers protègent les écritures directes.

**Exemple : un emprunt puis une restitution**

1. `emprunter_velo` vérifie l'abonnement, puis insère le mouvement et la location. Les triggers contrôlent R1 à R3, R6 et R7, et retirent le vélo de sa borne (position NULL).
2. `restituer_velo` choisit une borne libre et enregistre l'arrivée. Les triggers posent le vélo sur cette borne, calculent la durée et le coût, et créent la facture du trajet.

---

## 4. Optimisation

`optimisation.sql` ajoute 12 index, chacun justifié par la requête qu'il sert (par exemple `abonnement (id_utilisateur, date_fin)` pour l'abonnement valide vérifié à chaque emprunt), et des histogrammes de l'optimiseur recalculés chaque semaine. Les vues les plus lourdes (état des vélos, statistiques) sont écrites directement dans leur version optimisée dans `automatisation.sql`.

Les temps d'exécution des 28 requêtes principales, avant et après optimisation, sont dans le [rapport d'analyse des performances](7_rapport_performances.md). Ils se mesurent aussi en direct depuis la page « Requêtes » de l'interface.

---

## 5. Fonctionnalités

### 5.1 Fonctionnalités clés

| Fonctionnalité | Dans la base | Dans l'interface web |
|---|---|---|
| **Connexion et authentification** | `utilisateur` (e-mail unique, empreinte bcrypt, rôle) | Inscription, connexion et déconnexion ; menus et pages selon le rôle ; gestion des comptes et des rôles par l'administrateur |
| **Gestion des stations** : description, état, vélos disponibles par type et bornes libres en temps réel | `station`, `borne`, vue `v_disponibilite_station` | Liste avec recherche (nom, adresse, code postal) et filtre par état ; fiche détaillée (bornes, vélos présents) ; création, modification, suppression ; ajout de bornes et changement de leur état |
| **Gestion de la flotte** : type, mise en service, état, batterie, position, historique | `velo`, `velo_electrique`, `changement_etat`, `mouvement` ; vue `v_velo` | Espace maintenance (onglets vélos, stations, signalements) ; vélos présents sur la fiche de chaque station |
| **Abonnements et tarification** : formules, souscription, renouvellement, expiration | `formule`, `abonnement`, `facture` ; R11, R18, R22 ; vue `v_abonnement` | Formules et tarifs ; souscription, renouvellement, changement de formule (avec confirmation) ; historique et statut des abonnements ; modification des tarifs par l'administrateur |
| **Gestion des locations** : emprunt, restitution, règles métier, durée, coût, facturation | `mouvement`, `location`, `facture` ; R1 à R7, R4 ; vue `v_location` | Emprunt (choix de la station puis du vélo, casque en option) ; restitution (choix de la station d'arrivée) ; coût en cours affiché ; historique des trajets ; factures et paiement |
| **Signalements et maintenance** | `signalement…`, `intervention…` ; R9, R10, R13, R19, R20 | Signaler un vélo ou une station ; retrait d'un vélo, remise en circulation, réforme, clôture d'une fausse alerte, travaux de station |
| **Régulation** : stations pleines ou vides, propositions de déplacements, tournées | Vues `v_regulation`, `v_proposition_deplacement` ; `tournee`, `vehicule`, `transfert` ; R14 à R17 | Stations à rééquilibrer et propositions ; démarrage d'une tournée (choix du véhicule), chargement, dépôt, clôture |
| **Statistiques** : trajets par période, heures de pointe, origine-destination, remplissage par tranche horaire, recettes par formule, indisponibilité de la flotte | Une vue `v_stat_*` par statistique demandée | Tableau de bord des statistiques sur 30 jours, 3 mois ou 12 mois ; page du taux de remplissage par station et par heure |

L'interface couvre donc les quatre parties exigées (authentification, stations, locations, statistiques) et va plus loin : abonnements, signalements, maintenance, régulation et administration.

### 5.2 Exigences générales du sujet

| Exigence | Réalisation |
|---|---|
| Ajouter, modifier, supprimer | Stations et bornes, utilisateurs et rôles, formules ; emprunts, restitutions, abonnements, signalements, interventions, tournées |
| Rechercher | Stations par nom, adresse ou code postal ; utilisateurs par nom, prénom ou e-mail |
| Filtrer | Stations par état, utilisateurs par rôle, signalements par statut et par cible, statistiques par période |
| Statistiques et rapports | Vues `v_stat_*` ; page « Requêtes » qui exécute et chronomètre les requêtes d'analyse, plus une console SQL en lecture seule pour l'administrateur |
| Formulaires | Toutes les actions passent par des formulaires validés côté serveur. Les actions irréversibles ou payantes demandent une confirmation. |
| Multi-utilisateurs | Inscription et connexion, 4 rôles, verrous de la base contre les accès concurrents |
| 3NF | § 2.4 |

### 5.3 Architecture de l'interface

PHP 8.2 sans framework : Twig pour les gabarits, FastRoute pour le routage, PDO pour la base. Le code est organisé en couches (`Domain`, `Application`, `Infrastructure`, `Presentation`). Les écritures passent par les procédures stockées et les lectures par les vues : la logique métier reste dans la base, et l'interface ne fait que l'appeler.

---

## 6. Sécurité et confidentialité

- **Mots de passe** : stockés uniquement sous forme d'empreinte bcrypt (`password_hash`). Un `CHECK` refuse une valeur trop courte pour être une empreinte.
- **Injections SQL** : toutes les requêtes de l'application sont préparées avec PDO. La console SQL de l'administrateur s'exécute dans une transaction `READ ONLY`.
- **Sessions et formulaires** : jeton CSRF sur chaque formulaire, identifiant de session régénéré à la connexion.
- **Droits** : chaque route déclare les rôles autorisés, et la base revérifie les rôles (R12). Un usager ne peut agir que sur ses propres locations, abonnements et factures.
- **Données personnelles** : aucune donnée bancaire n'est stockée. Le paiement n'enregistre que la date de règlement.

---

## 7. Données factices et simulation d'activité

- **`peuplement_velo.py`** simule un an d'activité avec Faker, en respectant toutes les règles : 8 000 usagers, 122 stations sur 35 communes, environ 1 700 bornes, 1 000 vélos (40 % électriques), 10 véhicules, 30 000 abonnements et 280 000 trajets. Les trajets ont des heures de pointe, des allers-retours domicile-travail et des variations saisonnières, et la maintenance comme la régulation sont simulées. La base contient aussi des situations en cours (locations, tournée, vélos à l'atelier, signalements ouverts) et quatre comptes de démonstration.
- **`simulation.sql`** fait vivre la base en temps réel grâce à des événements MySQL : emprunts et restitutions, recharge des batteries, signalements, maintenance, tournées, paiements, inscriptions et renouvellements. Tout passe par les procédures stockées, donc par les règles. Le « mode démo » multiplie le volume par 5 pour que les disponibilités changent à l'œil nu.

---

## 8. Limites

- **Casque** : seul `location.avec_casque` est stocké. Il n'y a ni stock de casques par station ni suivi d'un casque non rendu (le cas « Déposer un casque » n'a pas de donnée propre).
- **Changement de formule** : il est programmé à la fin de l'abonnement en cours, qui n'est ni écourté ni remboursé. Cela évite de modifier une période déjà facturée et déjà utilisée par des trajets.
- **Propositions de déplacement et statistiques** : ce sont des vues, recalculées à chaque lecture. Rien n'est stocké, donc rien ne peut être périmé ; le coût de calcul est maîtrisé par les index et la réécriture des vues (§ 4).
- **Généralisations complètes** : leur côté « existence » (une ligne mère a toujours une ligne fille) repose sur les procédures. Une insertion directe de la seule ligne mère reste possible hors de l'interface.
