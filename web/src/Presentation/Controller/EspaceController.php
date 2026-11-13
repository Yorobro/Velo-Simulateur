<?php

declare(strict_types=1);

namespace App\Presentation\Controller;

use App\Application\Page;
use App\Application\Usager\EspaceUsagerService;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Request;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use App\Presentation\View\Vue;

/** Espace de l'usager : trajets, historique, abonnements, factures. */
final class EspaceController extends Controleur
{
    public function __construct(Vue $vue, Session $session, Authentification $auth, private readonly EspaceUsagerService $espace)
    {
        parent::__construct($vue, $session, $auth);
    }

    public function index(Request $requete): Response
    {
        return $this->rendre('pages/espace/index.html.twig',
            $this->espace->tableauDeBord($this->utilisateur()->id, $requete->queryEntier('station')));
    }

    public function emprunter(Request $requete): Response
    {
        $this->espace->emprunter($this->utilisateur()->id, $requete->entier('velo'), $requete->coche('casque'));

        return $this->rediriger('/espace', 'Bonne route ! Le vélo est à vous.');
    }

    public function restituer(Request $requete): Response
    {
        $this->espace->restituer($this->utilisateur()->id, $requete->id(), $requete->entier('station'));

        return $this->rediriger('/espace', 'Vélo restitué. Merci !');
    }

    public function locations(Request $requete): Response
    {
        return $this->rendre('pages/espace/locations.html.twig', [
            'page' => $this->espace->historique($this->utilisateur()->id, Page::numeroValide($requete->queryEntier('page'))),
        ]);
    }

    public function abonnements(Request $requete): Response
    {
        return $this->rendre('pages/espace/abonnements.html.twig', $this->espace->abonnements($this->utilisateur()->id));
    }

    public function souscrire(Request $requete): Response
    {
        $abonnement = $this->espace->souscrire($this->utilisateur()->id, $requete->entier('formule'));
        $message = ($abonnement['statut'] ?? '') === 'A_VENIR'
            ? sprintf('Changement programmé : votre abonnement %s commencera le %s.',
                      mb_strtolower((string) $abonnement['formule']), self::jour((string) $abonnement['date_debut']))
            : 'Abonnement souscrit.';

        return $this->rediriger('/espace/abonnements', $message . ' La facture est disponible dans vos factures.');
    }

    public function renouveler(Request $requete): Response
    {
        $abonnement = $this->espace->renouveler($this->utilisateur()->id, $requete->id());
        $message = isset($abonnement['date_debut'])
            ? sprintf('Abonnement renouvelé : la suite commence le %s.', self::jour((string) $abonnement['date_debut']))
            : 'Abonnement renouvelé.';

        return $this->rediriger('/espace/abonnements', $message);
    }

    private static function jour(string $date): string
    {
        return (new \DateTimeImmutable($date))->format('d/m/Y');
    }

    public function factures(Request $requete): Response
    {
        $usager = $this->utilisateur()->id;

        return $this->rendre('pages/espace/factures.html.twig', [
            'page' => $this->espace->factures($usager, Page::numeroValide($requete->queryEntier('page'))),
            'impayees' => $this->espace->impayees($usager),
        ]);
    }

    public function regler(Request $requete): Response
    {
        $this->espace->regler($this->utilisateur()->id, $requete->id());

        return $this->rediriger($requete->pagePrecedente('/espace/factures'), 'Facture réglée.');
    }
}
