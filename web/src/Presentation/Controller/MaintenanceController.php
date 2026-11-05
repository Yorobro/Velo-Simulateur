<?php

declare(strict_types=1);

namespace App\Presentation\Controller;

use App\Application\Maintenance\MaintenanceService;
use App\Application\Page;
use App\Application\Signalement\SignalementService;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Request;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use App\Presentation\View\Vue;

final class MaintenanceController extends Controleur
{
    private const ONGLETS = ['velos', 'stations', 'signalements'];

    public function __construct(
        Vue $vue,
        Session $session,
        Authentification $auth,
        private readonly MaintenanceService $maintenance,
        private readonly SignalementService $signalements,
    ) {
        parent::__construct($vue, $session, $auth);
    }

    public function index(Request $requete): Response
    {
        $onglet = in_array($requete->query('onglet'), self::ONGLETS, true) ? $requete->query('onglet') : 'velos';
        $donnees = $this->maintenance->tableau() + ['onglet' => $onglet];
        if ($onglet === 'signalements') {
            $donnees['statut'] = $requete->query('statut');
            $donnees['cible'] = $requete->query('cible');
            $donnees['page'] = $this->signalements->rechercher($donnees['statut'], $donnees['cible'],
                Page::numeroValide($requete->queryEntier('page')));
        }

        return $this->rendre('pages/maintenance.html.twig', $donnees);
    }

    public function retirer(Request $requete): Response
    {
        $id = $this->maintenance->retirer($this->utilisateur()->id, $requete->entier('velo'), $requete->texte('description'));

        return $this->rediriger('/maintenance', "Vélo retiré pour maintenance (intervention n° {$id}).");
    }

    public function remettre(Request $requete): Response
    {
        $this->maintenance->remettre($requete->id(), $requete->entier('station'));

        return $this->rediriger('/maintenance', 'Vélo remis en circulation.');
    }

    public function reformer(Request $requete): Response
    {
        $this->maintenance->reformer($requete->id());

        return $this->rediriger('/maintenance', 'Vélo réformé.');
    }

    public function cloturerSignalement(Request $requete): Response
    {
        $this->signalements->cloturer($requete->id());

        return $this->rediriger($requete->pagePrecedente('/maintenance?onglet=signalements'), 'Signalement clos.');
    }

    public function demarrerTravaux(Request $requete): Response
    {
        $this->maintenance->demarrerTravaux($this->utilisateur()->id, $requete->entier('signalement'),
            $requete->texte('description'));

        return $this->rediriger('/maintenance?onglet=stations', 'Intervention sur la station démarrée.');
    }

    public function terminerTravaux(Request $requete): Response
    {
        $resolu = $requete->texte('resolu') === '1';
        $this->maintenance->terminerTravaux($requete->id(), $resolu);

        return $this->rediriger('/maintenance?onglet=stations',
            $resolu ? 'Intervention terminée, signalement clos.' : 'Intervention terminée, le signalement reste ouvert.');
    }
}
