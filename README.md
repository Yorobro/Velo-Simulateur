# Velo-Simulateur

Réseau de vélos en libre-service : projet de base de données BD70.

## Base de données

Les scripts SQL sont dans `data/`. Le fichier [`data/memo.md`](data/memo.md) décrit chaque contrainte, fonction, procédure, trigger, événement et vue.

Ordre de chargement (MySQL 8.4 LTS ou 9.x) :

1. `data/structure.sql` : tables et contraintes (recrée la base de zéro) ;
2. `peuplement_velo.py` : données factices en grand volume, générées avec Faker (ou, pour un petit jeu de données écrit à la main, `data/donnes.sql`) ;
3. `data/automatisation.sql` : fonctions, procédures, triggers, vues ;
4. `data/optimisation.sql` : index, vues optimisées, statistiques.

```bash
mysql -u root -p < data/structure.sql
pip install -r requirements.txt
python peuplement_velo.py --mot-de-passe <mot de passe MySQL>
mysql -u root -p velo_libre_service < data/automatisation.sql
mysql -u root -p velo_libre_service < data/optimisation.sql
```

Par défaut, `peuplement_velo.py` simule un an d'activité : environ 3 000 usagers, 40 stations et 93 000 trajets. `python peuplement_velo.py --help` liste les options (volumes, durée, connexion, `--vider` pour remplacer les données).

Comptes de démonstration (mot de passe `velo2026`) : `admin@velo.example.org`, `regulation@velo.example.org`, `maintenance@velo.example.org`, `usager@velo.example.org`.

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

Au premier lancement, la base se construit dans l'ordre des scripts : `structure.sql` (service `db`), `peuplement_velo.py` (service `peuplement`, environ une minute), `automatisation.sql` puis `optimisation.sql` (service `automatisation`) ; l'interface démarre ensuite. Les lancements suivants gardent les données du volume `velo_mysql` et rejouent seulement les deux derniers scripts.

Pour tout régénérer (après une modification de `structure.sql`, par exemple) :

```bash
docker compose down -v
docker compose up --build
```

Le mot de passe et les ports côté hôte se changent par variables d'environnement ou dans un fichier `.env` à la racine : `DB_PASSWORD`, `PORT_WEB`, `PORT_PMA`, `PORT_DB`.
