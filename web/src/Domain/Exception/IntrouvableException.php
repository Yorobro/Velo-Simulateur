<?php

declare(strict_types=1);

namespace App\Domain\Exception;

/** L'élément demandé n'existe pas (page 404). */
final class IntrouvableException extends \RuntimeException
{
}
