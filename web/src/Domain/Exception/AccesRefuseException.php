<?php

declare(strict_types=1);

namespace App\Domain\Exception;

/** L'utilisateur n'a pas le droit d'agir sur cet élément (page 403). */
final class AccesRefuseException extends \RuntimeException
{
}
