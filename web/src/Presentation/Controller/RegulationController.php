<?php

declare(strict_types=1);

namespace App\Presentation\Controller;

use App\Application\Regulation\RegulationService;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Request;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use App\Presentation\View\Vue;

final class RegulationController extends Controleur
{
    public function __construct(Vue $vue, Session $session, Authentification $auth, private readonly RegulationService $regulation)
    {
        parent::__construct($vue, $session, $auth);
    }

    public function index(Request $requete): Response
    {
        return $this->rendre('pages/regulation.html.twig',
            $this->regulation->tableau($this->utilisateur(), $requete->queryEntier('station')));
    }

    public function demarrer(Request $requete): Response
    {
        $tournee = $this->regulation->demarrer($this->utilisateur(), $requete->entier('vehicule'));

        return $this->rediriger('/regulation', "Tournée n° {$tournee} démarrée.");
    }

    public function charger(Request $requete): Response
    {
        $this->regulation->charger($this->utilisateur(), $requete->id(), $requete->entier('velo'));

        return $this->rediriger($requete->pagePrecedente('/regulation'), 'Vélo chargé dans le véhicule.');
    }

    public function deposer(Request $requete): Response
    {
        $this->regulation->deposer($this->utilisateur(), $requete->id(), $requete->entier('station'));

        return $this->rediriger('/regulation', 'Vélo déposé.');
    }

    public function cloturer(Request $requete): Response
    {
        $this->regulation->cloturer($this->utilisateur(), $requete->id());

        return $this->rediriger('/regulation', 'Tournée clôturée.');
    }
}
