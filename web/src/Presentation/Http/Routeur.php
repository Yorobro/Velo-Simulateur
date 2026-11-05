<?php

declare(strict_types=1);

namespace App\Presentation\Http;

use FastRoute\Dispatcher;
use FastRoute\RouteCollector;

use function FastRoute\simpleDispatcher;

/**
 * Table des routes (config/routes.php) : méthode, chemin, [contrôleur, méthode], accès.
 * Accès : 'invite' (non connecté), 'connecte' (tout utilisateur) ou liste de rôles.
 */
final class Routeur
{
    private Dispatcher $dispatcher;

    /** @param list<array{0: string, 1: string, 2: array{0: class-string, 1: string}, 3: string|list<string>}> $routes */
    public function __construct(array $routes)
    {
        $this->dispatcher = simpleDispatcher(static function (RouteCollector $collecteur) use ($routes): void {
            foreach ($routes as [$methode, $chemin, $action, $acces]) {
                $collecteur->addRoute($methode, $chemin, ['action' => $action, 'acces' => $acces]);
            }
        });
    }

    /**
     * @return array{statut: int, action?: array{0: class-string, 1: string}, acces?: string|list<string>, parametres?: array<string, string>}
     */
    public function trouver(string $methode, string $chemin): array
    {
        $resultat = $this->dispatcher->dispatch($methode, $chemin);

        return match ($resultat[0]) {
            Dispatcher::FOUND => [
                'statut' => 200,
                'action' => $resultat[1]['action'],
                'acces' => $resultat[1]['acces'],
                'parametres' => $resultat[2],
            ],
            Dispatcher::METHOD_NOT_ALLOWED => ['statut' => 405],
            default => ['statut' => 404],
        };
    }
}
