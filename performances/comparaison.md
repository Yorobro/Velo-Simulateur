| Requête | Avant | Après | Gain | Lignes lues avant | Lignes lues après |
|---|---:|---:|---:|---:|---:|
| **Temps réel** | | | | | |
| Disponibilité de toutes les stations | 70,6 ms | 28,0 ms | × 2,5 | 18 000 | 11 276 |
| Recherche de stations (« gare »), page Stations | 62,8 ms | 25,6 ms | × 2,5 | 18 024 | 11 300 |
| Fiche d'une station | 33,4 ms | 7,0 ms | × 4,8 | 9 879 | 2 168 |
| Fiche de tous les vélos (v_velo) | 1,49 s | 36,2 ms | × 41,1 | 379 779 | 9 316 |
| Locations en cours | 1,44 s | 20,2 ms | × 71,3 | 379 779 | 9 316 |
| **Usager** | | | | | |
| 20 derniers trajets d'un usager | 4,0 ms | 3,2 ms | × 1,2 | 104 | 104 |
| Abonnement valide (vérifié à chaque emprunt) | 1,1 ms | 0,7 ms | × 1,6 | 3 | 3 |
| Dernier mouvement d'un vélo (triggers de mouvement) | 2,2 ms | 1,3 ms | × 1,6 | 299 | 1 |
| **Exploitation** | | | | | |
| Stations à réguler (v_regulation) | 48,9 ms | 27,2 ms | × 1,8 | 17 913 | 11 189 |
| Propositions de déplacement | 92,5 ms | 50,0 ms | × 1,8 | 35 651 | 22 205 |
| Signalements ouverts | 2,0 ms | 0,9 ms | × 2,1 | 2 113 | 9 |
| Factures impayées | 184 ms | 52,1 ms | × 3,5 | 310 602 | 2 641 |
| Recherche d'utilisateurs (« martin »), page Utilisateurs | 11,4 ms | 6,0 ms | × 1,9 | 8 036 | 1 379 |
| Trajets d'une station sur 7 jours | 41,5 ms | 58,8 ms | × 0,7 | 10 204 | 10 204 |
| **Statistiques (site, 30 j)** | | | | | |
| Indicateurs du tableau de bord | 3,74 s | 229 ms | × 16,3 | 1 857 514 | 178 665 |
| Trajets par jour | 242 ms | 204 ms | × 1,2 | 445 104 | 125 671 |
| Départs par heure | 206 ms | 103 ms | × 2,0 | 445 097 | 125 664 |
| 10 trajets origine-destination les plus fréquents | 313 ms | 269 ms | × 1,2 | 454 844 | 135 469 |
| Recettes par formule | 2,20 s | 526 ms | × 4,2 | 765 977 | 260 220 |
| **Vues de statistiques** | | | | | |
| v_stat_trajets_par_jour (tout l'historique) | 2,70 s | 1,47 s | × 1,8 | 839 977 | 839 986 |
| v_stat_heures_pointe (tout l'historique) | 1,18 s | 1,17 s | × 1,0 | 839 387 | 839 396 |
| v_stat_origine_destination (tout l'historique) | 4,28 s | 2,06 s | × 2,1 | 1 362 370 | 902 876 |
| v_stat_recettes_formule (tout l'historique) | 4,88 s | 4,83 s | × 1,0 | 1 390 643 | 1 390 713 |
| v_stat_indisponibilite_flotte (30 jours) | 1,56 s | 50,6 ms | × 30,8 | 474 878 | 39 613 |
| v_stat_remplissage_horaire (30 jours) | > 180 s | 2,23 s | > × 81 | — | 1 465 152 |
| **Écritures (triggers compris)** | | | | | |
| Emprunt : mouvement + location | 12,0 ms | 8,6 ms | × 1,4 | 1 141 | 206 |
| Restitution : arrivée, position, facture | 9,7 ms | 4,9 ms | × 2,0 | 955 | 20 |
| Souscription : abonnement + facture (R22) | 4,0 ms | 3,8 ms | × 1,1 | 4 | 4 |
