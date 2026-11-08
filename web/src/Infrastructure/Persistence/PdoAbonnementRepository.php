<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Application\Port\AbonnementRepository;

final class PdoAbonnementRepository implements AbonnementRepository
{
    public function __construct(private readonly BaseDeDonnees $db)
    {
    }

    public function actif(int $utilisateur): ?array
    {
        return $this->db->ligne(
            'SELECT v.*, f.duree_gratuite_min, f.prix_tranche, f.duree_tranche_min, f.supplement_casque
               FROM v_abonnement v
               JOIN abonnement a ON a.id_abonnement = v.id_abonnement
               JOIN formule f ON f.id_formule = a.id_formule
              WHERE v.id_utilisateur = ? AND v.statut = \'ACTIF\'
              ORDER BY v.date_debut DESC LIMIT 1',
            [$utilisateur],
        );
    }

    public function duUtilisateur(int $utilisateur): array
    {
        return $this->db->lignes(
            'SELECT v.*, f.prix, f.duree_validite_jours
               FROM v_abonnement v
               JOIN abonnement a ON a.id_abonnement = v.id_abonnement
               JOIN formule f ON f.id_formule = a.id_formule
              WHERE v.id_utilisateur = ?
              ORDER BY v.date_debut DESC',
            [$utilisateur],
        );
    }

    public function titulaire(int $abonnement): ?int
    {
        $id = $this->db->valeur('SELECT id_utilisateur FROM abonnement WHERE id_abonnement = ?', [$abonnement]);

        return $id === null ? null : (int) $id;
    }

    public function souscrire(int $utilisateur, int $formule): int
    {
        return (int) $this->db->appeler('souscrire_abonnement', [$utilisateur, $formule, null], 1)[0];
    }

    public function renouveler(int $abonnement): int
    {
        return (int) $this->db->appeler('renouveler_abonnement', [$abonnement], 1)[0];
    }

    public function formules(): array
    {
        return $this->db->lignes('SELECT * FROM formule ORDER BY duree_validite_jours, prix');
    }

    public function modifierFormule(int $formule, array $donnees): void
    {
        $this->db->executer(
            'UPDATE formule SET prix = ?, duree_validite_jours = ?, duree_gratuite_min = ?, duree_tranche_min = ?,
                    prix_tranche = ?, supplement_electrique = ?, supplement_casque = ?
              WHERE id_formule = ?',
            [(string) $donnees['prix'], (int) $donnees['duree_validite_jours'], (int) $donnees['duree_gratuite_min'],
             (int) $donnees['duree_tranche_min'], (string) $donnees['prix_tranche'],
             (string) $donnees['supplement_electrique'], (string) $donnees['supplement_casque'], $formule],
        );
    }
}
