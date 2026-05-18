param(
    [Parameter(Mandatory = $true)]
    [string]$IncidentId,

    [Parameter(Mandatory = $true)]
    [string]$Comment,

    [string]$Classification,
    [string]$Determination,
    [string]$Status,

    [string[]]$CustomTags = @("Analysis Done by AI")
)

#change following variables as per organization below are dummy values
#============================================================================
$tenantId = "d621fa9-84-4ddf-a17b-56b6e352b57d" 
$clientId = "82f2a73-5f-4c0c-b584-3feb162dc75c"
$clientSecret = "qgS8~kF16_QtvZI9nLqv~jFngLCebqIjZ~aQa"
#============================================================================

function Get-GraphToken {
    $tokenResponse = Invoke-RestMethod `
        -Method POST `
        -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{
            client_id     = $clientId
            client_secret = $clientSecret
            scope         = "https://graph.microsoft.com/.default"
            grant_type    = "client_credentials"
        }

    return $tokenResponse.access_token
}

function Get-Headers {
    param([string]$AccessToken)

    return @{
        Authorization = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    }
}

function Get-Incident {
    param(
        [string]$AccessToken,
        [string]$IncidentId
    )

    $headers = @{
        Authorization = "Bearer $AccessToken"
    }

    return Invoke-RestMethod `
        -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/security/incidents/$IncidentId" `
        -Headers $headers
}

function Add-IncidentComment {
    param(
        [string]$AccessToken,
        [string]$IncidentId,
        [string]$Comment
    )

    $headers = Get-Headers -AccessToken $AccessToken

    $body = @{
        "@odata.type" = "microsoft.graph.security.alertComment"
        comment       = $Comment
    } | ConvertTo-Json -Depth 5

    return Invoke-RestMethod `
        -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/security/incidents/$IncidentId/comments" `
        -Headers $headers `
        -Body $body
}

function Update-Incident {
    param(
        [string]$AccessToken,
        [string]$IncidentId,
        [string]$Classification,
        [string]$Determination,
        [string]$Status,
        [string[]]$CustomTags
    )

    $headers = Get-Headers -AccessToken $AccessToken

    $body = @{}

    if ($Classification) { $body.classification = $Classification }
    if ($Determination)  { $body.determination  = $Determination }
    if ($Status)         { $body.status         = $Status }
    if ($CustomTags -and $CustomTags.Count -gt 0) { $body.customTags = $CustomTags }

    if ($body.Count -eq 0) {
        Write-Host "No incident metadata fields supplied for PATCH. Skipping update."
        return $null
    }

    $bodyJson = $body | ConvertTo-Json -Depth 5

    Write-Host "PATCH body:"
    Write-Host $bodyJson

    $response = Invoke-RestMethod `
        -Method PATCH `
        -Uri "https://graph.microsoft.com/v1.0/security/incidents/$IncidentId" `
        -Headers $headers `
        -Body $bodyJson

    Write-Host "PATCH completed."
    return $response
}

try {
    Write-Host "Getting Graph access token..."
    $accessToken = Get-GraphToken

    Write-Host "Reading current incident state..."
    $before = Get-Incident -AccessToken $accessToken -IncidentId $IncidentId

    Write-Host "Posting analyst comment..."
    $commentResult = Add-IncidentComment -AccessToken $accessToken -IncidentId $IncidentId -Comment $Comment

    Write-Host "Updating incident fields..."
    $updateResult = Update-Incident `
        -AccessToken $accessToken `
        -IncidentId $IncidentId `
        -Classification $Classification `
        -Determination $Determination `
        -Status $Status `
        -CustomTags $CustomTags

    Write-Host "Verifying final incident state..."
    $after = Get-Incident -AccessToken $accessToken -IncidentId $IncidentId

    $commentVerified = $false
    if ($after.comments) {
        $commentVerified = @($after.comments | Where-Object { $_.comment -eq $Comment }).Count -gt 0
    }

    $tagsVerified = $true
    if ($CustomTags -and $CustomTags.Count -gt 0) {
        foreach ($tag in $CustomTags) {
            if ($after.customTags -notcontains $tag) {
                $tagsVerified = $false
            }
        }
    }

    $classificationVerified = $true
    if ($Classification) {
        $classificationVerified = ($after.classification -eq $Classification)
    }

    $determinationVerified = $true
    if ($Determination) {
        $determinationVerified = ($after.determination -eq $Determination)
    }

    $statusVerified = $true
    if ($Status) {
        $statusVerified = ($after.status -eq $Status)
    }

    [PSCustomObject]@{
        IncidentId              = $after.id
        DisplayName             = $after.displayName
        CommentVerified         = $commentVerified
        TagsVerified            = $tagsVerified
        ClassificationVerified  = $classificationVerified
        DeterminationVerified   = $determinationVerified
        StatusVerified          = $statusVerified
        FinalStatus             = $after.status
        FinalClassification     = $after.classification
        FinalDetermination      = $after.determination
        FinalTags               = ($after.customTags -join ", ")
        CommentCount            = @($after.comments).Count
        LastUpdateDateTime      = $after.lastUpdateDateTime
    } | Format-List
}
catch {
    Write-Error $_.Exception.Message
    throw
}
