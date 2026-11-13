#!/usr/bin/env python3
"""Peuplement de la base velo_libre_service avec des données factices (Faker).

Le script simule l'activité du réseau de vélos en libre-service sur une
période (un an par défaut) puis insère le résultat dans la base :
usagers et personnel, abonnements et renouvellements, stations et bornes,
flotte mécanique et électrique, trajets (heures de pointe, trajets domicile -
travail), tournées de rééquilibrage, signalements, interventions de
maintenance, réformes, factures et règlements.

Toutes les règles de la base sont respectées (contraintes de structure.sql et
règles R1 à R22 tenues ensuite par les triggers) : un vélo à un seul endroit,
une borne = un vélo, une location à la fois par usager, abonnement valide,
pas d'emprunt d'un vélo défectueux (un vélo signalé passe DEFECTUEUX),
montants calculés selon la formule, une facture par location terminée (même
à 0 €), rôles des opérateurs, capacité des véhicules de régulation, dates
cohérentes. À la date courante, la base contient aussi
des situations en cours : locations, tournée, vélos en atelier, vélos bloqués
sur leur borne, signalements ouverts.

ORDRE D'EXÉCUTION (remplace donnes.sql) :
    structure.sql -> peuplement_velo.py -> automatisation.sql -> optimisation.sql
Le script refuse de s'exécuter si les triggers d'automatisation.sql sont déjà
chargés : ils recréeraient eux-mêmes factures et changements d'état.

Installation :   pip install -r requirements.txt
Utilisation :    python peuplement_velo.py --mot-de-passe secret
                 python peuplement_velo.py --usagers 5000 --jours 730 --vider
Connexion : options --hote, --port, --utilisateur, --mot-de-passe, --base,
ou variables d'environnement DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME.

Comptes de démonstration (mot de passe : velo2026, le même pour tous les
comptes générés) :
    admin@velo.example.org         administrateur
    regulation@velo.example.org    opérateur de régulation
    maintenance@velo.example.org   opérateur de maintenance
    usager@velo.example.org        usager avec un abonnement annuel en cours
"""
from __future__ import annotations

import argparse
import bisect
import datetime as dt
import heapq
import itertools
import math
import os
import sys
import time
import unicodedata
from collections import defaultdict
from decimal import Decimal
from random import Random

try:
    import pymysql
    from faker import Faker
except ImportError:
    sys.exit("Modules manquants : pip install -r requirements.txt (Faker, PyMySQL)")


# =============================================================================
#  Paramètres du réseau
# =============================================================================

# Empreinte bcrypt du mot de passe de démonstration « velo2026 »
# (password_hash de PHP : vérifiable avec password_verify).
MOT_DE_PASSE_DEMO = "velo2026"
EMPREINTE_DEMO = "$2y$10$F8AZNwHgSxkQUcHkv3NC8OfyvAn3A8JyfOQ6SRNxIibn0u5Xj3KUO"

# id, libellé, prix, validité (j), gratuit (min), tranche (min), prix tranche,
# supplément électrique, supplément casque — prix en centimes
FORMULES = [
    (1, "Ticket journée", 500, 1, 30, 30, 100, 100, 100),
    (2, "Mensuel", 1500, 30, 45, 30, 100, 50, 50),
    (3, "Annuel", 12000, 365, 45, 30, 75, 50, 50),
    (4, "Tarif réduit", 6000, 365, 45, 30, 50, 25, 25),
]
FORMULE = {f[0]: f for f in FORMULES}
# profil d'usager -> formule
ID_FORMULE = {"TICKET_JOURNEE": 1, "MENSUEL": 2, "ANNUEL": 3, "TARIF_REDUIT": 4}

# Véhicules de régulation : immatriculation, capacité (vélos transportés à la fois)
VEHICULES = [("FG-482-KL", 12), ("HM-157-PZ", 12), ("BV-903-RT", 10), ("KD-318-WX", 14),
             ("GT-604-NB", 16), ("LC-271-SE", 12), ("MP-835-HA", 10), ("RX-119-JD", 14),
             ("TB-560-QU", 8), ("ZN-742-FC", 16)]

# commune : (code postal, latitude, longitude du centre, rayon en km)
COMMUNES = {
    "Belfort": ("90000", 47.6380, 6.8630, 2.2),
    "Valdoie": ("90300", 47.6690, 6.8430, 0.5),
    "Offemont": ("90300", 47.6625, 6.8775, 0.5),
    "Cravanche": ("90300", 47.6535, 6.8320, 0.4),
    "Essert": ("90850", 47.6385, 6.8175, 0.4),
    "Bavilliers": ("90800", 47.6235, 6.8300, 0.5),
    "Danjoutin": ("90400", 47.6185, 6.8650, 0.5),
    "Andelnans": ("90400", 47.6020, 6.8640, 0.4),
    "Sevenans": ("90400", 47.5874, 6.8628, 0.3),
    "Trévenans": ("90400", 47.5658, 6.8650, 0.3),
    "Meroux-Moval": ("90400", 47.5865, 6.8990, 0.3),
    # première et deuxième couronnes du Grand Belfort, sud du Territoire, pays de Montbéliard
    "Pérouse": ("90160", 47.6370, 6.8980, 0.35),
    "Bessoncourt": ("90160", 47.6460, 6.9280, 0.35),
    "Denney": ("90160", 47.6560, 6.9170, 0.3),
    "Chèvremont": ("90340", 47.6290, 6.9200, 0.35),
    "Vétrigne": ("90300", 47.6720, 6.9010, 0.3),
    "Éloie": ("90300", 47.6900, 6.8580, 0.3),
    "Sermamagny": ("90300", 47.6880, 6.8320, 0.3),
    "Évette-Salbert": ("90350", 47.6770, 6.7980, 0.4),
    "Giromagny": ("90200", 47.7420, 6.8270, 0.5),
    "Lepuix": ("90200", 47.7600, 6.8160, 0.3),
    "Rougegoutte": ("90200", 47.7330, 6.8530, 0.3),
    "Botans": ("90400", 47.5970, 6.8460, 0.3),
    "Dorans": ("90400", 47.5880, 6.8320, 0.3),
    "Châtenois-les-Forges": ("90700", 47.5600, 6.8440, 0.5),
    "Bourogne": ("90140", 47.5640, 6.9170, 0.4),
    "Morvillars": ("90120", 47.5480, 6.9340, 0.3),
    "Grandvillars": ("90600", 47.5400, 6.9680, 0.5),
    "Delle": ("90100", 47.5080, 7.0000, 0.7),
    "Beaucourt": ("90500", 47.4880, 6.9220, 0.6),
    "Montreux-Château": ("90130", 47.6100, 6.9990, 0.35),
    "Héricourt": ("70400", 47.5770, 6.7620, 0.8),
    "Montbéliard": ("25200", 47.5100, 6.7980, 1.0),
    "Sochaux": ("25600", 47.5080, 6.8270, 0.5),
    "Audincourt": ("25400", 47.4830, 6.8400, 0.7),
}

