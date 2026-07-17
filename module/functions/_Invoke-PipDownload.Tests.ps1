#Requires -Version 7.0
#Requires -Modules Pester

# These tests exercise the real native-command invocation (no mocks) — that is the whole point,
# since the bug this guards against was pip's stdout leaking into the success stream. 'python3'
# stands in for pip and is guaranteed present wherever pip itself would be.
#
# Pester evaluates -Skip: during discovery but runs It bodies later, and the two phases do not
# share variables — so the interpreter is resolved once per phase.
BeforeDiscovery {
    $hasPython = [bool]((Get-Command python3 -ErrorAction SilentlyContinue) -or
                        (Get-Command python  -ErrorAction SilentlyContinue))
}

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'ZeroFailed.Deploy.Fabric.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop

    $script:python = (Get-Command python3 -ErrorAction SilentlyContinue)?.Source ??
                     (Get-Command python -ErrorAction SilentlyContinue)?.Source
}

Describe '_Invoke-PipDownload' {

    It 'writes nothing to the success stream even when the command prints to stdout' -Skip:(-not $hasPython) {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ py = $script:python } {
            param($py)
            $script = 'print("Collecting edap-data-validation"); print("Saved x.whl")'
            $result = _Invoke-PipDownload -PythonExecutable $py -Arguments @('-c', $script)
            $result | Should -BeNullOrEmpty
        }
    }

    It 'surfaces the command output on the verbose stream' -Skip:(-not $hasPython) {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ py = $script:python } {
            param($py)
            $verbose = _Invoke-PipDownload -PythonExecutable $py -Arguments @('-c', 'print("Collecting foo")') -Verbose 4>&1
            ($verbose | ForEach-Object { "$_" }) -join "`n" | Should -BeLike '*Collecting foo*'
        }
    }

    It 'throws with the exit code and the command output when the command fails' -Skip:(-not $hasPython) {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ py = $script:python } {
            param($py)
            $script = 'import sys; print("No matching distribution found"); sys.exit(1)'
            { _Invoke-PipDownload -PythonExecutable $py -Arguments @('-c', $script) } |
                Should -Throw '*exit code 1*No matching distribution found*'
        }
    }

    It 'captures stderr in the failure message' -Skip:(-not $hasPython) {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ py = $script:python } {
            param($py)
            $script = 'import sys; sys.stderr.write("ERROR: Requires-Python mismatch\n"); sys.exit(1)'
            { _Invoke-PipDownload -PythonExecutable $py -Arguments @('-c', $script) } |
                Should -Throw '*Requires-Python mismatch*'
        }
    }

    It 'does not throw when the command succeeds' -Skip:(-not $hasPython) {
        InModuleScope ZeroFailed.Deploy.Fabric -Parameters @{ py = $script:python } {
            param($py)
            { _Invoke-PipDownload -PythonExecutable $py -Arguments @('-c', 'pass') } | Should -Not -Throw
        }
    }
}
