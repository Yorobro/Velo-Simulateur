#!/usr/bin/env python3
"""Banc de mesure des requêtes principales de velo_libre_service.

Mesure le temps d'exécution des requêtes de l'application (lectures du
site, statistiques, écritures avec leurs triggers) et relève leur plan
d'exécution et le nombre de lignes lues par le moteur. Sert au rapport
V2/rapport_performances.md, dans deux états de la base :
  - « avant » : automatisation.sql seul (voir performances/sans_optimisation.sql) ;
  - « apres » : automatisation.sql + optimisation.sql (état normal).

Méthode
  - un passage d'échauffement (données en mémoire), puis N mesures ; on
    garde la médiane, le minimum et le maximum ;
  - une requête lente est mesurée moins souvent (3 fois au-delà de 2 s,
    une fois au-delà de 20 s) et interrompue au-delà de --delai secondes ;
  - le temps comprend l'exécution et la lecture de toutes les lignes du
    résultat par le client, comme dans l'interface ;
  - « lignes lues » = somme des compteurs Handler_read_* de la session :
    nombre de lignes que le moteur a parcourues (index ou table) ;
  - les écritures (emprunt, restitution, souscription) sont exécutées dans
    une transaction annulée à la fin : triggers compris, aucune donnée n'est
    modifiée ;
  - la simulation d'activité (simulation.sql) est suspendue pendant la mesure
    puis relancée.

Utilisation (dans l'image Python du projet, réseau Docker de la base) :
    python performances/banc_performances.py --etat apres
    python performances/banc_performances.py --comparer performances/resultats_avant.json \\
                                             performances/resultats_apres.json
Connexion : DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME (ou options).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import statistics
import sys
import time
from pathlib import Path

try:
    import pymysql
except ImportError:
    sys.exit("Module manquant : pip install PyMySQL")

DOSSIER = Path(__file__).resolve().parent
USAGER_DEMO = "(SELECT id_utilisateur FROM utilisateur WHERE email = 'usager@velo.example.org')"
TRAJETS = "FROM location l JOIN mouvement m ON m.id_mouvement = l.id_mouvement"
DUREE = "CEIL(TIMESTAMPDIFF(SECOND, m.date_heure_depart, m.date_heure_arrivee) / 60)"
STATIONS = """SELECT d.id_station, d.nom, d.etat, d.nb_bornes, d.bornes_en_service, d.velos_presents,
       d.velos_mecaniques_disponibles, d.velos_electriques_disponibles, d.bornes_libres,
       d.taux_remplissage_pct, s.adresse, s.code_postal, s.latitude, s.longitude
  FROM v_disponibilite_station d JOIN station s ON s.id_station = d.id_station"""

# Requêtes de lecture : (id, catégorie, titre, SQL). Ce sont les requêtes du
# site (repositories PHP) et du catalogue de la page « Requêtes ».
LECTURES = [
    # --- temps réel et usager
    ("disponibilite", "Temps réel", "Disponibilité de toutes les stations",
     "SELECT * FROM v_disponibilite_station"),
    ("recherche_station", "Temps réel", "Recherche de stations (« gare »), page Stations",
     STATIONS + " WHERE (s.nom LIKE '%gare%' OR s.adresse LIKE '%gare%' OR s.code_postal LIKE '%gare%')"
     " ORDER BY s.nom"),
    ("fiche_station", "Temps réel", "Fiche d'une station",
     STATIONS + " WHERE d.id_station = 1"),
    ("flotte", "Temps réel", "Fiche de tous les vélos (v_velo)",
     "SELECT * FROM v_velo"),
    ("en_location", "Temps réel", "Locations en cours",
     "SELECT * FROM v_velo WHERE situation = 'EN_LOCATION'"),
    ("historique_usager", "Usager", "20 derniers trajets d'un usager",
     f"SELECT * FROM v_location WHERE id_utilisateur = {USAGER_DEMO} ORDER BY date_heure_depart DESC LIMIT 20"),
    ("abonnement_valide", "Usager", "Abonnement valide (vérifié à chaque emprunt)",
     f"SELECT fn_abonnement_valide({USAGER_DEMO}, CURDATE()) AS abonnement"),
    ("dernier_mouvement", "Usager", "Dernier mouvement d'un vélo (triggers de mouvement)",
     "SELECT * FROM mouvement WHERE id_velo = 7 ORDER BY date_heure_depart DESC LIMIT 1"),
    # --- exploitation
    ("regulation", "Exploitation", "Stations à réguler (v_regulation)",
     "SELECT * FROM v_regulation"),
    ("propositions", "Exploitation", "Propositions de déplacement",
     "SELECT * FROM v_proposition_deplacement"),
    ("signalements", "Exploitation", "Signalements ouverts",
     "SELECT * FROM signalement WHERE date_heure_cloture IS NULL ORDER BY date_heure_signalement"),
    ("impayees", "Exploitation", "Factures impayées",
     "SELECT * FROM facture WHERE date_reglement IS NULL AND montant > 0 ORDER BY date_emission"),
    ("recherche_utilisateur", "Exploitation", "Recherche d'utilisateurs (« martin »), page Utilisateurs",
     "SELECT id_utilisateur, nom, prenom, email, telephone, date_inscription, role FROM utilisateur"
     " WHERE (nom LIKE '%martin%' OR prenom LIKE '%martin%' OR email LIKE '%martin%')"
     " ORDER BY nom, prenom LIMIT 20"),
    ("locations_station_periode", "Exploitation", "Trajets d'une station sur 7 jours",
     "SELECT * FROM v_location WHERE id_station_depart = 1"
     " AND date_heure_depart >= NOW() - INTERVAL 7 DAY ORDER BY date_heure_depart DESC"),
    # --- page Statistiques du site (période de 30 jours)
    ("tableau_de_bord", "Statistiques (site, 30 j)", "Indicateurs du tableau de bord",
     f"""SELECT (SELECT COUNT(*) {TRAJETS} WHERE m.date_heure_depart >= CURDATE()) AS trajets_jour,
        (SELECT COUNT(*) {TRAJETS} WHERE m.date_heure_depart >= CURDATE() - INTERVAL 29 DAY) AS trajets_30j,
        (SELECT COALESCE(SUM(montant), 0) FROM facture WHERE date_emission >= CURDATE() - INTERVAL 29 DAY) AS recettes,
        (SELECT COUNT(DISTINCT id_utilisateur) FROM abonnement WHERE CURDATE() BETWEEN date_debut AND date_fin) AS abonnes,
        (SELECT COUNT(*) FROM v_velo WHERE situation = 'EN_LOCATION') AS en_location,
        (SELECT COALESCE(SUM(velos_mecaniques_disponibles + velos_electriques_disponibles), 0)
           FROM v_disponibilite_station) AS velos_disponibles"""),
    ("site_trajets_jour", "Statistiques (site, 30 j)", "Trajets par jour",
     f"SELECT DATE(m.date_heure_depart) AS jour, COUNT(*), ROUND(AVG({DUREE}), 1) {TRAJETS}"
     " WHERE m.date_heure_depart >= CURDATE() - INTERVAL 30 DAY GROUP BY DATE(m.date_heure_depart) ORDER BY jour"),
    ("site_heures", "Statistiques (site, 30 j)", "Départs par heure",
     f"SELECT HOUR(m.date_heure_depart) AS heure, COUNT(*) {TRAJETS}"
     " WHERE m.date_heure_depart >= CURDATE() - INTERVAL 30 DAY GROUP BY HOUR(m.date_heure_depart)"),
    ("site_origine_destination", "Statistiques (site, 30 j)", "10 trajets origine-destination les plus fréquents",
     f"""SELECT t.*, sd.nom, sa.nom
           FROM (SELECT m.id_station_depart, m.id_station_arrivee, COUNT(*) AS trajets, ROUND(AVG({DUREE}), 1) AS duree
                   {TRAJETS}
                  WHERE m.date_heure_depart >= CURDATE() - INTERVAL 30 DAY AND m.id_station_arrivee IS NOT NULL
                  GROUP BY m.id_station_depart, m.id_station_arrivee ORDER BY trajets DESC LIMIT 10) t
           JOIN station sd ON sd.id_station = t.id_station_depart
           JOIN station sa ON sa.id_station = t.id_station_arrivee ORDER BY t.trajets DESC"""),
    ("site_recettes", "Statistiques (site, 30 j)", "Recettes par formule",
     """SELECT f.id_formule, f.libelle, COALESCE(SUM(r.abonnements), 0), COALESCE(SUM(r.locations), 0), COUNT(r.id_formule)
          FROM formule f
          LEFT JOIN (SELECT a.id_formule, fa.montant AS abonnements, 0 AS locations
                       FROM facture fa JOIN abonnement a ON a.id_abonnement = fa.id_abonnement
                      WHERE fa.date_emission >= CURDATE() - INTERVAL 30 DAY
                     UNION ALL
                     SELECT a.id_formule, 0, fa.montant
                       FROM facture fa JOIN location l ON l.id_mouvement = fa.id_location
                       JOIN abonnement a ON a.id_abonnement = l.id_abonnement
                      WHERE fa.date_emission >= CURDATE() - INTERVAL 30 DAY) r ON r.id_formule = f.id_formule
         GROUP BY f.id_formule, f.libelle ORDER BY f.id_formule"""),
    # --- vues de statistiques (tout l'historique ou fenêtre fixe)
    ("stat_trajets_jour", "Vues de statistiques", "v_stat_trajets_par_jour (tout l'historique)",
     "SELECT * FROM v_stat_trajets_par_jour"),
    ("stat_heures", "Vues de statistiques", "v_stat_heures_pointe (tout l'historique)",
     "SELECT * FROM v_stat_heures_pointe"),
    ("stat_od", "Vues de statistiques", "v_stat_origine_destination (tout l'historique)",
     "SELECT * FROM v_stat_origine_destination"),
    ("stat_recettes", "Vues de statistiques", "v_stat_recettes_formule (tout l'historique)",
     "SELECT * FROM v_stat_recettes_formule"),
    ("stat_indispo", "Vues de statistiques", "v_stat_indisponibilite_flotte (30 jours)",
     "SELECT * FROM v_stat_indisponibilite_flotte"),
    ("stat_remplissage", "Vues de statistiques", "v_stat_remplissage_horaire (30 jours)",
     "SELECT * FROM v_stat_remplissage_horaire"),
]

ECRITURES = [
    ("emprunt", "Écritures (triggers compris)", "Emprunt : mouvement + location"),
    ("restitution", "Écritures (triggers compris)", "Restitution : arrivée, position, facture"),
    ("souscription", "Écritures (triggers compris)", "Souscription : abonnement + facture (R22)"),
]


class Banc:
    def __init__(self, cfg):
        self.cfg = cfg
        self.cnx = pymysql.connect(host=cfg.hote, port=cfg.port, user=cfg.utilisateur, password=cfg.mot_de_passe,
                                   database=cfg.base, charset="utf8mb4", autocommit=True)
        self.c = self.cnx.cursor()
        self.c.execute("SELECT 1")
        self.c.fetchall()
        self.base_lectures = 0
        self.base_lectures = self.lectures_requete("SELECT 1")   # coût du relevé lui-même

    # ------------------------------------------------------------- outils
    def valeur(self, sql):
        self.c.execute(sql)
        ligne = self.c.fetchone()
        return ligne[0] if ligne else None

    def compteurs(self) -> int:
        self.c.execute("SHOW SESSION STATUS LIKE 'Handler_read%'")
        return sum(int(v) for _, v in self.c.fetchall())

    def lectures_requete(self, sql) -> int:
        avant = self.compteurs()
        self.c.execute(sql)
        self.c.fetchall()
        return max(0, self.compteurs() - avant - self.base_lectures)

    def plan(self, sql) -> list[str]:
        try:
            self.c.execute("EXPLAIN " + sql)
        except pymysql.MySQLError as e:
            return [f"(plan indisponible : {e.args[-1]})"]
        noms = [d[0] for d in self.c.description]
        resume = []
        for ligne in self.c.fetchall():
            r = dict(zip(noms, ligne))
            if r.get("table") is None:
                continue
            acces = r.get("type") or "?"
            cle = f" ({r['key']})" if r.get("key") else ""
            resume.append(f"{r['table']} : {acces}{cle}, ~{r.get('rows')} lignes")
        return resume

    def chronometrer(self, fonction) -> list[float]:
        fonction()   # échauffement
        mesures = []
        debut = time.perf_counter()
        fonction()
        mesures.append((time.perf_counter() - debut) * 1000)
        n = self.cfg.repetitions if mesures[0] < 2000 else (3 if mesures[0] < 20000 else 1)
        for _ in range(n - 1):
            debut = time.perf_counter()
            fonction()
            mesures.append((time.perf_counter() - debut) * 1000)
        return mesures

    # ------------------------------------------------------------- lectures
    def mesurer_lecture(self, ident, categorie, titre, sql) -> dict:
        res = dict(id=ident, categorie=categorie, titre=titre, sql=" ".join(sql.split()))
        self.c.execute(f"SET SESSION max_execution_time = {self.cfg.delai * 1000}")
        try:
            def executer():
                self.c.execute(sql)
                res["lignes"] = len(self.c.fetchall())
            mesures = self.chronometrer(executer)
            res.update(mediane_ms=round(statistics.median(mesures), 2), min_ms=round(min(mesures), 2),
                       max_ms=round(max(mesures), 2), executions=len(mesures),
                       lectures=self.lectures_requete(sql), erreur=None)
        except pymysql.MySQLError as e:
            if e.args[0] == 3024:   # max_execution_time dépassé
                res.update(mediane_ms=None, interrompue_s=self.cfg.delai,
                           erreur=f"interrompue après {self.cfg.delai} s")
            else:
                res.update(mediane_ms=None, erreur=str(e.args[-1]))
        finally:
            self.c.execute("SET SESSION max_execution_time = 0")
        res["plan"] = self.plan(sql)
        return res

    # ------------------------------------------------------------- écritures
    def parametres_ecriture(self):
        p = {}
        self.c.execute("""SELECT v.id_velo, v.id_station FROM velo v
                            JOIN station s ON s.id_station = v.id_station AND s.etat = 'EN_SERVICE'
                            JOIN borne b ON b.id_station = v.id_station AND b.numero = v.numero_borne
                                        AND b.etat = 'EN_SERVICE'
                           WHERE fn_etat_velo(v.id_velo) = 'EN_SERVICE' ORDER BY v.id_velo LIMIT 1""")
        p["velo"], p["station_depart"] = self.c.fetchone()
        self.c.execute("""SELECT a.id_utilisateur, a.id_abonnement FROM abonnement a
                            JOIN utilisateur u ON u.id_utilisateur = a.id_utilisateur
                           WHERE CURDATE() BETWEEN a.date_debut AND a.date_fin
                             AND u.email <> 'usager@velo.example.org'
                             AND NOT EXISTS (SELECT 1 FROM abonnement a2 JOIN location l ON l.id_abonnement = a2.id_abonnement
                                               JOIN mouvement m ON m.id_mouvement = l.id_mouvement
                                              WHERE a2.id_utilisateur = a.id_utilisateur AND m.date_heure_arrivee IS NULL)
                           ORDER BY a.id_abonnement LIMIT 1""")
        p["usager"], p["abonnement"] = self.c.fetchone()
        p["station_arrivee"] = self.valeur(
            f"""SELECT id_station FROM station WHERE etat = 'EN_SERVICE' AND id_station <> {p['station_depart']}
                  AND fn_borne_libre(id_station) IS NOT NULL ORDER BY id_station LIMIT 1""")
        p["borne_arrivee"] = self.valeur(f"SELECT fn_borne_libre({p['station_arrivee']})")
        p["sans_abonnement"] = self.valeur(
            """SELECT u.id_utilisateur FROM utilisateur u WHERE u.role = 'USAGER'
                  AND NOT EXISTS (SELECT 1 FROM abonnement a WHERE a.id_utilisateur = u.id_utilisateur
                                     AND a.date_fin >= CURDATE() - INTERVAL 400 DAY)
                ORDER BY u.id_utilisateur LIMIT 1""") or self.valeur(
            """SELECT u.id_utilisateur FROM utilisateur u WHERE u.role = 'USAGER'
                  AND NOT EXISTS (SELECT 1 FROM abonnement a WHERE a.id_utilisateur = u.id_utilisateur
                                     AND a.date_fin >= CURDATE())
                ORDER BY u.id_utilisateur LIMIT 1""")
        return p

    def mesurer_ecriture(self, ident, categorie, titre, p) -> dict:
        res = dict(id=ident, categorie=categorie, titre=titre, plan=[], lignes=None)
        emprunt = [f"INSERT INTO mouvement (id_velo) VALUES ({p['velo']})",
                   f"INSERT INTO location (id_mouvement, avec_casque, id_abonnement)"
                   f" VALUES (LAST_INSERT_ID(), FALSE, {p['abonnement']})"]
        restitution = [f"""UPDATE mouvement SET date_heure_arrivee = NOW() + INTERVAL 15 MINUTE,
                               id_station_arrivee = {p['station_arrivee']}, numero_borne_arrivee = {p['borne_arrivee']}
                            WHERE id_velo = {p['velo']} AND date_heure_arrivee IS NULL"""]
        souscription = [f"INSERT INTO abonnement (date_debut, date_fin, id_utilisateur, id_formule)"
                        f" VALUES (CURDATE(), CURDATE(), {p['sans_abonnement']}, 2)"]
        prealable, mesurees = {"emprunt": ([], emprunt), "restitution": (emprunt, restitution),
                               "souscription": ([], souscription)}[ident]
        res["sql"] = " ; ".join(" ".join(s.split()) for s in mesurees)
        lectures = []

        def executer():
            self.c.execute("START TRANSACTION")
            try:
                for s in prealable:
                    self.c.execute(s)
                avant = self.compteurs()
                debut = time.perf_counter()
                for s in mesurees:
                    self.c.execute(s)
                duree = (time.perf_counter() - debut) * 1000
                lectures.append(max(0, self.compteurs() - avant - self.base_lectures))
                return duree
            finally:
                self.c.execute("ROLLBACK")

        try:
            executer()   # échauffement
            mesures = [executer() for _ in range(self.cfg.repetitions)]
            res.update(mediane_ms=round(statistics.median(mesures), 2), min_ms=round(min(mesures), 2),
                       max_ms=round(max(mesures), 2), executions=len(mesures), lectures=lectures[-1], erreur=None)
        except pymysql.MySQLError as e:
            res.update(mediane_ms=None, erreur=str(e.args[-1]))
        return res

    # ------------------------------------------------------------- exécution
    def volumes(self) -> dict:
        tables = ["utilisateur", "abonnement", "station", "borne", "velo", "changement_etat", "mouvement",
                  "location", "transfert", "tournee", "facture", "signalement", "intervention"]
        return {t: self.valeur(f"SELECT COUNT(*) FROM {t}") for t in tables}

    def executer(self) -> dict:
        simulation = self.valeur("SELECT COUNT(*) FROM information_schema.routines"
                                 " WHERE routine_schema = DATABASE() AND routine_name = 'sim_arreter'")
        if simulation:
            self.c.execute("CALL sim_arreter()")
            time.sleep(5)   # laisse finir un événement en cours
        try:
            rapport = dict(
                etat=self.cfg.etat,
                date=dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
                serveur=self.valeur("SELECT VERSION()"),
                buffer_pool_mo=int(self.valeur("SELECT @@innodb_buffer_pool_size")) // 2**20,
                index_idx=self.valeur("SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics"
                                      " WHERE table_schema = DATABASE() AND index_name LIKE 'idx\\_%'"),
                volumes=self.volumes(),
                repetitions=self.cfg.repetitions,
                resultats=[],
            )
            for (ident, cat, titre, sql) in LECTURES:
                r = self.mesurer_lecture(ident, cat, titre, sql)
                rapport["resultats"].append(r)
                print(f"  {ident:<28} {fmt(r)}", flush=True)
            p = self.parametres_ecriture()
            for (ident, cat, titre) in ECRITURES:
                r = self.mesurer_ecriture(ident, cat, titre, p)
                rapport["resultats"].append(r)
                print(f"  {ident:<28} {fmt(r)}", flush=True)
        finally:
            if simulation and not self.cfg.garder_arretee:
                self.c.execute("CALL sim_demarrer()")
        return rapport


def fmt(r) -> str:
    if r.get("mediane_ms") is None:
        return f"ERREUR : {r.get('erreur')}"
    return f"{r['mediane_ms']:>10.2f} ms   ({r['executions']} ex., {r.get('lectures')} lignes lues)"


def duree(ms) -> str:
    if ms is None:
        return "—"
    if ms >= 1000:
        return f"{ms / 1000:.2f} s".replace(".", ",")
    return f"{ms:.1f} ms".replace(".", ",") if ms < 100 else f"{ms:.0f} ms"


def nombre(n) -> str:
    return "—" if n is None else f"{n:,}".replace(",", " ")


def comparer(fichier_avant: Path, fichier_apres: Path) -> str:
    avant = {r["id"]: r for r in json.loads(fichier_avant.read_text(encoding="utf-8"))["resultats"]}
    apres_doc = json.loads(fichier_apres.read_text(encoding="utf-8"))
    lignes, categorie = [], None
    for r in apres_doc["resultats"]:
        a = avant.get(r["id"], {})
        if r["categorie"] != categorie:
            categorie = r["categorie"]
            lignes.append(f"| **{categorie}** | | | | | |")
        gain = "—"
        if a.get("interrompue_s"):
            t_av = f"> {a['interrompue_s']} s"
            if r.get("mediane_ms"):
                gain = f"> × {a['interrompue_s'] * 1000 / r['mediane_ms']:.0f}"
        else:
            t_av = duree(a.get("mediane_ms"))
            if a.get("mediane_ms") and r.get("mediane_ms"):
                gain = f"× {a['mediane_ms'] / r['mediane_ms']:.1f}".replace(".", ",")
        lignes.append(f"| {r['titre']} | {t_av} | {duree(r.get('mediane_ms'))} | {gain} | "
                      f"{nombre(a.get('lectures'))} | {nombre(r.get('lectures'))} |")
    entete = ("| Requête | Avant | Après | Gain | Lignes lues avant | Lignes lues après |\n"
              "|---|---:|---:|---:|---:|---:|")
    return entete + "\n" + "\n".join(lignes)


def main():
    for flux in (sys.stdout, sys.stderr):
        if hasattr(flux, "reconfigure"):
            flux.reconfigure(encoding="utf-8", errors="replace")
    p = argparse.ArgumentParser(description="Banc de mesure des requêtes principales.")
    p.add_argument("--hote", default=os.environ.get("DB_HOST", "127.0.0.1"))
    p.add_argument("--port", type=int, default=int(os.environ.get("DB_PORT", "3306")))
    p.add_argument("--utilisateur", default=os.environ.get("DB_USER", "root"))
    p.add_argument("--mot-de-passe", default=os.environ.get("DB_PASSWORD", ""))
    p.add_argument("--base", default=os.environ.get("DB_NAME", "velo_libre_service"))
    p.add_argument("--etat", choices=["avant", "apres"], help="état mesuré (nom du fichier de résultats)")
    p.add_argument("--repetitions", type=int, default=10, help="mesures par requête (défaut 10)")
    p.add_argument("--delai", type=int, default=180, help="durée maximale d'une requête en secondes (défaut 180)")
    p.add_argument("--garder-arretee", action="store_true", help="ne pas relancer la simulation après la mesure")
    p.add_argument("--comparer", nargs=2, metavar=("AVANT", "APRES"), help="tableau comparatif Markdown")
    cfg = p.parse_args()
    if cfg.comparer:
        print(comparer(Path(cfg.comparer[0]), Path(cfg.comparer[1])))
        return
    if not cfg.etat:
        p.error("--etat ou --comparer est requis")
    print(f"Mesure de l'état « {cfg.etat} »…", flush=True)
    rapport = Banc(cfg).executer()
    sortie = DOSSIER / f"resultats_{cfg.etat}.json"
    sortie.write_text(json.dumps(rapport, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    print(f"Résultats : {sortie}")


if __name__ == "__main__":
    main()
