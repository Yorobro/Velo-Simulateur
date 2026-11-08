<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Application\Page;
use App\Application\Port\FactureRepository;

final class PdoFactureRepository implements FactureRepository
{
    /** Factures d'un usager : souscriptions et trajets (deux requêtes indexées réunies). */
    private const FACTURES = '
        SELECT f.id_facture, f.date_emission, f.montant, f.date_reglement,
               \'ABONNEMENT\' AS objet, fo.libelle AS detail
          FROM facture f
          JOIN abonnement a ON a.id_abonnement = f.id_abonnement
          JOIN formule fo   ON fo.id_formule = a.id_formule
         WHERE a.id_utilisateur = ?
        UNION ALL
        SELECT f.id_facture, f.date_emission, f.montant, f.date_reglement,
               \'LOCATION\', CONCAT(\'Trajet n° \', f.id_location)
          FROM facture f
          JOIN location l   ON l.id_mouvement = f.id_location
          JOIN abonnement a ON a.id_abonnement = l.id_abonnement
         WHERE a.id_utilisateur = ?';

    public function __construct(private readonly BaseDeDonnees $db)
    {
    }

    public function duUtilisateur(int $utilisateur, int $page, int $parPage): Page
    {
        $total = (int) $this->db->valeur('SELECT COUNT(*) FROM (' . self::FACTURES . ') t', [$utilisateur, $utilisateur]);
        $pagination = new Page([], $total, $page, $parPage);

        return new Page($this->db->lignes(
            'SELECT * FROM (' . self::FACTURES . ') t ORDER BY date_emission DESC, id_facture DESC LIMIT ? OFFSET ?',
            [$utilisateur, $utilisateur, $parPage, $pagination->decalage()],
        ), $total, $page, $parPage);
    }

    public function impayees(int $utilisateur): array
    {
        $ligne = $this->db->ligne(
            'SELECT COUNT(*) AS nb, COALESCE(SUM(montant), 0) AS montant
               FROM (' . self::FACTURES . ') t WHERE date_reglement IS NULL AND montant > 0',
            [$utilisateur, $utilisateur],
        ) ?? [];

        return ['nb' => (int) ($ligne['nb'] ?? 0), 'montant' => (float) ($ligne['montant'] ?? 0)];
    }

    public function titulaire(int $facture): ?int
    {
        $id = $this->db->valeur(
            'SELECT COALESCE(a.id_utilisateur, al.id_utilisateur)
               FROM facture f
               LEFT JOIN abonnement a  ON a.id_abonnement = f.id_abonnement
               LEFT JOIN location l    ON l.id_mouvement = f.id_location
               LEFT JOIN abonnement al ON al.id_abonnement = l.id_abonnement
              WHERE f.id_facture = ?',
            [$facture],
        );

        return $id === null ? null : (int) $id;
    }

    public function regler(int $facture): void
    {
        $this->db->appeler('regler_facture', [$facture]);
    }
}
