<?php

declare(strict_types=1);

namespace App\Domain\Exception;

/** Une règle métier refuse l'action (message destiné à l'utilisateur). */
class RegleMetierException extends \DomainException
{
}
