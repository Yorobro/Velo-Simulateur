<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Application\Page;
use App\Application\Port\LocationRepository;

/** Locations : lecture par la vue v_location, emprunt et restitution par procédures stockées. */
final class PdoLocationRepository implements LocationRepository
{
    public function __construct(private readonly BaseDeDonnees $db)
    {
    }

    public function enCours(int $utilisateur): ?array
    {
        return $this->db->ligne(
            'SELECT * FROM v_location WHERE id_utilisateur = ? AND statut = \'EN_COURS\'
              ORDER BY date_heure_depart DESC LIMIT 1',
            [$utilisateur],
        );
    }

    public function historique(int $utilisateur, int $page, int $parPage): Page
    {
        $total = (int) $this->db->valeur(
            'SELECT COUNT(*) FROM location l JOIN abonnement a ON a.id_abonnement = l.id_abonnement
              WHERE a.id_utilisateur = ?',
            [$utilisateur],
        );
        $pagination = new Page([], $total, $page, $parPage);

        return new Page($this->db->lignes(
            'SELECT * FROM v_location WHERE id_utilisateur = ? ORDER BY date_heure_depart DESC LIMIT ? OFFSET ?',
            [$utilisateur, $parPage, $pagination->decalage()],
        ), $total, $page, $parPage);
    }

    public function bilan(int $utilisateur): array
    {
        $ligne = $this->db->ligne(
            'SELECT COUNT(*) AS nb,
                    COALESCE(SUM(CEIL(TIMESTAMPDIFF(SECOND, m.date_heure_depart, m.date_heure_arrivee) / 60)), 0) AS minutes,
                    COALESCE(SUM(f.montant), 0) AS depense
               FROM location l
               JOIN abonnement a ON a.id_abonnement = l.id_abonnement
               JOIN mouvement m  ON m.id_mouvement = l.id_mouvement
               LEFT JOIN facture f ON f.id_location = l.id_mouvement
              WHERE a.id_utilisateur = ? AND m.date_heure_arrivee IS NOT NULL',
            [$utilisateur],
        ) ?? [];

        return ['nb' => (int) ($ligne['nb'] ?? 0), 'minutes' => (int) ($ligne['minutes'] ?? 0),
                'depense' => (float) ($ligne['depense'] ?? 0)];
    }

    public function titulaire(int $location): ?int
    {
        $id = $this->db->valeur(
            'SELECT a.id_utilisateur FROM location l JOIN abonnement a ON a.id_abonnement = l.id_abonnement
              WHERE l.id_mouvement = ?',
            [$location],
        );

        return $id === null ? null : (int) $id;
    }

    public function emprunter(int $utilisateur, int $velo, bool $casque): int
    {
        return (int) $this->db->appeler('emprunter_velo', [$utilisateur, $velo, $casque], 1)[0];
    }

    public function restituer(int $location, int $station): void
    {
        $this->db->appeler('restituer_velo', [$location, $station, null]);
    }
}
