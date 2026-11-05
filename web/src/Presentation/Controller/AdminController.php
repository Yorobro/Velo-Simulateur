<?php

declare(strict_types=1);

namespace App\Presentation\Controller;

use App\Application\Admin\AdminService;
use App\Application\Page;
use App\Domain\Role;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Request;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use App\Presentation\View\Vue;

final class AdminController extends Controleur
{
    private const CHAMPS_FORMULE = ['prix', 'duree_validite_jours', 'duree_gratuite_min', 'duree_tranche_min',
                                    'prix_tranche', 'supplement_electrique', 'supplement_casque'];

    public function __construct(Vue $vue, Session $session, Authentification $auth, private readonly AdminService $admin)
    {
        parent::__construct($vue, $session, $auth);
    }

    public function utilisateurs(Request $requete): Response
    {
        $recherche = $requete->query('q');
        $role = $requete->query('role');

        return $this->rendre('pages/admin/utilisateurs.html.twig', [
            'page' => $this->admin->utilisateurs($recherche, $role, Page::numeroValide($requete->queryEntier('page'))),
            'recherche' => $recherche,
            'role' => $role,
            'roles' => array_map(static fn (Role $r): string => $r->value, Role::cases()),
            'compte' => $this->admin->compterParRole(),
        ]);
    }

    public function changerRole(Request $requete): Response
    {
        $this->admin->changerRole($this->utilisateur(), $requete->id(), $requete->texte('role'));

        return $this->rediriger($requete->pagePrecedente('/admin/utilisateurs'), 'Rôle mis à jour.');
    }

    public function supprimerUtilisateur(Request $requete): Response
    {
        $this->admin->supprimer($this->utilisateur(), $requete->id());

        return $this->rediriger($requete->pagePrecedente('/admin/utilisateurs'), 'Utilisateur supprimé.');
    }

    public function formules(Request $requete): Response
    {
        return $this->rendre('pages/admin/formules.html.twig', ['formules' => $this->admin->formules()]);
    }

    public function modifierFormule(Request $requete): Response
    {
        $saisie = [];
        foreach (self::CHAMPS_FORMULE as $champ) {
            $saisie[$champ] = $requete->texte($champ);
        }
        $this->admin->modifierFormule($requete->id(), $saisie);

        return $this->rediriger('/admin/formules', 'Formule mise à jour.');
    }
}
