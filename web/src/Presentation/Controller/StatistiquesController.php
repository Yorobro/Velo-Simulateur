<?php

declare(strict_types=1);

namespace App\Presentation\Controller;

use App\Application\Statistiques\StatistiquesService;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Request;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use App\Presentation\View\Vue;

final class StatistiquesController extends Controleur
{
    public function __construct(Vue $vue, Session $session, Authentification $auth, private readonly StatistiquesService $statistiques)
    {
        parent::__construct($vue, $session, $auth);
    }

    public function index(Request $requete): Response
    {
        return $this->rendre('pages/statistiques/index.html.twig', $this->statistiques->tableau($requete->query('periode', '30j')));
    }

    public function remplissage(Request $requete): Response
    {
        return $this->rendre('pages/statistiques/remplissage.html.twig', ['stations' => $this->statistiques->remplissage()]);
    }
}
