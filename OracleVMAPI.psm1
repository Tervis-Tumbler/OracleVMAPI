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
            Invoke-RestMethod -Uri $URL -Method Get -Headers $headers -UseBasicParsing -verbose
        }
        if($Method -eq "PUT"){
            Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body $InputJSON -UseBasicParsing -verbose
        }
        if($Method -eq "POST"){
            Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $InputJSON -UseBasicParsing -verbose
        }
        if($Method -eq "DELETE"){
            Invoke-RestMethod -Uri $url -Method DELETE -Headers $headers -Body $InputJSON -UseBasicParsing -verbose
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
            Invoke-OracleVMManagerAPICall -Method GET -URIPath "/Vm/$VMID"
        }
        Else{
            $VMListing = Invoke-OracleVMManagerAPICall -Method get -URIPath "/Vm"
            if ($Name){
                $VMListing | where name -eq $Name
            }
            else {
                $VMListing
            }
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
        [parameter(ValueFromPipelineByPropertyName,ParameterSetName="ByID")][switch]$Transcript
    )
    process{
        if ($PSCmdlet.ParameterSetName -eq "ByID"){
            $URIPath = "/Job/$JobID"
            if($Transcript){
                $URIPath += "/transcript"
            }
        }
        if ($PSCmdlet.ParameterSetName -eq "AllJobs"){
            $URIPath = "/Job/id?startTime=$StartTime&endTime=$EndTime&maxJobs=$MaxJobs"
        }
        if ($PSCmdlet.ParameterSetName -eq "ActiveJobs"){
            $URIPath = "/Job/active"
        }
        Invoke-OracleVMManagerAPICall -Method GET -URIPath $URIPath
    }
}

function New-OVMVirtualMachineClone {
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$TemplateID,
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$Name,
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$ServerPoolID,
        [parameter(ValueFromPipelineByPropertyName)]$RepositoryID,
        [parameter(ValueFromPipelineByPropertyName)]$VMCloneDefinitionID
    )
    process{
        $URIPath = "/Vm/$TemplateID/clone?serverPoolId=$ServerPoolID&createTemplate=false"
        
        if($RepositoryID){
            $URIPath += "&repositoryId=$RepositoryID"
        }
        if($VMCloneDefinitionID){
            $URIPath += "&vmCloneDefinitionId=$VMCloneDefinitionID&createTemplate=false"
        }
        $CloneResult = Invoke-OracleVMManagerAPICall -Method PUT -URIPath $URIPath
        do{
            Start-Sleep 1
            $CloneJob = Get-OVMJob -JobID $CloneResult.id.value
        }while($CloneJob.done -eq $false)
        $ClonedVirtualMachine = Get-OVMVirtualMachines -ID $CloneJob.resultId.value    
        New-OVMVirtualNIC -VMID $ClonedVirtualMachine.id.value
        Start-OVMVirtualMachine -VMID $ClonedVirtualMachine.id.value
        New-OVMVirtualMachineConsole -Name $ClonedVirtualMachine.id.name
        Start-Sleep -Seconds 60

        $InitialConfigJSON = [pscustomobject][ordered]@{
            key = "com.oracle.linux.network.bootproto.0"
            value = "dhcp"
        },
        [pscustomobject][ordered]@{
            key = "com.oracle.linux.network.onboot.0"
            value = "yes"
        },
        [pscustomobject][ordered]@{
            key = "com.oracle.linux.network.device.0"
            value = "eth0"
        },
        [pscustomobject][ordered]@{
            key = "com.oracle.linux.root-password"
            value = $RootPassword
        },
        [pscustomobject][ordered]@{
            key = "com.oracle.linux.network.hostname"
            value = "$Hostname"
        },
        [pscustomobject][ordered]@{
            key = "com.oracle.linux.network.host.0"
            value = $Hostname
        } | convertto-json
        Invoke-OVMSendMessagetoVM -VMID $vm.id.value -JSON $InitialConfigJSON
    
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
    param(
        [parameter(mandatory)]$VMID,
        [switch]$DeleteVirtualDisks,
        [switch]$ASync
        
    )
    $VM = Get-OVMVirtualMachines -ID $VMID
    $VirtualDisks = $VM.vmDiskMappingIds.value | %{Get-OVMVirtualDisk -VMDiskMappingID $_}
    $ResultantJob = Invoke-OracleVMManagerAPICall -Method DELETE -URIPath "/Vm/$VMID"
    if(-not $ASync){
        do{
            Start-Sleep 1
            $ResultantJob = Get-OVMJob -JobID $ResultantJob.id.value
        }while($ResultantJob.done -eq $false)
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
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$VirtualDiskID,
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$RepositoryID,
        [switch]$ASync
    )
    $ResultantJob = Invoke-OracleVMManagerAPICall -Method DELETE -URIPath "/Repository/$RepositoryID/VirtualDisk/$VirtualDiskId"
    if(-not $ASync){
        do{
            Start-Sleep 1
            $ResultantJob = Get-OVMJob -JobID $ResultantJob.id.value
        }while($ResultantJob.done -eq $false)
    }
    $ResultantJob
}

function Start-OVMVirtualMachine {
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$VMID
    )
    process{
        Invoke-OracleVMManagerAPICall -Method put `
        -URIPath "/Vm/$VMID/start" `
    }
}

function Stop-OVMVirtualMachine {
    param(
        [parameter(ValueFromPipelineByPropertyName,mandatory)]$VMID
    )
    process{
        Invoke-OracleVMManagerAPICall -Method put `
        -URIPath "/Vm/$VMID/Stop" `
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
            if ($Name){
                $NetworkList | where name -eq $Name
            }
            else {
                $NetworkList
            }
        }
    }
}

function New-OVMVirtualNIC {
    [CmdletBinding()]
    param(
        [parameter(ValueFromPipelineByPropertyName,Mandatory)]$VMID
#        [parameter(ValueFromPipelineByPropertyName,Mandatory)]$NetworkName,
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
        $NewVMNICJobresult
        if(-not $ASync){
            do{
                Start-Sleep 1
                $ResultantJob = Get-OVMJob -JobID $NewVMNICJobresult.id.value
            }while($ResultantJob.done -eq $false)    
        }
        $ResultantJob
    }
}
