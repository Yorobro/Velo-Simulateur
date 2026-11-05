<?php

declare(strict_types=1);

namespace App\Presentation\View;

use App\Domain\Role;
use App\Domain\Utilisateur;

/** Navigation latérale : seules les entrées autorisées pour le rôle sont affichées. */
final class Menu
{
    private const PERSONNEL = ['OPERATEUR_REGULATION', 'OPERATEUR_MAINTENANCE'];

    /** section => liste [libellé, url, icône, rôles autorisés (null = tous)] */
    private const ENTREES = [
        'Général' => [
            ['Tableau de bord', '/', 'grille', null],
            ['Stations', '/stations', 'station', null],
            ['Signaler un problème', '/signaler', 'drapeau', null],
        ],
        'Mon espace' => [
            ['Mes trajets', '/espace', 'velo', ['USAGER']],
            ['Historique', '/espace/locations', 'horloge', ['USAGER']],
            ['Abonnements', '/espace/abonnements', 'ticket', ['USAGER']],
            ['Factures', '/espace/factures', 'facture', ['USAGER']],
        ],
        'Exploitation' => [
            ['Régulation', '/regulation', 'camion', ['OPERATEUR_REGULATION']],
            ['Maintenance', '/maintenance', 'cle', ['OPERATEUR_MAINTENANCE']],
            ['Statistiques', '/statistiques', 'graphique', self::PERSONNEL],
        ],
        'Administration' => [
            ['Requêtes', '/requetes', 'base', []],
            ['Utilisateurs', '/admin/utilisateurs', 'utilisateurs', []],
            ['Formules', '/admin/formules', 'reglages', []],
        ],
    ];

    /** @return list<array{titre: string, entrees: list<array{libelle: string, url: string, icone: string}>}> */
    public static function pour(?Utilisateur $utilisateur): array
    {
        if ($utilisateur === null) {
            return [];
        }
        $sections = [];
        foreach (self::ENTREES as $titre => $entrees) {
            $visibles = [];
            foreach ($entrees as [$libelle, $url, $icone, $roles]) {
                $autorise = $roles === null
                    || ($roles === ['USAGER'] ? $utilisateur->role === Role::Usager : $utilisateur->role->autorise($roles));
                if ($autorise) {
                    $visibles[] = ['libelle' => $libelle, 'url' => $url, 'icone' => $icone];
                }
            }
            if ($visibles !== []) {
                $sections[] = ['titre' => $titre, 'entrees' => $visibles];
            }
        }

        return $sections;
    }
}
