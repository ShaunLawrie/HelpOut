﻿### DO NOT EDIT THIS FILE DIRECTLY ###

#.ExternalHelp HelpOut-Help.xml
function ConvertTo-MAML
{
    
    [CmdletBinding(DefaultParameterSetName='CommandInfo')]
    [OutputType([string],[xml])]
    param( 
    # The name of or more commands.
    [Parameter(ParameterSetName='ByName',Position=0,ValueFromPipelineByPropertyName=$true)]
    [string[]]
    $Name,

    # The name of one or more modules.
    [Parameter(ParameterSetName='ByModule',ValueFromPipelineByPropertyName=$true)]
    [string[]]
    $Module,

    # The CommandInfo object (returned from Get-Command).
    [Parameter(Mandatory=$true,ParameterSetName='FromCommandInfo', ValueFromPipeline=$true)]
    [Management.Automation.CommandInfo[]]
    $CommandInfo,

    # If set, the generated MAML will be compact (no extra whitespace or indentation).  If not set, the MAML will be indented.
    [switch]
    $Compact,
    
    # If set, will return the MAML as an XmlDocument.  The default is to return the MAML as a string.
    [switch]
    $XML,
    
    # If set, the generate MAML will not contain a version number.  
    # This slightly reduces the size of the MAML file, and reduces the rate of changes in the MAML file.
    [Alias('Unversioned')]
    [switch]
    $NoVersion)
    
    begin {
        # First, we need to create a list of all commands we encounter (so we can process them at the end)
        $allCommands = [Collections.ArrayList]::new()
        # Then, we want to get the type accelerators (so we don't have to keep getting them each time we're interested)
        $typeAccelerators = [PSOBject].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Get

        # Next up, we're going to declare a bunch of ScriptBlocks, which we'll call to construct the XML in pieces.
        # This way we can create a nested structure (in this case, XML), by calling the pieces we want and letting them return the XML in chunks


        #region Get TypeName        
        $GetTypeName = {param([Type]$t)
            # We'll want to check to see if there are any accelerators.
            if (-not $typeAccelerators -and $typeAccelerators.GetEnumerator) {  # If there weren't
                return $t.Fullname # return the fullname.
            }
             
            foreach ($_ in $typeAccelerators.GetEnumerator()) { # Loop through the accelerators.
                if ($_.Value -eq $t) { # If it's an accelrator for the target type
                    return $_.Key.Substring(0,1).ToUpper() + $_.Key.Substring(1) # return the key (and fix it's casing)
                }
            }
            return $t.Fullname # If we didn't find it in the accelerators list, return the fullname.
        }
        #endregion Get TypeName

        #region Write Type

        # Both Inputs and Outputs have the same internal tag structure for a value, so one script block handles both cases.        
        $WriteType = {param($t) 
            $typename = $t.type[0].name
            $descriptionLines = $null
            
            
            if ($in.description) { # If we have a description, 
                $descriptionLines = $in.Description[0].text -split "`n|`r`n" -ne '' # we we're good.
            } else { # If we didn't, it's probably because comment based help mangles things a bit (it puts everything in a long typename).
                # Let's fix this by assigning the inType from the first line, and setting the rest as description lines
                $typename, $descriptionLines = $t.type[0].Name -split "`n|`r`n" -ne ''
            }
            $typename = [Security.SecurityElement]::Escape("$typename".Trim())
            

            "<dev:type><maml:name>$typename</maml:name><maml:uri/><maml:description /></dev:type>" # Write the type information
            if ($descriptionLines) { # If we had a description
                '<maml:description>' 
                foreach ($line in $descriptionLines) { # Write each line in it's own para tag so that it renders right.
                    $esc = [Security.SecurityElement]::Escape($line)
                    "<maml:para>$esc</maml:para>"
                }
                '</maml:description>'
            }
        }
        #endregion Write Type

        #region Write Command Details
        $writeCommandDetails = {
            # The command.details tag has 5 parts we want to provide
            # * Name,
            # * Noun
            # * Verb
            # * Synopsis
            # * Version
            $Version = "<dev:version>$(if ($cmdInfo.Version) { $cmdInfo.Version.ToString() })</dev:version>"
           
            "<command:details>
                <command:name>$([Security.SecurityElement]::Escape($cmdInfo.Name))</command:name>
                <command:noun>$noun</command:noun>
                <command:verb>$verb</command:verb>
                <maml:description>
                    <maml:para>$([Security.SecurityElement]::Escape($commandHelp.Synopsis))</maml:para>
                </maml:description>
                $(if (-not $NoVersion) { $Version})
            </command:details>
            <maml:description>
                $(
                foreach ($line in @($commandHelp.Description)[0].text -split "`n|`r`n") {
                    if (-not $line) { continue }
                    "<maml:para>$([Security.SecurityElement]::Escape($Line))</maml:para>"
                    }
                )                
            </maml:description>
            "
        }
        #endregion Write Command Details
        
        #region Write Parameter 
        $WriteParameter = {
            # Prepare the command.parameter attributes:
            $position  = if ($param.Position -ge 0) { $param.Position } else {"named" } #* Position
            $fromPipeline = #*FromPipeline
                if ($param.ValueFromPipeline) { "True (ByValue)" }
                elseif ($param.ValueFromPipelineByPropertyName) { "True (ByPropertyName)" }
                else { "False" } 
            $isRequired = if ($param.IsMandatory) { "true" } else { "false" } #*Required
            
            
            # Pick out the help for a given parameter 
            $paramHelp = foreach ($_ in $commandHelp.parameters.parameter) {
                    if ( $_.Name -eq $param.Name ){
                        $_
                        break
                    }
                }
            $paramTypeName = & $GetTypeName $param.ParameterType # and get the type name of the parameter type.
                                
            "<command:parameter required='$isRequired' position='$position' pipelineInput='$fromPipeline' aliases='' variableLength='true' globbing='false'>" #* Echo the start tag
            "<maml:name>$($param.Name)</maml:name>" #* The maml.name tag
            '<maml:description>' #*The description tag
            foreach ($d in $paramHelp.Description) { 
                "<maml:para>$([Security.SecurityElement]::Escape($d.Text))</maml:para>"
            }
            '</maml:description>' 
            #*The parameterValue tag (which oddly enough, describes the parameter type)
            "<command:parameterValue required='$isRequired' variableLength='true'>$paramTypeName</command:parameterValue>" 
            #*The type tag (which is also it's type)
            "<dev:type><maml:name>$paramTypeName</maml:name><maml:uri /></dev:type>"
            #*and an empty default value.
            '<dev:defaultValue></dev:defaultValue>'
            #* Then close the parameter tag.
            '</command:parameter>'
        }
        #endregion Write Parameter 

        #region Write Parameters        
        $WriteCommandParameters = {
            '<command:parameters>' # *Open the parameters tag;
            foreach ($param in ($cmdMd.Parameters.Values | Sort-Object Name)) { #*Loop through the command's parameters alphabetically
                & $WriteParameter #*Write each parameter.
            }
            '</command:parameters>' #*Close the parameters tag
        } 
        #endregion Write Parameters


        #region Write Examples
        $WriteExamples = {
            # If there were no examples, return.            
            if (-not $commandHelp.Examples.example) { return }

            
            "<command:examples>" 
            foreach ($ex in $commandHelp.Examples.Example) { # For each example:
                '<command:example>' #*Start an example tag
                '<maml:title>'
                $ex.Title  #*Put it's title in a maml:title tag
                '</maml:title>'
                '<maml:introduction>'#* Put it's introduction in a maml:introduction tag
                foreach ($i in $ex.Introduction) {
                    '<maml:para>'
                    [Security.SecurityElement]::Escape($i.Text)
                    '</maml:para>'
                }
                '</maml:introduction>'
                '<dev:code>' #* Put it's code in a dev:code tag
                [Security.SecurityElement]::Escape($ex.Code)
                '</dev:code>'
                '<dev:remarks>' #* Put it's remarks in a dev:remarks tag
                foreach ($i in $ex.Remarks) {
                    if (-not $i -or -not $i.Text.Trim()) { continue }                        
                    '<maml:para>'
                    [Security.SecurityElement]::Escape($i.Text)
                    '</maml:para>'
                }
                '</dev:remarks>'
                '</command:example>'
            }
            '</command:examples>'
        }
        #endregion Write Examples

 

        #region Write Inputs
        $WriteInputs = {
            if (-not $commandHelp.inputTypes) { return } # If there were no input types, return.


            '<command:inputTypes>' #*Open the inputTypes Tag.
            foreach ($in in $commandHelp.inputTypes[0].inputType) { #*Walk thru each type in help.
                '<command:inputType>'  
                    & $WriteType $in #*Write the type information (in an inputType tag).
                '</command:inputType>'
            }
            '</command:inputTypes>' #*Close the Input Types Tag.
        }
        #endregion Write Inputs

        #region Write Outputs
        $WriteOutputs = {
            if (-not $commandHelp.returnValues) { return } # If there were no return values, return. 
            
            '<command:returnValues>' # *Open the returnValues tag
            foreach ($rt in $commandHelp.returnValues[0].returnValue) { # *Walk thru each return value
                '<command:returnValue>' 
                    & $WriteType $rt # *write the type information (in an returnValue tag)
                '</command:returnValue>'
            }
            '</command:returnValues>' #*Close the returnValues tag
        }
        #endregion Write Outputs

        #region Write Notes
        $WriteNotes = {
            if (-not $commandHelp.alertSet) { return } # If there were no notes, return.
            "<maml:alertSet><maml:title></maml:title>" #*Open the alertSet tag and emit an empty title
            foreach ($note in $commandHelp.alertSet[0].alert) { #*Walk thru each note
                "<maml:alert><maml:para>"                    
                    $([Security.SecurityElement]::Escape($note.Text)) #*Put each note in a maml:alert element
                "</maml:para></maml:alert>"
            } 
            "</maml:alertSet>" #*Close the alertSet tag
        }
        #endregion Write Notes

        #region Write Syntax
        $WriteSyntax = {
            if (-not $cmdInfo.ParameterSets) { return } # If this command didn't have parameters, return
            
            "<command:syntax>" #*Open the syntax tag
            foreach ($syn in $cmdInfo.ParameterSets) {#*Walk thru each parameter set
                "<command:syntaxItem><maml:name>$($cmdInfo.Name)</maml:name>"  #*Create a syntaxItem tag, with the name of the command. 
                foreach ($param in $syn.Parameters) { 
                    #* Skip parameters that are not directly declared (e.g. -ErrorAction)
                    if (-not $cmdMd.Parameters.ContainsKey($param.Name))  { continue } 
                    & $WriteParameter #* Write help for each parameter                    
                }
                "</command:syntaxItem>" #*Close the syntax item tag
            }
            "</command:syntax>"#*Close the syntax tag   
            
        }
        #endregion Write Syntax                

        #region Write Links
        $WriteLinks = {
            # If the command didn't have any links, return.
            if (-not $commandHelp.relatedLinks.navigationLink) { return }
            
            '<maml:relatedLinks>' #* Open a related Links tag            
            foreach ($l in $commandHelp.relatedLinks.navigationLink) { #*Walk thru each link
                $linkText, $LinkUrl = "$($l.linkText)".Trim(), "$($l.Uri)".Trim() # and write it's tag.
                '<maml:navigationLink>'
                    "<maml:linkText>$linkText</maml:linkText>"
                    "<maml:uri>$LinkUrl</maml:uri>"
                '</maml:navigationLink>'
            }
            '</maml:relatedLinks>' #* Close the related Links tag
        }    
        #endregion Write Links


        #- - -  Now that we've declared all of these little ScriptBlock parts, we'll put them in a list in the order they'll run.
        $WriteMaml = $writeCommandDetails, $writeSyntax,$WriteCommandParameters,$WriteInputs,$writeOutputs, $writeNotes, $WriteExamples, $writeLinks
        #- - -
    }
    
    process {
        
        if ($PSCmdlet.ParameterSetName -eq 'ByName') { # If we're getting comamnds by name,
            $CommandInfo = @(foreach ($n in $name) { 
                $ExecutionContext.InvokeCommand.GetCommands($N,'Function,Cmdlet', $true) # find each command (treating Name like a wildcard).
            })
        }


        if ($PSCmdlet.ParameterSetName -eq 'ByModule') { # If we're getting commands by module
            $CommandInfo = @(foreach ($m in $module) {  # find each module
                (Get-Module -Name $m).ExportedCommands.Values # and get it's exports.
            })
        }


        $filteredCmds = @(foreach ($ci in $CommandInfo) { # Filter the list of commands 
            if ($ci -is [Management.Automation.AliasInfo] -or # (throw out aliases and applications).
                $ci -is [Management.Automation.ApplicationInfo]) { continue }
            $ci 
        })
         
        if ($filteredCmds) { 
            $null = $allCommands.AddRange($filteredCmds)
        }
    }
    
    end {
        $c, $t, $id, $maml = # Create some variables for our progress bar, 
        0, $allCommands.Count, [Random]::new().Next(), [Text.StringBuilder]::new('<helpItems schema="maml">') # and initialize our MAML.
        
        foreach ($cmdInfo in $allCommands) { # Walk thru each command.
            $commandHelp = $null
            $c++
            $p = $c * 100 / $t
            Write-Progress 'Converting to MAML' "$cmdInfo [$c of $t]" -PercentComplete $p -Id $id # Write a progress message
            $commandHelp = $cmdInfo | Get-Help # get it's help
            $cmdMd = [Management.Automation.CommandMetaData]$cmdInfo # get it's command metadata 
            if (-not $commandHelp -or $commandHelp -is [string]) { # (error if we couldn't Get-Help)
                Write-Error "$cmdInfo Must have a help topic to convert to MAML"
                return
            }                
            $verb, $noun  = $cmdInfo.Name -split "-" # and split out the noun and verb.
            


            # Now we're ready to run all of those script blocks we declared in begin.
            # All we need to do is append the command node, run each of the script blocks in $WriteMaml, and close the node.
            $mamlCommand = 
                "<command:command 
                    xmlns:maml='http://schemas.microsoft.com/maml/2004/10' 
                    xmlns:command='http://schemas.microsoft.com/maml/dev/command/2004/10' 
                    xmlns:dev='http://schemas.microsoft.com/maml/dev/2004/10'>
                    $(foreach ($_ in $WriteMaml) { & $_ })
                </command:command>"
            $null = $maml.AppendLine($mamlCommand)
        }

        Write-Progress "Exporting Maml" " " -Completed -Id $id # Then we indicate we're done,
        $null = $maml.Append("</helpItems>") # close the opening tag. 
        $mamlAsXml = [xml]"$maml" # and convert the whole thing to XML.
        if (-not $mamlAsXml) { return }  # If we couldn't, return.
        
        
        if ($XML) { return $mamlAsXml } # If we wanted the XML, return it.

        
        $strWrite = [IO.StringWriter]::new() # Now for a little XML magic:


        # If we create a [IO.StringWriter], we can save it as pretty or compacted XML.
        $mamlAsXml.PreserveWhitespace = $Compact # Oddly enough, if we're compacting we're setting preserveWhiteSpace to true, which in turn strips all of the whitespace except that inside of your nodes.
        $mamlAsXml.Save($strWrite) # Anyways, we can save this to the string writer, and it will either make our XML perfectly balanced and indented or compact and free of most whitespace. 
        # Unfortunately, it will not get it's encoding declaration "right".  This is because $strWrite is Unicode, and in most cases we'll want our XML to be UTF8.  
        # The next step of the pipeline needs to convert it as it is saved, which is as easy as | Out-File -Encoding UTF8.
        "$strWrite".Replace('<?xml version="1.0" encoding="utf-16"?>','<?xml version="1.0" encoding="utf-8"?>') 
        $strWrite.Close()
        $strWrite.Dispose()
    }
} 
#.ExternalHelp HelpOut-Help.xml
function Install-MAML
{
    
    [OutputType([Nullable], [IO.FileInfo])]
    param(
    # The name of one or more modules.
    [Parameter(Mandatory=$true,Position=0,ParameterSetName='Module',ValueFromPipelineByPropertyName=$true)]
    [string[]]
    $Module,
    
    # If set, will refresh the documentation for the module before generating the commands file.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [switch]
    $NoRefresh,

    # If set, will compact the generated MAML.  This will be ignored if -Refresh is not passed, since no new MAML will be generated.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [switch]
    $Compact,
   
    # The name of the combined script.  By default, allcommands.ps1.
    [Parameter(Position=1,ValueFromPipelineByPropertyName=$true)]
    [string]
    $ScriptName = 'allcommands.ps1',

    # The root directories containing functions.  If not provided, the function root will be the module root.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [string[]]
    $FunctionRoot,

    # If set, the function roots will not be recursively searched.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [switch]
    $NoRecurse,

    # The encoding of the combined script.  By default, UTF8.
    [Parameter(Position=2,ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNull()]
    [Text.Encoding]
    $Encoding = [Text.Encoding]::UTF8,

    # A list of wildcards to exclude.  This list will always contain the ScriptName.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [string[]]
    $Exclude,

    # If set, the generate MAML will not contain a version number.  
    # This slightly reduces the size of the MAML file, and reduces the rate of changes in the MAML file.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [Alias('Unversioned')]
    [switch]
    $NoVersion,

    # If provided, will save the MAML to a different directory than the current UI culture.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [Globalization.CultureInfo]
    $Culture,

    # If set, will return the files that were generated.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [switch]
    $PassThru
    )

    process {        
        if ($ScriptName -notlike '*.ps1') { # First, let's check that the scriptname is a .PS1.
            $ScriptName += '.ps1' # If it wasn't, add the extension.
        }

        $Exclude += $ScriptName # Then, add the script name to the list of exclusions.

        if (-not $Culture) { # If no culture was specified,
            $Culture = [Globalization.CultureInfo]::CurrentUICulture # use the current UI culture.
        }

        foreach ($m in $Module) { 
            $theModule = Get-Module $m # Resolve the module.
            if (-not $theModule) { continue }  # If we couldn't, continue to the next.
            $theModuleRoot =  $theModule | Split-Path # Find the module's root.
            
            if ($PSBoundParameters.FunctionRoot) { # If we provided a function root parameter
                $functionRoot = foreach ($f in $FunctionRoot) { # then turn each root into an absolute path.
                    if ([IO.File]::Exists($F)) {
                        $f
                    } else {
                        Join-Path $theModuleRoot $f
                    }
                }
            } else {
                $FunctionRoot = "$theModuleRoot" # otherwise, just use the module root.
            }
            
            $fileList = @(foreach ($f in $FunctionRoot) { # Walk thru each function root.
                Get-ChildItem -Path $f -Recurse:$(-not $Recurse) -Filter *.ps1 | # recursively find all .PS1s
                    & { process {
                        if ($_.Name -notlike '*-*' -or $_.Name -like '*.*.*') { return  }  
                        foreach ($ex in $Exclude) { 
                            if ($_.Name -like $ex) { return } 
                        }
                        return $_
                    } }
            })

            #region Save the MAMLs
            if (-not $NoRefresh) { # If we're refreshing the MAML,
                $saveMamlCmd =  # find the command Save-MAML
                    if ($MyInvocation.MyCommand.ScriptBlock.Module) {
                        $MyInvocation.MyCommand.ScriptBlock.Module.ExportedCommands['Save-MAML']
                    } else {
                        $ExecutionContext.SessionState.InvokeCommand.GetCommand('Save-MAML', 'Function')
                    }
                $saveMamlSplat = @{} + $PSBoundParameters # and pick out the parameters that this function and Save-MAML have in common.
                foreach ($k in @($saveMamlSplat.Keys)) {
                    if (-not $saveMamlCmd.Parameters.ContainsKey($k)) {
                        $saveMamlSplat.Remove($k)
                    }
                }
                $saveMamlSplat.Module = $m # then, set the module
                Save-MAML @saveMamlSplat # and call Save-MAML
            }
            #endregion Save the MAMLs

            #region Generate the Combined Script
            # Prepare a regex to find function definitions.
            $regex = [Regex]::new('
                (?<![-\s\#]{1,}) # not preceeded by a -, or whitespace, or a comment
                function # function keyword
                \s{1,1} # a single space or tab
                (?<Name>[^\-]{1,1}\S+) # any non-whitespace, starting with a non-dash
                \s{0,} # optional whitespace
                [\(\{] # opening parenthesis or brackets
', 'MultiLine,IgnoreCase,IgnorePatternWhitespace')

            
            $newFileContent = # We'll assign new file content by
                foreach ($f in $fileList) { # walking thru each file. 
                    $fileBytes = [IO.File]::ReadAllBytes($f.Fullname) # We'll read the file content in as bytes
                    $ms = [IO.MemoryStream]::new($fileBytes) # so we can use an [IO.MemoryStream] and 
                    $sr = [IO.StreamReader]::new($ms, $true) # an [IO.Streamreader] to peek at the encoding 
                    $fileContent = $sr.ReadToEnd() # and read it as a string.
                    $start = 0
                    do { 
                        $matched = $regex.Match($fileContent,$start) # See if we find a functon. 
                        if ($matched.Success) { # If we found one,
                            $insert = ([Environment]::NewLine + "#.ExternalHelp $M-Help.xml" + [Environment]::NewLine) # insert a line for help.
                            $fileContent = if ($matched.Index) {
                                $fileContent.Insert($matched.Index - 1, $insert)
                            } else {
                                $insert + $fileContent
                            }
                            $start += $matched.Index + $matched.Length
                            $start += $insert.Length # and update our starting position.
                        }        
                        # Keep doing this until we've reached the end of the file or the end of the matches.
                    } while ($start -le $filecontent.Length -and $matched.Success) 
  
                    # Then output the file content, stripped of block comments.
                    $fileContent -replace '\<\#(?<Block>(.|\s)+?(?=\#>))\#\>', ''

                    $sr.Close()
                    $sr.Dispose()               
                }
            
            # Last but not least, we 
            $combinedCommandsPath = Join-Path $theModuleRoot $ScriptName # determine the path for our combined commands file.

            "### DO NOT EDIT THIS FILE DIRECTLY ###" | Set-Content -Path $combinedCommandsPath -Encoding $Encoding.HeaderName.Replace('-','') # add a header
            [IO.File]::AppendAllText($combinedCommandsPath, $newFileContent, $Encoding) # and add our content.
            #endregion Generate the Combined Script

            if ($PassThru) {
                Get-Item -Path $combinedCommandsPath
            }
        }
    }
}
 
#.ExternalHelp HelpOut-Help.xml
function Save-MAML
{
    
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
