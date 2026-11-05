<?php

declare(strict_types=1);

namespace App\Infrastructure;

use LogicException;
use ReflectionClass;
use ReflectionNamedType;

/**
 * Conteneur d'injection minimal : chaque service est créé une seule fois.
 * Une classe concrète se construit seule (paramètres du constructeur résolus
 * par leur type) ; une interface doit être liée à son implémentation.
 */
final class Container
{
    /** @var array<string, callable|string> */
    private array $definitions = [];

    /** @var array<string, mixed> */
    private array $instances = [];

    /** Lie un identifiant à une fabrique (callable) ou à une classe d'implémentation. */
    public function set(string $id, callable|string $definition): void
    {
        $this->definitions[$id] = $definition;
    }

    public function get(string $id): mixed
    {
        if (array_key_exists($id, $this->instances)) {
            return $this->instances[$id];
        }
        $definition = $this->definitions[$id] ?? null;
        $instance = match (true) {
            is_string($definition) => $this->get($definition),
            is_callable($definition) => $definition($this),
            default => $this->construire($id),
        };

        return $this->instances[$id] = $instance;
    }

    private function construire(string $classe): object
    {
        if (!class_exists($classe)) {
            throw new LogicException("Service inconnu : {$classe}");
        }
        $reflexion = new ReflectionClass($classe);
        $constructeur = $reflexion->getConstructor();
        if ($constructeur === null) {
            return new $classe();
        }
        $arguments = [];
        foreach ($constructeur->getParameters() as $parametre) {
            $type = $parametre->getType();
            if ($type instanceof ReflectionNamedType && !$type->isBuiltin()) {
                $arguments[] = $this->get($type->getName());
            } elseif ($parametre->isDefaultValueAvailable()) {
                $arguments[] = $parametre->getDefaultValue();
            } else {
                throw new LogicException("Paramètre \${$parametre->getName()} de {$classe} impossible à résoudre");
            }
        }

        return $reflexion->newInstanceArgs($arguments);
    }
}
