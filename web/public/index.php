<?php

declare(strict_types=1);

use App\Presentation\Http\Noyau;
use App\Presentation\Http\Request;

// Serveur intégré de PHP (php -S) : les fichiers statiques sont servis tels quels.
if (PHP_SAPI === 'cli-server') {
    $fichier = __DIR__ . parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
    if (is_file($fichier)) {
        return false;
    }
}

require dirname(__DIR__) . '/vendor/autoload.php';

$conteneur = require dirname(__DIR__) . '/config/container.php';
$conteneur->get(Noyau::class)->traiter(Request::depuisGlobales())->envoyer();
