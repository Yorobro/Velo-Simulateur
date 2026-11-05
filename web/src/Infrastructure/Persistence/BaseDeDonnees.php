<?php

declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Exception\RegleMetierException;
use App\Infrastructure\Config;
use PDO;
use PDOException;
use PDOStatement;
use RuntimeException;
use Throwable;

/**
 * Accès PDO à MySQL : requêtes préparées, appel des procédures stockées et
 * traduction des erreurs de la base en messages lisibles.
 */
final class BaseDeDonnees
{
    /** Messages des contraintes UNIQUE et CHECK de structure.sql. */
    private const CONTRAINTES = [
        'uq_utilisateur_email' => 'Cette adresse e-mail est déjà utilisée.',
        'uq_station_adresse' => 'Une station existe déjà à cette adresse.',
        'uq_station_coordonnees' => 'Une station existe déjà à ces coordonnées.',
        'ck_utilisateur_email' => 'L\'adresse e-mail n\'est pas valide.',
        'ck_utilisateur_telephone' => 'Le téléphone doit contenir 10 à 15 chiffres.',
        'ck_station_code_postal' => 'Le code postal doit contenir 5 chiffres.',
        'ck_formule_tranche' => 'La durée d\'une tranche doit être positive.',
        'ck_formule_validite' => 'La durée de validité doit être positive.',
    ];

    private ?PDO $pdo = null;

    public function __construct(private readonly Config $config)
    {
    }

    public function pdo(): PDO
    {
        if ($this->pdo === null) {
            $dsn = sprintf(
                'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
                $this->config->get('db.hote'),
                $this->config->get('db.port'),
                $this->config->get('db.base'),
            );
            try {
                $this->pdo = new PDO($dsn, (string) $this->config->get('db.utilisateur'),
                    (string) $this->config->get('db.mot_de_passe'), [
                        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                        PDO::ATTR_EMULATE_PREPARES => false,
                        // Même collation que la base (et que ses vues) : évite les erreurs
                        // « Illegal mix of collations » sur les comparaisons de textes.
                        PDO::MYSQL_ATTR_INIT_COMMAND => 'SET collation_connection = @@collation_database',
                    ]);
            } catch (PDOException $e) {
                throw new RuntimeException('Connexion à la base impossible : ' . $e->getMessage(), 0, $e);
            }
        }

        return $this->pdo;
    }

    /**
     * @param array<int|string, mixed> $parametres
     * @return list<array<string, mixed>>
     */
    public function lignes(string $sql, array $parametres = []): array
    {
        $requete = $this->executerRequete($sql, $parametres);
        $lignes = $requete->fetchAll();
        $requete->closeCursor();

        return $lignes;
    }

    /**
     * @param array<int|string, mixed> $parametres
     * @return array<string, mixed>|null
     */
    public function ligne(string $sql, array $parametres = []): ?array
    {
        return $this->lignes($sql, $parametres)[0] ?? null;
    }

    /** @param array<int|string, mixed> $parametres */
    public function valeur(string $sql, array $parametres = []): mixed
    {
        $ligne = $this->ligne($sql, $parametres);

        return $ligne === null ? null : reset($ligne);
    }

    /** @param array<int|string, mixed> $parametres */
    public function executer(string $sql, array $parametres = []): int
    {
        $requete = $this->executerRequete($sql, $parametres);
        $nb = $requete->rowCount();
        $requete->closeCursor();

        return $nb;
    }

    public function dernierId(): int
    {
        return (int) $this->pdo()->lastInsertId();
    }

    /**
     * Appelle une procédure stockée : CALL nom(entrées…, @s1, @s2…).
     *
     * @param list<mixed> $entrees
     * @return list<mixed> valeurs des paramètres OUT
     */
    public function appeler(string $procedure, array $entrees, int $nbSorties = 0): array
    {
        $sorties = $nbSorties > 0 ? array_map(static fn (int $i): string => "@_sortie{$i}", range(1, $nbSorties)) : [];
        $marqueurs = array_merge(array_fill(0, count($entrees), '?'), $sorties);
        $this->executer(sprintf('CALL %s(%s)', $procedure, implode(', ', $marqueurs)), $entrees);
        if ($nbSorties === 0) {
            return [];
        }

        return array_values($this->ligne('SELECT ' . implode(', ', $sorties)) ?? []);
    }

    /**
     * @template T
     * @param callable(): T $operation
     * @return T
     */
    public function transaction(callable $operation): mixed
    {
        $pdo = $this->pdo();
        $pdo->beginTransaction();
        try {
            $resultat = $operation();
            $pdo->commit();

            return $resultat;
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
    }

    /** Erreur de la base -> exception métier (message pour l'utilisateur) ou erreur technique. */
    public function traduire(PDOException $e): Throwable
    {
        $etat = (string) ($e->errorInfo[0] ?? $e->getCode());
        $code = (int) ($e->errorInfo[1] ?? 0);
        $message = (string) ($e->errorInfo[2] ?? $e->getMessage());
        if ($etat === '45000') {
            return new RegleMetierException($message, 0, $e);
        }

        return match ($code) {
            1062, 3819 => new RegleMetierException($this->messageContrainte($message, $code), 0, $e),
            1451 => new RegleMetierException(
                'Cet élément a un historique (trajets, mouvements, factures…) : il ne peut pas être supprimé.', 0, $e),
            1452 => new RegleMetierException('Élément introuvable : vérifiez le numéro saisi.', 0, $e),
            3024, 1969 => new RegleMetierException('Requête interrompue : durée maximale dépassée.', 0, $e),
            default => $e,
        };
    }

    /** @param array<int|string, mixed> $parametres */
    private function executerRequete(string $sql, array $parametres): PDOStatement
    {
        try {
            $requete = $this->pdo()->prepare($sql);
            foreach ($parametres as $cle => $valeur) {
                $requete->bindValue(is_int($cle) ? $cle + 1 : ':' . $cle, ...$this->typer($valeur));
            }
            $requete->execute();

            return $requete;
        } catch (PDOException $e) {
            throw $this->traduire($e);
        }
    }

    /** @return array{0: mixed, 1: int} */
    private function typer(mixed $valeur): array
    {
        return match (true) {
            $valeur === null => [null, PDO::PARAM_NULL],
            is_bool($valeur) => [(int) $valeur, PDO::PARAM_INT],
            is_int($valeur) => [$valeur, PDO::PARAM_INT],
            default => [(string) $valeur, PDO::PARAM_STR],
        };
    }

    private function messageContrainte(string $message, int $code): string
    {
        foreach (self::CONTRAINTES as $nom => $texte) {
            if (str_contains($message, $nom)) {
                return $texte;
            }
        }

        return $code === 1062 ? 'Cette valeur existe déjà.' : 'Valeur refusée par une contrainte de la base.';
    }
}