# nom, commune, profil, coordonnées connues (ou None), adresse connue (ou None).
# Les deux stations fermées sont dans les dix premières (toujours présentes).
STATIONS = [
    ("Gare de Belfort", "Belfort", "gare", (47.633900, 6.854600), "2 avenue Wilson"),
    ("Place d'Armes", "Belfort", "centre", (47.638000, 6.863500), "1 place d'Armes"),
    ("République", "Belfort", "centre", (47.637200, 6.858900), "place de la République"),
    ("Techn'Hom – UTBM", "Belfort", "campus", (47.644100, 6.843500), "rue Ernest-Thierry-Mieg"),
    ("Atria", "Belfort", "centre", (47.641000, 6.856800), "avenue de l'Espérance"),
    ("Hôpital Nord Franche-Comté", "Trévenans", "travail", (47.565800, 6.865000), "100 route de Moval"),
    ("Glacis du Château", "Belfort", "loisirs", (47.636000, 6.866500), "boulevard Carnot"),
    ("Sevenans – UTBM", "Sevenans", "campus", (47.587400, 6.862800), "rue de Leupe"),
    ("Valdoie Centre", "Valdoie", "residentiel", None, None),
    ("Bavilliers Centre", "Bavilliers", "residentiel", None, None),
    ("Lion de Belfort", "Belfort", "loisirs", (47.636900, 6.864100), None),
    ("Hôtel de ville", "Belfort", "centre", None, None),
    ("Faubourg de France", "Belfort", "centre", None, None),
    ("IUT Belfort-Montbéliard", "Belfort", "campus", None, None),
    ("Les Glacis", "Belfort", "residentiel", None, None),
    ("Bellevue", "Belfort", "residentiel", None, None),
    ("La Pépinière", "Belfort", "residentiel", None, None),
    ("Jean Jaurès", "Belfort", "residentiel", None, None),
    ("Étang des Forges", "Belfort", "loisirs", None, None),
    ("Offemont Mairie", "Offemont", "residentiel", None, None),
    ("Danjoutin", "Danjoutin", "residentiel", None, None),
    ("Gare TGV Belfort-Montbéliard", "Meroux-Moval", "gare", (47.586500, 6.899000), None),
    ("Marché Fréry", "Belfort", "centre", None, None),
    ("Les Forges", "Belfort", "residentiel", None, None),
    ("Essert Mairie", "Essert", "residentiel", None, None),
    ("Cravanche", "Cravanche", "residentiel", None, None),
    ("Parc de la Douce", "Belfort", "loisirs", None, None),
    ("Arsenal", "Belfort", "centre", None, None),
    ("Châteaudun", "Belfort", "residentiel", None, None),
    ("Zone des Prés", "Andelnans", "travail", None, None),
    ("La Miotte", "Belfort", "residentiel", None, None),
    ("Quai Vauban", "Belfort", "centre", None, None),
    ("Saint-Christophe", "Belfort", "residentiel", None, None),
    ("Médiathèque", "Belfort", "centre", None, None),
    ("Piscine Pannoux", "Belfort", "loisirs", None, None),
    ("Lycée Condorcet", "Belfort", "campus", None, None),
    ("Parc à Ballons", "Belfort", "travail", None, None),
    ("Valdoie Gare", "Valdoie", "residentiel", None, None),
    ("Bavilliers Les Prés", "Bavilliers", "residentiel", None, None),
    ("Danjoutin Bourg", "Danjoutin", "residentiel", None, None),
    # --- extension du réseau : Belfort
    ("Porte de Brisach", "Belfort", "loisirs", None, None),
    ("Tour 41", "Belfort", "loisirs", None, None),
    ("Place Corbis", "Belfort", "centre", None, None),
    ("Maison du Peuple", "Belfort", "centre", None, None),
    ("Théâtre Granit", "Belfort", "centre", None, None),
    ("Square du Souvenir", "Belfort", "centre", None, None),
    ("Musée d'Art moderne", "Belfort", "loisirs", None, None),
    ("Conservatoire", "Belfort", "centre", None, None),
    ("Préfecture", "Belfort", "travail", None, None),
    ("Cité administrative", "Belfort", "travail", None, None),
    ("Palais de justice", "Belfort", "travail", None, None),
    ("Stade Serzian", "Belfort", "loisirs", None, None),
    ("Patinoire", "Belfort", "loisirs", None, None),
    ("Parc des Expositions", "Belfort", "loisirs", None, None),
    ("La Poudrière", "Belfort", "loisirs", None, None),
    ("Le Mont", "Belfort", "residentiel", None, None),
    ("Les Barres", "Belfort", "residentiel", None, None),
    ("Dardel", "Belfort", "residentiel", None, None),
    ("Les Résidences", "Belfort", "residentiel", None, None),
    ("Vauban – Mulhouse", "Belfort", "residentiel", None, None),
    ("Pont Carnot", "Belfort", "centre", None, None),
    ("Rue de Strasbourg", "Belfort", "residentiel", None, None),
    ("Lycée Courbet", "Belfort", "campus", None, None),
    ("Lycée Diderot", "Belfort", "campus", None, None),
    ("Collège Châteaudun", "Belfort", "campus", None, None),
    ("Faculté de droit", "Belfort", "campus", None, None),
    ("Cité universitaire", "Belfort", "campus", None, None),
    ("Techn'Hom 3", "Belfort", "travail", None, None),
    ("Techn'Hom 5", "Belfort", "travail", None, None),
    ("Gare routière", "Belfort", "gare", None, None),
    # --- première couronne
    ("Valdoie Mairie", "Valdoie", "residentiel", None, None),
    ("Valdoie Les Prés", "Valdoie", "residentiel", None, None),
    ("Offemont Centre", "Offemont", "residentiel", None, None),
    ("Offemont Collège", "Offemont", "campus", None, None),
    ("Cravanche Mairie", "Cravanche", "residentiel", None, None),
    ("Essert Centre", "Essert", "residentiel", None, None),
    ("Essert Zone commerciale", "Essert", "travail", None, None),
    ("Bavilliers Mairie", "Bavilliers", "residentiel", None, None),
    ("Danjoutin Gare", "Danjoutin", "gare", None, None),
    ("Andelnans Village", "Andelnans", "residentiel", None, None),
    ("Pérouse Mairie", "Pérouse", "residentiel", None, None),
    ("Pérouse Zone d'activités", "Pérouse", "travail", None, None),
    ("Bessoncourt Centre", "Bessoncourt", "residentiel", None, None),
    ("Bessoncourt Zone commerciale", "Bessoncourt", "travail", None, None),
    ("Denney Village", "Denney", "residentiel", None, None),
    ("Chèvremont Mairie", "Chèvremont", "residentiel", None, None),
    ("Vétrigne Village", "Vétrigne", "residentiel", None, None),
    ("Éloie Village", "Éloie", "residentiel", None, None),
    ("Sermamagny Étang", "Sermamagny", "loisirs", None, None),
    ("Évette-Salbert Lac du Malsaucy", "Évette-Salbert", "loisirs", None, None),
    ("Évette-Salbert Mairie", "Évette-Salbert", "residentiel", None, None),
    ("Botans Village", "Botans", "residentiel", None, None),
    ("Dorans Village", "Dorans", "residentiel", None, None),
    ("Sevenans Village", "Sevenans", "residentiel", None, None),
    ("Trévenans Mairie", "Trévenans", "residentiel", None, None),
    ("Meroux Village", "Meroux-Moval", "residentiel", None, None),
    # --- nord du Territoire
    ("Giromagny Centre", "Giromagny", "centre", None, None),
    ("Giromagny Collège", "Giromagny", "campus", None, None),
    ("Lepuix Ballon d'Alsace", "Lepuix", "loisirs", None, None),
    ("Rougegoutte Mairie", "Rougegoutte", "residentiel", None, None),
    # --- sud du Territoire
    ("Châtenois-les-Forges Centre", "Châtenois-les-Forges", "residentiel", None, None),
    ("Châtenois-les-Forges Canal", "Châtenois-les-Forges", "loisirs", None, None),
    ("Bourogne Port", "Bourogne", "travail", None, None),
    ("Bourogne Mairie", "Bourogne", "residentiel", None, None),
    ("Morvillars Gare", "Morvillars", "gare", None, None),
    ("Grandvillars Centre", "Grandvillars", "centre", None, None),
    ("Grandvillars Gare", "Grandvillars", "gare", None, None),
    ("Delle Gare", "Delle", "gare", None, None),
    ("Delle Centre", "Delle", "centre", None, None),
    ("Delle Lycée", "Delle", "campus", None, None),
    ("Beaucourt Centre", "Beaucourt", "centre", None, None),
    ("Beaucourt Musée Japy", "Beaucourt", "loisirs", None, None),
    ("Montreux-Château Gare", "Montreux-Château", "gare", None, None),
    # --- pays d'Héricourt et de Montbéliard
    ("Héricourt Gare", "Héricourt", "gare", None, None),
    ("Héricourt Centre", "Héricourt", "centre", None, None),
    ("Montbéliard Gare", "Montbéliard", "gare", None, None),
    ("Montbéliard Château", "Montbéliard", "loisirs", None, None),
    ("Montbéliard Centre", "Montbéliard", "centre", None, None),
    ("Montbéliard Université", "Montbéliard", "campus", None, None),
    ("Sochaux Usine", "Sochaux", "travail", None, None),
    ("Sochaux Stade Bonal", "Sochaux", "loisirs", None, None),
    ("Audincourt Centre", "Audincourt", "centre", None, None),
]
FERMEES = {"Hôpital Nord Franche-Comté": "EN_TRAVAUX", "Glacis du Château": "HORS_SERVICE"}
BORNES_PAR_PROFIL = {"gare": (18, 24), "centre": (14, 18), "campus": (12, 18),
                     "loisirs": (10, 14), "travail": (10, 14), "residentiel": (10, 14)}
POPULARITE = {"gare": 3.0, "centre": 2.5, "campus": 2.2, "loisirs": 1.6, "travail": 1.4, "residentiel": 1.0}
POIDS_DOMICILE = {"residentiel": 4.0, "centre": 1.5, "campus": 1.2, "gare": 0.6, "loisirs": 0.4, "travail": 0.1}
POIDS_TRAVAIL = {"campus": 3.0, "centre": 2.5, "travail": 2.5, "gare": 2.0, "residentiel": 0.3, "loisirs": 0.3}

# Demande par heure de la journée (semaine / week-end) et par mois
HEURES_SEMAINE = [0.2, 0.1, 0.05, 0.05, 0.1, 0.4, 1.5, 4.5, 6.5, 3.5, 2.0, 2.4,
                  3.6, 3.0, 2.2, 2.4, 3.4, 5.8, 6.2, 3.6, 2.2, 1.4, 0.9, 0.5]
