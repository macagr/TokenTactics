function Parse-JWTtoken {
    <#
    .DESCRIPTION
        Parse JWTtoken code from https://www.michev.info/Blog/Post/2140/decode-jwt-access-and-id-tokens-via-powershell
    .EXAMPLE
        Parse-JWTtoken -Token ey....
    #>
    [cmdletbinding()]
    param([Parameter(Mandatory=$true)][string]$token)
 
    if (!$token.Contains(".") -or !$token.StartsWith("eyJ")) { Write-Error "Invalid token" -ErrorAction Stop }

    $tokenheader = $token.Split(".")[0].Replace('-', '+').Replace('_', '/')

    while ($tokenheader.Length % 4) { 
		$tokenheader += "=" 
	}
    [System.Text.Encoding]::ASCII.GetString([system.convert]::FromBase64String($tokenheader)) | ConvertFrom-Json | fl | Out-Default
 
    $tokenPayload = $token.Split(".")[1].Replace('-', '+').Replace('_', '/')
	
    while ($tokenPayload.Length % 4) { 
		$tokenPayload += "=" 
	}

    $tokenByteArray = [System.Convert]::FromBase64String($tokenPayload)
    $tokenArray = [System.Text.Encoding]::ASCII.GetString($tokenByteArray)

    $tokobj = $tokenArray | ConvertFrom-Json
    return $tokobj
}

