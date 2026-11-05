<?php

declare(strict_types=1);

namespace App\Application\Requete;

use App\Application\Port\RequeteRepository;
use App\Application\Validateur;
use App\Domain\Exception\IntrouvableException;
use App\Domain\Exception\RegleMetierException;

/**
 * Exécution des requêtes principales (catalogue) et console de lecture,
 * avec mesure du temps d'exécution : base du rapport de performances.
 */
final class RequeteService
{
    private const MAX_LIGNES = 200;
    private const DELAI_MS = 15000;

    public function __construct(private readonly RequeteRepository $requetes)
    {
    }

    /** @return array<string, array{titre: string, description: string, sql: string}> */
    public function catalogue(): array
    {
        return $this->requetes->catalogue();
    }

    public function executerCatalogue(string $id): Resultat
    {
        $requete = $this->catalogue()[$id] ?? throw new IntrouvableException();

        return $this->requetes->executer($requete['sql'], self::MAX_LIGNES, self::DELAI_MS);
    }

    /**
     * Exécute tout le catalogue : un temps par requête (banc de mesure).
     *
     * @return list<array{id: string, titre: string, duree_ms: float|null, lignes: int|null, erreur: string|null}>
     */
    public function executerTout(): array
    {
        $mesures = [];
        foreach ($this->catalogue() as $id => $requete) {
            try {
                $resultat = $this->requetes->executer($requete['sql'], 1, self::DELAI_MS);
                $mesures[] = ['id' => $id, 'titre' => $requete['titre'], 'duree_ms' => $resultat->dureeMs,
                              'lignes' => $resultat->nbLignes, 'erreur' => null];
            } catch (RegleMetierException $e) {
                $mesures[] = ['id' => $id, 'titre' => $requete['titre'], 'duree_ms' => null,
                              'lignes' => null, 'erreur' => $e->getMessage()];
            }
        }

        return $mesures;
    }

    /** Console : une seule instruction de lecture (SELECT, WITH, EXPLAIN, SHOW, DESCRIBE). */
    public function console(string $sql, bool $expliquer): Resultat
    {
        $sql = rtrim(trim($sql), "; \t\n\r");
        (new Validateur())
            ->requis('sql', $sql, 'La requête')
            ->longueur('sql', $sql, 1, 10000, 'La requête')
            ->si(str_contains($sql, ';'), 'sql', 'Une seule instruction à la fois (pas de « ; »).')
            ->motif('sql', $sql, '/^\s*(SELECT|WITH|EXPLAIN|SHOW|DESCRIBE|DESC)\b/i',
                'Seules les requêtes de lecture sont permises : SELECT, WITH, EXPLAIN, SHOW, DESCRIBE.')
            ->si((bool) preg_match('/\bINTO\s+(OUTFILE|DUMPFILE|@)/i', $sql), 'sql', 'SELECT … INTO est interdit.')
            ->verifier();
        if ($expliquer && !preg_match('/^\s*EXPLAIN\b/i', $sql)) {
            $sql = 'EXPLAIN ' . $sql;
        }

        return $this->requetes->executer($sql, self::MAX_LIGNES, self::DELAI_MS);
    }
}