HEURES_WEEKEND = [0.4, 0.3, 0.2, 0.1, 0.1, 0.2, 0.4, 0.8, 1.5, 2.4, 3.4, 3.8,
                  3.8, 3.6, 4.0, 4.4, 4.4, 4.0, 3.4, 2.6, 1.8, 1.2, 0.9, 0.6]
SAISON = {1: 0.55, 2: 0.6, 3: 0.8, 4: 0.95, 5: 1.1, 6: 1.25, 7: 1.15, 8: 0.95,
          9: 1.2, 10: 1.05, 11: 0.8, 12: 0.6}
JOUR_SEMAINE = [1.0, 1.0, 1.0, 1.0, 1.0, 0.85, 0.7]
VITESSE_KMH = {False: 13.0, True: 17.0}          # mécanique / électrique

# Profils d'usagers : (formule, poids de tirage, intensité d'usage)
PROFILS_USAGER = [("ANNUEL", 0.30, 1.0), ("MENSUEL", 0.35, 1.3),
                  ("TARIF_REDUIT", 0.15, 1.0), ("TICKET_JOURNEE", 0.20, 4.0)]

# Pannes de vélo : signalement, intervention, électrique seulement, probabilité de réforme
PANNES_VELO = [
    ("Le frein arrière ne freine presque plus.", "Remplacement des plaquettes et réglage du frein arrière", False, 0.0),
    ("Le frein avant grince et freine mal.", "Réglage et nettoyage du frein avant", False, 0.0),
    ("La chaîne saute quand on pédale.", "Remplacement de la chaîne et réglage du dérailleur", False, 0.0),
    ("Pneu avant crevé.", "Remplacement de la chambre à air avant", False, 0.0),
    ("Pneu arrière à plat.", "Réparation de la crevaison du pneu arrière", False, 0.0),
    ("La selle est cassée et ne se règle plus.", "Remplacement de la selle et du collier", False, 0.0),
    ("L'éclairage avant ne s'allume pas.", "Remplacement du phare avant", False, 0.0),
    ("Le garde-boue arrière frotte contre la roue.", "Redressage et fixation du garde-boue arrière", False, 0.0),
    ("Le guidon est desserré.", "Serrage de la potence et contrôle de la direction", False, 0.0),
    ("Les vitesses ne passent plus.", "Remplacement du câble de dérailleur", False, 0.0),
    ("La roue arrière est voilée.", "Dévoilage de la roue arrière", False, 0.02),
    ("Le cadre est fissuré près du pédalier.", "Expertise du cadre fissuré", False, 0.4),
    ("La fourche est tordue après un choc.", "Remplacement de la fourche avant", False, 0.15),
    ("La pédale gauche est cassée.", "Remplacement de la pédale gauche", False, 0.0),
    ("La pédale droite tourne dans le vide.", "Remplacement du pédalier", False, 0.0),
    ("La béquille ne tient plus le vélo.", "Remplacement de la béquille", False, 0.0),
    ("La sonnette est arrachée.", "Remplacement de la sonnette", False, 0.0),
    ("Le feu arrière ne fonctionne plus.", "Remplacement du feu arrière", False, 0.0),
    ("Le panier avant est cassé.", "Remplacement du panier avant", False, 0.0),
    ("La poignée de frein est cassée.", "Remplacement du levier de frein", False, 0.0),
    ("La chaîne est rouillée et grince.", "Nettoyage et graissage de la transmission", False, 0.0),
    ("Le vélo a été tagué.", "Nettoyage du cadre", False, 0.0),
    ("Le vélo a été retrouvé dans la Savoureuse.", "Expertise complète après immersion", False, 0.6),
    ("La batterie se vide en quelques minutes.", "Remplacement de la batterie", True, 0.0),
    ("L'assistance électrique se coupe en route.", "Remplacement du connecteur du moteur", True, 0.05),
    ("L'écran du vélo reste éteint.", "Remplacement de l'afficheur", True, 0.0),
    ("Le vélo électrique ne se recharge pas sur la borne.", "Remplacement du contact de charge", True, 0.0),
    ("Le moteur fait un bruit de frottement.", "Remplacement des roulements du moteur", True, 0.03),
    ("Le capteur de pédalage ne réagit plus.", "Remplacement du capteur de pédalage", True, 0.0),
    ("La batterie est gonflée.", "Remplacement de la batterie et contrôle du chargeur", True, 0.1),
]
FAUSSES_ALERTES = ["Bruit suspect quand on pédale.", "La selle était mouillée et glissante.",
                   "Le vélo semblait mal accroché à la borne.", "La sonnette ne sonne pas fort.",
                   "Le panier est un peu tordu.", "Le vélo est sale.", "La selle est trop haute.",
                   "Les pneus semblent un peu dégonflés.", "Un autocollant est décollé sur le cadre.",
                   "Le vélo électrique semble moins puissant que d'habitude."]
PANNES_STATION = [
    ("La borne n°{n} ne libère pas le vélo.", "Remplacement du verrou de la borne n°{n}"),
    ("La borne n°{n} ne détecte pas le vélo restitué.", "Remplacement du capteur de la borne n°{n}"),
    ("L'écran de la station reste éteint.", "Remplacement de l'alimentation de l'écran"),
    ("Le paiement par carte est impossible à la station.", "Remplacement du lecteur de carte"),
    ("L'éclairage de la station est en panne.", "Remplacement des éclairages de la station"),
    ("La station est couverte de tags.", "Nettoyage de la station"),
    ("Le plan du réseau est arraché.", "Remplacement du panneau d'information"),
    ("La borne n°{n} est tordue.", "Redressage et fixation de la borne n°{n}"),
    ("La borne n°{n} affiche une erreur.", "Remplacement de la carte électronique de la borne n°{n}"),
    ("Le terminal de la station ne répond plus.", "Redémarrage et mise à jour du terminal"),
    ("L'abri de la station a une vitre brisée.", "Remplacement de la vitre de l'abri"),
    ("La station est inondée après l'orage.", "Pompage et contrôle électrique de la station"),
    ("Des déchets encombrent la station.", "Nettoyage de la station"),
]

COLONNES = {
    "utilisateur": ("id_utilisateur", "nom", "prenom", "email", "mot_de_passe_hash", "telephone",
                    "date_inscription", "role"),
    "formule": ("id_formule", "libelle", "prix", "duree_validite_jours", "duree_gratuite_min",
                "duree_tranche_min", "prix_tranche", "supplement_electrique", "supplement_casque"),
    "abonnement": ("id_abonnement", "date_debut", "date_fin", "id_utilisateur", "id_formule",
                   "id_abonnement_precedent"),
    "station": ("id_station", "nom", "adresse", "code_postal", "latitude", "longitude", "etat"),
    "borne": ("id_station", "numero", "etat"),
    "velo": ("id_velo", "date_mise_service", "id_station", "numero_borne"),
    "velo_electrique": ("id_velo", "niveau_batterie"),
    "changement_etat": ("id_changement", "date_heure_changement", "etat", "id_velo"),
    "vehicule": ("id_vehicule", "immatriculation", "capacite"),
    "tournee": ("id_tournee", "date_heure_debut", "date_heure_fin", "id_utilisateur", "id_vehicule"),
    "mouvement": ("id_mouvement", "date_heure_depart", "date_heure_arrivee", "id_velo",
                  "id_station_depart", "numero_borne_depart", "id_station_arrivee", "numero_borne_arrivee"),
    "location": ("id_mouvement", "avec_casque", "id_abonnement"),
    "transfert": ("id_mouvement", "id_tournee"),
    "facture": ("id_facture", "date_emission", "montant", "date_reglement", "id_abonnement", "id_location"),
    "intervention": ("id_intervention", "description", "id_utilisateur"),
    "intervention_velo": ("id_intervention", "id_mouvement"),
    "signalement": ("id_signalement", "date_heure_signalement", "description", "date_heure_cloture",
                    "id_utilisateur"),
    "signalement_velo": ("id_signalement", "id_velo", "id_intervention_velo"),
    "signalement_station": ("id_signalement", "id_station"),
    "intervention_station": ("id_intervention", "date_heure_debut", "date_heure_fin", "id_signalement_station"),
}
MINUTE = dt.timedelta(minutes=1)


def minutes(n: float) -> dt.timedelta:
    return dt.timedelta(minutes=round(n))


def euros(centimes: int) -> Decimal:
    return Decimal(centimes).scaleb(-2)


def sans_accents(texte: str) -> str:
    texte = unicodedata.normalize("NFKD", texte)
    texte = "".join(c for c in texte if not unicodedata.combining(c)).lower()
    return "".join(c if c.isalnum() else "-" for c in texte).strip("-")


