<?php

declare(strict_types=1);

namespace App\Presentation\Controller;

use App\Application\Auth\AuthService;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Request;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use App\Presentation\View\Vue;

final class AuthController extends Controleur
{
    public function __construct(Vue $vue, Session $session, Authentification $auth, private readonly AuthService $service)
    {
        parent::__construct($vue, $session, $auth);
    }

    public function formConnexion(Request $requete): Response
    {
        return $this->rendre('pages/auth/connexion.html.twig');
    }

    public function connexion(Request $requete): Response
    {
        $utilisateur = $this->service->connecter($requete->texte('email'), (string) ($requete->toutLePost()['mot_de_passe'] ?? ''));
        $this->auth->connecter($utilisateur);

        return $this->rediriger('/', "Bonjour {$utilisateur->prenom} !");
    }

    public function formInscription(Request $requete): Response
    {
        return $this->rendre('pages/auth/inscription.html.twig');
    }

    public function inscription(Request $requete): Response
    {
        $post = $requete->toutLePost();
        $utilisateur = $this->service->inscrire([
            'prenom' => $requete->texte('prenom'),
            'nom' => $requete->texte('nom'),
            'email' => $requete->texte('email'),
            'telephone' => $requete->texte('telephone'),
            'mot_de_passe' => (string) ($post['mot_de_passe'] ?? ''),
            'confirmation' => (string) ($post['confirmation'] ?? ''),
        ]);
        $this->auth->connecter($utilisateur);

        return $this->rediriger('/espace/abonnements', 'Bienvenue ! Choisissez une formule pour emprunter vos premiers vélos.');
    }

    public function deconnexion(Request $requete): Response
    {
        $this->auth->deconnecter();

        return $this->rediriger('/connexion', 'Vous êtes déconnecté.');
    }
}
