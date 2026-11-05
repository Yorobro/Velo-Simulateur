<?php

declare(strict_types=1);

namespace App\Presentation\Http;

use App\Domain\Exception\AccesRefuseException;
use App\Domain\Exception\IntrouvableException;
use App\Domain\Exception\RegleMetierException;
use App\Infrastructure\Container;
use App\Presentation\View\Vue;
use Throwable;

/**
 * Traitement d'une requête : route, contrôle d'accès (connexion, rôle, jeton
 * CSRF), appel du contrôleur, puis traduction des erreurs en pages ou en
 * messages. Une règle métier refusée (par exemple par une procédure stockée)
 * revient sur la page précédente avec son message.
 */
final class Noyau
{
    public function __construct(
        private readonly Container $conteneur,
        private readonly Routeur $routeur,
        private readonly Session $session,
        private readonly Authentification $auth,
        private readonly Vue $vue,
    ) {
    }

    public function traiter(Request $requete): Response
    {
        $this->session->demarrer($requete->estHttps());
        $this->vue->definirRequete($requete);
        try {
            $reponse = $this->distribuer($requete);
        } catch (RegleMetierException $e) {
            if (!$requete->estPost()) {
                $reponse = $this->vue->erreur(400, $e->getMessage());
            } else {
                $this->session->flash('erreur', $e->getMessage());
                $this->session->memoriserSaisie($requete->toutLePost());
                $reponse = Response::redirection($this->retour($requete));
            }
        } catch (IntrouvableException) {
            $reponse = $this->vue->erreur(404);
        } catch (AccesRefuseException) {
            $reponse = $this->vue->erreur(403);
        } catch (Throwable $e) {
            error_log((string) $e);
            $reponse = $this->vue->erreur(500, null, $e);
        }

        return $reponse
            ->avecEntete('X-Content-Type-Options', 'nosniff')
            ->avecEntete('X-Frame-Options', 'DENY')
            ->avecEntete('Referrer-Policy', 'same-origin');
    }

    /**
     * Page où revenir après une action refusée : la page précédente si elle se
     * consulte en GET, sinon son adresse parente (/requetes/banc -> /requetes).
     */
    private function retour(Request $requete): string
    {
        $retour = $requete->pagePrecedente();
        $chemin = (string) parse_url($retour, PHP_URL_PATH);
        while ($chemin !== '' && $chemin !== '/' && $this->routeur->trouver('GET', $chemin)['statut'] !== 200) {
            $chemin = substr($chemin, 0, (int) strrpos($chemin, '/'));
            $retour = $chemin === '' ? '/' : $chemin;
        }

        return $retour;
    }

    private function distribuer(Request $requete): Response
    {
        $route = $this->routeur->trouver($requete->methode, $requete->chemin);
        if ($route['statut'] !== 200) {
            return $this->vue->erreur($route['statut']);
        }
        $utilisateur = $this->auth->utilisateur();
        $acces = $route['acces'];
        if ($acces === 'invite' && $utilisateur !== null) {
            return Response::redirection('/');
        }
        if ($acces !== 'invite' && $utilisateur === null) {
            if ($requete->chemin !== '/') {
                $this->session->flash('info', 'Connectez-vous pour accéder à cette page.');
            }

            return Response::redirection('/connexion');
        }
        if (is_array($acces) && !$utilisateur->role->autorise($acces)) {
            return $this->vue->erreur(403);
        }
        if ($requete->estPost() && !$this->session->csrfValide($requete->texte('_csrf'))) {
            $this->session->flash('erreur', 'Le formulaire a expiré : recommencez.');

            return Response::redirection($this->retour($requete));
        }
        [$classe, $methode] = $route['action'];

        return $this->conteneur->get($classe)->$methode($requete->avecAttributs($route['parametres']));
    }
}
