# MLD — Réseau de vélos en libre-service (V2)

Modèle logique (schéma relationnel), traduit depuis le MCD [mcd.mmd](mcd.mmd). Il est vérifié contre le diagramme de cas d'utilisation [cas_utilisation_complet.mmd](cas_utilisation_complet.mmd) et contre le sujet [A26_Velo_Libre_Service.pdf](../A26_Velo_Libre_Service.pdf) (§ 7).

**Notation** : <u>souligné</u> = clé primaire ; `#` = clé étrangère ; `#(a, b)` = clé étrangère composée. Les attributs facultatifs (pouvant être `NULL`) sont signalés au § 2 ; tous les autres sont `NOT NULL`.

## 0. Changements par rapport au MLD V1

| Changement dans le MCD ou le diagramme de cas | Effet sur le MLD |
|---|---|
| `FORMULE.type` (énumération `TypeFormule`) remplacé par `libelle` | `libelle` est une clé candidate (`UNIQUE`). L'énumération disparaît : les formules du sujet (ticket journée, mensuel, annuel, tarif réduit) deviennent des lignes de FORMULE. |
| Nouvel attribut `LOCATION.avec_casque` | Colonne booléenne, faux par défaut. Elle entre dans le calcul du coût (R4). |
| Nouvelle classe `VEHICULE` | Nouvelle relation VEHICULE ; `immatriculation` unique, `capacite` > 0 |
| Nouvelle association `TOURNEE` « réalisée avec » `VEHICULE` (1 — 0..*) | `#id_vehicule` NOT NULL dans TOURNEE ; nouvelles règles R15 (capacité) et R16 (un véhicule par tournée en cours) |
| `TRANSFERT` « fait partie » `TOURNEE` passe de `1..*` à `0..*` | Plus besoin de contrôler qu'une tournée a au moins un transfert : elle démarre vide (UC31), puis on charge les vélos (UC32) |
| L'administrateur hérite des deux opérateurs (diagramme de cas) | R12 : un administrateur peut faire une tournée comme une intervention (le MLD V1 ne le disait que pour les interventions) |
| UC10 et UC11 : seul l'usager signale un problème | R12 : l'auteur d'un signalement est un usager |
| UC13 : « vélo non signalé défectueux » | R20 : un signalement de vélo fait passer le vélo à l'état `DEFECTUEUX`, ce qui le rend non empruntable (R3) |
| UC34 : clôturer la tournée | R17 : on ne clôture pas une tournée tant qu'un vélo est encore dans le véhicule |

On passe de 19 à **20 relations**.

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

Les 22 associations du MCD donnent 22 clés étrangères, et les 7 sous-classes des 4 généralisations en donnent 7 : 29 au total.

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
| ABONNEMENT | un abonnement est renouvelé une fois au plus ; il ne se renouvelle pas lui-même (`id_abonnement_precedent ≠ id_abonnement`) | UNIQUE, CHECK |
| FACTURE | **exactement une** cible : `(id_abonnement IS NOT NULL) <> (id_location IS NOT NULL)` | CHECK |
| FACTURE | `montant ≥ 0` | CHECK |
| FACTURE | `date_reglement` NULL ou ≥ `date_emission` | CHECK |
| FACTURE | une facture à 0 € n'est pas à payer (UC16 : Payer seulement si montant > 0) : `date_reglement IS NULL OR montant > 0` | CHECK |
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

Ces règles ne s'écrivent pas en contrainte déclarative. Elles sont garanties par des triggers, ou par les procédures qui réalisent les cas d'utilisation (une procédure par cas, dans une transaction). R1 à R14 reprennent la numérotation de la V1, mise à jour ; R15 à R21 sont nouvelles.

