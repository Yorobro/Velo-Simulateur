<?php

declare(strict_types=1);

namespace App\Presentation\Http;

use App\Domain\Exception\AccesRefuseException;
use App\Domain\Role;
use App\Domain\Utilisateur;

/** Utilisateur connecté, conservé dans la session (sans son mot de passe). */
final class Authentification
{
    private ?Utilisateur $utilisateur = null;

    public function __construct(private readonly Session $session)
    {
    }

    public function connecter(Utilisateur $utilisateur): void
    {
        $this->session->regenerer();
        $this->session->set('utilisateur', [
            'id' => $utilisateur->id,
            'nom' => $utilisateur->nom,
            'prenom' => $utilisateur->prenom,
            'email' => $utilisateur->email,
            'role' => $utilisateur->role->value,
        ]);
        $this->utilisateur = null;
    }

    public function deconnecter(): void
    {
        $this->session->detruire();
        $this->utilisateur = null;
    }

    public function utilisateur(): ?Utilisateur
    {
        if ($this->utilisateur === null) {
            $donnees = $this->session->get('utilisateur');
            if (!is_array($donnees) || Role::tryFrom((string) $donnees['role']) === null) {
                return null;
            }
            $this->utilisateur = new Utilisateur(
                (int) $donnees['id'],
                (string) $donnees['nom'],
                (string) $donnees['prenom'],
                (string) $donnees['email'],
                Role::from((string) $donnees['role']),
            );
        }

        return $this->utilisateur;
    }

    /** Utilisateur connecté, ou refus (les routes protégées garantissent déjà la connexion). */
    public function exiger(): Utilisateur
    {
        return $this->utilisateur() ?? throw new AccesRefuseException();
    }
}
