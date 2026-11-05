<?php

declare(strict_types=1);

namespace App\Presentation\Controller;

use App\Application\Signalement\SignalementService;
use App\Application\Station\StationService;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Request;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use App\Presentation\View\Vue;

final class SignalementController extends Controleur
{
    public function __construct(
        Vue $vue,
        Session $session,
        Authentification $auth,
        private readonly SignalementService $signalements,
        private readonly StationService $stations,
    ) {
        parent::__construct($vue, $session, $auth);
    }

    public function formulaire(Request $requete): Response
    {
        return $this->rendre('pages/signaler.html.twig', [
            'dernier_velo' => $this->signalements->dernierVelo($this->utilisateur()->id),
            'stations' => $this->stations->lister('', ''),
            'station_choisie' => $requete->queryEntier('station'),
            'velo_choisi' => $requete->queryEntier('velo'),
        ]);
    }

    public function signalerVelo(Request $requete): Response
    {
        $this->signalements->signalerVelo($this->utilisateur()->id, $requete->entier('velo'), $requete->texte('description'));

        return $this->rediriger('/signaler', 'Merci ! Votre signalement a été transmis à l\'équipe de maintenance.');
    }

    public function signalerStation(Request $requete): Response
    {
        $this->signalements->signalerStation($this->utilisateur()->id, $requete->entier('station'), $requete->texte('description'));

        return $this->rediriger('/signaler', 'Merci ! Votre signalement a été transmis à l\'équipe de maintenance.');
    }
}
