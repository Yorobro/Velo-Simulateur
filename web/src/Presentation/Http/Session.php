<?php

declare(strict_types=1);

namespace App\Presentation\Http;

/** Session PHP : messages flash, jeton CSRF, saisie à réafficher après une erreur. */
final class Session
{
    private ?array $saisie = null;

    public function demarrer(bool $https): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            return;
        }
        session_name('velo_session');
        session_set_cookie_params(['path' => '/', 'httponly' => true, 'samesite' => 'Lax', 'secure' => $https]);
        session_start();
    }

    public function get(string $cle, mixed $defaut = null): mixed
    {
        return $_SESSION[$cle] ?? $defaut;
    }

    public function set(string $cle, mixed $valeur): void
    {
        $_SESSION[$cle] = $valeur;
    }

    public function supprimer(string $cle): void
    {
        unset($_SESSION[$cle]);
    }

    /** Nouvel identifiant de session (à la connexion) : évite la fixation de session. */
    public function regenerer(): void
    {
        session_regenerate_id(true);
    }

    public function detruire(): void
    {
        $_SESSION = [];
        session_regenerate_id(true);
    }

    public function flash(string $type, string $message): void
    {
        $_SESSION['_flash'][] = ['type' => $type, 'message' => $message];
    }

    /** @return list<array{type: string, message: string}> */
    public function flashes(): array
    {
        $messages = $_SESSION['_flash'] ?? [];
        unset($_SESSION['_flash']);

        return $messages;
    }

    public function jetonCsrf(): string
    {
        if (!isset($_SESSION['_csrf'])) {
            $_SESSION['_csrf'] = bin2hex(random_bytes(32));
        }

        return $_SESSION['_csrf'];
    }

    public function csrfValide(string $jeton): bool
    {
        return isset($_SESSION['_csrf']) && hash_equals($_SESSION['_csrf'], $jeton);
    }

    /** @param array<string, mixed> $donnees */
    public function memoriserSaisie(array $donnees): void
    {
        unset($donnees['_csrf'], $donnees['mot_de_passe'], $donnees['confirmation']);
        $_SESSION['_saisie'] = $donnees;
    }

    /** @return array<string, mixed> */
    public function saisie(): array
    {
        if ($this->saisie === null) {
            $this->saisie = $_SESSION['_saisie'] ?? [];
            unset($_SESSION['_saisie']);
        }

        return $this->saisie;
    }
}
