function Invoke-OracleVMManagerAPICall{
    param(
        [parameter(ValueFromPipelineByPropertyName,Mandatory)]$Method,
        [parameter(ValueFromPipelineByPropertyName,Mandatory)]$URIPath,
        $InputJSON
    )
    begin{
        $OVMManagerPasswordstateEntryDetails = Get-PasswordstateEntryDetails -PasswordID 4157
        $username = $OVMManagerPasswordstateEntryDetails.Username
        $password = $OVMManagerPasswordstateEntryDetails.Password
        $URL = "https://" + ([System.Uri]$OVMManagerPasswordstateEntryDetails.url).Authority + "/ovm/core/wsapi/rest" + $URIPath
        add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate,
                                      WebRequest request, int certificateProblem) {
        return true;
    }
 }
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        $credPair = "$($username):$($password)"
        $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add('Authorization',"Basic $encodedCredentials")
        $headers.Add('Accept',"application/json")
        $headers.Add('Content-Type',"application/json")
    }
    process{
        if($Method -eq "GET"){
            Invoke-RestMethod -Uri $URL -Method Get -Headers $headers -UseBasicParsing #-verbose
        }
        else{
            Invoke-RestMethod -Uri $url -Method $Method -Headers $headers -Body $InputJSON -UseBasicParsing #-verbose
        }
    }
}

function Get-OVMVirtualMachines {
    [CmdletBinding(DefaultParameterSetName="__AllParameterSets")]
    param(
        [parameter(ValueFromPipelineByPropertyName,Mandatory,ParameterSetName="Name")]$Name,
        [parameter(ValueFromPipelineByPropertyName,Mandatory,ParameterSetName="ID")]$ID
    )
    process{
        if ($ID){
            Invoke-OracleVMManagerAPICall -Method GET -URIPath "/Vm/$ID"
        }
        Else{
            $VMListing = Invoke-OracleVMManagerAPICall -Method get -URIPath "/Vm"
            $VMListing | where{-not $Name -or $_.name -eq $name}
        }
    }
}

function Invoke-OVMSendMessagetoVM {
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$VMID,
        [parameter(Mandatory,ValueFromPipeline)]$JSON
    )
    process{
        Invoke-OracleVMManagerAPICall -Method put `
        -URIPath "/Vm/$VMID/sendMessage?logFlag=Yes" `
        -InputJSON $JSON
    }
}

function Get-OVMMessagesFromVM {
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$VMID
    )
    process{
        Invoke-OracleVMManagerAPICall -Method GET -URIPath "/Vm/$VMID/messages"
    }
}

function Get-OVMJob {
    param(
        [parameter(ValueFromPipelineByPropertyName,ParameterSetName="ByID")]$JobID,
        [parameter(ValueFromPipelineByPropertyName,ParameterSetName="AllJobs")]$StartTime,
        [parameter(ValueFromPipelineByPropertyName,ParameterSetName="AllJobs")]$EndTime,
        [parameter(ValueFromPipelineByPropertyName,ParameterSetName="AllJobs")]$MaxJobs,
        [parameter(ValueFromPipelineByPropertyName,ParameterSetName="ActiveJobs")][switch]$Active,
        [parameter(ValueFromPipelineByPropertyName,ParameterSetName="ByID")][switch]$WaitToComplete
    )
    process{
        if ($PSCmdlet.ParameterSetName -eq "ByID"){
            $URIPath = "/Job/$JobID"
            if($WaitToComplete){
                do{
                    $Job = Invoke-OracleVMManagerAPICall -Method GET -URIPath $URIPath
                    Write-Progress -Activity $Job.name -status $Job.jobRunState
                    Start-Sleep 1
                }while($Job.done -eq $false)
            }
        }
        if ($PSCmdlet.ParameterSetName -eq "AllJobs"){
            $URIPath = "/Job/id?startTime=$StartTime&endTime=$EndTime&maxJobs=$MaxJobs"
            Invoke-OracleVMManagerAPICall -Method GET -URIPath $URIPath
        }
        if ($PSCmdlet.ParameterSetName -eq "ActiveJobs"){
            $URIPath = "/Job/active"
            Invoke-OracleVMManagerAPICall -Method GET -URIPath $URIPath
        }
        Invoke-OracleVMManagerAPICall -Method GET -URIPath $URIPath
    }
}

