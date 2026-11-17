# Rapport d'analyse des performances — Réseau de vélos en libre-service

Ce rapport liste les temps d'exécution des requêtes principales de l'application, avant et après optimisation (index de `optimisation.sql`, vues réécrites), et explique les écarts. Il complète la [documentation de conception](6_documentation.md) (§ 4).

## 1. Environnement de mesure

| Élément | Valeur |
|---|---|
| SGBD | MySQL 8.4.13 (InnoDB), conteneur Docker du projet |
| Machine | 16 processeurs, 3,5 Go de mémoire alloués à Docker |
| Cache InnoDB (`innodb_buffer_pool_size`) | 128 Mo (valeur par défaut) |
| Date | 12 novembre 2026 |

**Volume de données** (jeu par défaut de `peuplement_velo.py`, plus quelques heures de simulation) :

| Table | Lignes | Table | Lignes |
|---|---:|---|---:|
| utilisateur | 8 033 | mouvement | 363 747 |
| abonnement | 30 902 | location | 279 750 |
| station | 122 | transfert | 80 107 |
| borne | 1 681 | facture | 310 631 |
| velo | 1 030 | changement_etat | 9 791 |
| tournee | 7 081 | signalement | 2 110 |

## 2. Méthode

Les mesures sont faites par le script `Velo-Simulateur/performances/banc_performances.py`, qu'on peut rejouer (§ 6).

- **Requêtes mesurées (28)** : 19 requêtes exécutées par le site (disponibilités, recherches, tableau de bord, statistiques sur 30 jours…), les 6 vues de statistiques demandées par le sujet et les 3 écritures les plus fréquentes.
- **Mesure** : un passage d'échauffement pour mettre les données en mémoire, puis 10 exécutions, dont on garde la **médiane**. Une requête de plus de 2 s n'est mesurée que 3 fois. Le temps comprend la lecture de toutes les lignes du résultat par le client, comme dans le site.
- **Lignes lues** : somme des compteurs `Handler_read_*` du moteur pendant la requête, c'est-à-dire le nombre de lignes parcourues dans les index ou les tables. Ce compteur explique les temps mieux que le chronomètre, qui varie d'une exécution à l'autre.
- **Écritures** : un emprunt, une restitution et une souscription, exécutés avec leurs triggers dans une transaction **annulée** à la fin. Aucune donnée n'est modifiée.
- **Conditions** : la simulation d'activité (`simulation.sql`) est suspendue pendant la mesure, puis relancée.
- **Deux états de la même base** :
  - **avant** : les vues dans leur version de référence et les seuls index des clés primaires, étrangères et `UNIQUE` (script `performances/sans_optimisation.sql`) ;
  - **après** : l'état normal, soit les vues optimisées de `automatisation.sql`, plus les 12 index ciblés et les histogrammes de l'optimiseur de `optimisation.sql`.

## 3. Résultats

Temps médian par requête ; le gain est le rapport entre le temps avant et le temps après.

