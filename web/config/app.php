<?php

declare(strict_types=1);

/*
 * Configuration de l'application.
 * Les valeurs viennent des variables d'environnement (Docker, serveur) ;
 * config/local.php (non versionné) peut les remplacer pour le poste local.
 */

$env = static function (string $cle, string $defaut): string {
    $valeur = getenv($cle);

    return $valeur === false || $valeur === '' ? $defaut : $valeur;
};

$config = [
    'app' => [
        'nom' => 'Vélo libre-service',
        'debug' => $env('APP_DEBUG', '1') === '1',
        'racine' => dirname(__DIR__),
    ],
    'db' => [
        'hote' => $env('DB_HOST', '127.0.0.1'),
        'port' => (int) $env('DB_PORT', '3306'),
        'base' => $env('DB_NAME', 'velo_libre_service'),
        'utilisateur' => $env('DB_USER', 'root'),
        'mot_de_passe' => $env('DB_PASSWORD', ''),
    ],
];

$local = __DIR__ . '/local.php';

return is_file($local) ? array_replace_recursive($config, require $local) : $config;