function New-OVMVirtualMachineClone {
    param(
        [Parameter(Mandatory)]
        [ValidateLength(1,11)]
        [ValidateScript({ Test-ShouldBeAlphaNumeric -Name VMNameWithoutEnvironmentPrefix -String $_ })]
        [String]$VMNameWithoutEnvironmentPrefix,

#        [Parameter(Mandatory)]
#        [ValidateSet("Windows Server 2012 R2"�,"Windows Server 2012","Windows Server 2008 R2", "PerfSonar", "CentOS 7","Windows Server 2016","VyOS","Arch Linux","OEL-75-Template")]
        [String]$VMOperatingSystemTemplateName,
        
#        [Parameter(Mandatory)]
#        [ValidateSet("�Delta"�,"Epsilon"�,"Production","Infrastructure")]
#        [ValidateScript({$_ -in $(Get-TervisEnvironmentName) })]
        
        [Parameter(Mandatory)]
        [String]$EnvironmentName
    )
    process{
        $ServerPoolID = "0004fb000002000029e778af2539d7ca"
        $VMTemplate = Get-OVMVirtualMachines -Name $VMOperatingSystemTemplateName
        $VMTemplateId = $VMTemplate.id.value
        $VMName = Get-TervisVMName -VMNameWithoutEnvironmentPrefix $VMNameWithoutEnvironmentPrefix -Environmentname $EnvironmentName
        
        $URIPath = "/Vm/$VMTemplateID/clone?serverPoolId=$ServerPoolID&createTemplate=false"
        
        if($RepositoryID){
            $URIPath += "&repositoryId=$RepositoryID"
        }
        if($VMCloneDefinitionID){
            $URIPath += "&vmCloneDefinitionId=$VMCloneDefinitionID&createTemplate=false"
        }
        $CloneJob = Invoke-OracleVMManagerAPICall -Method PUT -URIPath $URIPath
        $CompletedCloneJob = Get-OVMJob -JobID $CloneJob.id.value -WaitToComplete
        $ClonedVirtualMachine = Get-OVMVirtualMachines -ID $CompletedCloneJob.resultId.value    
#        Get-OVMJob -JobID ((Rename-OVMVirtualMachine -VMID $clonedvirtualmachine.id.value -NewName $VMName).id.value)
        (Rename-OVMVirtualMachine -VMID $clonedvirtualmachine.id.value -NewName $VMName).id.value | Out-Null
        $FinalVM = Get-OVMVirtualMachines -ID $ClonedVirtualMachine.id.value
        $FinalVM
    }
}

function Get-OVMDiskMapping {
    param(
        [parameter(ValueFromPipelineByPropertyName)]$DiskMappingID
    )
    process{
        if ($DiskMappingID){
            Invoke-OracleVMManagerAPICall -Method GET -URIPath "/VmDiskMapping/$DiskMappingID"
        }
        else {
            Invoke-OracleVMManagerAPICall -Method GET -URIPath "/VmDiskMapping"
        }
    }
}
function Get-OVMVirtualDisk {
    [CmdletBinding(DefaultParameterSetName="__AllParameterSets")]
    param(
        [parameter(ValueFromPipelineByPropertyName,ParameterSetName="VirtualDiskID")]$VirtualDiskID,
        [parameter(ValueFromPipelineByPropertyName,ParameterSetName="VMDiskMappingID")]$VMDiskMappingID
    )
    process{
        if ($VmDiskMappingID){
            (Invoke-OracleVMManagerAPICall -Method GET -URIPath "/VmDiskMapping/$VmDiskMappingID/VirtualDisk") | Where diskType -eq "VIRTUAL_DISK"
        }
        elseif ($VirtualDiskID) {
            (Invoke-OracleVMManagerAPICall -Method GET -URIPath "/VirtualDisk/$VirtualDiskID") | Where diskType -eq "VIRTUAL_DISK"
        }
        else {(Invoke-OracleVMManagerAPICall -Method GET -URIPath "/VirtualDisk") | Where diskType -eq "VIRTUAL_DISK" }
    }
}