function Get-AzureToken {
    <#
    .DESCRIPTION
        Generate a device code to be used at https://www.microsoft.com/devicelogin. Once a user has successfully authenticated, you will be presented with a JSON Web Token JWT in the variable $response.
    .EXAMPLE
        Get-AzureToken -Client Substrate
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$True)]
        [String[]]
        [ValidateSet("Outlook","Teams","Graph","Core","Webshell","MSGraph","Custom","Substrate")]
        $Client,
        [Parameter(Mandatory=$False)]
        [String]
        $ClientID = "d3590ed6-52b3-4102-aeff-aad2292ab01c",    
        [Parameter(Mandatory=$False)]
        [String]
        $Resource = "https://graph.microsoft.com"
        
    )
    
    if($Client -eq "Outlook") {

        $body=@{
            "client_id" = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
            "resource" =  "https://outlook.office365.com"
        }
    }
    elseif ($Client -eq "Substrate") {

        $body=@{
            "client_id" = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
            "resource" =  "https://substrate.office.com"
        }
    }
    elseif ($Client -eq "Custom") {

        $body=@{
            "client_id" = $ClientID
            "resource" =  $Resource
        }
    }
    elseif ($Client -eq "Teams") {
        
        $body = @{
            "client_id" =     "d3590ed6-52b3-4102-aeff-aad2292ab01c"
            "resource" =      "https://api.spaces.skype.com"   
        }
    }
    elseif ($Client -eq "Graph") {
        
        $body = @{
            "client_id" =     "d3590ed6-52b3-4102-aeff-aad2292ab01c"
            "resource" =      "https://graph.windows.net"  
        }
    }
    elseif ($Client -eq "MSGraph") {
        
        $body = @{
            "client_id" =     "d3590ed6-52b3-4102-aeff-aad2292ab01c"
            "resource" =      "https://graph.microsoft.com"  
        }
    }
    elseif ($Client -eq "Webshell") {
        
        $body = @{
            "client_id" =     "89bee1f7-5e6e-4d8a-9f3d-ecd601259da7"
            "resource" =      "https://webshell.suite.office.com"  
        }
    }
    
    elseif ($Client -eq "Core") {
        
        $body = @{
            "client_id" =     "d3590ed6-52b3-4102-aeff-aad2292ab01c"
            "resource" =      "https://management.core.windows.net"
        }
    }

    # Login Process
    $authResponse = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "https://login.microsoftonline.com/common/oauth2/devicecode?api-version=1.0" -Body $body
    write-output $authResponse
    $continue = $true
    $interval = $authResponse.interval
    $expires =  $authResponse.expires_in
    $body=@{
        "client_id" =  $ClientID
        "grant_type" = "urn:ietf:params:oauth:grant-type:device_code"
        "code" =       $authResponse.device_code
    }
    while($continue)
    {
        Start-Sleep -Seconds $interval
        $total += $interval

        if($total -gt $expires)
        {
            Write-Error "Timeout occurred"
            return
        }          
        # Try to get the response. Will give 40x while pending so we need to try&catch
        try
        {
            $global:response = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "https://login.microsoftonline.com/Common/oauth2/token?api-version=1.0 " -Body $body -ErrorAction SilentlyContinue
        }
        catch
        {
            # This is normal flow, always returns 40x unless successful
            $details=$_.ErrorDetails.Message | ConvertFrom-Json
            $continue = $details.error -eq "authorization_pending"
            Write-Output $details.error

            if(!$continue)
            {
                # Not pending so this is a real error
                Write-Error $details.error_description
                return
            }
        }

        # If we got response, all okay!
        if($response)
        {
            write-output $response
            $jwt = $response.access_token
            
            $output = Parse-JWTtoken -token $jwt
            $global:upn = $output.upn
            write-output $upn
            break
        }
    }
}
# Refresh Token Functions
function RefreshTo-SubstrateToken {
    <#
    .DESCRIPTION
        Generate a Substrate token from a refresh token.
    .EXAMPLE
        RefreshTo-SubstrateToken -domain myclient.org -refreshToken ey....
        $SubstrateToken.access_token
    #>

    [cmdletbinding()]
    Param([Parameter(Mandatory=$true)]
    [string]$domain,
    [Parameter(Mandatory=$false)]
    [string]$refreshToken = $response.refresh_token
    )
    $Resource = "https://substrate.office.com"
    $ClientId = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
    $TenantId = Get-TenantID -domain $domain
    $authUrl = "https://login.microsoftonline.com/$($TenantId)"
    
    Write-Output $refreshToken
    $body = @{
        "resource" =      $Resource
        "client_id" =     $ClientId
        "grant_type" =    "refresh_token"
        "refresh_token" = $refreshToken
        "scope" = "openid"
    }

    $global:SubstrateToken = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "$($authUrl)/oauth2/token?api-version=1.0 " -Body $body
    Write-Output $SubstrateToken
}
function RefreshTo-MSManageToken {
    <#
    .DESCRIPTION
        Generate a manage token from a refresh token.
    .EXAMPLE
        RefreshTo-MSManage -domain myclient.org -refreshToken ey....
        $MSManageToken.access_token
    #>
    [cmdletbinding()]
    Param([Parameter(Mandatory=$true)]
    [string]$domain,
    [Parameter(Mandatory=$false)]
    [string]$refreshToken = $response.refresh_token
    )
    $Resource = "https://enrollment.manage.microsoft.com"
    $ClientId = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
    $TenantId = Get-TenantID -domain $domain
    $authUrl = "https://login.microsoftonline.com/$($TenantId)"
    
    Write-Output $refreshToken
    $body = @{
        "resource" =      $Resource
        "client_id" =     $ClientId
        "grant_type" =    "refresh_token"
        "refresh_token" = $refreshToken
        "scope" = "openid"
    }

    $global:MSManageToken = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "$($authUrl)/oauth2/token?api-version=1.0 " -Body $body
    Write-Output $MSManageToken
}
function RefreshTo-MSTeamsToken {
    <#
    .DESCRIPTION
        Generate a Microsoft Teams token from a refresh token.
    .EXAMPLE
        RefreshTo-MSTeamsToken -domain myclient.org -refreshToken ey....
        $MSTeamsToken.access_token
    #>
    [cmdletbinding()]
    Param([Parameter(Mandatory=$true)]
    [string]$domain,
    [Parameter(Mandatory=$false)]
    [string]$refreshToken = $response.refresh_token
    )
    $Resource = "https://api.spaces.skype.com"
    $ClientId = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
    $TenantId = Get-TenantID -domain $domain
    $authUrl = "https://login.microsoftonline.com/$($TenantId)"
    
    Write-Output $refreshToken
    $body = @{
        "resource" =      $Resource
        "client_id" =     $ClientId
        "grant_type" =    "refresh_token"
        "refresh_token" = $refreshToken
        "scope" = "openid"
    }

    $global:MSTeamsToken = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "$($authUrl)/oauth2/token?api-version=1.0 " -Body $body
    Write-Output $MSTeamsToken
}
function RefreshTo-ManageOfficeToken {
    <#
    .DESCRIPTION
        Generate a Office Manage token from a refresh token.
    .EXAMPLE
        RefreshTo-ManageOfficeToken -domain myclient.org -refreshToken ey....
        $ManageOfficeToken.access_token
    #>
    [cmdletbinding()]
    Param([Parameter(Mandatory=$true)]
    [string]$domain,
    [Parameter(Mandatory=$false)]
    [string]$refreshToken = $response.refresh_token
    )
    $Resource = "https://manage.office.com"
    $ClientId = "00b41c95-dab0-4487-9791-b9d2c32c80f2"
    $TenantId = Get-TenantID -domain $domain
    $authUrl = "https://login.microsoftonline.com/$($TenantId)"
    $global:refreshToken = $response.refresh_token 
    
    $body = @{
        "resource" = $Resource
        "client_id" =     $ClientId
        "grant_type" =    "refresh_token"
        "refresh_token" = $refreshToken
        "scope"=         "openid"
    }

    $global:OfficeManagementToken = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "$($authUrl)/oauth2/token?api-version=1.0 " -Body $body
    Write-Output $OfficeManagementToken
}
function RefreshTo-OutlookToken {
    <#
    .DESCRIPTION
        Generate a Microsoft Outlook token from a refresh token.
    .EXAMPLE
        RefreshTo-OutlookToken -domain myclient.org -refreshToken ey....
        $OutlookToken.access_token
    #>
    [cmdletbinding()]
    Param([Parameter(Mandatory=$true)]
    [string]$domain,
    [Parameter(Mandatory=$false)]
    [string]$refreshToken = $response.refresh_token
    )
    $Resource = "https://outlook.office365.com"
    $ClientId = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
    $TenantId = Get-TenantID -domain $domain
    $authUrl = "https://login.microsoftonline.com/$($TenantId)"
    $global:refreshToken = $response.refresh_token 
    
    $body = @{
        "resource" = $Resource
        "client_id" =     $ClientId
        "grant_type" =    "refresh_token"
        "refresh_token" = $refreshToken
        "scope"=         "openid"
    }

    $global:OutlookToken = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "$($authUrl)/oauth2/token?api-version=1.0 " -Body $body
    Write-Output $OutlookToken
}
function RefreshTo-MSGraphToken {
    <#
    .DESCRIPTION
        Generate a Microsoft Graph token from a refresh token.
    .EXAMPLE
        RefreshTo-MSGraphToken -domain myclient.org -refreshToken ey....
        $MSGraphToken.access_token
    #>
    [cmdletbinding()]
    Param([Parameter(Mandatory=$true)]
    [string]$domain,
    [Parameter(Mandatory=$false)]
    [string]$refreshToken = $response.refresh_token,
    [Parameter(Mandatory=$false)]
    [string]$ClientID = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
    )
      
    $Resource = "https://graph.microsoft.com"
    $ClientId = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
    $TenantId = Get-TenantID -domain $domain
    $authUrl = "https://login.microsoftonline.com/$($TenantId)"
    $global:refreshToken = $response.refresh_token 
    
    $body = @{
        "resource" = $Resource
        "client_id" =     $ClientId
        "grant_type" =    "refresh_token"
        "refresh_token" = $refreshToken
        "scope"=         "openid"
    }

    $global:MSGraphToken = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "$($authUrl)/oauth2/token?api-version=1.0 " -Body $body
    Write-Output $MSGraphToken
}
function RefreshTo-GraphToken {
    <#
    .DESCRIPTION
        Generate a windows graph token from a refresh token.
    .EXAMPLE
        RefreshTo-GraphToken -domain myclient.org -refreshToken ey....
        $GraphToken.access_token
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$domain,
        [Parameter(Mandatory=$false)]
        [string]$refreshToken = $response.refresh_token,
        [Parameter(Mandatory=$false)]
        [string]$ClientID = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
    )
    $Resource = "https://graph.windows.net"
    $ClientId = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
    $TenantId = Get-TenantID -domain $domain
    $authUrl = "https://login.microsoftonline.com/$($TenantId)"

    Write-Output $refreshToken
    $body = @{
        "resource" =      $Resource
       "client_id" =     $ClientId
        "grant_type" =    "refresh_token"
        "refresh_token" = $refreshToken
        "scope"=         "openid"
    }
    $global:GraphToken = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "$($authUrl)/oauth2/token?api-version=1.0 " -Body $body
    Write-Output $GraphToken
}
function RefreshTo-OfficeAppsToken {
    <#
    .DESCRIPTION
        Generate a Microsoft Office Apps token from a refresh token.
    .EXAMPLE
        RefreshTo-OfficeAppsToken -domain myclient.org -refreshToken ey....
        $OfficeAppsToken.access_token
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$domain,
        [Parameter(Mandatory=$false)]
        [string]$refreshToken = $response.refresh_token,
        [Parameter(Mandatory=$false)]
        [string]$ClientID = "ab9b8c07-8f02-4f72-87fa-80105867a763"
        )

    $Resource = "https://officeapps.live.com"
    $ClientId = "ab9b8c07-8f02-4f72-87fa-80105867a763"
    $TenantId = Get-TenantID -domain $domain
    $authUrl = "https://login.microsoftonline.com/$($TenantId)"
    $global:refreshToken = $response.refresh_token
    Write-Output $refreshToken
    $body2 = @{
        "resource" =      $Resource
        "client_id" =     $ClientId
        "grant_type" =    "refresh_token"
        "refresh_token" = $refreshToken
        "scope"=         "openid"
    }
    
    $global:OfficeAppsToken = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "$($authUrl)/oauth2/token?api-version=1.0" -Body $body2
    Write-Output $OfficeAppsToken
}
function RefreshTo-AzureCoreManagementToken {
    <#
    .DESCRIPTION
        Generate a Microsoft Azure Core Mangement token from a refresh token.
    .EXAMPLE
        RefreshTo-AzureCoreManagementToken -domain myclient.org -refreshToken ey....
        $AzureCoreManagementToken.access_token
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$domain,
        [Parameter(Mandatory=$false)]
        [string]$refreshToken = $response.refresh_token
        )
    $Resource = "https://management.core.windows.net"
    $ClientId = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
    $TenantId = Get-TenantID -domain $domain
    $authUrl = "https://login.microsoftonline.com/$($TenantId)"
    $global:refreshToken = $response.refresh_token 
    Write-Output $refreshToken
    $body = @{
        "resource" =      $Resource
        "client_id" =     $ClientId
        "grant_type" =    "refresh_token"
        "refresh_token" = $refreshToken
        "scope"=         "openid"
    }

    $global:AzureCoreManagementToken = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "$($authUrl)/oauth2/token?api-version=1.0 " -Body $body
    Write-Output $AzureCoreManagementToken
}
function RefreshTo-AzureManagementToken {
    <#
    .DESCRIPTION
        Generate a Microsoft Azure Mangement token from a refresh token.
    .EXAMPLE
        RefreshTo-AzureManagementToken -domain myclient.org -refreshToken ey....
        $AzureManagementToken.access_token
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$domain,
        [Parameter(Mandatory=$false)]
        [string]$refreshToken = $response.refresh_token
        )
    $Resource = "https://management.azure.com"
    $ClientId = "d3590ed6-52b3-4102-aeff-aad2292ab01c"
    $TenantId = Get-TenantID -domain $domain
    $authUrl = "https://login.microsoftonline.com/$($TenantId)"
    $global:refreshToken = $response.refresh_token 
    Write-Output $refreshToken
    $body = @{
        "resource" =      $Resource
        "client_id" =     $ClientId
        "grant_type" =    "refresh_token"
        "refresh_token" = $refreshToken
        "scope"=         "openid"
    }

    $global:AzureManagementToken = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "$($authUrl)/oauth2/token?api-version=1.0 " -Body $body
    Write-Output $AzureManagementToken
}
function RefreshTo-MAMToken {
    <#
    .DESCRIPTION
        Generate a Microsoft intune mam token from a refresh token.
    .EXAMPLE
        RefreshTo-MAMToken -domain myclient.org -refreshToken ey....
        $MAMToken.access_token
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$domain,
        [Parameter(Mandatory=$false)]
        [string]$refreshToken = $response.refresh_token
        )
    $Resource = "https://intunemam.microsoftonline.com"
    $ClientId = "6c7e8096-f593-4d72-807f-a5f86dcc9c77"
    $TenantId = Get-TenantID -domain $domain
    $authUrl = "https://login.microsoftonline.com/$($TenantId)"
    $global:refreshToken = $response.refresh_token 
    Write-Output $refreshToken
    $body = @{
        "resource" =      $Resource
        "client_id" =     $ClientId
        "grant_type" =    "refresh_token"
        "refresh_token" = $refreshToken
        "scope"=         "openid"
    }

    $global:MAMToken = Invoke-RestMethod -UseBasicParsing -Method Post -Uri "$($authUrl)/oauth2/token?api-version=1.0 " -Body $body
    Write-Output $MamToken
}

function Get-TenantID
{
    [cmdletbinding()]
    Param(
        [Parameter(ParameterSetName='Domain',Mandatory=$True)]
        [String]$domain
    )
    Process
    {
        $openIdConfig=Invoke-RestMethod "https://login.microsoftonline.com/$domain/.well-known/openid-configuration"
        $TenantId = $OpenIdConfig.authorization_endpoint.Split("/")[3]
        return $TenantId
    }
}
