# MLD — Réseau de vélos en libre-service

Schéma relationnel traduit du MCD ([2_mcd_uml.svg](2_mcd_uml.svg)).

**Notation** : <u>souligné</u> = clé primaire ; `#` = clé étrangère ; `#(a, b)` = clé étrangère composée. Les attributs facultatifs (pouvant être `NULL`) sont signalés au § 2 ; tous les autres sont `NOT NULL`.

## 1. Schéma relationnel

**Utilisateurs, abonnements, facturation**

**UTILISATEUR** (<u>id_utilisateur</u>, nom, prenom, email, mot_de_passe_hash, telephone, date_inscription, role)

**FORMULE** (<u>id_formule</u>, libelle, prix, duree_validite_jours, duree_gratuite_min, duree_tranche_min, prix_tranche, supplement_electrique, supplement_casque)

**ABONNEMENT** (<u>id_abonnement</u>, date_debut, date_fin, #id_utilisateur, #id_formule, #id_abonnement_precedent)

**FACTURE** (<u>id_facture</u>, date_emission, montant, date_reglement, #id_abonnement, #id_location)

**Réseau et flotte**

**STATION** (<u>id_station</u>, nom, adresse, code_postal, latitude, longitude, etat)

**BORNE** (<u>#id_station, numero</u>, etat)

**VELO** (<u>id_velo</u>, date_mise_service, #(id_station, numero_borne))

**VELO_ELECTRIQUE** (<u>#id_velo</u>, niveau_batterie)

**CHANGEMENT_ETAT** (<u>id_changement</u>, date_heure_changement, etat, #id_velo)

**Mouvements**

**MOUVEMENT** (<u>id_mouvement</u>, date_heure_depart, date_heure_arrivee, #id_velo, #(id_station_depart, numero_borne_depart), #(id_station_arrivee, numero_borne_arrivee))

**LOCATION** (<u>#id_mouvement</u>, avec_casque, #id_abonnement)

**TRANSFERT** (<u>#id_mouvement</u>, #id_tournee)

**Régulation**

**VEHICULE** (<u>id_vehicule</u>, immatriculation, capacite)

**TOURNEE** (<u>id_tournee</u>, date_heure_debut, date_heure_fin, #id_utilisateur, #id_vehicule)

**Signalements**

**SIGNALEMENT** (<u>id_signalement</u>, date_heure_signalement, description, date_heure_cloture, #id_utilisateur)

**SIGNALEMENT_VELO** (<u>#id_signalement</u>, #id_velo, #id_intervention_velo)

**SIGNALEMENT_STATION** (<u>#id_signalement</u>, #id_station)

**Interventions de maintenance**

**INTERVENTION** (<u>id_intervention</u>, description, #id_utilisateur)

**INTERVENTION_VELO** (<u>#id_intervention</u>, #id_mouvement)

**INTERVENTION_STATION** (<u>#id_intervention</u>, date_heure_debut, date_heure_fin, #id_signalement_station)

20 relations, une par classe du MCD. Les 4 énumérations deviennent des domaines d'attributs (§ 3).

## 2. Clés étrangères et attributs facultatifs

| Relation | Clé étrangère | Référence | NULL ? | Vient de l'association |
|---|---|---|---|---|
| ABONNEMENT | id_utilisateur | UTILISATEUR(id_utilisateur) | non | souscrit |
| ABONNEMENT | id_formule | FORMULE(id_formule) | non | relève de |
| ABONNEMENT | id_abonnement_precedent | ABONNEMENT(id_abonnement) | oui, UNIQUE | renouvelle (réflexive) |
| FACTURE | id_abonnement | ABONNEMENT(id_abonnement) | oui, UNIQUE | facturer abonnement |
| FACTURE | id_location | LOCATION(id_mouvement) | oui, UNIQUE | facturer location |
| BORNE | id_station | STATION(id_station) | non | compose |
| VELO | (id_station, numero_borne) | BORNE(id_station, numero) | oui, UNIQUE | stationne |
| VELO_ELECTRIQUE | id_velo | VELO(id_velo) | non | généralisation |
| CHANGEMENT_ETAT | id_velo | VELO(id_velo) | non | subit |
| MOUVEMENT | id_velo | VELO(id_velo) | non | concerne |
| MOUVEMENT | (id_station_depart, numero_borne_depart) | BORNE(id_station, numero) | non | part de |
| MOUVEMENT | (id_station_arrivee, numero_borne_arrivee) | BORNE(id_station, numero) | oui | arrive à |
| LOCATION | id_mouvement | MOUVEMENT(id_mouvement) | non | généralisation |
| LOCATION | id_abonnement | ABONNEMENT(id_abonnement) | non | utilise |
| TRANSFERT | id_mouvement | MOUVEMENT(id_mouvement) | non | généralisation |
| TRANSFERT | id_tournee | TOURNEE(id_tournee) | non | fait partie |
| TOURNEE | id_utilisateur | UTILISATEUR(id_utilisateur) | non | effectuée par |
| TOURNEE | id_vehicule | VEHICULE(id_vehicule) | non | réalisée avec |
| SIGNALEMENT | id_utilisateur | UTILISATEUR(id_utilisateur) | non | émis par |
| SIGNALEMENT_VELO | id_signalement | SIGNALEMENT(id_signalement) | non | généralisation |
| SIGNALEMENT_VELO | id_velo | VELO(id_velo) | non | porte sur |
| SIGNALEMENT_VELO | id_intervention_velo | INTERVENTION_VELO(id_intervention) | oui | traité par |
| SIGNALEMENT_STATION | id_signalement | SIGNALEMENT(id_signalement) | non | généralisation |
| SIGNALEMENT_STATION | id_station | STATION(id_station) | non | porte sur |
| INTERVENTION | id_utilisateur | UTILISATEUR(id_utilisateur) | non | réalisée par |
| INTERVENTION_VELO | id_intervention | INTERVENTION(id_intervention) | non | généralisation |
| INTERVENTION_VELO | id_mouvement | MOUVEMENT(id_mouvement) | non, UNIQUE | donne lieu à |
| INTERVENTION_STATION | id_intervention | INTERVENTION(id_intervention) | non | généralisation |
| INTERVENTION_STATION | id_signalement_station | SIGNALEMENT_STATION(id_signalement) | non | traite |

**Suppression** : une ligne encore référencée ne peut pas être supprimée, ce qui protège l'historique. Seules les sous-classes (VELO_ELECTRIQUE, LOCATION, TRANSFERT, SIGNALEMENT_VELO, SIGNALEMENT_STATION, INTERVENTION_VELO, INTERVENTION_STATION) et les bornes d'une station sont supprimées en cascade avec leur ligne mère.

**Attributs facultatifs** (`[0..1]` dans le MCD : événements pas encore survenus) :
- `FACTURE.date_reglement` : facture non réglée, ou à 0 € ;
- `MOUVEMENT.date_heure_arrivee` : mouvement en cours ;
- `TOURNEE.date_heure_fin` : tournée en cours ;
- `SIGNALEMENT.date_heure_cloture` : signalement ouvert ;
- `INTERVENTION_STATION.date_heure_fin` : intervention en cours.

**Valeurs par défaut** : `UTILISATEUR.role` = `USAGER` ; `UTILISATEUR.date_inscription` et `SIGNALEMENT.date_heure_signalement` = date et heure courantes ; `STATION.etat` et `BORNE.etat` = `EN_SERVICE` ; `FORMULE.supplement_electrique` et `supplement_casque` = 0 ; `LOCATION.avec_casque` = faux.

## 3. Contraintes de domaine et d'intégrité

| Relation | Contrainte | Type SQL prévu |
|---|---|---|
| UTILISATEUR | `email` unique, au format `texte@texte.texte` | UNIQUE, CHECK |
| UTILISATEUR | `nom` et `prenom` non vides | CHECK |
| UTILISATEUR | `mot_de_passe_hash` : empreinte bcrypt (au moins 60 caractères), jamais le mot de passe en clair | CHECK |
| UTILISATEUR | `telephone` : 10 à 15 chiffres, `+` initial facultatif | CHECK |
| UTILISATEUR | `role` ∈ {USAGER, OPERATEUR_REGULATION, OPERATEUR_MAINTENANCE, ADMINISTRATEUR} | ENUM |
| FORMULE | `libelle` unique et non vide | UNIQUE, CHECK |
| FORMULE | `prix`, `prix_tranche`, `supplement_electrique`, `supplement_casque` ≥ 0 | CHECK |
| FORMULE | `duree_validite_jours` > 0 ; `duree_tranche_min` > 0 (pas de division par zéro dans R4) ; `duree_gratuite_min` ≥ 0 | CHECK |
| ABONNEMENT | `date_fin ≥ date_debut` | CHECK |
| ABONNEMENT | un abonnement est renouvelé une fois au plus ; il ne se renouvelle pas lui-même (`id_abonnement_precedent ≠ id_abonnement`) | UNIQUE ; trigger (MySQL refuse un CHECK sur une colonne AUTO_INCREMENT) |
| FACTURE | **exactement une** cible : `(id_abonnement IS NOT NULL) <> (id_location IS NOT NULL)` | CHECK |
| FACTURE | `montant ≥ 0` | CHECK |
| FACTURE | `date_reglement` NULL ou ≥ `date_emission` | CHECK |
| FACTURE | une facture à 0 € n'est pas à payer (le paiement n'a lieu que si le montant est > 0) : `date_reglement IS NULL OR montant > 0` | CHECK |
| STATION | `nom` non vide ; `code_postal` de 5 chiffres ; latitude ∈ [-90, 90], longitude ∈ [-180, 180] | CHECK |
| STATION | (`adresse`, `code_postal`) unique ; (`latitude`, `longitude`) unique | UNIQUE |
| STATION | `etat` ∈ {EN_SERVICE, HORS_SERVICE, EN_TRAVAUX} | ENUM |
| BORNE | `numero` > 0 et unique dans sa station | CHECK, clé primaire (id_station, numero) |
| BORNE | `etat` ∈ {EN_SERVICE, HORS_SERVICE} | ENUM |
| VELO | une borne accueille au plus un vélo | UNIQUE (id_station, numero_borne) |
| VELO | `id_station` et `numero_borne` tous deux renseignés ou tous deux NULL | CHECK |
| VELO_ELECTRIQUE | `niveau_batterie` entre 0 et 100 | CHECK |
| CHANGEMENT_ETAT | `etat` ∈ {EN_SERVICE, DEFECTUEUX, REFORME} | ENUM |
| CHANGEMENT_ETAT | pas deux changements au même instant pour un vélo | UNIQUE (id_velo, date_heure_changement) |
| MOUVEMENT | `date_heure_arrivee` NULL ou > `date_heure_depart` | CHECK |
| MOUVEMENT | station et numéro de la borne d'arrivée renseignés ensemble ou NULL ensemble | CHECK |
| MOUVEMENT | pas de borne d'arrivée sans date d'arrivée. L'inverse n'est permis que pour un vélo réformé (R19). | CHECK + trigger |
| LOCATION | `avec_casque` booléen | BOOLEAN NOT NULL |
| VEHICULE | `immatriculation` unique et non vide | UNIQUE, CHECK |
| VEHICULE | `capacite` > 0 | CHECK |
| TOURNEE | `date_heure_fin` NULL ou > `date_heure_debut` | CHECK |
| SIGNALEMENT | `description` non vide ; `date_heure_cloture` NULL ou ≥ `date_heure_signalement` | CHECK |
| INTERVENTION | `description` non vide | CHECK |
| INTERVENTION_VELO | un mouvement donne lieu à une intervention au plus | UNIQUE (id_mouvement) |
| INTERVENTION_STATION | `date_heure_fin` NULL ou > `date_heure_debut` | CHECK |

## 4. Règles métier sur plusieurs tables

Ces règles ne s'écrivent pas en contrainte déclarative. Elles sont garanties par des triggers, ou par les procédures qui réalisent les cas d'utilisation (une procédure par cas, dans une transaction).

| N° | Règle | Origine | Garantie par |
|---|---|---|---|
| R1 | Un usager n'a qu'une location en cours à la fois (location dont le mouvement n'a pas de `date_heure_arrivee`). | Sujet | trigger avant insertion dans LOCATION |
| R2 | Il faut un abonnement valide de l'usager le jour de l'emprunt : `date_debut ≤ jour ≤ date_fin`. | Sujet | trigger avant insertion dans LOCATION |
| R3 | Un vélo dont l'état actuel (dernier CHANGEMENT_ETAT) est `DEFECTUEUX` ou `REFORME` ne peut pas être emprunté. Avec R20, cela couvre le vélo « signalé défectueux ». | Sujet | trigger avant insertion dans LOCATION |
| R4 | À la restitution, la durée et le coût sont calculés. `coût = ⌈max(0, durée_min − duree_gratuite_min) / duree_tranche_min⌉ × prix_tranche + supplement_electrique` (si le vélo est dans VELO_ELECTRIQUE) `+ supplement_casque` (si `avec_casque`). Les tarifs sont ceux de la formule de l'abonnement utilisé. La facture du trajet reçoit ce montant. | Sujet | trigger après mise à jour de MOUVEMENT |
| R5 | Un vélo n'est qu'à un seul endroit. Sa position (`VELO.id_station`, `numero_borne`) passe à NULL au départ d'un mouvement, puis prend la borne d'arrivée. Elle n'est jamais modifiée directement. | Sujet (remarque générale) | triggers sur MOUVEMENT et VELO |
| R6 | Un mouvement part de la borne où se trouve le vélo. Il arrive sur une borne libre et `EN_SERVICE` d'une station `EN_SERVICE`. Pour une **location**, la borne et la station de départ doivent aussi être en service. Un transfert ou un retrait de maintenance peut partir d'une station hors service ou en travaux, justement pour la vider. | Sujet | triggers sur MOUVEMENT |
| R7 | Un vélo n'a qu'un mouvement en cours. Cela découle de R5 et R6 : pendant un mouvement, la position du vélo est NULL, donc aucun autre mouvement ne peut partir. | Sujet (remarque générale) | trigger avant insertion dans MOUVEMENT |
| R8 | Un mouvement est **soit** une location, **soit** un transfert, **soit** le mouvement d'une intervention sur vélo, jamais deux à la fois (`{incomplete, disjoint}` + « donne lieu à »). Il est toujours créé avec son type. | MCD | triggers sur LOCATION, TRANSFERT, INTERVENTION_VELO (exclusion) ; procédures (existence) |
| R9 | Un signalement porte sur un vélo **ou** sur une station : une ligne dans une seule des deux sous-tables, et forcément dans l'une d'elles. | MCD (`{complete, disjoint}`) | triggers (exclusion) ; procédures de signalement (existence) |
| R10 | Une intervention porte sur un vélo **ou** sur une station, de la même façon. | MCD (`{complete, disjoint}`) | triggers (exclusion) ; procédures d'intervention (existence) |
| R11 | `date_fin = date_debut + duree_validite_jours − 1`. Un renouvellement appartient au même usager que l'abonnement précédent et commence après sa fin. | Sujet | triggers sur ABONNEMENT |
| R12 | Rôles, d'après les acteurs du diagramme de cas : une tournée est faite par un `OPERATEUR_REGULATION` ou un `ADMINISTRATEUR`. Une intervention est réalisée par un `OPERATEUR_MAINTENANCE` ou un `ADMINISTRATEUR`. Seul un `USAGER` souscrit un abonnement, et donc loue un vélo. Seul un `USAGER` émet un signalement. Le rôle est vérifié à la création. | Diagramme de cas (acteurs, héritage de l'administrateur) | triggers sur TOURNEE, INTERVENTION, ABONNEMENT, SIGNALEMENT |
| R13 | Un signalement de vélo et l'intervention qui le traite concernent le même vélo : `SIGNALEMENT_VELO.id_velo` = `id_velo` du MOUVEMENT de l'INTERVENTION_VELO. | MCD | trigger sur SIGNALEMENT_VELO |
| R14 | Une intervention commence après le signalement qu'elle traite. Les transferts d'une tournée ont lieu entre son début et sa fin. | MCD | triggers sur INTERVENTION_STATION, TRANSFERT, TOURNEE |
| R15 | Le nombre de vélos dans le véhicule ne dépasse pas sa capacité : transferts en cours de la tournée ≤ `VEHICULE.capacite`. | Sujet (véhicule) | trigger avant insertion dans TRANSFERT |
| R16 | Un véhicule n'est engagé que dans une tournée en cours à la fois. Un opérateur n'a qu'une tournée en cours à la fois. | Diagramme de cas | trigger avant insertion dans TOURNEE |
| R17 | Une tournée n'est clôturée que lorsque tous ses vélos ont été déposés (aucun transfert en cours). | Diagramme de cas ; « un vélo à un seul endroit » | trigger avant mise à jour de TOURNEE |
| R18 | **Facturation obligatoire.** Tout abonnement a exactement une facture : la procédure de souscription ou de renouvellement crée l'abonnement et sa facture dans la même transaction, avec `montant = FORMULE.prix`. Toute location terminée a exactement une facture, créée à la restitution, même à 0 €. Une location en cours n'en a pas. | MCD (multiplicité « 1 ») ; souscrire, renouveler et restituer incluent « Générer la facture » | procédures de souscription et de renouvellement ; trigger de restitution (R4) |
| R19 | **Cycle de maintenance.** Retirer le vélo crée un MOUVEMENT depuis sa borne et l'INTERVENTION_VELO qui y renvoie ; les signalements ouverts du vélo y sont rattachés. La fin de l'intervention conclut la réparation. Si le mouvement arrive sur une borne (remise en circulation), un CHANGEMENT_ETAT `EN_SERVICE` est ajouté. S'il se termine sans borne (réforme), c'est un CHANGEMENT_ETAT `REFORME`, et le vélo ne bouge plus. Dans les deux cas, les signalements traités sont clôturés. | Sujet | procédures de retrait et de remise en circulation ; triggers sur INTERVENTION_VELO et MOUVEMENT |
| R20 | **Historisation automatique de l'état.** La mise en service d'un vélo crée son premier CHANGEMENT_ETAT `EN_SERVICE`. Un signalement sur un vélo ajoute un CHANGEMENT_ETAT `DEFECTUEUX`, s'il ne l'est pas déjà. Un signalement clos sans intervention (fausse alerte) remet le vélo `EN_SERVICE`, s'il n'est pas en atelier et qu'aucun autre signalement ne reste ouvert. L'état n'est jamais stocké dans VELO. | Sujet (historisation, « vélo signalé défectueux ») | triggers sur VELO et SIGNALEMENT_VELO ; procédure de clôture d'un signalement |
| R21 | Une station a au moins une borne (multiplicité `1..*` de « compose »). | MCD | procédure de création de station |
| R22 | **Un abonnement à la fois.** Les périodes `[date_debut, date_fin]` des abonnements d'un même usager ne se chevauchent pas. Renouveler reste possible : le renouvellement commence après la fin du précédent (R11). Changer de formule programme le nouvel abonnement au lendemain de la fin du dernier abonnement en cours ou à venir, sans écourter l'actuel. | Choix de conception | triggers sur ABONNEMENT ; procédure de souscription (date de début) |

> **Exclusion et existence.** Un trigger peut interdire qu'une ligne appartienne à deux sous-classes à la fois. Il ne peut pas exiger qu'une sous-classe existe, car la ligne mère est insérée avant la ligne fille. L'existence (R8, R9, R10, R18, R21) est donc garantie par les procédures, qui créent les deux lignes dans la même transaction.