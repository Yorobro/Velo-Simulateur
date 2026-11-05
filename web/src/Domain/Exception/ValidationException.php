<?php

declare(strict_types=1);

namespace App\Domain\Exception;

/** Saisie invalide : un message par champ en erreur. */
final class ValidationException extends RegleMetierException
{
    /** @param array<string, string> $erreurs */
    public function __construct(public readonly array $erreurs)
    {
        parent::__construct(implode(' ', $erreurs));
    }
}
