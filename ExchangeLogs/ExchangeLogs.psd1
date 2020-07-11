@{
    # Script module or binary module file associated with this manifest
    RootModule        = 'ExchangeLogs.psm1'

    # Version number of this module.
    ModuleVersion     = '1.2.1'

    # ID used to uniquely identify this module
    GUID              = '4182cc5a-25fa-434a-a852-853483481e35'

    # Author of this module
    Author            = 'Andreas Bellstedt'

    # Company or vendor of this module
    CompanyName       = ''

    # Copyright statement for this module
    Copyright         = 'Copyright (c) 2020 Andreas Bellstedt'

    # Description of the functionality provided by this module
    Description       = 'Module for interpreting and transforming Microsoft Exchange Server Log Files'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.0'

    # Modules that must be imported into the global environment prior to importing
    # this module
    RequiredModules   = @(
        @{ ModuleName = 'PSFramework'; ModuleVersion = '1.1.59' }
        @{ ModuleName = 'PoshRSJob'; ModuleVersion = '1.7.4.4' }
    )

    # Assemblies that must be loaded prior to importing this module
    # RequiredAssemblies = @('bin\ExchangeLogs.dll')

    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess    = @('xml\ExchangeLogs.Types.ps1xml')

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess  = @('xml\ExchangeLogs.Format.ps1xml')

    # Functions to export from this module
    FunctionsToExport = @(
        'Get-ELExchangeLog'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = ''

    # Variables to export from this module
    VariablesToExport = ''

    # Aliases to export from this module
    AliasesToExport   = @(
        'gel'
    )

    # List of all modules packaged with this module
    ModuleList        = @()

    # List of all files packaged with this module
    FileList          = @()

    # Private data to pass to the module specified in ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData       = @{

        #Support for PowerShellGet galleries.
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @(
                "Exchange",
                "ExchangeServer",
                "MicrosoftExchangeServer",
                "Logs",
                "Logfile",
                "Logfiles"
            )

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/AndiBellstedt/ExchangeLogs/blob/master/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/AndiBellstedt/ExchangeLogs'

            # A URL to an icon representing this module.
            IconUri      = 'https://github.com/AndiBellstedt/ExchangeLogs/tree/master/ExchangeLogs/assets/ExchangeLogs_128x128.png'

            # ReleaseNotes of this module
            ReleaseNotes = 'https://github.com/AndiBellstedt/ExchangeLogs/blob/master/ExchangeLogs/changelog.md'

        } # End of PSData hashtable

    } # End of PrivateData hashtable
}