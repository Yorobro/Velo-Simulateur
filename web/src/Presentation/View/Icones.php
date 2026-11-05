<?php

declare(strict_types=1);

namespace App\Presentation\View;

/** Icônes SVG en ligne (tracés simples, 24 × 24, couleur du texte). */
final class Icones
{
    private const TRACES = [
        'grille' => '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
        'station' => '<path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/>',
        'velo' => '<circle cx="5.5" cy="17" r="3.5"/><circle cx="18.5" cy="17" r="3.5"/><path d="M15 5h2.5l1 12M5.5 17l4-8h7.5M9.5 9l3 8h-7"/>',
        'horloge' => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
        'ticket' => '<path d="M3 8.5a2.5 2.5 0 0 0 0 5V17a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1v-3.5a2.5 2.5 0 0 1 0-5V7a1 1 0 0 0-1-1H4a1 1 0 0 0-1 1z"/><path d="M14 6v12" stroke-dasharray="2 2"/>',
        'facture' => '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6M9 16h3"/>',
        'camion' => '<path d="M2 6h12v10H2zM14 9h4l4 4v3h-8"/><circle cx="6.5" cy="17.5" r="2"/><circle cx="17.5" cy="17.5" r="2"/>',
        'cle' => '<path d="M14.7 6.3a4 4 0 0 0 5 5L22 9a6 6 0 0 1-8-8l-2.3 2.3a4 4 0 0 0 3 3zM13 8 3 18l3 3L16 11"/>',
        'graphique' => '<path d="M3 21h18M6 17V11M11 17V5M16 17v-8M21 17v-4"/>',
        'base' => '<ellipse cx="12" cy="5.5" rx="8" ry="2.8"/><path d="M4 5.5v13c0 1.5 3.6 2.8 8 2.8s8-1.3 8-2.8v-13M4 12c0 1.5 3.6 2.8 8 2.8s8-1.3 8-2.8"/>',
        'utilisateurs' => '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M21.5 20a6.5 6.5 0 0 0-4-6"/>',
        'utilisateur' => '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
        'reglages' => '<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>',
        'drapeau' => '<path d="M5 21V4M5 4h12l-2.5 4.5L17 13H5"/>',
        'sortie' => '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
        'alerte' => '<path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
        'ok' => '<path d="M20 6 9 17l-5-5"/>',
        'info' => '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
        'plus' => '<path d="M12 5v14M5 12h14"/>',
        'loupe' => '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
        'eclair' => '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
        'fleche' => '<path d="M5 12h14M13 6l6 6-6 6"/>',
        'croix' => '<path d="M18 6 6 18M6 6l12 12"/>',
        'menu' => '<path d="M3 6h18M3 12h18M3 18h18"/>',
        'euro' => '<path d="M17.5 6.5a6.5 6.5 0 1 0 0 11M4 10h9M4 14h9"/>',
        'batterie' => '<rect x="2" y="7" width="17" height="10" rx="2"/><path d="M22 11v2M6 10v4M9.5 10v4"/>',
        'lecture' => '<path d="m7 4 13 8-13 8z"/>',
        'stop' => '<rect x="6" y="6" width="12" height="12" rx="1.5"/>',
        'corbeille' => '<path d="M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14M10 11v5M14 11v5"/>',
        'crayon' => '<path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
        'borne' => '<rect x="7" y="3" width="10" height="18" rx="2"/><path d="M10 7h4M12 17h.01"/>',
        'calendrier' => '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
        'cadenas' => '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
        'carte' => '<path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2zM9 4v14M15 6v14"/>',
        'chrono' => '<circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2M9 2h6"/>',
    ];

    public static function svg(string $nom, int $taille = 18, string $classe = ''): string
    {
        $traces = self::TRACES[$nom] ?? self::TRACES['info'];
        $classe = htmlspecialchars(trim('icone ' . $classe), ENT_QUOTES);

        return sprintf(
            '<svg class="%s" width="%d" height="%d" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            . 'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">%s</svg>',
            $classe,
            $taille,
            $taille,
            $traces,
        );
    }
}
