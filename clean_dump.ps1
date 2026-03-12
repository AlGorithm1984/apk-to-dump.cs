<#
.SYNOPSIS
    IL2CPP dump.cs cleaner for War Robots 11.8.0 modding.
    Strips all third-party/framework DLL images and inline compiler noise.
    Output: 11.8.0_cleaned_dump.cs

.APPROACH
    Pass 1 - Header Parse: Read the image header to build a map of
             ImageIndex -> (Name, StartTypeDefIndex, EndTypeDefIndex).
    Pass 2 - Stream Filter: Process the file line-by-line using a state machine.
             - Track current TypeDefIndex from class declarations.
             - Skip entire class blocks that belong to cut images.
             - Within kept classes, strip inline noise (GenericInstMethod blocks,
               debugger attributes, anonymous type classes).
#>

$InputFile  = "$PSScriptRoot\11.8.0_dump.cs"
$OutputFile = "$PSScriptRoot\11.8.0_cleaned_dump.cs"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: Build the Image -> TypeDefIndex range map from the file header
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[1/3] Parsing image header..."

$imageMap = @{} # ImageIndex -> @{ Name; StartTDI; EndTDI }
$lastImageIdx = -1
$lastStartTDI = -1

# Read only the header (first ~200 lines)
$headerLines = [System.IO.File]::ReadLines($InputFile) | Select-Object -First 200

foreach ($line in $headerLines) {
    if ($line -match '^// Image (\d+): (.+?) - (\d+)') {
        $imgIdx  = [int]$Matches[1]
        $imgName = $Matches[2].Trim()
        $startTDI = [int]$Matches[3]

        if ($lastImageIdx -ge 0) {
            $imageMap[$lastImageIdx].EndTDI = $startTDI - 1
        }

        $imageMap[$imgIdx] = @{
            Name     = $imgName
            StartTDI = $startTDI
            EndTDI   = [int]::MaxValue  # Will be overwritten by next image, or left as max for last
        }
        $lastImageIdx = $imgIdx
        $lastStartTDI = $startTDI
    }
}