function Rename-OVMVirtualMachine {
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$VMID,
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$NewName,
        $Description,
        [switch]$ASync
    )
    process{
        $VM = Get-OVMVirtualMachines -ID $VMID
        
        $VM.name = $NewName
        if($description){
            $VM.description = $Description
        }
        $RenameJSON = $VM | ConvertTo-Json
        $ResultantJob = Invoke-OracleVMManagerAPICall -Method put -URIPath "/Vm/$($VM.ID.Value)" -InputJSON $RenameJSON
        if(-not $ASync){
            do{
                Start-Sleep 1
                $ResultantJob = Get-OVMJob -JobID $ResultantJob.id.value
            }while($ResultantJob.done -eq $false)    
        }
        $ResultantJob
    }
}

function Remove-OVMVirtualMachine {
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact="High"
    )]
    param(
#        [parameter(mandatory)]$VMID,
        [parameter(Mandatory, ValueFromPipeline)]$VM,
        [switch]$DeleteVirtualDisks,
        [switch]$ASync
        
    )
    $VM = Get-OVMVirtualMachines -ID $VM.ID.value
    $VirtualDisks = $VM.vmDiskMappingIds.value | %{Get-OVMVirtualDisk -VMDiskMappingID $_}
    if ($PSCmdlet.ShouldProcess($VM.Name)){
        $ResultantJob = Invoke-OracleVMManagerAPICall -Method DELETE -URIPath "/Vm/$($VM.ID.value)"
        if(-not $ASync){
            do{
                Start-Sleep 1
                $ResultantJob = Get-OVMJob -JobID $ResultantJob.id.value
            }while($ResultantJob.done -eq $false)
        }   
    }   
    if($DeleteVirtualDisks){
            $VirtualDisks | %{$ResultantJob = Remove-OVMVirtualDisk -VirtualDiskID $_.id.value -RepositoryID $_.repositoryid.value
                if(-not $ASync){
                    do{
                        Start-Sleep 1
                        $ResultantJob = Get-OVMJob -JobID $ResultantJob.id.value
                    }while($ResultantJob.done -eq $false)
                }
            }
    }
}

function Remove-OVMVirtualDisk {
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact="High"
    )]
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$VirtualDiskID,
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$RepositoryID,
        [switch]$ASync
    )
    if ($PSCmdlet.ShouldProcess($VirtualDiskID)){
        $ResultantJob = Invoke-OracleVMManagerAPICall -Method DELETE -URIPath "/Repository/$RepositoryID/VirtualDisk/$VirtualDiskId"
        if(-not $ASync){
            do{
                Start-Sleep 1
                $ResultantJob = Get-OVMJob -JobID $ResultantJob.id.value
            }while($ResultantJob.done -eq $false)
        }
    }   
    $ResultantJob
}

function Start-OVMVirtualMachine {
    param(
        [parameter(ValueFromPipelineByPropertyName,Mandatory,ParameterSetName="Name")]$Name,
        [parameter(ValueFromPipelineByPropertyName,Mandatory,ParameterSetName="ID")]$ID
    )
    process{
        if ($ID){
            $Job = Invoke-OracleVMManagerAPICall -Method put -URIPath "/Vm/$ID/start"
        }
        Elseif($Name){
            $VM = Get-OVMVirtualMachines | where name -eq $Name
            $Job = Invoke-OracleVMManagerAPICall -Method put -URIPath "/Vm/$($VM.id.value)/start"
        }
        Get-OVMJob -JobID $Job.id.value -WaitToComplete
    }
}

function Stop-OVMVirtualMachine {
    param(
        [parameter(ValueFromPipelineByPropertyName,Mandatory,ParameterSetName="Name")]$Name,
        [parameter(ValueFromPipelineByPropertyName,Mandatory,ParameterSetName="ID")]$ID
    )
    process{
        if ($ID){
            $Job = Invoke-OracleVMManagerAPICall -Method put -URIPath "/Vm/$VMID/stop"
        }
        Elseif($Name){
            $VM = Get-OVMVirtualMachines | where name -eq $Name
            $Job = Invoke-OracleVMManagerAPICall -Method put -URIPath "/Vm/$($VM.id.value)/stop"
        }
        Get-OVMJob -JobID $Job.id.value -WaitToComplete
    }
}

