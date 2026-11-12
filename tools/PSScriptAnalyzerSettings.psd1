@{
    # Warnings and errors gate. Excluded because they are style or false positives for console scripts:
    #   Write-Host                 deliberate: these scripts talk to a person at a console
    #   singular nouns, approved verbs, ShouldProcess: naming and -WhatIf style on internal helpers, not defects
    #   empty catch                best-effort cleanup (logon, logoff) where a failure must never stop the script
    #   unused parameter, $using   false positives: a parameter used inside a nested function, an -ArgumentList job
    # Everything else stays on, including Invoke-Expression, plaintext passwords and missing BOM on non-ASCII files.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseSingularNouns'
        'PSUseApprovedVerbs'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSAvoidUsingEmptyCatchBlock'
        'PSReviewUnusedParameter'
        'PSUseUsingScopeModifierInNewRunspaces'
    )
}
