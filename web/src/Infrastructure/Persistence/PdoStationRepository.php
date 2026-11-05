<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Application\Port\StationRepository;

/** Stations et bornes : lecture par la vue v_disponibilite_station, écriture directe. */
final class PdoStationRepository implements StationRepository
{
    private const SELECTION = 'SELECT d.id_station, d.nom, d.etat, d.nb_bornes, d.bornes_en_service, d.velos_presents,
               d.velos_mecaniques_disponibles, d.velos_electriques_disponibles, d.bornes_libres,
               d.taux_remplissage_pct, s.adresse, s.code_postal, s.latitude, s.longitude
          FROM v_disponibilite_station d
          JOIN station s ON s.id_station = d.id_station';

    public function __construct(private readonly BaseDeDonnees $db)
    {
    }

    public function lister(string $recherche = '', string $etat = ''): array
    {
        $motif = '%' . addcslashes($recherche, '%_\\') . '%';

        return $this->db->lignes(
            self::SELECTION . '
             WHERE (? = \'\' OR s.nom LIKE ? OR s.adresse LIKE ? OR s.code_postal LIKE ?)
               AND (? = \'\' OR s.etat = ?)
             ORDER BY s.nom',
            [$recherche, $motif, $motif, $motif, $etat, $etat],
        );
    }

    public function detail(int $id): ?array
    {
        return $this->db->ligne(self::SELECTION . ' WHERE d.id_station = ?', [$id]);
    }

    public function bornes(int $id): array
    {
        return $this->db->lignes(
            'SELECT b.numero, b.etat, v.id_velo,
                    IF(v.id_velo IS NULL, NULL, IF(ve.id_velo IS NULL, \'MECANIQUE\', \'ELECTRIQUE\')) AS type_velo,
                    ve.niveau_batterie, e.etat AS etat_velo
               FROM borne b
               LEFT JOIN velo v ON v.id_station = b.id_station AND v.numero_borne = b.numero
               LEFT JOIN velo_electrique ve ON ve.id_velo = v.id_velo
               LEFT JOIN v_etat_actuel_velo e ON e.id_velo = v.id_velo
              WHERE b.id_station = ?
              ORDER BY b.numero',
            [$id],
        );
    }

    public function creer(array $donnees, int $nbBornes): int
    {
        return $this->db->transaction(function () use ($donnees, $nbBornes): int {
            $this->db->executer(
                'INSERT INTO station (nom, adresse, code_postal, latitude, longitude, etat) VALUES (?, ?, ?, ?, ?, ?)',
                [$donnees['nom'], $donnees['adresse'], $donnees['code_postal'],
                 $donnees['latitude'], $donnees['longitude'], $donnees['etat']],
            );
            $id = $this->db->dernierId();
            $valeurs = implode(', ', array_fill(0, $nbBornes, '(?, ?, \'EN_SERVICE\')'));
            $parametres = [];
            foreach (range(1, $nbBornes) as $numero) {
                array_push($parametres, $id, $numero);
            }
            $this->db->executer("INSERT INTO borne (id_station, numero, etat) VALUES {$valeurs}", $parametres);

            return $id;
        });
    }

    public function modifier(int $id, array $donnees): void
    {
        $this->db->executer(
            'UPDATE station SET nom = ?, adresse = ?, code_postal = ?, latitude = ?, longitude = ?, etat = ?
              WHERE id_station = ?',
            [$donnees['nom'], $donnees['adresse'], $donnees['code_postal'],
             $donnees['latitude'], $donnees['longitude'], $donnees['etat'], $id],
        );
    }

    public function supprimer(int $id): void
    {
        $this->db->executer('DELETE FROM station WHERE id_station = ?', [$id]);
    }

    public function ajouterBorne(int $id): int
    {
        $numero = (int) $this->db->valeur('SELECT COALESCE(MAX(numero), 0) + 1 FROM borne WHERE id_station = ?', [$id]);
        $this->db->executer('INSERT INTO borne (id_station, numero, etat) VALUES (?, ?, \'EN_SERVICE\')', [$id, $numero]);

        return $numero;
    }

    public function changerEtatBorne(int $id, int $numero, string $etat): void
    {
        $this->db->executer('UPDATE borne SET etat = ? WHERE id_station = ? AND numero = ?', [$etat, $id, $numero]);
    }

    public function avecVelos(): array
    {
        return $this->db->lignes(
            'SELECT id_station, nom, velos_mecaniques_disponibles AS mecaniques,
                    velos_electriques_disponibles AS electriques
               FROM v_disponibilite_station
              WHERE etat = \'EN_SERVICE\' AND velos_mecaniques_disponibles + velos_electriques_disponibles > 0
              ORDER BY nom',
        );
    }

    public function avecPlace(): array
    {
        return $this->db->lignes(
            'SELECT id_station, nom, bornes_libres FROM v_disponibilite_station
              WHERE etat = \'EN_SERVICE\' AND bornes_libres > 0 ORDER BY nom',
        );
    }

    public function velosDisponibles(int $id): array
    {
        return $this->db->lignes(
            'SELECT v.id_velo, v.type_velo, v.niveau_batterie, v.numero_borne
               FROM v_velo v
               JOIN borne b ON b.id_station = v.id_station AND b.numero = v.numero_borne
              WHERE v.id_station = ? AND v.situation = \'SUR_BORNE\' AND v.etat = \'EN_SERVICE\'
                AND b.etat = \'EN_SERVICE\'
              ORDER BY v.type_velo DESC, v.numero_borne',
            [$id],
        );
    }
}
