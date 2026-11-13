@{
    # Run by hand:
    #   Invoke-ScriptAnalyzer -Path .\src -Settings .\PSScriptAnalyzerSettings.psd1
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # A console report: Write-Host is what gives the coloured PASS/FAIL output.
        'PSAvoidUsingWriteHost'
        # -FailuresOnly and -Offline are script parameters read inside helper functions.
        'PSReviewUnusedParameter'
    )
}