Write-Host "   Found $($imageMap.Count) images."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Define which images to CUT (by index)
# Images NOT in this set are KEPT.
# ─────────────────────────────────────────────────────────────────────────────
$cutImages = [System.Collections.Generic.HashSet[int]]::new()
@(
     1,  # mscorlib.dll
     3,  # UnityEngine.UIElementsModule.dll
     4,  # System.Xml.dll
     5,  # Unity.InputSystem.dll
     6,  # System.dll
     8,  # Unity.Mathematics.dll
     9,  # Newtonsoft.Json.dll
    11,  # System.Data.dll
    12,  # DotNetty.dll
    14,  # Unity.RenderPipelines.Core.Runtime.dll
    16,  # Zenject.dll
    17,  # System.Core.dll
    18,  # Unity.TextMeshPro.dll
    19,  # Unity.Collections.dll
    21,  # Cinemachine.dll
    22,  # Unity.Burst.dll
    23,  # MessagePack.dll
    24,  # protobuf-net.dll
    25,  # System.Runtime.Serialization.dll
    26,  # UnityEngine.UI.dll
    27,  # com.pixonic.resourcesystem.dll
    28,  # Ionic.Zip.Unity.dll
    29,  # System.Collections.Immutable.dll
    30,  # UnityEngine.TextCoreTextEngineModule.dll
    31,  # Unity.SharpZipLib.dll
    32,  # spine-csharp.dll
    33,  # spine-unity.dll
    34,  # DOTween.dll
    35,  # Unity.Serialization.dll
    36,  # Unity.Splines.dll
    37,  # games.my.mrgs.core.dll
    38,  # Unity.Timeline.dll
    39,  # UnityEngine.IMGUIModule.dll
    41,  # Mono.Security.dll
    43,  # UnityEngine.PropertiesModule.dll
    44,  # ReactiveBindings.dll
    46,  # PS.PixRender.Runtime.dll
    47,  # games.my.mrgs.authentication.dll
    49,  # System.IO.Compression.dll
    50,  # UnityEngine.AndroidJNIModule.dll
    51,  # UnityEngine.ParticleSystemModule.dll
    55,  # XMediator.dll
    56,  # XMediator.Android.dll
    57,  # games.my.mrgs.notifications.dll
    58,  # com.pixonic.deliverysystem.dll
    59,  # com.pixonic.deliverysystem.resourcesystem.dll
    60,  # games.my.mrgs.bank.dll
    62,  # ThirdParty.AppsFlyer.dll
    63,  # System.ServiceModel.Internals.dll
    64,  # games.my.mrgs.gdpr.dll
    65,  # JsonFx.Json.dll
    66,  # com.pixonic.qualitymanager.dll
    67,  # System.Drawing.dll
    68,  # BrunoMikoski.AnimationSequencer.dll
    69,  # DOTween.Modules.dll
    71,  # RSG.Promise.dll
    72,  # System.Numerics.dll
    73,  # Unity.Notifications.Android.dll
    74,  # PS.Logs.dll
    75,  # UnityEngine.AnimationModule.dll
    76,  # PS.IAP.NativePurchasing.dll
    77,  # PS.PixBooth.Runtime.dll
    79,  # games.my.mrgs.didomi.dll
    80,  # System.Xml.Linq.dll
    81,  # ThirdParty.Appmetr.dll
    82,  # UnityEngine.UnityWebRequestModule.dll
    83,  # ThirdParty.AdsQuality.dll
    84,  # PixMage.dll
    85,  # UnityEngine.TextCoreFontEngineModule.dll
    86,  # PixEffects.Ui.Runtime.dll
    89,  # UnityEngine.XRModule.dll
    90,  # com.pixonic.resourcesystem.languageprovider.dll
    91,  # UnityEngine.AudioModule.dll
    92,  # UnityEngine.Physics2DModule.dll
    93,  # games.my.support.dll
    94,  # PS.Ads.dll
    95,  # Zenject-usage.dll
    97,  # DOTweenPro.Scripts.dll
    98,  # System.ServiceModel.dll
    99,  # PS.Video.dll
   100,  # PS.IntegrationsManager.MRGS.dll
   101,  # spine-timeline.dll
   102,  # UnityEngine.TextRenderingModule.dll
   103,  # ThirdParty.Zendesk.dll
   104,  # UnityEngine.InputLegacyModule.dll
   105,  # UnityEngine.GameCenterModule.dll
   106,  # UnityEngine.TerrainModule.dll
   107,  # UnityEngine.TilemapModule.dll
   109,  # UnityEngine.SharedInternalsModule.dll
   110,  # PS.Ads.Providers.Loomit.dll
   111,  # UnityEngine.VFXModule.dll
   112,  # Remaster.RenderPipelines.WRSRP.Runtime.dll
   113,  # DOTweenPro.dll
   114,  # UnityEngine.VideoModule.dll
   115,  # UnityEngine.SubsystemsModule.dll
   116,  # PS.IntegrationsManager.Core.dll
   117,  # PS.IntegrationsManagers.AdsRuntime.dll
   118,  # UnityEngine.AssetBundleModule.dll
   119,  # PS.IntegrationsManager.AppsFlyer.dll
   120,  # Unity.Properties.UI.dll
   121,  # UnityEngine.DirectorModule.dll
   122,  # UnityEngine.InputModule.dll
   123,  # UnityEngine.UnityAnalyticsModule.dll
   124,  # Microsoft.Extensions.Logging.Abstractions.dll
   125,  # UnityEngine.AIModule.dll
   126,  # UnityEngine.VRModule.dll
   127,  # PS.NativeServices.Crashlytics.dll
   128,  # UnityEngine.JSONSerializeModule.dll
   129,  # UnityEngine.UnityWebRequestAudioModule.dll
   130,  # UnityEngine.UnityWebRequestWWWModule.dll
   131,  # UnityEngine.CrashReportingModule.dll
   132,  # UnityEngine.ImageConversionModule.dll
   134,  # Microsoft.Bcl.AsyncInterfaces.dll
   136,  # PS.IntegrationsManager.AppmetrRuntime.dll
   137,  # UnityEngine.GridModule.dll
   138,  # UnityEngine.PerformanceReportingModule.dll
   139,  # UnityEngine.SpriteMaskModule.dll
   140,  # UnityEngine.SpriteShapeModule.dll
   141,  # UnityEngine.UnityAnalyticsCommonModule.dll
   142,  # com.pixonic.qualitymanager.loader.dll
   143,  # games.my.mrgs.advertising.dll
   144,  # PS.Ads.Providers.MRGS.dll
   145,  # MessagePack.Annotations.dll
   147,  # Unity.RenderPipeline.Universal.ShaderLibrary.dll
   148,  # Microsoft.Extensions.Logging.dll
   149,  # PS.Ads.Providers.Tapjoy.dll
   150,  # Beebyte.Obfuscator.dll
   151,  # PS.IntegrationsManager.NativeServices.Runtime.dll
   152,  # PS.Logs.Cheats.dll  -- NOTE: keep this one actually
   153,  # System.Net.Http.dll
   154,  # System.Runtime.CompilerServices.Unsafe.dll
   155,  # Unity.Burst.Unsafe.dll
   156,  # com.pixonic.playbench.dll
   157,  # System.Configuration.dll
   158,  # Facebook.Embedded.Link.dll
   159,  # Unity.InputSystem.ForUI.dll
   160,  # Unity.Collections.LowLevel.ILSupport.dll
   161   # __Generated
) | ForEach-Object { [void]$cutImages.Add($_) }

# Remove 152 from cut list - PS.Logs.Cheats.dll is relevant (cheat detection logging)
[void]$cutImages.Remove(152)

Write-Host "   Cutting $($cutImages.Count) DLL images."

# Build the CUT TypeDefIndex ranges as [start, end] pairs for fast lookup
$cutRanges = [System.Collections.Generic.List[object]]::new()
foreach ($imgIdx in $cutImages) {
    if ($imageMap.ContainsKey($imgIdx)) {
        $entry = $imageMap[$imgIdx]
        $cutRanges.Add(@{ S = $entry.StartTDI; E = $entry.EndTDI })
    }
}
# Sort by start for potential binary search (not strictly needed with hash approach)
$cutRanges = $cutRanges | Sort-Object { $_.S }

