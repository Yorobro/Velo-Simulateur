<?php

declare(strict_types=1);

namespace App\Presentation\Controller;

use App\Application\Maintenance\MaintenanceService;
use App\Application\Regulation\RegulationService;
use App\Application\Statistiques\StatistiquesService;
use App\Domain\Role;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Request;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use App\Presentation\View\Vue;

/** Tableau de bord : l'usager va à son espace, le personnel voit l'état du réseau. */
final class AccueilController extends Controleur
{
    public function __construct(
        Vue $vue,
        Session $session,
        Authentification $auth,
        private readonly StatistiquesService $statistiques,
        private readonly RegulationService $regulation,
        private readonly MaintenanceService $maintenance,
    ) {
        parent::__construct($vue, $session, $auth);
    }

    public function index(Request $requete): Response
    {
        if ($this->utilisateur()->role === Role::Usager) {
            return $this->rediriger('/espace');
        }
        $stations = $this->regulation->stations();

        return $this->rendre('pages/accueil.html.twig', [
            'indicateurs' => $this->statistiques->indicateurs(),
            'compte_stations' => array_count_values(array_column($stations, 'statut')),
            'a_reguler' => array_slice(array_values(array_filter(
                $stations,
                static fn (array $s): bool => $s['statut'] !== 'EQUILIBREE',
            )), 0, 6),
            'maintenance' => $this->maintenance->compteurs(),
        ]);
    }
}
