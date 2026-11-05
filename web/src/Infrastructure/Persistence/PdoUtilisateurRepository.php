<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Application\Page;
use App\Application\Port\UtilisateurRepository;
use App\Domain\Role;
use App\Domain\Utilisateur;

final class PdoUtilisateurRepository implements UtilisateurRepository
{
    private const COLONNES = 'id_utilisateur, nom, prenom, email, role, mot_de_passe_hash';

    public function __construct(private readonly BaseDeDonnees $db)
    {
    }

    public function parEmail(string $email): ?Utilisateur
    {
        return $this->hydrater($this->db->ligne('SELECT ' . self::COLONNES . ' FROM utilisateur WHERE email = ?', [$email]));
    }

    public function parId(int $id): ?Utilisateur
    {
        return $this->hydrater($this->db->ligne('SELECT ' . self::COLONNES . ' FROM utilisateur WHERE id_utilisateur = ?', [$id]));
    }

    public function inscrire(array $donnees, string $motDePasseHash): int
    {
        $this->db->executer(
            'INSERT INTO utilisateur (nom, prenom, email, mot_de_passe_hash, telephone, role)
             VALUES (?, ?, ?, ?, ?, \'USAGER\')',
            [$donnees['nom'], $donnees['prenom'], $donnees['email'], $motDePasseHash, $donnees['telephone']],
        );

        return $this->db->dernierId();
    }

    public function rechercher(string $recherche, ?Role $role, int $page, int $parPage): Page
    {
        $conditions = [];
        $parametres = [];
        if ($recherche !== '') {
            $motif = '%' . addcslashes($recherche, '%_\\') . '%';
            $conditions[] = '(nom LIKE ? OR prenom LIKE ? OR email LIKE ?)';
            array_push($parametres, $motif, $motif, $motif);
        }
        if ($role !== null) {
            $conditions[] = 'role = ?';
            $parametres[] = $role->value;
        }
        $where = $conditions === [] ? '' : 'WHERE ' . implode(' AND ', $conditions);
        $total = (int) $this->db->valeur("SELECT COUNT(*) FROM utilisateur {$where}", $parametres);
        $pagination = new Page([], $total, $page, $parPage);
        $lignes = $this->db->lignes(
            "SELECT id_utilisateur, nom, prenom, email, telephone, date_inscription, role
               FROM utilisateur {$where} ORDER BY nom, prenom LIMIT ? OFFSET ?",
            [...$parametres, $parPage, $pagination->decalage()],
        );

        return new Page($lignes, $total, $page, $parPage);
    }

    public function compterParRole(): array
    {
        $compte = [];
        foreach ($this->db->lignes('SELECT role, COUNT(*) AS nb FROM utilisateur GROUP BY role') as $ligne) {
            $compte[(string) $ligne['role']] = (int) $ligne['nb'];
        }

        return $compte;
    }

    public function changerRole(int $id, Role $role): void
    {
        $this->db->executer('UPDATE utilisateur SET role = ? WHERE id_utilisateur = ?', [$role->value, $id]);
    }

    public function supprimer(int $id): void
    {
        $this->db->executer('DELETE FROM utilisateur WHERE id_utilisateur = ?', [$id]);
    }

    /** @param array<string, mixed>|null $ligne */
    private function hydrater(?array $ligne): ?Utilisateur
    {
        if ($ligne === null) {
            return null;
        }

        return new Utilisateur(
            (int) $ligne['id_utilisateur'],
            (string) $ligne['nom'],
            (string) $ligne['prenom'],
            (string) $ligne['email'],
            Role::from((string) $ligne['role']),
            (string) $ligne['mot_de_passe_hash'],
        );
    }
}