function Test-TDICut {
    param([int]$tdi)
    foreach ($r in $cutRanges) {
        if ($tdi -ge $r.S -and $tdi -le $r.E) { return $true }
        if ($r.S -gt $tdi) { break }  # ranges are sorted, can early-exit
    }
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: Stream-process the file with a state machine
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[2/3] Processing file (this will take a minute)..."

$reader = [System.IO.StreamReader]::new($InputFile, [System.Text.Encoding]::UTF8)
$writer = [System.IO.StreamWriter]::new($OutputFile, $false, [System.Text.Encoding]::UTF8)

$currentTDI        = -1      # TypeDefIndex of the current class block
$skipBlock         = $false  # Are we currently skipping a cut image's class?
$inGenericComment  = $false  # Are we inside a /* GenericInstMethod */ block?
$pendingLines      = [System.Collections.Generic.List[string]]::new()  # Buffer for lookahead
$inClassBlock      = $false  # Tracking brace depth for skipping anonymous types

# Anonymous type class patterns (compiler scaffolding, not game classes)
$anonClassPattern  = [regex]'^(internal|private|public)?\s*(sealed\s+)?class\s+(<>f__AnonymousType\d+|<>c__DisplayClass\d+|<\w+>d__\d+|<>c)\b'
$skipAnonDepth     = 0
$skipAnonMode      = $false

# Lines to count progress
$lineCount   = 0
$keptLines   = 0
$progressStep = 100000

$line = $null
while (($line = $reader.ReadLine()) -ne $null) {
    $lineCount++
    if ($lineCount % $progressStep -eq 0) {
        Write-Host "   Processed $([math]::Round($lineCount/1000))k lines, kept $keptLines lines..."
    }

    # ── HANDLE GenericInstMethod multi-line comment blocks ──────────────────
    if ($inGenericComment) {
        if ($line -match '\*/') {
            $inGenericComment = $false
        }
        # Drop this line entirely
        continue
    }
    # Detect start of a GenericInstMethod comment block
    if ($line -match '/\*\s*GenericInstMethod') {
        if ($line -match '\*/') {
            # Single-line comment, just skip it
        } else {
            $inGenericComment = $true
        }
        continue
    }

    # ── DETECT TypeDefIndex from class declarations ──────────────────────────
    if ($line -match '//\s*TypeDefIndex\s*:\s*(\d+)') {
        $newTDI = [int]$Matches[1]
        $currentTDI = $newTDI
        $skipBlock = Test-TDICut -tdi $currentTDI
        $skipAnonMode = $false
        $skipAnonDepth = 0
    }

    # ── SKIP entire block for cut images ────────────────────────────────────
    if ($skipBlock) {
        continue
    }

    # ── DETECT anonymous/compiler-generated class declarations to strip ──────
    # These appear as class blocks we want to drop entirely
    if (-not $skipAnonMode -and $line -match $anonClassPattern) {
        $skipAnonMode  = $true
        $skipAnonDepth = 0
        continue
    }
    if ($skipAnonMode) {
        # Count braces to know when the class ends
        foreach ($ch in $line.ToCharArray()) {
            if ($ch -eq '{') { $skipAnonDepth++ }
            elseif ($ch -eq '}') {
                $skipAnonDepth--
                if ($skipAnonDepth -le 0) {
                    $skipAnonMode = $false
                    break
                }
            }
        }
        continue
    }

    # ── STRIP noisy attribute lines ─────────────────────────────────────────
    $stripped  = $line.Trim()
    if ($stripped -eq '[DebuggerBrowsable(0)]'    -or
        $stripped -eq '[DebuggerBrowsable(DebuggerBrowsableState.Never)]' -or
        $stripped -eq '[DebuggerHidden]'           -or
        $stripped -eq '[DebuggerStepThrough]'      -or
        $stripped -eq '[CompilerGenerated]'        -or
        $stripped -eq '[IteratorStateMachine]'     -or
        $stripped -match '^\[IteratorStateMachine\(typeof\(') {
        continue
    }

    # ── WRITE the line ───────────────────────────────────────────────────────
    $writer.WriteLine($line)
    $keptLines++
}

$reader.Close()
$reader.Dispose()
$writer.Flush()
$writer.Close()
$writer.Dispose()

Write-Host "[3/3] Done!"
Write-Host ""
$origSize  = (Get-Item $InputFile).Length
$cleanSize = (Get-Item $OutputFile).Length
$pctKept   = [math]::Round($cleanSize / $origSize * 100, 1)
$pctCut    = 100 - $pctKept
Write-Host "  Original : $([math]::Round($origSize/1MB, 2)) MB"
Write-Host "  Cleaned  : $([math]::Round($cleanSize/1MB, 2)) MB"
Write-Host "  Reduction: $pctCut% cut ($pctKept% kept)"
Write-Host "  Lines in : $lineCount"
Write-Host "  Lines out: $keptLines"
Write-Host ""
Write-Host "Output: $OutputFile"