| N° | Règle | Origine | Garantie par |
|---|---|---|---|
| R1 | Un usager n'a qu'une location en cours à la fois (location dont le mouvement n'a pas de `date_heure_arrivee`). | Sujet ; UC13 | trigger avant insertion dans LOCATION |
| R2 | Il faut un abonnement valide de l'usager le jour de l'emprunt : `date_debut ≤ jour ≤ date_fin`. | Sujet ; UC13 | trigger avant insertion dans LOCATION |
| R3 | Un vélo dont l'état actuel (dernier CHANGEMENT_ETAT) est `DEFECTUEUX` ou `REFORME` ne peut pas être emprunté. Avec R20, cela couvre le vélo « signalé défectueux ». | Sujet ; UC13 | trigger avant insertion dans LOCATION |
| R4 | À la restitution, la durée et le coût sont calculés. `coût = ⌈max(0, durée_min − duree_gratuite_min) / duree_tranche_min⌉ × prix_tranche + supplement_electrique` (si le vélo est dans VELO_ELECTRIQUE) `+ supplement_casque` (si `avec_casque`). Les tarifs sont ceux de la formule de l'abonnement utilisé. La facture du trajet reçoit ce montant. | Sujet ; UC8, UC14, UC15, UC50 | trigger après mise à jour de MOUVEMENT |
| R5 | Un vélo n'est qu'à un seul endroit. Sa position (`VELO.id_station`, `numero_borne`) passe à NULL au départ d'un mouvement, puis prend la borne d'arrivée. Elle n'est jamais modifiée directement. | Sujet (remarque générale) | triggers sur MOUVEMENT et VELO |
| R6 | Un mouvement part de la borne où se trouve le vélo. Il arrive sur une borne libre et `EN_SERVICE` d'une station `EN_SERVICE`. Pour une **location**, la borne et la station de départ doivent aussi être en service. Un transfert ou un retrait de maintenance peut partir d'une station hors service ou en travaux, justement pour la vider (UC29). | Sujet ; UC7, UC8, UC29, UC33 | triggers sur MOUVEMENT |
| R7 | Un vélo n'a qu'un mouvement en cours. Cela découle de R5 et R6 : pendant un mouvement, la position du vélo est NULL, donc aucun autre mouvement ne peut partir. | Sujet (remarque générale) | trigger avant insertion dans MOUVEMENT |
| R8 | Un mouvement est **soit** une location, **soit** un transfert, **soit** le mouvement d'une intervention sur vélo, jamais deux à la fois (`{incomplete, disjoint}` + « donne lieu à »). Il est toujours créé avec son type. | MCD | triggers sur LOCATION, TRANSFERT, INTERVENTION_VELO (exclusion) ; procédures (existence) |
| R9 | Un signalement porte sur un vélo **ou** sur une station : une ligne dans une seule des deux sous-tables, et forcément dans l'une d'elles. | MCD (supposé `{complete, disjoint}`, § 8) | triggers (exclusion) ; procédures UC10 et UC11 (existence) |
| R10 | Une intervention porte sur un vélo **ou** sur une station, de la même façon. | MCD (supposé `{complete, disjoint}`, § 8) | triggers (exclusion) ; procédures UC21 (existence) |
| R11 | `date_fin = date_debut + duree_validite_jours − 1`. Un renouvellement appartient au même usager que l'abonnement précédent et commence après sa fin. | Sujet ; UC6, UC17 | triggers sur ABONNEMENT |
| R12 | Rôles, d'après les acteurs du diagramme de cas : une tournée est faite par un `OPERATEUR_REGULATION` ou un `ADMINISTRATEUR`. Une intervention est réalisée par un `OPERATEUR_MAINTENANCE` ou un `ADMINISTRATEUR`. Seul un `USAGER` souscrit un abonnement, et donc loue un vélo. Seul un `USAGER` émet un signalement. Le rôle est vérifié à la création. | Diagramme de cas (acteurs, héritage de l'administrateur) | triggers sur TOURNEE, INTERVENTION, ABONNEMENT, SIGNALEMENT |
| R13 | Un signalement de vélo et l'intervention qui le traite concernent le même vélo : `SIGNALEMENT_VELO.id_velo` = `id_velo` du MOUVEMENT de l'INTERVENTION_VELO. | MCD | trigger sur SIGNALEMENT_VELO |
| R14 | Une intervention commence après le signalement qu'elle traite. Les transferts d'une tournée ont lieu entre son début et sa fin. | MCD | triggers sur INTERVENTION_STATION, TRANSFERT, TOURNEE |
| R15 | Le nombre de vélos dans le véhicule ne dépasse pas sa capacité : transferts en cours de la tournée ≤ `VEHICULE.capacite`. | Sujet (véhicule) ; UC32 | trigger avant insertion dans TRANSFERT |
| R16 | Un véhicule n'est engagé que dans une tournée en cours à la fois. Un opérateur n'a qu'une tournée en cours à la fois. | UC31 | trigger avant insertion dans TOURNEE |
| R17 | Une tournée n'est clôturée que lorsque tous ses vélos ont été déposés (aucun transfert en cours). | UC34 ; « un vélo à un seul endroit » | trigger avant mise à jour de TOURNEE |
| R18 | **Facturation obligatoire** (option A, § 5). Tout abonnement a exactement une facture : la procédure de souscription ou de renouvellement crée l'abonnement et sa facture dans la même transaction, avec `montant = FORMULE.prix`. Toute location terminée a exactement une facture, créée à la restitution, même à 0 €. Une location en cours n'en a pas. | MCD (multiplicité « 1 ») ; UC6, UC17, UC8 incluent UC15 | procédures UC6 et UC17 ; trigger de restitution (R4) |
| R19 | **Cycle de maintenance.** Retirer le vélo (UC22) crée un MOUVEMENT depuis sa borne et l'INTERVENTION_VELO qui y renvoie ; les signalements ouverts du vélo y sont rattachés. La fin de l'intervention conclut la réparation (UC23). Si le mouvement arrive sur une borne (remise en circulation, UC24), un CHANGEMENT_ETAT `EN_SERVICE` est ajouté. S'il se termine sans borne (réforme), c'est un CHANGEMENT_ETAT `REFORME`, et le vélo ne bouge plus. Dans les deux cas, les signalements traités sont clôturés. | Sujet ; UC21 à UC24 | procédures UC22 et UC24 ; triggers sur INTERVENTION_VELO et MOUVEMENT |
| R20 | **Historisation automatique de l'état.** La mise en service d'un vélo crée son premier CHANGEMENT_ETAT `EN_SERVICE`. Un signalement sur un vélo ajoute un CHANGEMENT_ETAT `DEFECTUEUX`, s'il ne l'est pas déjà. L'état n'est jamais stocké dans VELO. | Sujet (historisation, « vélo signalé défectueux ») ; UC10, UC13, UC41 | triggers sur VELO et SIGNALEMENT_VELO |
| R21 | Une station a au moins une borne (multiplicité `1..*` de « compose »). | MCD | procédure de création de station (UC40) |

