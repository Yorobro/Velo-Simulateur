<?php

declare(strict_types=1);

namespace App\Application\Auth;

use App\Application\Port\HacheurMotDePasse;
use App\Application\Port\UtilisateurRepository;
use App\Application\Validateur;
use App\Domain\Exception\RegleMetierException;
use App\Domain\Utilisateur;

/** Connexion et inscription. */
final class AuthService
{
    public function __construct(
        private readonly UtilisateurRepository $utilisateurs,
        private readonly HacheurMotDePasse $hacheur,
    ) {
    }

    public function connecter(string $email, string $motDePasse): Utilisateur
    {
        (new Validateur())
            ->requis('email', $email, 'L\'adresse e-mail')
            ->requis('mot_de_passe', $motDePasse, 'Le mot de passe')
            ->verifier();
        $utilisateur = $this->utilisateurs->parEmail(mb_strtolower($email));
        if ($utilisateur === null || !$this->hacheur->verifier($motDePasse, $utilisateur->motDePasseHash)) {
            throw new RegleMetierException('Adresse e-mail ou mot de passe incorrect.');
        }

        return $utilisateur;
    }

    /** @param array<string, string> $saisie */
    public function inscrire(array $saisie): Utilisateur
    {
        $telephone = preg_replace('/[\s.\-]/', '', $saisie['telephone'] ?? '') ?? '';
        (new Validateur())
            ->requis('prenom', $saisie['prenom'] ?? '', 'Le prénom')
            ->requis('nom', $saisie['nom'] ?? '', 'Le nom')
            ->requis('email', $saisie['email'] ?? '', 'L\'adresse e-mail')
            ->requis('telephone', $telephone, 'Le téléphone')
            ->requis('mot_de_passe', $saisie['mot_de_passe'] ?? '', 'Le mot de passe')
            ->longueur('prenom', $saisie['prenom'] ?? '', 1, 50, 'Le prénom')
            ->longueur('nom', $saisie['nom'] ?? '', 1, 50, 'Le nom')
            ->email('email', $saisie['email'] ?? '')
            ->motif('telephone', $telephone, '/^\+?\d{10,15}$/', 'Le téléphone doit contenir 10 à 15 chiffres.')
            ->longueur('mot_de_passe', $saisie['mot_de_passe'] ?? '', 8, 72, 'Le mot de passe')
            ->si(($saisie['mot_de_passe'] ?? '') !== ($saisie['confirmation'] ?? ''), 'confirmation',
                'Les deux mots de passe ne correspondent pas.')
            ->verifier();

        $id = $this->utilisateurs->inscrire([
            'nom' => $saisie['nom'],
            'prenom' => $saisie['prenom'],
            'email' => mb_strtolower($saisie['email']),
            'telephone' => $telephone,
        ], $this->hacheur->hacher($saisie['mot_de_passe']));

        return $this->utilisateurs->parId($id) ?? throw new RegleMetierException('Inscription impossible.');
    }
}
