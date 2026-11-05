<?php

declare(strict_types=1);

namespace App\Presentation\View;

use App\Infrastructure\Config;
use App\Presentation\Http\Authentification;
use App\Presentation\Http\Request;
use App\Presentation\Http\Response;
use App\Presentation\Http\Session;
use Throwable;
use Twig\Environment;
use Twig\Loader\FilesystemLoader;

/** Rendu des pages avec Twig (échappement HTML automatique). */
final class Vue
{
    private Environment $twig;
    private ?Request $requete = null;

    public function __construct(
        private readonly Config $config,
        private readonly Session $session,
        private readonly Authentification $auth,
    ) {
        $racine = (string) $config->get('app.racine');
        $debug = (bool) $config->get('app.debug');
        $this->twig = new Environment(new FilesystemLoader($racine . '/templates'), [
            'cache' => $debug ? false : $racine . '/var/cache/twig',
            'debug' => $debug,
            'autoescape' => 'html',
        ]);
        $this->twig->addExtension(new ExtensionTwig());
    }

    public function definirRequete(Request $requete): void
    {
        $this->requete = $requete;
    }

    /** @param array<string, mixed> $donnees */
    public function rendre(string $gabarit, array $donnees = [], int $statut = 200): Response
    {
        $utilisateur = $this->auth->utilisateur();
        $globales = [
            'app_nom' => $this->config->get('app.nom'),
            'utilisateur' => $utilisateur,
            'menu' => Menu::pour($utilisateur),
            'flashes' => $this->session->flashes(),
            'csrf_jeton' => $this->session->jetonCsrf(),
            'saisie' => $this->session->saisie(),
            'chemin' => $this->requete?->chemin ?? '/',
            'query' => $this->requete?->toutesLesQuery() ?? [],
        ];

        // Variables globales : visibles aussi dans les macros des composants.
        foreach ($globales as $cle => $valeur) {
            $this->twig->addGlobal($cle, $valeur);
        }

        return Response::html($this->twig->render($gabarit, $donnees), $statut);
    }

    public function erreur(int $statut, ?string $message = null, ?Throwable $exception = null): Response
    {
        $titres = [
            400 => 'Action impossible',
            403 => 'Accès refusé',
            404 => 'Page introuvable',
            405 => 'Méthode non autorisée',
            500 => 'Erreur interne',
        ];
        $textes = [
            403 => 'Votre rôle ne permet pas d\'accéder à cette page.',
            404 => 'La page ou l\'élément demandé n\'existe pas.',
            405 => 'Cette adresse n\'accepte pas ce type de requête.',
            500 => 'Une erreur inattendue s\'est produite. Réessayez dans un instant.',
        ];
        $details = $exception !== null && $this->config->get('app.debug')
            ? get_class($exception) . ' : ' . $exception->getMessage() . "\n\n" . $exception->getTraceAsString()
            : null;

        return $this->rendre('pages/erreur.html.twig', [
            'statut' => $statut,
            'titre' => $titres[$statut] ?? 'Erreur',
            'message' => $message ?? ($textes[$statut] ?? ''),
            'details' => $details,
        ], $statut);
    }
}
