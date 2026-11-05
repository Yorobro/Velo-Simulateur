<?php

declare(strict_types=1);

namespace App\Presentation\Http;

/** Requête HTTP en lecture seule. */
final class Request
{
    /**
     * @param array<string, mixed> $query
     * @param array<string, mixed> $post
     * @param array<string, mixed> $server
     * @param array<string, string> $attributs paramètres de la route
     */
    public function __construct(
        public readonly string $methode,
        public readonly string $chemin,
        private readonly array $query = [],
        private readonly array $post = [],
        private readonly array $server = [],
        private readonly array $attributs = [],
    ) {
    }

    public static function depuisGlobales(): self
    {
        $chemin = (string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
        $chemin = $chemin === '' || $chemin === '/' ? '/' : rtrim(rawurldecode($chemin), '/');

        return new self(strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET'), $chemin, $_GET, $_POST, $_SERVER);
    }

    /** @param array<string, string> $attributs */
    public function avecAttributs(array $attributs): self
    {
        return new self($this->methode, $this->chemin, $this->query, $this->post, $this->server, $attributs);
    }

    public function estPost(): bool
    {
        return $this->methode === 'POST';
    }

    public function attribut(string $cle): string
    {
        return $this->attributs[$cle] ?? '';
    }

    public function id(string $cle = 'id'): int
    {
        return (int) $this->attribut($cle);
    }

    public function query(string $cle, string $defaut = ''): string
    {
        $valeur = $this->query[$cle] ?? $defaut;

        return is_string($valeur) ? trim($valeur) : $defaut;
    }

    public function queryEntier(string $cle): ?int
    {
        $valeur = $this->query($cle);

        return ctype_digit($valeur) ? (int) $valeur : null;
    }

    /** @return array<string, mixed> */
    public function toutesLesQuery(): array
    {
        return $this->query;
    }

    public function texte(string $cle): string
    {
        $valeur = $this->post[$cle] ?? '';

        return is_string($valeur) ? trim($valeur) : '';
    }

    public function entier(string $cle): ?int
    {
        $valeur = $this->texte($cle);

        return preg_match('/^-?\d+$/', $valeur) ? (int) $valeur : null;
    }

    public function coche(string $cle): bool
    {
        return isset($this->post[$cle]) && $this->post[$cle] !== '0';
    }

    /** @return array<string, mixed> */
    public function toutLePost(): array
    {
        return $this->post;
    }

    /** Page d'origine (même site) pour revenir après une action, sinon $defaut. */
    public function pagePrecedente(string $defaut = '/'): string
    {
        $referent = (string) ($this->server['HTTP_REFERER'] ?? '');
        $hote = (string) ($this->server['HTTP_HOST'] ?? '');
        $infos = parse_url($referent);
        if ($referent === '' || ($infos['host'] ?? '') . (isset($infos['port']) ? ':' . $infos['port'] : '') !== $hote) {
            return $defaut;
        }

        return ($infos['path'] ?? '/') . (isset($infos['query']) ? '?' . $infos['query'] : '');
    }

    public function estHttps(): bool
    {
        return ($this->server['HTTPS'] ?? '') !== '' && $this->server['HTTPS'] !== 'off';
    }
}
