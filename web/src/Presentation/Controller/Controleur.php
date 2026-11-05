<?php

declare(strict_types=1);

namespace App\Presentation\Controller;

use App\Domain\Utilisateur;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use App\Presentation\View\Vue;

/** Outils communs des contrôleurs (rendu, redirection, utilisateur connecté). */
abstract class Controleur
{
    public function __construct(
        protected readonly Vue $vue,
        protected readonly Session $session,
        protected readonly Authentification $auth,
    ) {
    }

    /** @param array<string, mixed> $donnees */
    protected function rendre(string $gabarit, array $donnees = []): Response
    {
        return $this->vue->rendre($gabarit, $donnees);
    }

    protected function rediriger(string $url, ?string $succes = null): Response
    {
        if ($succes !== null) {
            $this->session->flash('succes', $succes);
        }

        return Response::redirection($url);
    }

    protected function utilisateur(): Utilisateur
    {
        return $this->auth->exiger();
    }
}
