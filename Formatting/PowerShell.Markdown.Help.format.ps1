Write-FormatView -TypeName PowerShell.Markdown.Help -Action {
    $helpObject = $_
    $helpCmd = $ExecutionContext.SessionState.InvokeCommand.GetCommand($helpObject.Name, 'All')

    $MarkdownSections = [Ordered]@{
        Name =  {
            if ($helpObject.Rename) {
                Format-Markdown -Heading $helpObject.Rename
            } else {
                Format-Markdown -Heading $helpObject.Name
            }
        }
        Synopsis = {
            Format-Markdown -HeadingSize 3 -Heading "Synopsis"

            $helpObject.Synopsis | Out-String -Width 1mb            
        }
        Description = {
            Format-Markdown -HeadingSize 3 -Heading "Description"
            foreach ($desc in $helpObject.Description) {
                [Environment]::NewLine + $desc.text  + [Environment]::NewLine
            }
        }
        RelatedLinks = {
            if ($helpObject.RelatedLinks) {    
                Format-Markdown -Heading "Related Links" -headingsize 3
    
                foreach ($nav in $helpObject.RelatedLinks.navigationLink) {
                    $linkedCmd = $ExecutionContext.SessionState.InvokeCommand.GetCommand($nav.LinkText, 'All')
                    $linkUrl = 
                        if ($nav.Uri) {
                            $nav.Uri
                        }
                        elseif ($linkedCmd -and ($linkedCmd.Module -like 'microsoft.*' -or $linkedCmd.Source -like 'microsoft.*')) {
                            $linkSrc = if ($linkedCmd.Module) { $linkedCmd.Module} else { $linkedCmd.Source }
                            "https://docs.microsoft.com/powershell/module/$linkSrc/$linkedCmd"
                        } elseif ($helpObject.WikiLink) {
                            $nav.LinkText
                        } elseif ($null -ne $helpObject.DocLink) {
                            "$($nav.LinkText).md"
                        }
                        else {
                            ""
                        }

                    $linkText = if ($nav.LinkText) { $nav.linkText } else {$linkUrl}
                    
                    Format-Markdown -Link $linkUrl -inputObject $linkText -BulletPoint
                }
            }
        }
        Examples = {
            if ($helpObject.Examples) {                
                Format-Markdown -Heading "Examples" -headingsize 3
    
                foreach ($example in $helpObject.Examples.Example) {
                    (Format-Markdown -Heading ($example.Title -replace '^[-\s]+' -replace '[-\s]+$') -HeadingSize 4)
    
                    if ($example.Code) {
                        $example.Code | Format-Markdown -CodeLanguage PowerShell
                    }
    
                    if ($example.Remarks) {
                        ($example.Remarks | Out-String -Width 1mb).Trim()
                    }
                }
            }
        }
        Parameters = {
            if ($helpObject.Parameters) {                
                Format-Markdown -Heading "Parameters" -HeadingSize 3
    
                $parameterTotal= @($helpObject.parameters.parameter).Length
                $parameterCounter = 0 
                foreach ($parameter in $helpObject.Parameters.parameter) {
                    $parameterCounter++
                    $parameterDisplayName = 
                        if ($parameter.required) {
                            "**$($parameter.Name)**"
                        } else {
                            $parameter.Name
                        }
    
                    Format-Markdown -HeadingSize 4 -Heading $parameterDisplayName
    
                    if ($parameter.Name -in 'WhatIf', 'Confirm') {
                        "-$($parameter.Name) " +  
                            'is an automatic variable that is created when a command has ```[CmdletBinding(SupportsShouldProcess)]```.'
                        if ($parameter.Name -eq 'WhatIf') {
                            "-WhatIf is used to see what would happen, or return operations without executing them"
                        }
                        if ($parameter.Name -eq 'Confirm') {
                            '-Confirm is used to -Confirm each operation.
    
If you pass ```-Confirm:$false``` you will not be prompted.
    
    
If the command sets a ```[ConfirmImpact("Medium")]``` which is lower than ```$confirmImpactPreference```, you will not be prompted unless -Confirm is passed.
'
                        }
                        continue
                    }
    
                    ($parameter.description | Out-String -Width 1mb) -split '(?>\r\n|\n)' -replace '^-\s', '* ' -join [Environment]::NewLine
    
                    if (-not $helpObject.NoValidValueEnumeration -and $helpCmd -and $helpCmd.Parameters.($parameter.Name)) {
                        $parameterMetadata = $helpCmd.Parameters[$parameter.Name]
                        $validValuesList = @(
                            if ($parameterMetadata.ParameterType.IsSubclassOf([Enum])) {
                                [Enum]::GetValues($parameterMetadata.ParameterType)
                            } elseif ($parameterMetadata.Attributes.ValidValues) {
                                $parameterMetadata.Attributes.ValidValues
                            } elseif ($parameterMetadata.ParameterType.IsArray -and 
                                $parameterMetadata.ParameterType.GetElementType().IsSubclassOf([Enum])) {
                                [Enum]::GetValues($parameterMetadata.ParameterType.GetElementType())
                            }
                        )
                        if ($validValuesList) {
                            "Valid Values:" + [Environment]::NewLine
                            $validValuesList | Format-Markdown -BulletPoint
                            [Environment]::NewLine * 2
                        }
                    }

                    [Ordered]@{
                        Type = '```' + "[" + $($parameter.type.name -replace 'SwitchParameter', 'Switch') + "]" + '```'
                        Requried = $parameter.required
                        Postion = $parameter.position
                        PipelineInput = $parameter.pipelineInput                    
                    } | Format-Markdown
                    if ($parameterCounter -lt $parameterTotal) { '---' } 
                }            
            }            
        }
        Inputs = {
            if ($helpObject.inputTypes -and $helpObject.inputTypes.inputType) {
                 Format-Markdown -Heading "Inputs" -HeadingSize 3
                foreach ($inputType in $helpObject.inputTypes.inputType) {
                    $inputType.type.name + [Environment]::NewLine
                    foreach ($desc in $inputType.Description) {
                        $desc.text + [Environment]::NewLine
                    }
                }
            }            
        }
        Outputs = {
            if ($helpObject.returnValues -and $helpObject.returnValues.returnValue) {
                Format-Markdown -Heading "Outputs" -HeadingSize 3
                foreach ($returnValue in $helpObject.returnValues.returnValue) {                
                    $returnValue.Type.Name
                    [Environment]::NewLine
                }
            }
        }
        Syntax = {
            if ($helpObject.syntax.syntaxItem) {
                Format-Markdown -Heading "Syntax" -HeadingSize 3
                if ($helpObject.Rename) {
                    ($helpObject.syntax | Out-String) -split '(?>\r\n|\n)' -ne '' -replace "$($HelpObject.Name.Replace("\", "\\"))", $helpObject.Rename | Format-Markdown -CodeLanguage PowerShell
                } else {
                    ($helpObject.syntax | Out-String) -split '(?>\r\n|\n)' -ne '' | Format-Markdown -CodeLanguage PowerShell
                }
            }
        }
        Notes = {
            if ($helpObject.alertSet) {
                Format-Markdown -Heading "Notes" -HeadingSize 3
                foreach ($note in $helpObject.AlertSet.alert) {
                    ($note | Out-String).Trim() + [Environment]::NewLine
                }
            }
        }
    }

    @(
        $orderOfSections = @(if ($helpObject.SectionOrder) {
            $helpObject.SectionOrder
        } else {
            $MarkdownSections.Keys
        })

        $sectionCounter = 0 
        foreach ($sectionName in $orderOfSections) {
            $sectionCounter++
            $sectionContent = 
                if ($MarkdownSections.$sectionName -is [ScriptBlock]) {
                    & $MarkdownSections.$sectionName
                } else { $null }
            if ($sectionContent) {
                $sectionContent
                if ($sectionCounter -lt $orderOfSections.Length -and $sectionContent -notmatch '---\s{0,}$') { 
                    '---'
                }
            }
        }

    ) -join [Environment]::NewLine
}
 