| Requête | Avant | Après | Gain | Lignes lues avant | Lignes lues après |
|---|---:|---:|---:|---:|---:|
| **Temps réel** | | | | | |
| Disponibilité de toutes les stations | 70,6 ms | 28,0 ms | × 2,5 | 18 000 | 11 276 |
| Recherche de stations (« gare »), page Stations | 62,8 ms | 25,6 ms | × 2,5 | 18 024 | 11 300 |
| Fiche d'une station | 33,4 ms | 7,0 ms | × 4,8 | 9 879 | 2 168 |
| Fiche de tous les vélos (`v_velo`) | 1,49 s | 36,2 ms | × 41 | 379 779 | 9 316 |
| Locations en cours | 1,44 s | 20,2 ms | × 71 | 379 779 | 9 316 |
| **Usager** | | | | | |
| 20 derniers trajets d'un usager | 4,0 ms | 3,2 ms | × 1,2 | 104 | 104 |
| Abonnement valide (vérifié à chaque emprunt) | 1,1 ms | 0,7 ms | × 1,6 | 3 | 3 |
| Dernier mouvement d'un vélo (triggers) | 2,2 ms | 1,3 ms | × 1,6 | 299 | 1 |
| **Exploitation** | | | | | |
| Stations à réguler (`v_regulation`) | 48,9 ms | 27,2 ms | × 1,8 | 17 913 | 11 189 |
| Propositions de déplacement | 92,5 ms | 50,0 ms | × 1,8 | 35 651 | 22 205 |
| Signalements ouverts | 2,0 ms | 0,9 ms | × 2,1 | 2 113 | 9 |
| Factures à régler | 184 ms | 52,1 ms | × 3,5 | 310 602 | 2 641 |
| Recherche d'utilisateurs (« martin ») | 11,4 ms | 6,0 ms | × 1,9 | 8 036 | 1 379 |
| Trajets d'une station sur 7 jours | 41,5 ms | 58,8 ms | × 0,7 | 10 204 | 10 204 |
| **Statistiques du site (30 jours)** | | | | | |
| Indicateurs du tableau de bord | 3,74 s | 229 ms | × 16 | 1 857 514 | 178 665 |
| Trajets par jour | 242 ms | 204 ms | × 1,2 | 445 104 | 125 671 |
| Départs par heure | 206 ms | 103 ms | × 2,0 | 445 097 | 125 664 |
| 10 trajets origine-destination les plus fréquents | 313 ms | 269 ms | × 1,2 | 454 844 | 135 469 |
| Recettes par formule | 2,20 s | 526 ms | × 4,2 | 765 977 | 260 220 |
| **Vues de statistiques du sujet** | | | | | |
| `v_stat_trajets_par_jour` (tout l'historique) | 2,70 s | 1,47 s | × 1,8 | 839 977 | 839 986 |
| `v_stat_heures_pointe` (tout l'historique) | 1,18 s | 1,17 s | × 1,0 | 839 387 | 839 396 |
| `v_stat_origine_destination` (tout l'historique) | 4,28 s | 2,06 s | × 2,1 | 1 362 370 | 902 876 |
| `v_stat_recettes_formule` (tout l'historique) | 4,88 s | 4,83 s | × 1,0 | 1 390 643 | 1 390 713 |
| `v_stat_indisponibilite_flotte` (30 jours) | 1,56 s | 50,6 ms | × 31 | 474 878 | 39 613 |
| `v_stat_remplissage_horaire` (30 jours) | **> 180 s** (interrompue) | 2,23 s | > × 80 | — | 1 465 152 |
| **Écritures (triggers compris)** | | | | | |
| Emprunt : mouvement + location | 12,0 ms | 8,6 ms | × 1,4 | 1 141 | 206 |
| Restitution : arrivée, position, facture | 9,7 ms | 4,9 ms | × 2,0 | 955 | 20 |
| Souscription : abonnement + facture (R22) | 4,0 ms | 3,8 ms | × 1,1 | 4 | 4 |

**En résumé**
- **Pages du site** : toutes répondent en moins de 300 ms, sauf les recettes du tableau de bord des statistiques (0,5 s) et le taux de remplissage horaire (2,2 s). Avant l'optimisation, cinq d'entre elles dépassaient la seconde : la fiche des vélos, les locations en cours, le tableau de bord, les recettes et le remplissage.
- **Écritures** : un emprunt ou une restitution, triggers compris, prend moins de 10 ms.
- **Statistiques sur tout l'historique** : elles restent entre 1 et 5 s (§ 5).

## 4. Analyse des gains principaux

**Fiche des vélos, locations en cours, tableau de bord (× 16 à × 71).** La vue `v_velo` cherche, pour chaque vélo, son mouvement en cours (`date_heure_arrivee IS NULL`). Avec le seul index de clé étrangère sur `id_velo`, le moteur relit les quelque 350 mouvements de chaque vélo pour en trouver un : 1 030 × 353 ≈ 380 000 lignes lues. L'index `idx_mouvement_velo_arrivee (id_velo, date_heure_arrivee)` mène directement au mouvement en cours, d'où environ 9 000 lignes lues. Le tableau de bord en profite (il compte les locations en cours), ainsi que de `idx_mouvement_depart`, qui limite le comptage des trajets aux 30 derniers jours au lieu de toute la table.

**Remplissage horaire (> 180 s → 2,2 s).** La vue d'origine compte, pour chacun des 86 000 couples (station, heure) des 30 derniers jours, les séjours présents à cet instant parmi tout l'historique : son coût croît comme stations × instants × séjours, et elle n'a pas fini en 3 minutes. La vue réécrite ne garde que les mouvements de la fenêtre, puis compte les vélos présents par somme cumulée (+1 à l'arrivée, −1 au départ). Son coût croît comme séjours + stations × instants. Le résultat est identique, vérifié ligne à ligne.

**Indisponibilité de la flotte (× 31).** L'état actuel des vélos (`v_etat_actuel_velo`) était calculé par `ROW_NUMBER()` sur tout l'historique des états. Il est maintenant calculé par « dernier élément de chaque groupe » (`GROUP BY id_velo` + `MAX`), lu dans l'index unique `(id_velo, date_heure_changement)`. L'estimation de l'optimiseur passe de 37 millions de lignes intermédiaires à 113 000.

**Dernier mouvement, signalements ouverts.** Ces requêtes sont exécutées par les triggers ou affichées en permanence. Avec un index trié (`(id_velo, date_heure_depart)`, `(date_heure_cloture, date_heure_signalement)`), elles lisent 1 et 9 lignes au lieu de 299 et 2 113. Le temps change peu à cette échelle, mais il ne croîtra plus avec l'historique.

**Écritures.** Les triggers d'un emprunt et d'une restitution lisent 206 et 20 lignes, au lieu de 1 141 et 955 : dernière arrivée du vélo, location en cours de l'usager, borne libre. L'usager attend moins de 10 ms par action.

**Factures à régler (× 3,5).** Un premier index sur `date_reglement` seul était plus lent qu'avant optimisation (227 ms contre 184 ms) : 81 900 des 84 500 factures non réglées sont des trajets à 0 €, qui n'ont rien à payer. L'index `idx_facture_a_regler (date_reglement, montant)` ne lit que les 2 624 factures réellement à payer.

## 5. Limites et pistes d'amélioration

- **Statistiques sur tout l'historique (1 à 5 s)** : ces vues agrègent toutes les locations ou toutes les factures, ce qu'aucun index ne peut éviter. Le site ne les utilise pas : sa page Statistiques interroge les 30, 90 ou 365 derniers jours. Si l'historique grandit, ces agrégats pourront être pré-calculés chaque nuit.
- **Recettes par formule (0,5 s sur 30 jours)** : la requête parcourt tous les abonnements avant de filtrer les factures par date. Partir des factures de la période (`idx_facture_emission`) diviserait le travail.
- **Trajets d'une station sur une période (× 0,7)** : l'écart vient de la charge de Docker (minimum identique de 39 ms avant et après). Un index `(id_station_depart, date_heure_depart)` réduirait la lecture à la période demandée.
- **Variabilité** : sous Docker, deux exécutions de la même requête peuvent varier de ± 30 %. Un écart inférieur à 1,5 fois n'est significatif que si le nombre de lignes lues change aussi.

## 6. Reproduire les mesures

Le script `Velo-Simulateur/performances/banc_performances.py` mesure l'état courant de la base : `--etat avant` après `performances/sans_optimisation.sql`, `--etat apres` après `data/automatisation.sql` puis `data/optimisation.sql`, et `--comparer` produit le tableau comparatif. Les résultats bruts (temps, lignes lues, plan `EXPLAIN`) sont dans `performances/resultats_avant.json` et `performances/resultats_apres.json`.
