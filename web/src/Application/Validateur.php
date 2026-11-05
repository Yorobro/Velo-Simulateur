<?php

declare(strict_types=1);

namespace App\Application;

use App\Domain\Exception\ValidationException;

/** Contrôles de saisie avant l'appel à la base (les règles métier restent en base). */
final class Validateur
{
    /** @var array<string, string> */
    private array $erreurs = [];

    public function requis(string $champ, mixed $valeur, string $libelle): self
    {
        if ($valeur === null || $valeur === '') {
            $this->erreurs[$champ] ??= "{$libelle} est obligatoire.";
        }

        return $this;
    }

    public function longueur(string $champ, string $valeur, int $min, int $max, string $libelle): self
    {
        $n = mb_strlen($valeur);
        if ($valeur !== '' && ($n < $min || $n > $max)) {
            $this->erreurs[$champ] ??= "{$libelle} doit contenir entre {$min} et {$max} caractères.";
        }

        return $this;
    }

    public function email(string $champ, string $valeur): self
    {
        if ($valeur !== '' && filter_var($valeur, FILTER_VALIDATE_EMAIL) === false) {
            $this->erreurs[$champ] ??= 'L\'adresse e-mail n\'est pas valide.';
        }

        return $this;
    }

    public function motif(string $champ, string $valeur, string $regex, string $message): self
    {
        if ($valeur !== '' && !preg_match($regex, $valeur)) {
            $this->erreurs[$champ] ??= $message;
        }

        return $this;
    }

    public function intervalle(string $champ, ?float $valeur, float $min, float $max, string $libelle): self
    {
        if ($valeur !== null && ($valeur < $min || $valeur > $max)) {
            $this->erreurs[$champ] ??= "{$libelle} doit être compris entre {$min} et {$max}.";
        }

        return $this;
    }

    public function si(bool $condition, string $champ, string $message): self
    {
        if ($condition) {
            $this->erreurs[$champ] ??= $message;
        }

        return $this;
    }

    /** @throws ValidationException */
    public function verifier(): void
    {
        if ($this->erreurs !== []) {
            throw new ValidationException($this->erreurs);
        }
    }
}