> **Exclusion et existence.** Un trigger peut interdire qu'une ligne appartienne à deux sous-classes à la fois. Il ne peut pas exiger qu'une sous-classe existe, car la ligne mère est insérée avant la ligne fille. L'existence (R8, R9, R10, R18, R21) est donc garantie par les procédures, qui créent les deux lignes dans la même transaction.

## 5. Règles de passage MCD → MLD appliquées

| Élément du MCD | Traduction |
|---|---|
| Classe avec identifiant | Une relation ; l'identifiant devient la clé primaire |
| Association 1 — 0..* (souscrit, relève de, utilise, subit, concerne, part de, fait partie, effectuée par, **réalisée avec**, émis par, porte sur ×2, réalisée par, traite) | Clé étrangère `NOT NULL` dans la relation côté « 0..* » |
| Association 1 — 1..* (compose) | Clé étrangère `NOT NULL` dans BORNE ; le minimum « 1 » côté bornes est garanti par R21 |
| Association 0..1 — 1 (donne lieu à) | Clé étrangère `NOT NULL UNIQUE` dans INTERVENTION_VELO : une intervention sur vélo a toujours un mouvement, un mouvement a au plus une intervention |
| Association 0..1 — 1 (facturer abonnement) — **option A** | Clé étrangère facultative et `UNIQUE` dans FACTURE (`id_abonnement`). Voir le choix ci-dessous. |
| Association 0..1 — 0..1 (renouvelle, facturer location, stationne) | Clé étrangère facultative et `UNIQUE`, placée du côté qui permet les contrôles : dans le nouvel abonnement (renouvelle), dans FACTURE (facturer location), dans VELO (stationne, pour garantir qu'une borne accueille au plus un vélo) |
| Association 0..* — 0..1 (arrive à, traité par) | Clé étrangère facultative côté « 0..* » |
| BORNE, sans identifiant propre (numéro unique dans sa station) | Identifiant relatif : clé primaire composée (#id_station, numero). Les relations qui pointent vers une borne ont donc une clé étrangère composée. |
| Généralisations (VELO → VELO_ELECTRIQUE ; MOUVEMENT → LOCATION / TRANSFERT ; SIGNALEMENT → SIGNALEMENT_VELO / SIGNALEMENT_STATION ; INTERVENTION → INTERVENTION_VELO / INTERVENTION_STATION) | Une table par sous-classe, dont la clé primaire est aussi la clé étrangère vers la super-classe. Chaque sous-classe porte ses propres attributs et associations (`avec_casque` dans LOCATION, `#id_tournee` dans TRANSFERT, etc.). |
| VELO → VELO_ELECTRIQUE, sans contrainte | Un vélo sans ligne dans VELO_ELECTRIQUE est mécanique : le type se déduit, il n'est pas stocké |
| `{incomplete, disjoint}` sur MOUVEMENT | Un mouvement de maintenance reste une simple ligne de MOUVEMENT, sans table fille ; il est repéré par `INTERVENTION_VELO.id_mouvement`. Le côté « disjoint » est garanti par R8. |
| `{complete, disjoint}` (supposé pour SIGNALEMENT et INTERVENTION, § 8) | Pas exprimable par une clé : garanti par R9 et R10 |
| Énumération | Attribut au domaine contrôlé (`ENUM` ou `CHECK ... IN (...)`) |
| Attribut `[0..1]` | Colonne qui accepte `NULL` |

**Choix retenu pour la facturation (option A).** Le MCD dit qu'une facture concerne 0..1 abonnement et 0..1 location, qu'un abonnement a exactement 1 facture et qu'une location en a 0..1. FACTURE porte les deux clés `id_abonnement` et `id_location`, chacune facultative et `UNIQUE`, avec un CHECK « exactement une des deux ».
- **Ce que le schéma garantit** : une facture a une seule cible, et une cible a au plus une facture. Une facture ne peut donc pas être comptée deux fois dans les recettes par formule (UC52).
- **Ce qui reste à garantir** : le « 1 » côté FACTURE, c'est-à-dire que tout abonnement a sa facture. R18 s'en charge : UC6 et UC17 incluent UC15, donc la facture est toujours créée avec l'abonnement.
- **Option écartée** : avec `ABONNEMENT.id_facture NOT NULL UNIQUE`, le « 1 » serait déclaratif. Mais il faudrait alors un trigger pour empêcher qu'une facture soit à la fois celle d'un abonnement et celle d'une location. On a préféré une contrainte déclarative pour la règle dont la violation fausserait les recettes.

## 6. Vérification de la 3NF

- **1NF** : tous les attributs sont atomiques et monovalués. Les adresses sont découpées (`adresse`, `code_postal`) et les coordonnées séparées (`latitude`, `longitude`).
- **2NF** : seule BORNE a une clé composée, et son seul attribut non clé (`etat`) dépend de la borne entière, pas de la station seule. Toutes les autres relations ont une clé à un seul attribut.
- **3NF** : aucun attribut non clé ne dépend d'un autre attribut non clé. Les autres dépendances partent de clés candidates déclarées `UNIQUE` :
  - `UTILISATEUR.email` ;
  - `FORMULE.libelle` ;
  - `VEHICULE.immatriculation` ;
  - les deux couples de STATION ;
  - la borne de VELO ;
  - les deux clés de facturation ;
  - `INTERVENTION_VELO.id_mouvement`.

  La BCNF est donc aussi respectée.
- `LOCATION.avec_casque` dépend du trajet (le mouvement), pas de l'usager ni de la formule ; `TOURNEE.id_vehicule` dépend de la tournée.
- **Données calculées, non stockées** (elles se déduisent, donc les stocker créerait des redondances) :
  - durée et coût d'un trajet : le coût est figé dans `FACTURE.montant` au moment de la facturation, car les tarifs de la formule peuvent changer ensuite ;
  - type d'un vélo (présence dans VELO_ELECTRIQUE) ;
  - état actuel d'un vélo (dernier CHANGEMENT_ETAT) ;
  - position « en location », « en tournée » ou « en atelier » (mouvement en cours et sa sous-classe) ;
  - nombre de bornes d'une station, vélos disponibles par type, bornes libres ;
  - abonnement en cours ou expiré (comparaison de `date_fin` avec la date du jour, sans planificateur) ;
  - facture réglée (`date_reglement` renseignée, ou montant nul) ;
  - nombre de vélos dans le véhicule (transferts en cours de la tournée) ;
  - usager d'une location (via ABONNEMENT), vélo d'une intervention (via MOUVEMENT), station d'une intervention sur station (via SIGNALEMENT_STATION).

## 7. Traçabilité

### 7.1 Sujet → MLD

| Exigence du sujet | Traduction dans le MLD |
|---|---|
| Inscription, connexion ; opérateurs et administrateurs aux droits étendus | UTILISATEUR (`email` unique, `mot_de_passe_hash`, `role`) ; R12 |
| Station : nom, adresse, coordonnées, nombre de bornes, état | STATION ; nombre de bornes = nombre de lignes de BORNE (R21) |
| Vélos disponibles (par type) et bornes libres en temps réel | Position dans VELO + VELO_ELECTRIQUE + état des BORNE et du vélo ; vue `v_disponibilite_station` |
| Vélo : identifiant, type, mise en service, état, batterie, position (borne, en location, en atelier) | VELO, VELO_ELECTRIQUE, CHANGEMENT_ETAT ; position = borne, ou mouvement en cours (LOCATION, TRANSFERT ou INTERVENTION_VELO) |
| Historiser déplacements et changements d'état | MOUVEMENT et ses sous-tables, CHANGEMENT_ETAT ; R5, R20 |
| Formules et conditions (durée gratuite, tranche, supplément électrique) | FORMULE (plus le supplément casque des UC50 et UC51) |
| Souscription, renouvellement, expiration | ABONNEMENT (réflexive « renouvelle ») ; R11 ; expiration déduite de `date_fin` |
| Emprunt (station, date et heure) et restitution (station d'arrivée, date et heure) | MOUVEMENT (bornes et dates de départ et d'arrivée) + LOCATION |
| Un vélo à la fois, abonnement valide, vélo défectueux non empruntable | R1, R2, R3 (+ R20) |
| Calcul automatique de la durée et du coût, facturation | R4, R18 ; FACTURE |
| Signaler un problème sur un vélo ou une station | SIGNALEMENT, SIGNALEMENT_VELO, SIGNALEMENT_STATION ; R9 |
| Interventions (retrait, réparation, remise en circulation) | INTERVENTION, INTERVENTION_VELO, INTERVENTION_STATION, MOUVEMENT, CHANGEMENT_ETAT ; R10, R13, R19 |
| Stations pleines ou vides, propositions de déplacements | Vues `v_regulation` et `v_proposition_deplacement` (rien n'est stocké) |
| Tournées (véhicule, opérateur, vélos déplacés) | TOURNEE, VEHICULE, UTILISATEUR, TRANSFERT ; R14 à R17 |
| Statistiques (trajets par période, heures de pointe, origine-destination, remplissage par tranche horaire, recettes par formule, indisponibilité) | Vues `v_stat_*` sur MOUVEMENT, LOCATION, FACTURE, CHANGEMENT_ETAT (§ 7.2, UC48 à UC53) |
| Un vélo à un seul endroit ; une borne accueille un seul vélo | Une seule position par ligne de VELO ; `UNIQUE (id_station, numero_borne)` ; R5, R7 |
| Automatisation des calculs et de l'historisation | R4, R5, R18, R20 |
| Respect de la 3NF | § 6 |
| Sécurité et confidentialité | Empreinte du mot de passe uniquement ; aucune donnée bancaire stockée (le paiement n'enregistre que `date_reglement`) |

### 7.2 Cas d'utilisation → MLD

Les vues citées sont celles déjà définies dans `Velo-Simulateur/data/automatisation.sql`.

| Cas | Relations écrites (É) ou lues (L) | Règles, vue |
|---|---|---|
| **Usager** | | |
| UC1 S'inscrire | É UTILISATEUR (`role` = USAGER) | email unique, empreinte du mot de passe |
| UC2 S'authentifier (tous les acteurs) | L UTILISATEUR | `role` donne les droits |
| UC3 Voir les vélos disponibles (par type) | L STATION, BORNE, VELO, VELO_ELECTRIQUE, CHANGEMENT_ETAT | `v_disponibilite_station` |
| UC4 Voir les bornes libres | L BORNE, VELO | `v_disponibilite_station` |
| UC19 Rechercher et filtrer les stations | L idem UC3 et UC4 | filtres sur `v_disponibilite_station` |
| UC5 Consulter les formules et tarifs | L FORMULE | |
| UC6 Souscrire un abonnement | É ABONNEMENT, FACTURE | R11, R12, R18 |
| UC17 Renouveler un abonnement | É ABONNEMENT (`id_abonnement_precedent`), FACTURE | R11, R18 |
| UC18 Consulter ses abonnements (en cours / expirés) | L ABONNEMENT, FORMULE | statut déduit de `date_fin` ; `v_abonnement` |
| UC7 Emprunter un vélo | É MOUVEMENT, LOCATION ; VELO (position NULL) | R1 à R3, R5 à R8 |
| UC50 Récupérer un casque | É `LOCATION.avec_casque` = vrai | R4 (supplément casque) |
| UC8 Restituer un vélo | É MOUVEMENT (arrivée), VELO (position), FACTURE | R4 à R6, R18 |
| UC51 Déposer un casque | aucune donnée propre : le casque est rendu avec le vélo | § 8 |
| UC9 Consulter l'historique de ses trajets | L LOCATION, MOUVEMENT, ABONNEMENT, STATION | `v_location` |
| UC12 Consulter ses factures | L FACTURE, ABONNEMENT, LOCATION | |
| UC10 Signaler un problème sur un vélo | É SIGNALEMENT, SIGNALEMENT_VELO, CHANGEMENT_ETAT | R9, R12, R20 |
| UC11 Signaler un problème sur une station | É SIGNALEMENT, SIGNALEMENT_STATION | R9, R12 |
| **Système (cas inclus ou étendus)** | | |
| UC13 Vérifier les conditions d'emprunt | L ABONNEMENT, LOCATION, MOUVEMENT, CHANGEMENT_ETAT | R1, R2, R3 |
| UC14 Calculer la durée et le coût | L MOUVEMENT, LOCATION, ABONNEMENT, FORMULE, VELO_ELECTRIQUE | R4 |
| UC15 Générer la facture | É FACTURE | R18 ; CHECK « une seule cible » |
| UC16 Payer (si montant > 0) | É `FACTURE.date_reglement` | CHECK `date_reglement IS NULL OR montant > 0` |
| **Opérateurs** | | |
| UC20 Consulter la position et l'historique d'un vélo | L VELO, MOUVEMENT et ses sous-tables, CHANGEMENT_ETAT | `v_velo` |
| **Opérateur de régulation** | | |
| UC25 Identifier les stations pleines ou vides | L STATION, BORNE, VELO | `v_regulation` |
| UC26 Proposer des déplacements (inclut UC25) | rien n'est stocké | `v_proposition_deplacement` |
| UC27 Enregistrer une tournée | voir UC31 à UC34 | |
| UC31 Démarrer la tournée (choix du véhicule) | É TOURNEE (`id_vehicule`, `id_utilisateur`) | R12, R16 |
| UC32 Charger un vélo | É MOUVEMENT, TRANSFERT ; VELO (position NULL) | R5 à R8, R14, R15 |
| UC33 Déposer un vélo sur une borne | É MOUVEMENT (arrivée), VELO (position) | R5, R6, R14 |
| UC34 Clôturer la tournée | É `TOURNEE.date_heure_fin` | R14, R17 |
| UC35 Rechercher et filtrer les tournées (date, véhicule, opérateur) | L TOURNEE, VEHICULE, UTILISATEUR, TRANSFERT | |
| **Opérateur de maintenance** | | |
| UC28 Consulter les signalements | L SIGNALEMENT et ses sous-tables | `v_signalement` |
| UC21 Gérer les interventions | É INTERVENTION et ses sous-tables, INTERVENTION_STATION (intervention sur station) | R10, R12, R14 |
| UC22 Retirer le vélo | É INTERVENTION, INTERVENTION_VELO, MOUVEMENT, `SIGNALEMENT_VELO.id_intervention_velo` | R8, R13, R19 |
| UC23 Réparer le vélo | É CHANGEMENT_ETAT (`EN_SERVICE`, ou `REFORME` si le vélo est irréparable), `SIGNALEMENT.date_heure_cloture`, à la fin de l'intervention | R19 |
| UC24 Remettre le vélo en circulation | É MOUVEMENT (arrivée sur une borne), VELO (position) | R6, R19 |
| UC29 Changer l'état d'une station | É `STATION.etat` | effet sur R6 |
| UC30 Rechercher et filtrer les vélos (type, état, position, batterie) | L VELO, VELO_ELECTRIQUE, CHANGEMENT_ETAT, MOUVEMENT | `v_velo` |
| **Administrateur** (hérite aussi des cas des deux opérateurs) | | |
| UC40 Gérer les stations et leurs bornes | É STATION, BORNE | R21 |
| UC41 Gérer la flotte de vélos | É VELO, VELO_ELECTRIQUE, CHANGEMENT_ETAT | R20 |
| UC45 Gérer les véhicules de régulation | É VEHICULE | immatriculation unique, capacité > 0 |
| UC42 Gérer les formules tarifaires | É FORMULE | libellé unique |
| UC43 Gérer les comptes et les droits | É `UTILISATEUR.role` | R12 |
| UC46 Rechercher et filtrer les locations (usager, station, période) | L LOCATION, MOUVEMENT, ABONNEMENT, UTILISATEUR, STATION | `v_location` |
| **Statistiques** | | |
| UC44 Consulter les statistiques | les quatre cas enfants ci-dessous | |
| UC48 Statistiques des trajets (par période, heures de pointe, origine-destination) | L LOCATION, MOUVEMENT | `v_stat_trajets_par_jour`, `v_stat_heures_pointe`, `v_stat_origine_destination` |
| UC49 Taux de remplissage par tranche horaire | L MOUVEMENT, BORNE, VELO (occupation reconstituée depuis l'historique des mouvements) | `v_stat_remplissage_horaire` |
| UC52 Recettes par formule | L FACTURE, ABONNEMENT, LOCATION, FORMULE | `v_stat_recettes_formule` |
| UC53 Taux d'indisponibilité de la flotte | L CHANGEMENT_ETAT, MOUVEMENT, INTERVENTION_VELO | `v_stat_indisponibilite_flotte` |
| UC47 Générer un rapport | rien n'est stocké : export des vues de statistiques | |

Les 49 cas du diagramme sont couverts, et chacune des 20 relations sert au moins à un cas.

## 8. Points relevés dans le MCD et le diagramme de cas

Ces points ne changent pas le MLD ci-dessus. Ils signalent ce que le MCD ou le diagramme pourraient préciser.

1. **Pas de contrainte `{xor}` entre « facturer abonnement » et « facturer location ».** Telles qu'écrites, les multiplicités permettraient qu'une facture concerne à la fois un abonnement et une location. Le MLD l'interdit par le CHECK « exactement une cible » ; une note `{xor}` pourrait être ajoutée au MCD.
2. **Généralisations SIGNALEMENT et INTERVENTION sans note.** Seul MOUVEMENT porte une contrainte (`{incomplete, disjoint}`). Le MLD suppose `{complete, disjoint}` pour les deux autres (R9, R10), comme en V1 ; ces notes pourraient être ajoutées au MCD.
3. **UC51 « Déposer un casque » n'a pas de donnée propre.** Le MCD ne stocke que `LOCATION.avec_casque`. On considère que le casque est rendu avec le vélo à la restitution ; il n'y a ni stock de casques par station ni suivi de casque non rendu.
4. **« Vélo signalé défectueux » (sujet, UC13).** Le MCD sépare l'état (CHANGEMENT_ETAT) du signalement. Le MLD les relie par R20 : un signalement de vélo le fait passer à l'état `DEFECTUEUX`.
5. **UC26 « Proposer des déplacements », UC47 « Générer un rapport » et les statistiques** ne stockent rien : ce sont des vues ou des requêtes, sans table.
6. **Lien vers `mcd.md`.** Le MCD renvoie à un `mcd.md` (règles de gestion, dictionnaire des données) qui n'existe ni en V1 ni en V2. Les règles sont donc regroupées ici, aux § 3 et 4.
7. **Écarts avec la base actuelle** (`Velo-Simulateur/data/structure.sql` et `automatisation.sql`, écrits pour la V1) :
   - pas de table `vehicule` ni de colonne `tournee.id_vehicule` : `demarrer_tournee` ne choisit pas de véhicule, et R15 ainsi que la partie « véhicule » de R16 manquent ;
   - `formule.type` est un ENUM, au lieu de `libelle` ;
   - pas de colonne `location.avec_casque` : le casque n'est qu'un paramètre de `fn_cout_location` ;
   - `trg_tournee_bu` refuse encore de clôturer une tournée sans transfert (ancienne multiplicité `1..*`) ;
   - `signaler_velo` ne passe pas le vélo à `DEFECTUEUX` (R20), et le rôle de l'auteur d'un signalement n'est pas contrôlé (R12) ;
   - le CHECK `date_reglement IS NULL OR montant > 0` n'existe pas.

   Le reste est déjà en place, notamment :
   - les rôles des tournées, des interventions et des abonnements ;
   - une seule tournée en cours par opérateur ;
   - la clôture d'une tournée seulement après le dépôt de tous les vélos (R17) ;
   - la location au départ d'une station et d'une borne en service (R6) ;
   - le premier état d'un vélo à sa mise en service (R20).
