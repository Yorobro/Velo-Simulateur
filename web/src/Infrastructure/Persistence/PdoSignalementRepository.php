<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Application\Page;
use App\Application\Port\SignalementRepository;

final class PdoSignalementRepository implements SignalementRepository
{
    public function __construct(private readonly BaseDeDonnees $db)
    {
    }

    public function signalerVelo(int $utilisateur, int $velo, string $description): int
    {
        return (int) $this->db->appeler('signaler_velo', [$utilisateur, $velo, $description], 1)[0];
    }

    public function signalerStation(int $utilisateur, int $station, string $description): int
    {
        return (int) $this->db->appeler('signaler_station', [$utilisateur, $station, $description], 1)[0];
    }

    public function dernierVeloEmprunte(int $utilisateur): ?int
    {
        $velo = $this->db->valeur(
            'SELECT m.id_velo
               FROM location l
               JOIN abonnement a ON a.id_abonnement = l.id_abonnement
               JOIN mouvement m  ON m.id_mouvement = l.id_mouvement
              WHERE a.id_utilisateur = ?
              ORDER BY m.date_heure_depart DESC LIMIT 1',
            [$utilisateur],
        );

        return $velo === null ? null : (int) $velo;
    }

    public function rechercher(string $statut, string $cible, int $page, int $parPage): Page
    {
        $filtre = 'WHERE (? = \'\' OR statut = ?) AND (? = \'\' OR cible = ?)';
        $parametres = [$statut, $statut, $cible, $cible];
        $total = (int) $this->db->valeur("SELECT COUNT(*) FROM v_signalement {$filtre}", $parametres);
        $pagination = new Page([], $total, $page, $parPage);

        return new Page($this->db->lignes(
            "SELECT * FROM v_signalement {$filtre} ORDER BY date_heure_signalement DESC LIMIT ? OFFSET ?",
            [...$parametres, $parPage, $pagination->decalage()],
        ), $total, $page, $parPage);
    }

    public function cloturer(int $signalement): void
    {
        $this->db->appeler('cloturer_signalement', [$signalement]);
    }
}
