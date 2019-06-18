﻿function Save-MAML
{
    <#
    .Synopsis
        Saves a Module's MAML
    .Description
        Generates a Module's MAML file, and then saves it to the appropriate location.
    .Link
        ConvertTo-MAML
    .Example
        Save-Maml -Module HelpOut
    .Example
        Save-Maml -Module HelpOut -WhatIf
    .Example
        Save-Maml -Module HelpOut -PassThru
    #>
    [CmdletBinding(DefaultParameterSetName='CommandInfo',SupportsShouldProcess=$true)]
    [OutputType([Nullable])]
    param( 
    # The name of one or more modules.
    [Parameter(ParameterSetName='ByModule',ValueFromPipelineByPropertyName=$true)]
    [string[]]
    $Module,

    # If set, the generated MAML will be compact (no extra whitespace or indentation).  If not set, the MAML will be indented.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [switch]
    $Compact,
    
    # If provided, will save the MAML to a different directory than the current UI culture.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [Globalization.CultureInfo]
    $Culture,

    # If set, the generate MAML will not contain a version number.  
    # This slightly reduces the size of the MAML file, and reduces the rate of changes in the MAML file.
    [Alias('Unversioned')]
    [switch]
    $NoVersion,
    
    # If set, will return the files that were generated.
    [switch]
    $PassThru)

    begin {
        # First, let's cache a reference to ConvertTo-MAML
        $convertToMaml = 
            if ($MyInvocation.MyCommand.ScriptBlock.Module) {
                $MyInvocation.MyCommand.ScriptBlock.Module.ExportedCommands['ConvertTo-MAML']
            } else {
                $ExecutionContext.SessionState.InvokeCommand.GetCommand('ConvertTo-MAML', 'Function')
            }
    }

    process {
        if (-not $convertToMaml) { # If for whatever reason we don't have ConvertTo-Maml
            Write-Error "Could not Find ConvertTo-MAML" -Category ObjectNotFound -ErrorId ConvertTo-MAML.NotFound # error out.
            return
        }


        $c, $t, $id = 0, $Module.Length, [Random]::new().Next() 
        $splat = @{} + $PSBoundParameters # Copy our parameters
        foreach ($k in @($splat.Keys)) { # then strip out any parameter
            if (-not $convertToMaml.Parameters.ContainsKey($k)) { # that wasn't in ConvertTo-MAML.
                $splat.Remove($k)
            }
        }

        if (-not $Culture) { # If -Culture wasn't provided, use the current culture
            $Culture = [Globalization.CultureInfo]::CurrentCulture
        }

        #region Save the MAMLs
        foreach ($m in $Module) { # Walk thru the list of module names.
            $splat.Module = $m 
            if ($t -gt 1) {
                $c++
                Write-Progress 'Saving MAML' $m -PercentComplete $p  -Id $id
            }

            $theModule = Get-Module $m # Find the module
            if (-not $theModule) { continue } # (continue if we couldn't).
            $theModuleRoot = $theModule | Split-Path # Find the module's root,
            $theModuleCultureDir = Join-Path $theModuleRoot $Culture.Name # then find the culture folder.

            if (-not (Test-Path $theModuleCultureDir)) { # If that folder didn't exist,
                $null = New-Item -ItemType Directory -Path $theModuleCultureDir # create it.
            }
            
            $theModuleHelpFile = Join-Path $theModuleCultureDir "$m-Help.xml" # Construct the path to the module help file (e.g. en-us\Module-Help.xml)

            & $convertToMaml @splat | # Convert the module help to MAML,
                Set-Content -Encoding UTF8 -Path $theModuleHelpFile # and write the file.
         }

        if ($t -gt 1) {
            Write-Progress 'Saving MAML' 'Complete' -Completed -Id $id
        }
        #endregion Save the MAMLs
    }
}