def distance_km(a: tuple, b: tuple) -> float:
    (la1, lo1), (la2, lo2) = a, b
    p1, p2 = math.radians(la1), math.radians(la2)
    dp, dl = p2 - p1, math.radians(lo2 - lo1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * 6371 * math.asin(math.sqrt(h))


# =============================================================================
#  Simulation
# =============================================================================

class Simulation:
    """Rejoue l'activité du réseau dans l'ordre chronologique (file
    d'événements) en tenant l'état de chaque borne, vélo et usager, puis
    fournit les lignes de chaque table."""

    def __init__(self, cfg: argparse.Namespace):
        self.cfg = cfg
        self.rng = Random(cfg.graine)
        Faker.seed(cfg.graine)
        self.fake = Faker("fr_FR")
        self.maintenant = cfg.maintenant
        self.aujourdhui = self.maintenant.date()
        self.jour_debut = self.aujourdhui - dt.timedelta(days=cfg.jours)
        self.debut = dt.datetime.combine(self.jour_debut, dt.time())

        self.ids = defaultdict(int)
        self.file: list = []
        self.compteur = itertools.count()

        # lignes à insérer (les tables modifiées après coup sont des dict id -> liste)
        self.t = {nom: [] for nom in COLONNES}
        self.mouvements: dict[int, list] = {}
        self.tournees: dict[int, list] = {}
        self.signalements: dict[int, list] = {}
        self.sig_velo: dict[int, list] = {}
        self.interv_station: dict[int, list] = {}
        self.velos: dict[int, list] = {}

        # état courant
        self.stations: list[dict] = []
        self.libres: dict[int, set] = {}          # bornes libres en service, par station
        self.dispo: dict[int, set] = {}           # vélos empruntables, par station
        self.pos: dict[int, tuple | None] = {}    # vélo -> (station, borne) ou None
        self.etat: dict[int, str] = {}
        self.etat_depuis: dict[int, dt.datetime] = {}
        self.electrique: dict[int, bool] = {}
        self.en_atelier: dict[int, tuple] = {}    # vélo -> (intervention, mouvement, signalements)
        self.sig_ouverts: dict[int, list] = defaultdict(list)   # vélo -> signalements non traités
        self.usagers_en_location: set[int] = set()
        self.fin_tournee_op: dict[int, dt.datetime] = {}
        self.fin_tournee_veh: dict[int, dt.datetime] = {}

    # ------------------------------------------------------------- outils
    def nouvel_id(self, table: str) -> int:
        self.ids[table] += 1
        return self.ids[table]

    def planifier(self, quand: dt.datetime, action: str, *args):
        heapq.heappush(self.file, (quand, next(self.compteur), action, args))

    def heure_ouvree(self, quand: dt.datetime) -> dt.datetime:
        """Ramène une date dans les heures de travail (8 h - 18 h)."""
        if quand.hour < 8:
            quand = quand.replace(hour=8, minute=self.rng.randint(0, 59))
        elif quand.hour >= 18:
            quand = (quand + dt.timedelta(days=1)).replace(hour=8, minute=self.rng.randint(0, 59))
        return quand

    def instant_du_jour(self, jour: dt.date, poids: list) -> dt.datetime:
        heure = self.rng.choices(range(24), weights=poids)[0]
        return dt.datetime.combine(jour, dt.time(heure, self.rng.randint(0, 59)))

    # ------------------------------------------------------------- référentiels
    def creer_formules(self):
        for (i, libelle, prix, val, grat, tr, ptr, se, sc) in FORMULES:
            self.t["formule"].append((i, libelle, euros(prix), val, grat, tr, euros(ptr), euros(se), euros(sc)))

    def creer_vehicules(self):
        for immatriculation, capacite in VEHICULES:
            self.t["vehicule"].append((self.nouvel_id("vehicule"), immatriculation, capacite))
        self.capacite_vehicule = {v[0]: v[2] for v in self.t["vehicule"]}

    def creer_stations(self):
        nb = max(10, min(self.cfg.stations, 300))
        modeles = list(STATIONS)
        while len(modeles) < nb:   # au-delà de la liste : stations de quartier
            modeles.append((f"{self.fake.street_name()}", "Belfort", "residentiel", None, None))
        adresses, coords = set(), []
        for (nom, commune, profil, gps, adresse) in modeles[:nb]:
            cp, lat0, lon0, rayon = COMMUNES[commune]
            if gps is None:
                for _ in range(500):   # au moins 250 m entre deux stations
                    ang, r = self.rng.uniform(0, 2 * math.pi), rayon * math.sqrt(self.rng.random())
                    gps = (round(lat0 + r / 111.0 * math.cos(ang), 6),
                           round(lon0 + r / 75.0 * math.sin(ang), 6))
                    if all(distance_km(gps, c) > 0.25 for c in coords):
                        break
            while adresse is None or (adresse, cp) in adresses:
                adresse = f"{self.rng.randint(1, 120)} {self.fake.street_name()}"
            adresse_complete = f"{adresse}, {commune}"
            adresses.add((adresse, cp))
            coords.append(gps)
            sid = self.nouvel_id("station")
            etat = FERMEES.get(nom, "EN_SERVICE")
            self.t["station"].append((sid, nom, adresse_complete, cp, Decimal(f"{gps[0]:.6f}"),
                                      Decimal(f"{gps[1]:.6f}"), etat))
            st = dict(id=sid, nom=nom, profil=profil, gps=gps, active=(etat == "EN_SERVICE"), bornes=[])
            lo, hi = BORNES_PAR_PROFIL[profil]
            for numero in range(1, self.rng.randint(lo, hi) + 1):
                en_service = st["active"] and self.rng.random() > 0.04
                self.t["borne"].append((sid, numero, "EN_SERVICE" if en_service else "HORS_SERVICE"))
                if en_service:
                    st["bornes"].append(numero)
            self.stations.append(st)
            self.libres[sid] = set(st["bornes"])
            self.dispo[sid] = set()
        self.actives = [s for s in self.stations if s["active"]]
        self.par_id = {s["id"]: s for s in self.stations}
        ids = [s["id"] for s in self.actives]
        self.dist = {a: {b: distance_km(self.par_id[a]["gps"], self.par_id[b]["gps"]) for b in ids} for a in ids}
        # poids de destination (modèle gravitaire) depuis chaque station
        self.poids_dest = {}
        for a in ids:
            w = [POPULARITE[self.par_id[b]["profil"]] * math.exp(-self.dist[a][b] / 2.0) for b in ids]
            self.poids_dest[a] = (ids, w)

    # ------------------------------------------------------------- personnes
    def creer_utilisateurs(self):
        self.emails = set()
        self.roles = defaultdict(list)
        self.usagers = []   # dict par usager
        debut_personnel = self.debut - dt.timedelta(days=400)

        def ajouter(nom, prenom, role, inscription, email=None, domaine=None):
            if email is None:
                base = f"{sans_accents(prenom)}.{sans_accents(nom)}"
                email, n = f"{base}@{domaine}", 1
                while email in self.emails:
                    n += 1
                    email = f"{base}{n}@{domaine}"
            self.emails.add(email)
            uid = self.nouvel_id("utilisateur")
            telephone = "0" + self.rng.choice("67") + "".join(self.rng.choice("0123456789") for _ in range(8))
            self.t["utilisateur"].append((uid, nom, prenom, email, EMPREINTE_DEMO, telephone, inscription, role))
            self.roles[role].append(uid)
            return uid

        def date_personnel():
            return debut_personnel + dt.timedelta(days=self.rng.randint(0, 300), hours=self.rng.randint(8, 17))

        comptes_demo = [("ADMINISTRATEUR", "admin"), ("OPERATEUR_REGULATION", "regulation"),
                        ("OPERATEUR_MAINTENANCE", "maintenance")]
        for role, prefixe in comptes_demo:
            ajouter(self.fake.last_name(), self.fake.first_name(), role, date_personnel(),
                    email=f"{prefixe}@velo.example.org")
        for role, nb in (("ADMINISTRATEUR", 3), ("OPERATEUR_REGULATION", 12), ("OPERATEUR_MAINTENANCE", 12)):
            for _ in range(nb):
                ajouter(self.fake.last_name(), self.fake.first_name(), role, date_personnel(),
                        domaine="velo.example.org")
        self.regulation = self.roles["OPERATEUR_REGULATION"]
        self.maintenance = self.roles["OPERATEUR_MAINTENANCE"]
        self.administrateurs = self.roles["ADMINISTRATEUR"]

        # usagers : 35 % inscrits avant la période, les autres au fil de la période
        domaines = ["example.org", "example.com", "example.net"]
        profils, poids = zip(*[(p, w) for p, w, _ in PROFILS_USAGER])
        intensite = {p: i for p, _, i in PROFILS_USAGER}
        for k in range(self.cfg.usagers):
            demo = (k == 0)
            if demo or self.rng.random() < 0.35:
                inscription = self.debut - dt.timedelta(days=self.rng.randint(1, 700))
            else:
                # croissance : plus d'inscriptions vers la fin de la période
                frac = math.sqrt(self.rng.random())
                inscription = self.debut + dt.timedelta(days=frac * (self.cfg.jours - 1))
            inscription = inscription.replace(hour=self.rng.randint(7, 22), minute=self.rng.randint(0, 59),
                                              second=0, microsecond=0)
            inscription = min(inscription, self.maintenant - dt.timedelta(hours=1))
            uid = ajouter(self.fake.last_name(), self.fake.first_name(), "USAGER", inscription,
                          email="usager@velo.example.org" if demo else None,
                          domaine=self.rng.choice(domaines))
            profil = "ANNUEL" if demo else self.rng.choices(profils, weights=poids)[0]
            self.usagers.append(dict(id=uid, inscription=inscription, profil=profil,
                                     intensite=intensite[profil], abos=[],
                                     domicile=self.station_au_hasard(POIDS_DOMICILE),
                                     travail=None))
            u = self.usagers[-1]
            for _ in range(10):
                u["travail"] = self.station_au_hasard(POIDS_TRAVAIL)
                if u["travail"] != u["domicile"]:
                    break

    def station_au_hasard(self, poids_profil: dict) -> int:
        st = self.rng.choices(self.actives, weights=[poids_profil[s["profil"]] for s in self.actives])[0]
        return st["id"]

    # ------------------------------------------------------------- abonnements
    def creer_abonnements(self):
        for u in self.usagers:
            if self.rng.random() < 0.04 and u["id"] != self.usagers[0]["id"]:
                continue   # inscrit mais jamais abonné
            jour0 = u["inscription"].date() + dt.timedelta(days=self.rng.randint(0, 3))
            profil = u["profil"]
            if profil == "TICKET_JOURNEE":
                premier = max(jour0, self.jour_debut)
                if premier > self.aujourdhui:
                    continue
                nb = self.rng.randint(1, 4 + (self.aujourdhui - premier).days // 25)
                jours = sorted({premier + dt.timedelta(days=self.rng.randint(0, (self.aujourdhui - premier).days))
                                for _ in range(nb)})
                for j in jours:
                    self.ajouter_abonnement(u, 1, j, None)
                continue
            fid = ID_FORMULE[profil]
            duree = FORMULE[fid][3]
            if u["id"] == self.usagers[0]["id"]:
                debut = self.aujourdhui - dt.timedelta(days=100)       # compte de démonstration
            elif jour0 < self.jour_debut:
                # déjà abonné au début de la période
                debut = max(jour0, self.jour_debut - dt.timedelta(days=self.rng.randint(0, duree - 1)))
            else:
                debut = jour0
            precedent = None
            renouvellement = 0.80 if duree == 365 else 0.88
            while debut <= self.aujourdhui:
                precedent = self.ajouter_abonnement(u, fid, debut, precedent)
                fin = debut + dt.timedelta(days=duree - 1)
                if fin >= self.aujourdhui:
                    break
                tirage = self.rng.random()
                if tirage < renouvellement:          # renouvellement à la suite
                    debut = fin + dt.timedelta(days=1)
                elif tirage < renouvellement + 0.08:  # pause puis nouvel abonnement
                    debut = fin + dt.timedelta(days=self.rng.randint(5, 60))
                    precedent = None
                else:                                 # abandon
                    break

    def ajouter_abonnement(self, u: dict, fid: int, debut: dt.date, precedent: int | None) -> int:
        aid = self.nouvel_id("abonnement")
        fin = debut + dt.timedelta(days=FORMULE[fid][3] - 1)
        self.t["abonnement"].append((aid, debut, fin, u["id"], fid, precedent))
        u["abos"].append((debut, fin, aid))
        # facture de souscription : le jour du début, après l'inscription
        emission = dt.datetime.combine(debut, dt.time(self.rng.randint(6, 21), self.rng.randint(0, 59)))
        if precedent is not None:
            emission = dt.datetime.combine(debut, dt.time(0, self.rng.randint(1, 30)))   # renouvellement auto
        emission = max(emission, u["inscription"] + MINUTE)
        emission = max(min(emission, self.maintenant - MINUTE), dt.datetime.combine(debut, dt.time()))
        self.ajouter_facture(emission, FORMULE[fid][2], abonnement=aid)
        return aid

    def ajouter_facture(self, emission, centimes, abonnement=None, location=None):
        tirage = self.rng.random()
        if centimes == 0:   # facture à 0 € : rien à régler
            reglement = None
        elif tirage < 0.95:
            reglement = emission + minutes(self.rng.randint(0, 5))
        elif tirage < 0.99 or (self.maintenant - emission).days < 10:
            reglement = emission + dt.timedelta(days=self.rng.randint(1, 20), hours=self.rng.randint(0, 10))
        else:
            reglement = None
        if reglement is not None and reglement > self.maintenant:
            reglement = None
        fid = self.nouvel_id("facture")
        self.t["facture"].append((fid, emission, euros(centimes), reglement, abonnement, location))

    def preparer_demande(self):
        """Usagers ayant un abonnement valable, jour par jour (règle R2)."""
        self.eligibles = defaultdict(list)
        for u in self.usagers:
            for (d, f, aid) in u["abos"]:
                j = max(d, self.jour_debut)
                while j <= min(f, self.aujourdhui):
                    self.eligibles[j].append(u)
                    j += dt.timedelta(days=1)
        self.tirage = {}
        for j, liste in self.eligibles.items():
            cumul = list(itertools.accumulate(u["intensite"] for u in liste))
            self.tirage[j] = (liste, cumul)

    def abonnement_valide(self, u: dict, jour: dt.date) -> int | None:
        valides = [(d, aid) for (d, f, aid) in u["abos"] if d <= jour <= f]
        return max(valides)[1] if valides else None

    # ------------------------------------------------------------- flotte
    def placer(self, v: int, sid: int, numero: int):
        self.libres[sid].remove(numero)
        self.pos[v] = (sid, numero)
        if self.etat[v] == "EN_SERVICE":
            self.dispo[sid].add(v)

    def enlever(self, v: int) -> tuple:
        sid, numero = self.pos[v]
        self.libres[sid].add(numero)
        self.dispo[sid].discard(v)
        self.pos[v] = None
        return sid, numero

    def changer_etat(self, v: int, etat: str, quand: dt.datetime):
        if v in self.etat_depuis and quand <= self.etat_depuis[v]:
            raise RuntimeError(f"changement d'état non chronologique pour le vélo {v}")
        self.t["changement_etat"].append((self.nouvel_id("changement_etat"), quand, etat, v))
        self.etat[v], self.etat_depuis[v] = etat, quand
        if self.pos.get(v):
            sid = self.pos[v][0]
            if etat == "EN_SERVICE":
                self.dispo[sid].add(v)
            else:
                self.dispo[sid].discard(v)

    def mettre_en_service(self, v: int, quand: dt.datetime, electrique: bool):
        self.velos[v] = [v, quand, None, None]
        self.electrique[v] = electrique
        if electrique:
            self.t["velo_electrique"].append([v, None])
        self.changer_etat(v, "EN_SERVICE", quand)

    def station_avec_place(self, depuis: int | None = None, exclure: int | None = None) -> int | None:
        """La plus proche station ayant une borne libre (ou la plus vide si depuis est None)."""
        cands = [s["id"] for s in self.actives if self.libres[s["id"]] and s["id"] != exclure]
        if not cands:
            return None
        if depuis is None:
            return self.rng.choices(cands, weights=[len(self.libres[c]) ** 2 for c in cands])[0]
        return min(cands, key=lambda c: self.dist[depuis][c])

    def creer_flotte(self):
        places = sum(len(s["bornes"]) for s in self.actives)
        total = self.cfg.velos or round(places * 0.65)
        total = min(total, places - len(self.actives))
        nouveaux = max(1, total // 12)
        for _ in range(total - nouveaux):
            v = self.nouvel_id("velo")
            service = self.debut - dt.timedelta(days=self.rng.randint(30, 900), hours=self.rng.randint(0, 9))
            self.mettre_en_service(v, service.replace(hour=max(service.hour, 8), minute=0), self.rng.random() < 0.40)
            sid = self.station_avec_place()
            self.placer(v, sid, self.rng.choice(sorted(self.libres[sid])))
            self.planifier_revisions(v, self.debut + dt.timedelta(days=self.rng.randint(0, 150)))
        for _ in range(nouveaux):   # vélos ajoutés pendant la période
            quand = self.heure_ouvree(self.debut + dt.timedelta(days=self.rng.randint(10, self.cfg.jours - 1),
                                                                hours=self.rng.randint(8, 16)))
            self.planifier(quand, "ev_mise_en_service", self.rng.random() < 0.40)

    def planifier_revisions(self, v: int, quand: dt.datetime):
        while quand < self.maintenant:
            self.planifier(self.heure_ouvree(quand), "ev_retrait", v, None)
            quand += dt.timedelta(days=self.rng.randint(110, 170))

    def ev_mise_en_service(self, quand, electrique):
        sid = self.station_avec_place()
        if sid is None:
            return
        v = self.nouvel_id("velo")
        self.mettre_en_service(v, quand, electrique)
        self.placer(v, sid, min(self.libres[sid]))
        self.planifier_revisions(v, quand + dt.timedelta(days=self.rng.randint(100, 170)))

    # ------------------------------------------------------------- mouvements
    def nouveau_mouvement(self, v: int, quand: dt.datetime) -> int:
        sid, numero = self.enlever(v)
        mid = self.nouvel_id("mouvement")
        self.mouvements[mid] = [mid, quand, None, v, sid, numero, None, None]
        return mid

    def arrivee(self, mid: int, quand: dt.datetime, sid: int | None):
        m = self.mouvements[mid]
        m[2] = quand
        if sid is not None:
            numero = min(self.libres[sid])
            m[6], m[7] = sid, numero
            self.placer(m[3], sid, numero)

    # ------------------------------------------------------------- trajets
    def planifier_trajets(self):
        moyenne = sum(len(l) for l in self.eligibles.values()) / max(1, len(self.eligibles))
        par_eligible = self.cfg.trajets_par_jour / max(1.0, moyenne)
        jour = self.jour_debut
        while jour <= self.aujourdhui:
            nb_elig = len(self.eligibles.get(jour, []))
            facteur = SAISON[jour.month] * JOUR_SEMAINE[jour.weekday()] * self.rng.uniform(0.85, 1.15)
            poids = HEURES_SEMAINE if jour.weekday() < 5 else HEURES_WEEKEND
            for _ in range(round(nb_elig * par_eligible * facteur)):
                self.planifier(self.instant_du_jour(jour, poids), "ev_demande")
            jour += dt.timedelta(days=1)

    def ev_demande(self, quand):
        liste, cumul = self.tirage.get(quand.date(), (None, None))
        if not liste:
            return
        for _ in range(3):
            u = liste[bisect.bisect_left(cumul, self.rng.random() * cumul[-1])]
            if u["id"] not in self.usagers_en_location and u["inscription"] < quand:
                break
        else:
            return
        aid = self.abonnement_valide(u, quand.date())
        semaine, h = quand.weekday() < 5, quand.hour
        loisir = False
        if semaine and 6 <= h <= 9 and self.rng.random() < 0.7:
            origine, dest = u["domicile"], u["travail"]
        elif semaine and 16 <= h <= 19 and self.rng.random() < 0.65:
            origine, dest = u["travail"], u["domicile"]
        else:
            loisir = not semaine or self.rng.random() < 0.3
            origine = u["domicile"] if self.rng.random() < 0.4 else self.station_au_hasard(POPULARITE)
            dest = None
        if not self.dispo[origine]:   # pas de vélo : station voisine à moins de 800 m
            proches = [s for s in self.dist[origine] if self.dispo[s] and self.dist[origine][s] < 0.8]
            if not proches:
                return   # demande perdue
            origine = min(proches, key=lambda s: self.dist[origine][s])
        if dest is None or dest == origine:
            ids, w = self.poids_dest[origine]
            # aller-retour (même station) : rare, et seulement pour une balade
            w = [x if s != origine else (x * 0.08 if loisir else 0) for s, x in zip(ids, w)]
            dest = self.rng.choices(ids, weights=w)[0]
        velos = sorted(self.dispo[origine])
        elec = [v for v in velos if self.electrique[v]]
        v = self.rng.choice(elec if elec and self.rng.random() < 0.35 else velos)
        # durée du trajet
        if dest == origine:
            duree = self.rng.randint(20, 90)
        else:
            duree = self.dist[origine][dest] / VITESSE_KMH[self.electrique[v]] * 60 * 1.3 + self.rng.uniform(1.5, 4)
            duree *= self.rng.lognormvariate(0, 0.2)
        if loisir:
            duree += self.rng.choice([0, 0, 10, 20, 40])
        if self.rng.random() < 0.03:
            duree += self.rng.randint(45, 200)
        mid = self.nouveau_mouvement(v, quand)
        casque = self.rng.random() < 0.08   # casque récupéré à l'emprunt
        self.t["location"].append((mid, casque, aid))
        self.usagers_en_location.add(u["id"])
        self.planifier(quand + minutes(max(2, duree)), "ev_restitution", mid, u, dest, aid, casque)

    def ev_restitution(self, quand, mid, u, dest, aid, casque):
        if not self.libres[dest]:   # station pleine : l'usager va à la plus proche
            autre = self.station_avec_place(depuis=dest, exclure=dest)
            if autre is None:
                self.planifier(quand + minutes(5), "ev_restitution", mid, u, dest, aid, casque)
                return
            detour = self.dist[dest][autre] / VITESSE_KMH[self.electrique[self.mouvements[mid][3]]] * 60 + 1
            self.planifier(quand + minutes(max(1, detour)), "ev_restitution", mid, u, autre, aid, casque)
            return
        self.arrivee(mid, quand, dest)
        self.usagers_en_location.discard(u["id"])
        # coût (même calcul que fn_cout_trajet) et facture du trajet, même à 0 €
        m = self.mouvements[mid]
        duree = int((quand - m[1]).total_seconds() // 60)
        f = FORMULE[self.formule_abonnement[aid]]
        _, _, _, _, gratuit, tranche, prix_tranche, supp_elec, supp_casque = f
        cout = math.ceil(max(0, duree - gratuit) / tranche) * prix_tranche
        cout += supp_elec if self.electrique[m[3]] else 0
        cout += supp_casque if casque else 0
        self.ajouter_facture(quand, cout, location=mid)
        # signalement d'un problème après le trajet
        if self.rng.random() < 0.007:
            self.planifier(quand + minutes(self.rng.randint(1, 10)), "ev_signalement_velo", m[3], u["id"])

    # ------------------------------------------------------------- signalements et maintenance
    def nouveau_signalement(self, quand, description, auteur) -> int:
        sid = self.nouvel_id("signalement")
        self.signalements[sid] = [sid, quand, description, None, auteur]
        return sid

    def ev_signalement_velo(self, quand, v, auteur):
        if self.etat[v] == "REFORME" or v in self.en_atelier:
            return
        pannes = [p for p in PANNES_VELO if self.electrique[v] or not p[2]]
        vraie = self.rng.random() < 0.75
        panne = self.rng.choice(pannes) if vraie else None
        sid = self.nouveau_signalement(quand, panne[0] if vraie else self.rng.choice(FAUSSES_ALERTES), auteur)
        self.sig_velo[sid] = [sid, v, None]
        self.sig_ouverts[v].append(sid)
        # R20 : le vélo signalé passe DEFECTUEUX (comme trg_signalement_velo_ai),
        # il n'est plus empruntable. S'il vient d'être emprunté à la même
        # minute, le changement d'état suit le départ d'une seconde.
        if self.etat[v] == "EN_SERVICE":
            seconde = dt.timedelta(seconds=1)
            quand_etat = quand + seconde if self.pos.get(v) is None else quand
            self.changer_etat(v, "DEFECTUEUX", max(quand_etat, self.etat_depuis[v] + seconde))
        if vraie:
            delai = dt.timedelta(hours=self.rng.randint(2, 50))
            self.planifier(self.heure_ouvree(quand + delai), "ev_retrait", v, panne)
        else:   # fausse alerte : un opérateur vérifie le vélo et clôt le signalement
            delai = dt.timedelta(hours=self.rng.randint(1, 24))
            self.planifier(self.heure_ouvree(quand + delai), "ev_cloture_signalement", sid, v)

    def ev_cloture_signalement(self, quand, sid, v):
        s = self.signalements[sid]
        if s[3] is None and self.sig_velo[sid][2] is None:
            s[3] = quand
            self.sig_ouverts[v].remove(sid)
            # R20 : fausse alerte close, le vélo redevient EN_SERVICE (comme
            # cloturer_signalement) s'il n'est pas en atelier et sans autre signalement
            if (self.etat[v] == "DEFECTUEUX" and v not in self.en_atelier and not self.sig_ouverts[v]
                    and quand > self.etat_depuis[v]):
                self.changer_etat(v, "EN_SERVICE", quand)

    def operateur_maintenance(self) -> int:
        if self.rng.random() < 0.05:
            return self.rng.choice(self.administrateurs)
        return self.rng.choice(self.maintenance)

    def ev_retrait(self, quand, v, panne):
        """Retrait pour maintenance (curative si panne, révision sinon)."""
        if self.etat[v] == "REFORME" or v in self.en_atelier:
            return
        if self.pos[v] is None or quand <= self.etat_depuis[v]:   # vélo en route : on repasse plus tard
            self.planifier(quand + minutes(self.rng.randint(30, 90)), "ev_retrait", v, panne)
            return
        if panne is None:
            texte = "Révision périodique : freins, pneus, transmission, éclairage"
            texte += " et batterie" if self.electrique[v] else ""
            duree, reforme = dt.timedelta(minutes=self.rng.randint(60, 240)), False
        else:
            texte = panne[1]
            duree = dt.timedelta(hours=self.rng.randint(3, 96))
            reforme = self.rng.random() < max(panne[3], 0.005)
        iid = self.nouvel_id("intervention")
        self.t["intervention"].append((iid, texte, self.operateur_maintenance()))
        mid = self.nouveau_mouvement(v, quand)
        self.t["intervention_velo"].append((iid, mid))
        if self.etat[v] != "DEFECTUEUX":
            self.changer_etat(v, "DEFECTUEUX", quand)
        # signalements ouverts de ce vélo rattachés à l'intervention (comme trg_intervention_velo_ai)
        rattaches = [s for s in self.sig_ouverts[v] if self.signalements[s][1] <= quand]
        for s in rattaches:
            self.sig_velo[s][2] = iid
            self.sig_ouverts[v].remove(s)
        self.en_atelier[v] = (iid, mid, rattaches)
        self.planifier(quand + duree, "ev_fin_maintenance", v, reforme)

    def ev_fin_maintenance(self, quand, v, reforme):
        iid, mid, rattaches = self.en_atelier[v]
        if reforme:
            self.arrivee(mid, quand, None)             # arrivée à l'atelier sans borne
            self.changer_etat(v, "REFORME", quand)
        else:
            sid = self.station_avec_place()
            if sid is None:
                self.planifier(quand + minutes(30), "ev_fin_maintenance", v, reforme)
                return
            self.arrivee(mid, quand, sid)
            self.changer_etat(v, "EN_SERVICE", quand)
        del self.en_atelier[v]
        for s in rattaches:                          # signalements traités : clos
            self.signalements[s][3] = quand

    def planifier_signalements_station(self):
        jour = self.jour_debut
        while jour <= self.aujourdhui:
            for _ in range((self.rng.random() < 0.35) + (self.rng.random() < 0.05)):
                quand = self.instant_du_jour(jour, HEURES_SEMAINE)
                self.planifier(quand, "ev_signalement_station")
            jour += dt.timedelta(days=1)

    def ev_signalement_station(self, quand):
        liste = self.eligibles.get(quand.date())
        if not liste:   # R12 : seul un usager signale un problème
            return
        u = self.rng.choice(liste)
        if u["inscription"] >= quand:
            return
        auteur = u["id"]
        st = self.par_id[self.station_au_hasard(POPULARITE)]
        numero = self.rng.choice(st["bornes"])
        texte_sig, texte_interv = self.rng.choice(PANNES_STATION)
        sid = self.nouveau_signalement(quand, texte_sig.format(n=numero), auteur)
        self.t["signalement_station"].append((sid, st["id"]))
        if self.rng.random() < 0.85:
            debut = self.heure_ouvree(quand + dt.timedelta(hours=self.rng.randint(2, 72)))
            self.planifier(debut, "ev_intervention_station", sid, texte_interv.format(n=numero), 1)
        else:   # problème inexistant ou résolu seul
            self.signalements[sid][3] = quand + dt.timedelta(days=self.rng.randint(1, 3))
            if self.signalements[sid][3] > self.maintenant:
                self.signalements[sid][3] = None

    def ev_intervention_station(self, quand, sid, texte, essai):
        if self.signalements[sid][3] is not None:
            return
        iid = self.nouvel_id("intervention")
        self.t["intervention"].append((iid, texte, self.operateur_maintenance()))
        self.interv_station[iid] = [iid, quand, None, sid]
        resolu = essai > 1 or self.rng.random() < 0.85
        self.planifier(quand + minutes(self.rng.randint(30, 360)), "ev_fin_intervention_station",
                       iid, sid, texte, essai, resolu)

    def ev_fin_intervention_station(self, quand, iid, sid, texte, essai, resolu):
        self.interv_station[iid][2] = quand
        if resolu:
            self.signalements[sid][3] = quand
        else:
            suite = self.heure_ouvree(quand + dt.timedelta(days=self.rng.randint(1, 4)))
            self.planifier(suite, "ev_intervention_station", sid, texte, essai + 1)

    def stations_fermees(self):
        """Les deux stations fermées : un signalement et des travaux à la date courante."""
        for st in self.stations:
            if st["nom"] not in FERMEES:
                continue
            # R12 : l'auteur est un usager inscrit avant le signalement (au plus tôt : J-21)
            inscrits = [u["id"] for u in self.usagers
                        if u["inscription"] < self.maintenant - dt.timedelta(days=21)]
            auteur = self.rng.choice(inscrits)
            if FERMEES[st["nom"]] == "EN_TRAVAUX":
                sid = self.nouveau_signalement(self.maintenant - dt.timedelta(days=21),
                                               "Station endommagée par un véhicule : bornes arrachées.", auteur)
                iid = self.nouvel_id("intervention")
                self.t["intervention"].append((iid, "Reconstruction du socle et des bornes", self.maintenance[0]))
                self.interv_station[iid] = [iid, self.maintenant - dt.timedelta(days=14), None, sid]
            else:
                sid = self.nouveau_signalement(self.maintenant - dt.timedelta(days=6),
                                               "Panne électrique générale de la station.", auteur)
                iid = self.nouvel_id("intervention")
                self.t["intervention"].append((iid, "Diagnostic de l'alimentation électrique de la station",
                                               self.maintenance[0]))
                debut = self.maintenant - dt.timedelta(days=5, hours=3)
                self.interv_station[iid] = [iid, debut, debut + dt.timedelta(hours=4), sid]
            self.t["signalement_station"].append((sid, st["id"]))

    # ------------------------------------------------------------- régulation
    def planifier_tournees(self):
        jour = self.jour_debut
        while jour <= self.aujourdhui:
            creneaux = [(10, 30), (12, 30), (15, 0), (18, 0), (20, 30)]
            creneaux += [(6, 30), (8, 30)] if jour.weekday() < 5 else []
            for (h, m) in creneaux:
                # réseau étendu : plusieurs véhicules partent en même temps
                for k in range(3):
                    self.planifier(dt.datetime.combine(jour, dt.time(h, m)) + minutes(5 * k), "ev_tournee", False)
            jour += dt.timedelta(days=1)
        # une tournée en cours à la date courante (démonstration)
        self.planifier(self.maintenant - minutes(25), "ev_tournee", True)

    def ev_tournee(self, quand, forcee):
        libres_op = [o for o in self.regulation if self.fin_tournee_op.get(o, self.debut) <= quand]
        # R16 : un véhicule n'est engagé que dans une tournée à la fois
        libres_veh = [v for v in self.capacite_vehicule if self.fin_tournee_veh.get(v, self.debut) <= quand]
        if not libres_op or not libres_veh:
            return
        etat = []
        for s in self.actives:
            capa = len(s["bornes"])
            occ = capa - len(self.libres[s["id"]])
            etat.append((s["id"], capa, occ))
        haut, bas = (0.6, 0.4) if forcee else (0.75, 0.25)
        sources = {sid: min(occ - round(capa * 0.55), len(self.dispo[sid]))
                   for sid, capa, occ in etat if capa and occ / capa >= haut}
        destinations = {sid: round(capa * 0.45) - occ for sid, capa, occ in etat if capa and occ / capa <= bas}
        sources = {k: v for k, v in sources.items() if v > 0}
        destinations = {k: v for k, v in destinations.items() if v > 0}
        if forcee and (not sources or not destinations):
            tri = sorted(etat, key=lambda e: (e[2] / e[1]) if e[1] else 0)
            destinations = {tri[0][0]: 2, tri[1][0]: 1}
            sources = {e[0]: min(2, len(self.dispo[e[0]])) for e in tri[-2:] if self.dispo[e[0]]}
        if not sources or not destinations:
            return
        veh = self.rng.choice(libres_veh)
        # R15 : pas plus de vélos à bord que la capacité du véhicule
        nb = min(self.capacite_vehicule[veh], sum(sources.values()), sum(destinations.values()))
        charges = [s for s, k in sorted(sources.items(), key=lambda x: -x[1]) for _ in range(k)][:nb]
        depots = [d for d, k in sorted(destinations.items(), key=lambda x: -x[1]) for _ in range(k)][:nb]
        op = self.rng.choice(libres_op)
        tournee = dict(id=None, op=op, veh=veh, debut=quand, charges={})
        t = quand + minutes(self.rng.randint(5, 10))
        for i, s in enumerate(charges):
            if i and s != charges[i - 1]:
                t += minutes(self.rng.randint(6, 12))   # trajet entre deux stations
            self.planifier(t, "ev_charger", tournee, s, i)
            t += minutes(2)
        t += minutes(self.rng.randint(8, 18))
        for i, d in enumerate(depots):
            if i and d != depots[i - 1]:
                t += minutes(self.rng.randint(6, 12))
            self.planifier(t, "ev_deposer", tournee, d, i)
            t += minutes(2)
        fin = t + minutes(self.rng.randint(3, 8))
        self.fin_tournee_op[op] = self.fin_tournee_veh[veh] = fin
        self.planifier(fin, "ev_fin_tournee", tournee)

    def ev_charger(self, quand, tournee, sid, i):
        if not self.dispo[sid]:
            return
        if tournee["id"] is None:   # on ne garde que les tournées qui ont déplacé au moins un vélo
            tournee["id"] = self.nouvel_id("tournee")
            self.tournees[tournee["id"]] = [tournee["id"], tournee["debut"], None, tournee["op"], tournee["veh"]]
        v = self.rng.choice(sorted(self.dispo[sid]))
        mid = self.nouveau_mouvement(v, quand)
        self.t["transfert"].append((mid, tournee["id"]))
        tournee["charges"][i] = mid

    def ev_deposer(self, quand, tournee, sid, i):
        mid = tournee["charges"].get(i)
        if mid is None:
            return
        if not self.libres[sid]:
            sid = self.station_avec_place(depuis=sid, exclure=sid)
            if sid is None:   # aucune place nulle part : le vélo reste dans le véhicule
                return
        self.arrivee(mid, quand, sid)
        del tournee["charges"][i]

    def ev_fin_tournee(self, quand, tournee):
        if tournee["id"] is None:
            return
        if tournee["charges"]:   # vélos restés à bord : déposés avant la clôture
            for i, mid in list(tournee["charges"].items()):
                sid = self.station_avec_place()
                if sid is None:
                    self.fin_tournee_op[tournee["op"]] = self.fin_tournee_veh[tournee["veh"]] = quand + minutes(15)
                    self.planifier(quand + minutes(15), "ev_fin_tournee", tournee)
                    return
                self.arrivee(mid, quand, sid)
                del tournee["charges"][i]
            quand += MINUTE
        self.tournees[tournee["id"]][2] = quand
        self.fin_tournee_op[tournee["op"]] = self.fin_tournee_veh[tournee["veh"]] = quand

    # ------------------------------------------------------------- exécution
    def executer(self):
        top = time.time()
        self.creer_formules()
        self.creer_vehicules()
        self.creer_stations()
        self.creer_utilisateurs()
        self.formule_abonnement = {}
        self.creer_abonnements()
        self.formule_abonnement = {a[0]: a[4] for a in self.t["abonnement"]}
        self.preparer_demande()
        self.creer_flotte()
        self.planifier_trajets()
        self.planifier_tournees()
        self.planifier_signalements_station()
        print(f"  {len(self.file)} événements planifiés, simulation jusqu'au {self.maintenant:%d/%m/%Y %H:%M}…")
        while self.file and self.file[0][0] <= self.maintenant:
            quand, _, action, args = heapq.heappop(self.file)
            getattr(self, action)(quand, *args)
        self.stations_fermees()
        self.finaliser()
        print(f"  simulation terminée en {time.time() - top:.1f} s")

    def finaliser(self):
        for v, ligne in self.velos.items():
            ligne[2], ligne[3] = self.pos.get(v) or (None, None)
        for ligne in self.t["velo_electrique"]:
            v = ligne[0]
            ligne[1] = self.rng.randint(0, 40) if v in self.en_atelier else self.rng.randint(15, 100)
        self.t["velo"] = [tuple(self.velos[v]) for v in sorted(self.velos)]
        self.t["velo_electrique"] = [tuple(l) for l in self.t["velo_electrique"]]
        self.t["tournee"] = [tuple(self.tournees[i]) for i in sorted(self.tournees)]
        self.t["mouvement"] = [tuple(self.mouvements[i]) for i in sorted(self.mouvements)]
        self.t["signalement"] = [tuple(self.signalements[i]) for i in sorted(self.signalements)]
        self.t["signalement_velo"] = [tuple(self.sig_velo[i]) for i in sorted(self.sig_velo)]
        self.t["intervention_station"] = [tuple(self.interv_station[i]) for i in sorted(self.interv_station)]
        self.t["location"].sort()
        self.t["transfert"].sort()


# =============================================================================
#  Insertion
# =============================================================================

def ouvrir_base(cfg: argparse.Namespace):
    """Se connecte et vérifie, avant toute simulation, que la base peut recevoir les données."""
    try:
        cnx = pymysql.connect(host=cfg.hote, port=cfg.port, user=cfg.utilisateur, password=cfg.mot_de_passe,
                              database=cfg.base, charset="utf8mb4", autocommit=False)
    except pymysql.MySQLError as e:
        sys.exit(f"Connexion impossible à {cfg.utilisateur}@{cfg.hote}:{cfg.port}/{cfg.base} : {e}")
    with cnx.cursor() as c:
        c.execute("SELECT COUNT(*) FROM utilisateur")
        deja_remplie = c.fetchone()[0] > 0
        if deja_remplie and cfg.si_vide:
            cnx.close()
            print("La base contient déjà des données : rien à faire (--si-vide).")
            sys.exit(0)
        c.execute("SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema = DATABASE()")
        if c.fetchone()[0]:
            sys.exit("Les triggers d'automatisation.sql sont déjà chargés : ils recréeraient eux-mêmes "
                     "factures et changements d'état.\nRechargez structure.sql, lancez ce script, "
                     "puis automatisation.sql et optimisation.sql.")
        if deja_remplie and not cfg.vider:
            sys.exit("La base contient déjà des données : relancez avec --vider pour les remplacer.")
    return cnx


def inserer(cnx, cfg: argparse.Namespace, sim: Simulation):
    top = time.time()
    with cnx.cursor() as c:
        if cfg.vider:
            c.execute("SET FOREIGN_KEY_CHECKS = 0")
            for table in reversed(list(COLONNES)):
                c.execute(f"TRUNCATE TABLE {table}")
            c.execute("SET FOREIGN_KEY_CHECKS = 1")
        for table, colonnes in COLONNES.items():
            lignes = sim.t[table]
            sql = (f"INSERT INTO {table} ({', '.join(colonnes)}) "
                   f"VALUES ({', '.join(['%s'] * len(colonnes))})")
            for i in range(0, len(lignes), 5000):
                c.executemany(sql, lignes[i:i + 5000])
            print(f"  {table:<22} {len(lignes):>8} lignes")
    cnx.commit()
    cnx.close()
    print(f"  insertion terminée en {time.time() - top:.1f} s")


def lire_arguments(argv=None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Remplit velo_libre_service avec des données factices (Faker).")
    g = p.add_argument_group("connexion")
    g.add_argument("--hote", default=os.environ.get("DB_HOST", "127.0.0.1"))
    g.add_argument("--port", type=int, default=int(os.environ.get("DB_PORT", "3306")))
    g.add_argument("--utilisateur", default=os.environ.get("DB_USER", "root"))
    g.add_argument("--mot-de-passe", default=os.environ.get("DB_PASSWORD", ""))
    g.add_argument("--base", default=os.environ.get("DB_NAME", "velo_libre_service"))
    v = p.add_argument_group("volumes")
    v.add_argument("--usagers", type=int, default=8000, help="nombre d'usagers (défaut 8000)")
    v.add_argument("--stations", type=int, default=len(STATIONS),
                   help=f"nombre de stations, de 10 à 300 (défaut {len(STATIONS)} : toutes les stations nommées)")
    v.add_argument("--velos", type=int, default=0, help="taille de la flotte (défaut : 65 %% des bornes)")
    v.add_argument("--jours", type=int, default=365, help="durée de l'historique en jours (défaut 365)")
    v.add_argument("--trajets-par-jour", type=int, default=900, help="trajets moyens par jour (défaut 900)")
    p.add_argument("--graine", type=int, default=2026, help="graine aléatoire : mêmes données à chaque exécution")
    p.add_argument("--maintenant", type=lambda s: dt.datetime.strptime(s, "%Y-%m-%d %H:%M"),
                   default=dt.datetime.now().replace(second=0, microsecond=0),
                   help='date de fin de la simulation, "AAAA-MM-JJ HH:MM" (défaut : maintenant)')
    existant = p.add_mutually_exclusive_group()
    existant.add_argument("--vider", action="store_true", help="vide les tables avant l'insertion")
    existant.add_argument("--si-vide", action="store_true",
                          help="ne fait rien, sans erreur, si la base contient déjà des données (Docker)")
    cfg = p.parse_args(argv)
    if cfg.jours < 30:
        p.error("--jours doit valoir au moins 30")
    return cfg


def main():
    for flux in (sys.stdout, sys.stderr):
        if hasattr(flux, "reconfigure"):
            flux.reconfigure(encoding="utf-8", errors="replace")
    cfg = lire_arguments()
    cnx = ouvrir_base(cfg)
    print("Simulation du réseau…")
    sim = Simulation(cfg)
    sim.executer()
    print(f"Insertion dans {cfg.base} ({cfg.hote}:{cfg.port})…")
    inserer(cnx, cfg, sim)
    print(f"Terminé. Comptes de démonstration : admin@velo.example.org, regulation@velo.example.org,\n"
          f"maintenance@velo.example.org, usager@velo.example.org (mot de passe : {MOT_DE_PASSE_DEMO}).")


if __name__ == "__main__":
    main()
