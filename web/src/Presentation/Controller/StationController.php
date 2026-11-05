<?php

declare(strict_types=1);

namespace App\Presentation\Controller;

use App\Application\Station\StationService;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Request;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use App\Presentation\View\Vue;

final class StationController extends Controleur
{
    private const CHAMPS = ['nom', 'adresse', 'code_postal', 'latitude', 'longitude', 'etat', 'nb_bornes'];

    public function __construct(Vue $vue, Session $session, Authentification $auth, private readonly StationService $stations)
    {
        parent::__construct($vue, $session, $auth);
    }

    public function index(Request $requete): Response
    {
        $recherche = $requete->query('q');
        $etat = $requete->query('etat');
        $stations = $this->stations->lister($recherche, $etat);

        return $this->rendre('pages/stations/index.html.twig', [
            'stations' => $stations,
            'recherche' => $recherche,
            'etat' => $etat,
            'etats' => StationService::ETATS,
            'totaux' => [
                'stations' => count($stations),
                'mecaniques' => array_sum(array_column($stations, 'velos_mecaniques_disponibles')),
                'electriques' => array_sum(array_column($stations, 'velos_electriques_disponibles')),
                'bornes_libres' => array_sum(array_column($stations, 'bornes_libres')),
            ],
        ]);
    }

    public function show(Request $requete): Response
    {
        $id = $requete->id();

        return $this->rendre('pages/stations/show.html.twig', [
            'station' => $this->stations->detail($id),
            'bornes' => $this->stations->bornes($id),
            'etats_borne' => StationService::ETATS_BORNE,
        ]);
    }

    public function nouvelle(Request $requete): Response
    {
        return $this->rendre('pages/stations/form.html.twig', ['station' => null, 'etats' => StationService::ETATS]);
    }

    public function creer(Request $requete): Response
    {
        $id = $this->stations->creer($this->saisie($requete));

        return $this->rediriger("/stations/{$id}", 'Station créée.');
    }

    public function edition(Request $requete): Response
    {
        return $this->rendre('pages/stations/form.html.twig', [
            'station' => $this->stations->detail($requete->id()),
            'etats' => StationService::ETATS,
        ]);
    }

    public function modifier(Request $requete): Response
    {
        $this->stations->modifier($requete->id(), $this->saisie($requete));

        return $this->rediriger("/stations/{$requete->id()}", 'Station modifiée.');
    }

    public function supprimer(Request $requete): Response
    {
        $this->stations->supprimer($requete->id());

        return $this->rediriger('/stations', 'Station supprimée.');
    }

    public function ajouterBorne(Request $requete): Response
    {
        $numero = $this->stations->ajouterBorne($requete->id());

        return $this->rediriger("/stations/{$requete->id()}", "Borne n° {$numero} ajoutée.");
    }

    public function etatBorne(Request $requete): Response
    {
        $this->stations->changerEtatBorne($requete->id(), $requete->id('numero'), $requete->texte('etat'));

        return $this->rediriger("/stations/{$requete->id()}", 'État de la borne mis à jour.');
    }

    /** @return array<string, string> */
    private function saisie(Request $requete): array
    {
        $saisie = [];
        foreach (self::CHAMPS as $champ) {
            $saisie[$champ] = $requete->texte($champ);
        }

        return $saisie;
    }
}
