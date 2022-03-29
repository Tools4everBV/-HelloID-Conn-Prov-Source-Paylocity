[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

Write-Information "Processing Persons"

#region Configuration
$config = ConvertFrom-Json $configuration
#endregion Configuration

#region Support Functions
function Get-AuthToken {
    [cmdletbinding()]
    Param (
        [string]$BaseUri,
        [string]$TokenURI,
        [string]$ClientKey,
        [string]$ClientSecret,
        [string]$PageSize,
        [string]$scope
    )
    Process {
        $requestUri = "{0}{1}" -f $BaseURI, $TokenURI
        $pair = "{0}:{1}" -f $ClientKey, $ClientSecret
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $bear_token = [System.Convert]::ToBase64String($bytes)
        $headers = @{
            Authorization = "Basic {0}" -f $bear_token
            Accept        = "application/json"
        }
        $parameters = @{grant_type = "client_credentials"; scope = $scope }
        Write-Information ("POST {0}" -f $requestUri)
        $splat = @{
            Method  = 'POST'
            URI     = $requestUri
            Body    = $parameters
            Headers = $headers
            Verbose = $false
        }

        $response = Invoke-RestMethod @splat
        
        $accessToken = $response.access_token
        
        #Add the authorization header to the request
        $authorization = @{
            Authorization  = "Bearer {0}" -f $accesstoken
            'Content-Type' = "application/json"
            Accept         = "application/json"
        }
        $authorization
    }
}

function Get-ObjectProperties 
{
    [cmdletbinding()]
    param (
        [object]$Object, 
        [int]$Depth = 0, 
        [int]$MaxDepth = 10
    )
    $OutObject = @{};

    foreach($prop in $Object.PSObject.properties)
    {
        if ($prop.TypeNameOfValue -eq "System.Management.Automation.PSCustomObject" -or $prop.TypeNameOfValue -eq "System.Object" -and $Depth -lt $MaxDepth)
        {
            $OutObject[$prop.Name] = Get-ObjectProperties -Object $prop.Value -Depth ($Depth + 1);
        }
        else
        {
            $OutObject[$prop.Name] = "$($prop.Value)";
        }
    }
    return $OutObject;
}

#endregion Support Functions


#Get Authorization
$splat = @{
    BaseURI      = $config.BaseURI
    TokenUri     = $config.TokenUri
    ClientKey    = $config.ClientKey
    ClientSecret = $config.ClientSecret
    PageSize     = $config.PageSize
    scope        = $config.scope
}
$AuthToken = Get-AuthToken @splat

#Get Employee List
$uri = "https://api.paylocity.com/api/v2/companies/$($config.companyID)/employees?pageSize=$($config.PageSize)&pageNumber=0"

while($uri -ne $null)
{
    Write-Information "Fetching - $($uri)"
    $list = Invoke-WebRequest -Uri $uri  -Headers $AuthToken
    $uri = $null

    if($list.Headers.Link -ne $null)
    {
        foreach ($header in $list.Headers.Link.split(",") ) 
        {
            if($header -like "*rel='next'*")
            {
                $uri = $header.split(';')[0]
                $uri = $uri.replace("<",'').replace(">",'')
            }
        }
    }

}


#Get Employee Details, Export Person Data
foreach ($employee in ($list.Content | ConvertFrom-Json)) 
{
    $uri = "https://api.paylocity.com/api/v2/companies/$($config.companyID)/employees/$($employee.employeeID)"
    Write-Information "Fetching - $($uri)"
    $details = Invoke-RestMethod -Uri $uri -Headers $AuthToken
    
    $person = @{};
    $person = Get-ObjectProperties -Object $details;

    $person["ExternalId"] = $employee.'employeeId';
    $person["DisplayName"] = "$($details.firstName) $($details.lastName) ($($person.ExternalId))"
    $person["Role"] = "Employee"
    $person["StatusCode"] = $employee.statusCode
    $person["StatusTypeCode"] = $employee.statusTypeCode

    $person["Contracts"] = [System.Collections.ArrayList]@();

    $contract = $person.PsObject.Copy()
    [void]$person.Contracts.Add($contract)

    $person | ConvertTo-Json -Depth 10
}

Write-Information "Finished Processing Persons"