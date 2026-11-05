<?php

declare(strict_types=1);

namespace App\Presentation\Controller;

use App\Application\Requete\RequeteService;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Request;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use App\Presentation\View\Vue;

/** Requêtes principales et console de lecture, avec temps d'exécution. */
final class RequeteController extends Controleur
{
    public function __construct(Vue $vue, Session $session, Authentification $auth, private readonly RequeteService $requetes)
    {
        parent::__construct($vue, $session, $auth);
    }

    public function index(Request $requete): Response
    {
        $id = $requete->query('requete');

        return $this->page([
            'choisie' => $id,
            'resultat' => $id !== '' ? $this->requetes->executerCatalogue($id) : null,
            'sql' => $id !== '' ? ($this->requetes->catalogue()[$id]['sql'] ?? '') : '',
        ]);
    }

    public function console(Request $requete): Response
    {
        $sql = (string) ($requete->toutLePost()['sql'] ?? '');

        return $this->page([
            'resultat' => $this->requetes->console($sql, $requete->texte('mode') === 'expliquer'),
            'sql' => $sql,
        ]);
    }

    public function banc(Request $requete): Response
    {
        $mesures = $this->requetes->executerTout();

        return $this->page([
            'mesures' => $mesures,
            'total_ms' => array_sum(array_map(static fn (array $m): float => (float) $m['duree_ms'], $mesures)),
        ]);
    }

    /** @param array<string, mixed> $donnees */
    private function page(array $donnees): Response
    {
        return $this->rendre('pages/requetes.html.twig', $donnees + [
            'catalogue' => $this->requetes->catalogue(),
            'choisie' => '',
            'resultat' => null,
            'sql' => '',
            'mesures' => null,
        ]);
    }
}
