<?php

declare(strict_types=1);

use App\Application\Port;
use App\Infrastructure\Config;
use App\Infrastructure\Container;
use App\Infrastructure\Persistence;
use App\Infrastructure\Securite\HacheurBcrypt;
use App\Presentation\Http\Routeur;

/*
 * Composition de l'application : chaque interface (port) est reliée à son
 * implémentation. Les autres classes se construisent automatiquement.
 */
$conteneur = new Container();

$conteneur->set(Container::class, static fn () => $conteneur);
$conteneur->set(Config::class, static fn () => new Config(require __DIR__ . '/app.php'));
$conteneur->set(Routeur::class, static fn () => new Routeur(require __DIR__ . '/routes.php'));

$conteneur->set(Port\HacheurMotDePasse::class, HacheurBcrypt::class);
$conteneur->set(Port\UtilisateurRepository::class, Persistence\PdoUtilisateurRepository::class);
$conteneur->set(Port\StationRepository::class, Persistence\PdoStationRepository::class);
$conteneur->set(Port\LocationRepository::class, Persistence\PdoLocationRepository::class);
$conteneur->set(Port\AbonnementRepository::class, Persistence\PdoAbonnementRepository::class);
$conteneur->set(Port\FactureRepository::class, Persistence\PdoFactureRepository::class);
$conteneur->set(Port\SignalementRepository::class, Persistence\PdoSignalementRepository::class);
$conteneur->set(Port\RegulationRepository::class, Persistence\PdoRegulationRepository::class);
$conteneur->set(Port\MaintenanceRepository::class, Persistence\PdoMaintenanceRepository::class);
$conteneur->set(Port\StatistiquesRepository::class, Persistence\PdoStatistiquesRepository::class);
$conteneur->set(Port\RequeteRepository::class, Persistence\PdoRequeteRepository::class);

return $conteneur;