function New-OVMVirtualMachineConsole {
    [CmdletBinding()]
    param(
    )
    DynamicParam {
        $ParameterName = 'Name'
        $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
        $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
        $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
        $ParameterAttribute.Mandatory = $true
        $ParameterAttribute.Position = 4
        $AttributeCollection.Add($ParameterAttribute)
        $arrSet = Get-OVMVirtualMachines | where vmRunState -ne "TEMPLATE" | select name -ExpandProperty name
        $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)
        $AttributeCollection.Add($ValidateSetAttribute)
        $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
        $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
        return $RuntimeParameterDictionary
    }
    begin {
        $Name = $PsBoundParameters[$ParameterName]
    }

    process{
        $OVMManagerPasswordstateEntryDetails = Get-PasswordstateEntryDetails -PasswordID 4157
        $VM = Get-OVMVirtualMachines -Name $Name
        $ConsoleURLPath = Invoke-OracleVMManagerAPICall -Method GET `
        -URIPath "/Vm/$($VM.id.value)/vmConsoleUrl"
        $ConsoleURL = "https://" + ([System.Uri]$OVMManagerPasswordstateEntryDetails.url).Authority + $ConsoleURLPath
        Start-Process -filePath $ConsoleURL
    }
}

function Get-OVMNetwork {
    [CmdletBinding(DefaultParameterSetName="__AllParameterSets")]
    param(
        [parameter(ValueFromPipelineByPropertyName,ParameterSetName="Name")]$Name,
        [parameter(ValueFromPipelineByPropertyName,ParameterSetName="ID")]$ID
    )
    process{
        if ($ID){
            Invoke-OracleVMManagerAPICall -Method GET -URIPath "/Network/$ID"
        }
        Else{
            $NetworkList = Invoke-OracleVMManagerAPICall -Method get -URIPath "/Network" 
            $NetworkList | where{-not $Name -or $_.name -eq $name}
        }
    }
}

function New-OVMVirtualNIC {
    [CmdletBinding()]
    param(
        [parameter(ValueFromPipelineByPropertyName,Mandatory)]$VMID
    )
        DynamicParam {
            $ParameterName = 'Network'
            $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
            $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
            $ParameterAttribute.Mandatory = $true
            $ParameterAttribute.Position = 4
            $AttributeCollection.Add($ParameterAttribute)
            $arrSet = Get-OVMNetwork | select Name -ExpandProperty Name
            $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)
            $AttributeCollection.Add($ValidateSetAttribute)
            $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
            $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
            return $RuntimeParameterDictionary
    }
    begin {
        $NetworkName = $PsBoundParameters[$ParameterName]
    }
    process{
        $VMNetwork = Get-OVMNetwork -Name $NetworkName
        $NewVMNICObject = [pscustomobject][ordered]@{
            name = $NetworkName
            description = ""
            networkId = [pscustomobject][ordered]@{
                type = $vmnetwork.id.type
                value = $vmnetwork.id.value
                uri = $vmnetwork.id.uri
                name = $vmnetwork.id.name
            }
        }
        $JSON = $NewVMNICObject | convertto-json
    
        $NewVMNICJob = Invoke-OracleVMManagerAPICall -Method POST -URIPath "/Vm/$VMID/VirtualNic"  -InputJSON $Json
        $NewVMNICJobresult = Get-OVMJob -JobID $NewVMNICJob.id.value
        Get-OVMJob -JobID $NewVMNICJobresult.id.value -WaitToComplete
    }
}

function Get-OVMVirtualNic {
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$VirtualNicID
    )
    process{
        Invoke-OracleVMManagerAPICall -Method GET `
        -URIPath "/VirtualNic/$VirtualNicID" `
    }
}

function Get-OVMVirtualNicMacAddress {
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$VirtualNicID
    )
    process{
        (Get-OVMVirtualNic -VirtualNicID $VirtualNicID).macAddress
    }
}

function Get-OVMManagerStatus {
    $Result = Invoke-OracleVMManagerAPICall -Method GET -URIPath "/Manager" 
    $Result | select Name,managerRunState,locked
}

function Set-OVMVirtualMachineCPUPinning {
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$VMID,
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$CPUs,
        [switch]$ASync
    )
    process{
        $VM = Get-OVMVirtualMachines -ID $VMID
        $VM.pinnedCPUs = $CPUs
        $RenameJSON = $VM | ConvertTo-Json
        $ResultantJob = Invoke-OracleVMManagerAPICall -Method put -URIPath "/Vm/$($VM.ID.Value)" -InputJSON $RenameJSON
        if(-not $ASync){
            do{
                Start-Sleep 1
                $ResultantJob = Get-OVMJob -JobID $ResultantJob.id.value
            }while($ResultantJob.done -eq $false)    
        }
        $ResultantJob
    }
}