function _Invoke-PipDownload {
    <#
    .SYNOPSIS
        Thin, mockable wrapper around 'python -m pip download'.
    .DESCRIPTION
        Isolates the single native pip invocation so that Save-FabricLibraryPackage can be unit
        tested without pip installed. Runs pip with the supplied arguments and throws if it exits
        with a non-zero status.

        The arguments are passed positionally so callers control exactly what pip receives; nothing
        is logged here (the caller is responsible for redacting any credentials it constructs).

        pip's stdout/stderr is deliberately kept OUT of the success stream: callers assign this
        function's output, and leaking 'Collecting ...' / 'Saved ...' lines would contaminate their
        results with strings. The output is surfaced via -Verbose instead, and reproduced verbatim
        in the exception when pip fails, so resolution errors are never lost.
    .PARAMETER PythonExecutable
        The python executable to invoke (e.g. 'python' or 'python3').
    .PARAMETER Arguments
        The full argument list passed to python, beginning with '-m','pip','download',...
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$PythonExecutable,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    # We inspect $LASTEXITCODE ourselves; stop PS 7.4+ raising NativeCommandExitException first,
    # which would discard pip's output before it could be attached to the error message.
    $PSNativeCommandUseErrorActionPreference = $false

    $output   = & $PythonExecutable @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        Write-Verbose "$line"
    }

    if ($exitCode -ne 0) {
        $detail = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
        throw "pip download failed with exit code $exitCode.$([Environment]::NewLine)$detail"
    }
}
