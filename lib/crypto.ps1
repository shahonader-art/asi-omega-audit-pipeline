# ASI-Omega Audit Pipeline — Shared Cryptographic Library
# All hash functions used by the pipeline are defined here.
# Import with: . (Join-Path $PSScriptRoot '..\lib\crypto.ps1')
#
# Implements RFC 6962 (Certificate Transparency) domain separation
# to prevent second-preimage attacks on the Merkle tree.

# ─────────────────────────────────────────────────────
# Core hash functions
# ─────────────────────────────────────────────────────

function Get-Sha256Hash([string]$InputString){
    <#
    .SYNOPSIS
        Compute SHA-256 of a UTF-8 string.
    .DESCRIPTION
        Returns lowercase 64-character hex digest.
    #>
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($bytes)) -Algorithm SHA256).Hash.ToLower()
}

function Get-Sha256FileHash([string]$FilePath){
    <#
    .SYNOPSIS
        Compute SHA-256 of a file on disk.
    .DESCRIPTION
        Returns lowercase 64-character hex digest.
    #>
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $FilePath).Hash.ToLower()
}

# ─────────────────────────────────────────────────────
# RFC 6962 Merkle Tree hash functions
# ─────────────────────────────────────────────────────

function Get-MerkleLeafHash([string]$Data){
    <#
    .SYNOPSIS
        RFC 6962 section 2.1: leaf hash = SHA-256(0x00 || data)
    .DESCRIPTION
        Prefixes data with 0x00 byte before hashing to distinguish
        leaf nodes from internal nodes (domain separation).
    #>
    $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
    $prefixed = [byte[]]::new(1 + $dataBytes.Length)
    $prefixed[0] = 0x00
    [Array]::Copy($dataBytes, 0, $prefixed, 1, $dataBytes.Length)
    return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($prefixed)) -Algorithm SHA256).Hash.ToLower()
}

function Get-MerkleInternalHash([string]$Left, [string]$Right){
    <#
    .SYNOPSIS
        RFC 6962 section 2.1: internal hash = SHA-256(0x01 || left || right)
    .DESCRIPTION
        Prefixes concatenated child hashes with 0x01 byte to distinguish
        internal nodes from leaf nodes (domain separation).
    #>
    $pairBytes = [System.Text.Encoding]::UTF8.GetBytes($Left + $Right)
    $prefixed = [byte[]]::new(1 + $pairBytes.Length)
    $prefixed[0] = 0x01
    [Array]::Copy($pairBytes, 0, $prefixed, 1, $pairBytes.Length)
    return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($prefixed)) -Algorithm SHA256).Hash.ToLower()
}

# ─────────────────────────────────────────────────────
# Merkle Tree construction
# ─────────────────────────────────────────────────────

function Build-MerkleTree([string[]]$Leaves){
    <#
    .SYNOPSIS
        Build a Merkle tree from an array of leaf data strings.
    .DESCRIPTION
        Applies RFC 6962 domain separation:
        - Each leaf is hashed with 0x00 prefix
        - Each internal node is hashed with 0x01 prefix
        - Odd-count levels are padded by duplicating the last node

        Returns the root hash (lowercase 64-char hex).
    .PARAMETER Leaves
        Array of strings (typically SHA-256 hex hashes from manifest).
    .OUTPUTS
        [string] Merkle root hash.
    #>
    if($Leaves.Count -eq 0){ throw "Cannot build Merkle tree from empty leaf set" }

    # Build leaf level
    $level = [System.Collections.Generic.List[string]]::new()
    foreach($leaf in $Leaves){
        [void]$level.Add((Get-MerkleLeafHash $leaf))
    }

    # Build tree upward
    while($level.Count -gt 1){
        if(($level.Count % 2) -ne 0){
            $level.Add($level[$level.Count - 1])
        }
        $next = [System.Collections.Generic.List[string]]::new()
        for($i = 0; $i -lt $level.Count; $i += 2){
            $next.Add((Get-MerkleInternalHash $level[$i] $level[$i + 1]))
        }
        $level = $next
    }

    return $level[0]
}
