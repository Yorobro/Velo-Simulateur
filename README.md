# Velo-Simulateur

Réseau de vélos en libre-service : projet de base de données BD70.

## Base de données

Les scripts SQL sont dans `data/`. Le fichier [`data/memo.md`](data/memo.md) décrit chaque contrainte, fonction, procédure, trigger, événement et vue.

Ordre de chargement (MySQL 8.4 LTS ou 9.x) :

1. `data/structure.sql` : tables et contraintes (recrée la base de zéro) ;
2. `peuplement_velo.py` : données factices en grand volume, générées avec Faker (ou, pour un petit jeu de données écrit à la main, `data/donnes.sql`) ;
3. `data/automatisation.sql` : fonctions, procédures, triggers, vues ;
4. `data/optimisation.sql` : index, vues optimisées, statistiques ;
5. `data/simulation.sql` : événements planifiés qui simulent l'activité du réseau en temps réel (facultatif).

```bash
mysql -u root -p < data/structure.sql
pip install -r requirements.txt
python peuplement_velo.py --mot-de-passe <mot de passe MySQL>
mysql -u root -p velo_libre_service < data/automatisation.sql
mysql -u root -p velo_libre_service < data/optimisation.sql
mysql -u root -p velo_libre_service < data/simulation.sql
```

Par défaut, `peuplement_velo.py` simule un an d'activité : 8 000 usagers, 122 stations réparties sur 35 communes (Grand Belfort, sud du Territoire, pays d'Héricourt et de Montbéliard), environ 1 700 bornes, 1 000 vélos (40 % électriques), 10 véhicules de régulation, 30 000 abonnements et 280 000 trajets. `python peuplement_velo.py --help` liste les options (volumes, durée, connexion, `--vider` pour remplacer les données).

### Règle des abonnements

Un usager n'a qu'un abonnement à la fois (règle R22, triggers de `abonnement`) : deux abonnements d'un même usager ne peuvent pas se chevaucher. Renouveler reste possible. Changer de formule programme le nouvel abonnement au lendemain de la fin de l'actuel, qui n'est pas écourté ; l'interface demande une confirmation avant ce changement.

### Simulation d'activité

`data/simulation.sql` crée des événements MySQL (planificateur `event_scheduler`, actif par défaut sous MySQL 8 et 9) qui font vivre la base : emprunts et restitutions selon l'heure de la journée, recharge des vélos électriques, signalements, maintenance (réparations, réformes, travaux de station), tournées de régulation, règlement des factures, inscriptions, renouvellements et changements de formule. Tout passe par les procédures stockées, donc par les triggers : un emprunt retire vraiment le vélo de sa borne, une restitution le pose sur une borne libre de la station d'arrivée et crée la facture. L'usager part le plus souvent de sa station habituelle à cette heure (domicile le matin, travail le soir), et la station d'arrivée est à une distance cohérente avec la durée du trajet. Les comptes de démonstration ne sont jamais utilisés par la simulation.

Le **mode démo** est actif par défaut : `sim_facteur_demo()` multiplie le volume par 5 (environ 3 600 trajets par jour en novembre, 50 à 120 vélos en circulation en journée), pour que les disponibilités changent à l'œil nu. Pour revenir au volume réaliste de l'historique, mettre `RETURN 1` dans cette fonction et rejouer `simulation.sql`.

À noter : la table `location` ne fait que grandir, c'est l'historique des emprunts. Une location en cours est une ligne dont le mouvement n'a pas encore de `date_heure_arrivee` (vue `v_velo`, situation `EN_LOCATION`).

```sql
CALL sim_arreter();                      -- suspend la simulation
CALL sim_demarrer();                     -- la relance
CALL sim_etat();                         -- événements et dernière exécution
SELECT * FROM v_simulation_activite;     -- activité de la dernière heure
```

Comptes de démonstration (mot de passe `velo2026`) : `admin@velo.example.org`, `regulation@velo.example.org`, `maintenance@velo.example.org`, `usager@velo.example.org`.

## Performances

`performances/banc_performances.py` mesure les 28 requêtes principales (temps médian, lignes lues, plan d'exécution), avant et après `optimisation.sql` ; `performances/sans_optimisation.sql` ramène la base à l'état « avant » pour la comparaison. Résultats et analyse : [`../V2/rapport_performances.md`](../V2/rapport_performances.md).

## Interface web

Le dossier `web/` contient une interface PHP pour exploiter la base : espace usager (emprunt, restitution, abonnements, factures), signalements, régulation, maintenance, statistiques, gestion des stations, des utilisateurs et des formules, et une page **Requêtes** qui exécute et chronomètre les requêtes d'analyse (plus une console SQL en lecture seule).

Elle passe par les procédures stockées et les vues de `data/automatisation.sql` et `data/optimisation.sql` : les quatre scripts doivent donc être chargés au préalable.

Stack : PHP 8.2+ sans framework, [Twig](https://twig.symfony.com/) pour les gabarits, [FastRoute](https://github.com/nikic/FastRoute) pour le routage, PDO pour la base. Le code suit une architecture en couches (`src/Domain`, `src/Application`, `src/Infrastructure`, `src/Presentation`).

### Lancement local

Prérequis : PHP 8.2 ou plus avec l'extension `pdo_mysql` activée (`extension=pdo_mysql` dans `php.ini`), et Composer.

```bash
cd web
composer install
cp config/local.example.php config/local.php
php -S 127.0.0.1:8000 -t public public/index.php
```

Renseigner dans `config/local.php` le port, l'utilisateur et le mot de passe MySQL, puis ouvrir <http://127.0.0.1:8000> et se connecter avec un compte de démonstration (boutons sur la page de connexion).

La connexion peut aussi se régler par variables d'environnement : `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`. `APP_DEBUG=0` masque le détail des erreurs et active le cache des gabarits (`var/cache`).

## Docker

`docker-compose.yml` monte tout le projet : base MySQL 8.4, données factices, interface web et phpMyAdmin.

```bash
docker compose up --build
```

- Interface web : <http://localhost:8090> (comptes de démonstration ci-dessus) ;
- phpMyAdmin : <http://localhost:8091> (`root` / `changeme`) ;
- MySQL depuis l'hôte : port `3307`.

Au premier lancement, la base se construit dans l'ordre des scripts : `structure.sql` (service `db`), `peuplement_velo.py` (service `peuplement`, quelques minutes), `automatisation.sql`, `optimisation.sql` puis `simulation.sql` (service `automatisation`) ; l'interface démarre ensuite. Les lancements suivants gardent les données du volume `velo_mysql` et rejouent seulement les trois derniers scripts (la simulation est donc relancée à chaque `up`).

Pour tout régénérer (après une modification de `structure.sql`, par exemple) :

```bash
docker compose down -v
docker compose up --build
```

Le mot de passe et les ports côté hôte se changent par variables d'environnement ou dans un fichier `.env` à la racine : `DB_PASSWORD`, `PORT_WEB`, `PORT_PMA`, `PORT_DB`.
