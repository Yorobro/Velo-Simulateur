<?php

declare(strict_types=1);

namespace App\Presentation\Http;

final class Response
{
    /** @param array<string, string> $entetes */
    public function __construct(
        private readonly string $corps = '',
        private readonly int $statut = 200,
        private array $entetes = [],
    ) {
    }

    public static function html(string $corps, int $statut = 200): self
    {
        return new self($corps, $statut, ['Content-Type' => 'text/html; charset=utf-8']);
    }

    public static function redirection(string $url): self
    {
        return new self('', 303, ['Location' => $url]);
    }

    public function statut(): int
    {
        return $this->statut;
    }

    public function avecEntete(string $nom, string $valeur): self
    {
        $copie = clone $this;
        $copie->entetes[$nom] = $valeur;

        return $copie;
    }

    public function envoyer(): void
    {
        http_response_code($this->statut);
        foreach ($this->entetes as $nom => $valeur) {
            header("{$nom}: {$valeur}");
        }
        echo $this->corps;
    }
}
