<?php

declare(strict_types=1);

use App\Presentation\Controller\AccueilController;
use App\Presentation\Controller\AdminController;
use App\Presentation\Controller\AuthController;
use App\Presentation\Controller\EspaceController;
use App\Presentation\Controller\MaintenanceController;
use App\Presentation\Controller\RegulationController;
use App\Presentation\Controller\RequeteController;
use App\Presentation\Controller\SignalementController;
use App\Presentation\Controller\StationController;
use App\Presentation\Controller\StatistiquesController;

/*
 * [méthode, chemin, [contrôleur, méthode], accès]
 * Accès : 'invite' (non connecté), 'connecte' (tout utilisateur connecté)
 * ou liste de rôles (l'administrateur est toujours autorisé).
 */
$usager = ['USAGER'];
$regulation = ['OPERATEUR_REGULATION'];
$maintenance = ['OPERATEUR_MAINTENANCE'];
$personnel = ['OPERATEUR_REGULATION', 'OPERATEUR_MAINTENANCE'];
$admin = [];

return [
    // Authentification
    ['GET', '/connexion', [AuthController::class, 'formConnexion'], 'invite'],
    ['POST', '/connexion', [AuthController::class, 'connexion'], 'invite'],
    ['GET', '/inscription', [AuthController::class, 'formInscription'], 'invite'],
    ['POST', '/inscription', [AuthController::class, 'inscription'], 'invite'],
    ['POST', '/deconnexion', [AuthController::class, 'deconnexion'], 'connecte'],

    // Tableau de bord et stations
    ['GET', '/', [AccueilController::class, 'index'], 'connecte'],
    ['GET', '/stations', [StationController::class, 'index'], 'connecte'],
    ['GET', '/stations/nouvelle', [StationController::class, 'nouvelle'], $admin],
    ['POST', '/stations', [StationController::class, 'creer'], $admin],
    ['GET', '/stations/{id:\d+}', [StationController::class, 'show'], 'connecte'],
    ['GET', '/stations/{id:\d+}/modifier', [StationController::class, 'edition'], $admin],
    ['POST', '/stations/{id:\d+}', [StationController::class, 'modifier'], $admin],
    ['POST', '/stations/{id:\d+}/supprimer', [StationController::class, 'supprimer'], $admin],
    ['POST', '/stations/{id:\d+}/bornes', [StationController::class, 'ajouterBorne'], $admin],
    ['POST', '/stations/{id:\d+}/bornes/{numero:\d+}', [StationController::class, 'etatBorne'], $admin],

    // Signalements (tout utilisateur)
    ['GET', '/signaler', [SignalementController::class, 'formulaire'], 'connecte'],
    ['POST', '/signaler/velo', [SignalementController::class, 'signalerVelo'], 'connecte'],
    ['POST', '/signaler/station', [SignalementController::class, 'signalerStation'], 'connecte'],

    // Espace usager
    ['GET', '/espace', [EspaceController::class, 'index'], $usager],
    ['POST', '/espace/emprunter', [EspaceController::class, 'emprunter'], $usager],
    ['POST', '/espace/locations/{id:\d+}/restituer', [EspaceController::class, 'restituer'], $usager],
    ['GET', '/espace/locations', [EspaceController::class, 'locations'], $usager],
    ['GET', '/espace/abonnements', [EspaceController::class, 'abonnements'], $usager],
    ['POST', '/espace/abonnements', [EspaceController::class, 'souscrire'], $usager],
    ['POST', '/espace/abonnements/{id:\d+}/renouveler', [EspaceController::class, 'renouveler'], $usager],
    ['GET', '/espace/factures', [EspaceController::class, 'factures'], $usager],
    ['POST', '/espace/factures/{id:\d+}/regler', [EspaceController::class, 'regler'], $usager],

    // Régulation
    ['GET', '/regulation', [RegulationController::class, 'index'], $regulation],
    ['POST', '/regulation/tournees', [RegulationController::class, 'demarrer'], $regulation],
    ['POST', '/regulation/tournees/{id:\d+}/charger', [RegulationController::class, 'charger'], $regulation],
    ['POST', '/regulation/tournees/{id:\d+}/cloturer', [RegulationController::class, 'cloturer'], $regulation],
    ['POST', '/regulation/transferts/{id:\d+}/deposer', [RegulationController::class, 'deposer'], $regulation],

    // Maintenance
    ['GET', '/maintenance', [MaintenanceController::class, 'index'], $maintenance],
    ['POST', '/maintenance/retraits', [MaintenanceController::class, 'retirer'], $maintenance],
    ['POST', '/maintenance/interventions/{id:\d+}/remettre', [MaintenanceController::class, 'remettre'], $maintenance],
    ['POST', '/maintenance/interventions/{id:\d+}/reformer', [MaintenanceController::class, 'reformer'], $maintenance],
    ['POST', '/maintenance/signalements/{id:\d+}/cloturer', [MaintenanceController::class, 'cloturerSignalement'], $maintenance],
    ['POST', '/maintenance/travaux', [MaintenanceController::class, 'demarrerTravaux'], $maintenance],
    ['POST', '/maintenance/travaux/{id:\d+}/terminer', [MaintenanceController::class, 'terminerTravaux'], $maintenance],

    // Statistiques
    ['GET', '/statistiques', [StatistiquesController::class, 'index'], $personnel],
    ['GET', '/statistiques/remplissage', [StatistiquesController::class, 'remplissage'], $personnel],

    // Administration
    ['GET', '/requetes', [RequeteController::class, 'index'], $admin],
    ['POST', '/requetes/console', [RequeteController::class, 'console'], $admin],
    ['POST', '/requetes/banc', [RequeteController::class, 'banc'], $admin],
    ['GET', '/admin/utilisateurs', [AdminController::class, 'utilisateurs'], $admin],
    ['POST', '/admin/utilisateurs/{id:\d+}/role', [AdminController::class, 'changerRole'], $admin],
    ['POST', '/admin/utilisateurs/{id:\d+}/supprimer', [AdminController::class, 'supprimerUtilisateur'], $admin],
    ['GET', '/admin/formules', [AdminController::class, 'formules'], $admin],
    ['POST', '/admin/formules/{id:\d+}', [AdminController::class, 'modifierFormule'], $admin],
];
