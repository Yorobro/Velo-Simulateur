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
