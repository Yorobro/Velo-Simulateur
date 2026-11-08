<?php

declare(strict_types=1);

namespace App\Presentation\View;

use DateTimeImmutable;
use Twig\Extension\AbstractExtension;
use Twig\TwigFilter;
use Twig\TwigFunction;

/** Filtres et fonctions d'affichage : montants, dates, durées, libellés et couleurs des états. */
final class ExtensionTwig extends AbstractExtension
{
    private const LIBELLES = [
        'EN_SERVICE' => 'En service', 'HORS_SERVICE' => 'Hors service', 'EN_TRAVAUX' => 'En travaux',
        'DEFECTUEUX' => 'Défectueux', 'REFORME' => 'Réformé',
        'MECANIQUE' => 'Mécanique', 'ELECTRIQUE' => 'Électrique',
        'SUR_BORNE' => 'Sur borne', 'EN_LOCATION' => 'En location', 'EN_TOURNEE' => 'En tournée',
        'EN_ATELIER' => 'En atelier', 'INCONNUE' => 'Inconnue',
        'EN_COURS' => 'En cours', 'TERMINEE' => 'Terminée',
        'ACTIF' => 'Actif', 'EXPIRE' => 'Expiré', 'A_VENIR' => 'À venir',
        'OUVERT' => 'Ouvert', 'EN_TRAITEMENT' => 'En traitement', 'CLOS' => 'Clos',
        'VIDE' => 'Vide', 'PLEINE' => 'Pleine', 'PRESQUE_VIDE' => 'Presque vide',
        'PRESQUE_PLEINE' => 'Presque pleine', 'EQUILIBREE' => 'Équilibrée',
        'USAGER' => 'Usager', 'OPERATEUR_REGULATION' => 'Opérateur régulation',
        'OPERATEUR_MAINTENANCE' => 'Opérateur maintenance', 'ADMINISTRATEUR' => 'Administrateur',
        'VELO' => 'Vélo', 'STATION' => 'Station', 'ABONNEMENT' => 'Abonnement', 'LOCATION' => 'Location',
        'PAYEE' => 'Payée', 'A_PAYER' => 'À payer', 'TOUS' => 'Toute la flotte',
    ];

    /** Couleur de badge par valeur (success, warning, danger, info, primary, accent, neutral). */
    private const TONS = [
        'EN_SERVICE' => 'success', 'HORS_SERVICE' => 'danger', 'EN_TRAVAUX' => 'warning',
        'DEFECTUEUX' => 'warning', 'REFORME' => 'neutral',
        'MECANIQUE' => 'primary', 'ELECTRIQUE' => 'accent',
        'SUR_BORNE' => 'success', 'EN_LOCATION' => 'info', 'EN_TOURNEE' => 'primary', 'EN_ATELIER' => 'warning',
        'EN_COURS' => 'info', 'TERMINEE' => 'neutral',
        'ACTIF' => 'success', 'EXPIRE' => 'neutral', 'A_VENIR' => 'info',
        'OUVERT' => 'danger', 'EN_TRAITEMENT' => 'warning', 'CLOS' => 'success',
        'VIDE' => 'danger', 'PLEINE' => 'danger', 'PRESQUE_VIDE' => 'warning',
        'PRESQUE_PLEINE' => 'warning', 'EQUILIBREE' => 'success',
        'USAGER' => 'neutral', 'OPERATEUR_REGULATION' => 'primary',
        'OPERATEUR_MAINTENANCE' => 'accent', 'ADMINISTRATEUR' => 'info',
        'PAYEE' => 'success', 'A_PAYER' => 'warning',
    ];

    public function getFilters(): array
    {
        return [
            new TwigFilter('euros', [$this, 'euros']),
            new TwigFilter('nombre', [$this, 'nombre']),
            new TwigFilter('date_fr', [$this, 'dateFr']),
            new TwigFilter('jour', [$this, 'jour']),
            new TwigFilter('duree', [$this, 'duree']),
            new TwigFilter('libelle', [$this, 'libelle']),
            new TwigFilter('ton', [$this, 'ton']),
        ];
    }

    public function getFunctions(): array
    {
        return [
            new TwigFunction('icone', [Icones::class, 'svg'], ['is_safe' => ['html']]),
            new TwigFunction('actif', [$this, 'actif'], ['needs_context' => true]),
        ];
    }

    public function euros(mixed $montant): string
    {
        return number_format((float) $montant, 2, ',', "\u{202F}") . "\u{00A0}€";
    }

    public function nombre(mixed $valeur, int $decimales = 0): string
    {
        return number_format((float) $valeur, $decimales, ',', "\u{202F}");
    }

    public function dateFr(mixed $date, bool $avecHeure = true): string
    {
        if ($date === null || $date === '') {
            return '—';
        }
        $d = $date instanceof DateTimeImmutable ? $date : new DateTimeImmutable((string) $date);

        return $d->format($avecHeure ? 'd/m/Y à H:i' : 'd/m/Y');
    }

    public function jour(mixed $date): string
    {
        return $this->dateFr($date, false);
    }

    /** Minutes -> « 12 min » ou « 1 h 05 ». */
    public function duree(mixed $minutes): string
    {
        if ($minutes === null || $minutes === '') {
            return '—';
        }
        $minutes = (int) round((float) $minutes);
        if ($minutes < 60) {
            return "{$minutes}\u{00A0}min";
        }
        $jours = intdiv($minutes, 1440);
        $heures = intdiv($minutes % 1440, 60);
        $reste = $minutes % 60;
        if ($jours > 0) {
            return "{$jours}\u{00A0}j {$heures}\u{00A0}h";
        }

        return sprintf("%d\u{00A0}h\u{00A0}%02d", $heures, $reste);
    }

    public function libelle(mixed $code): string
    {
        $code = (string) $code;

        return self::LIBELLES[$code] ?? ucfirst(strtolower(str_replace('_', ' ', $code)));
    }

    public function ton(mixed $code): string
    {
        return self::TONS[(string) $code] ?? 'neutral';
    }

    /** Vrai si le chemin courant correspond à l'entrée de menu (l'entrée la plus précise l'emporte). */
    public function actif(array $contexte, string $url): bool
    {
        $chemin = (string) ($contexte['chemin'] ?? '/');
        $correspond = static fn (string $u): bool => $u === '/' ? $chemin === '/' : ($chemin === $u || str_starts_with($chemin, $u . '/'));
        if (!$correspond($url)) {
            return false;
        }
        foreach ($contexte['menu'] ?? [] as $section) {
            foreach ($section['entrees'] as $entree) {
                $autre = $entree['url'];
                if ($autre !== $url && str_starts_with($autre, $url . '/') && $correspond($autre)) {
                    return false;
                }
            }
        }

        return true;
    }
}
