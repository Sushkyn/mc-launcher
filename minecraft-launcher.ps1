param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$Nickname
)

# --- Requirements Check ---
function Check-Command {
    param([string]$cmd, [string]$name)

    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "$name is required but not installed. Aborting."
        exit 1
    }
}

Check-Command "java" "Java (JRE8+)"
Check-Command "curl" "curl"
Check-Command "tar" "tar"   # optional, only if unpacking archives differently

# --- Directories ---
$GameDir     = "C:\Minecraft"
$VersionDir  = "$GameDir\versions\$Version"
$AssetsDir   = "$GameDir\assets"
$LibrariesDir= "$GameDir\libraries"

New-Item -ItemType Directory -Force -Path $GameDir, "$AssetsDir\objects", $LibrariesDir, "$VersionDir\natives" | Out-Null

# --- Fetch version manifest ---
$ManifestUrl = (Invoke-RestMethod https://piston-meta.mojang.com/mc/game/version_manifest.json).versions |
    Where-Object { $_.id -eq $Version } |
    Select-Object -ExpandProperty url

if (-not $ManifestUrl) {
    Write-Error "Minecraft version $Version not found."
    exit 1
}

$VersionMeta = Invoke-RestMethod $ManifestUrl

# --- Download client jar ---
$ClientUrl = $VersionMeta.downloads.client.url
Invoke-WebRequest -Uri $ClientUrl -OutFile "$VersionDir\$Version.jar"

# --- Asset index ---
$AssetIndexUrl  = $VersionMeta.assetIndex.url
$AssetIndexName = $VersionMeta.assetIndex.id
New-Item -ItemType Directory -Force -Path "$AssetsDir\indexes" | Out-Null
Invoke-WebRequest -Uri $AssetIndexUrl -OutFile "$AssetsDir\indexes\$AssetIndexName.json"

$AssetIndex = Get-Content "$AssetsDir\indexes\$AssetIndexName.json" | ConvertFrom-Json
foreach ($obj in $AssetIndex.objects.PSObject.Properties) {
    $hash = $obj.Value.hash
    $subdir = $hash.Substring(0,2)
    $outDir = "$AssetsDir\objects\$subdir"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $url = "https://resources.download.minecraft.net/$subdir/$hash"
    $outFile = "$outDir\$hash"
    if (-not (Test-Path $outFile)) {
        Invoke-WebRequest -Uri $url -OutFile $outFile
    }
}

# --- Libraries ---
foreach ($lib in $VersionMeta.libraries) {
    if ($lib.downloads.artifact.url) {
        $artifactPath = "$LibrariesDir\" + $lib.downloads.artifact.path
        $artifactDir  = Split-Path $artifactPath -Parent
        New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
        if (-not (Test-Path $artifactPath)) {
            Invoke-WebRequest -Uri $lib.downloads.artifact.url -OutFile $artifactPath
        }
    }
    if ($lib.downloads.classifiers."natives-windows".url) {
        $nativesPath = "$LibrariesDir\" + $lib.downloads.classifiers."natives-windows".path
        $nativesDir  = Split-Path $nativesPath -Parent
        New-Item -ItemType Directory -Force -Path $nativesDir | Out-Null
        Invoke-WebRequest -Uri $lib.downloads.classifiers."natives-windows".url -OutFile $nativesPath
        Expand-Archive -Path $nativesPath -DestinationPath "$VersionDir\natives" -Force
    }
}

# --- Classpath ---
$ClassPath = @()
foreach ($lib in $VersionMeta.libraries) {
    if ($lib.downloads.artifact.path) {
        $ClassPath += "$LibrariesDir\" + $lib.downloads.artifact.path
    }
}
$ClassPath += "$VersionDir\$Version.jar"
$ClassPathString = ($ClassPath -join ";") # Windows uses ; instead of :

$MainClass   = $VersionMeta.mainClass
$VersionType = $VersionMeta.type

# --- Run game ---
& java `
    -Xmx2G -Xss1M `
    -Dfile.encoding=UTF-8 `
    -Djava.library.path="$VersionDir\natives" `
    -Dminecraft.launcher.brand="ps-minecraft-launcher" `
    -Dminecraft.launcher.version="1.6.84-j" `
    -cp "$ClassPathString" "$MainClass" `
    $Nickname `
    --version $Version `
    --gameDir $GameDir `
    --assetsDir $AssetsDir `
    --assetIndex $AssetIndexName `
    --uuid "00000000-0000-0000-0000-000000000000" `
    --accessToken "null" `
    --userType "legacy" `
    --versionType $VersionType
