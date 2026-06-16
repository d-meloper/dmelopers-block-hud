param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [ValidateSet('wide', 'slim')]
    [string]$Model = 'wide'
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function New-PointF {
    param(
        [double]$X,
        [double]$Y
    )

    return (New-Object System.Drawing.PointF([single]$X, [single]$Y))
}

function New-SkinFace {
    param(
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height
    )

    return @{
        X = [int]$X
        Y = [int]$Y
        Width = [int]$Width
        Height = [int]$Height
    }
}

function New-WorldPoint {
    param(
        [double]$X,
        [double]$Y,
        [double]$Z
    )

    return @{
        X = [double]$X
        Y = [double]$Y
        Z = [double]$Z
    }
}

function Convert-DegreesToRadians {
    param([double]$Degrees)
    return $Degrees * [Math]::PI / 180.0
}

function New-ShadedFaceBitmap {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Texture,
        [Parameter(Mandatory = $true)]
        [hashtable]$Face,
        [double]$Brightness
    )

    $width = [int]$Face.Width
    $height = [int]$Face.Height
    $faceBitmap = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) {
            $color = $Texture.GetPixel(([int]$Face.X + $x), ([int]$Face.Y + $y))
            if ($color.A -eq 0) {
                continue
            }

            $red = [Math]::Max(0, [Math]::Min(255, [int][Math]::Round($color.R * $Brightness)))
            $green = [Math]::Max(0, [Math]::Min(255, [int][Math]::Round($color.G * $Brightness)))
            $blue = [Math]::Max(0, [Math]::Min(255, [int][Math]::Round($color.B * $Brightness)))
            $faceBitmap.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($color.A, $red, $green, $blue))
        }
    }

    return $faceBitmap
}

function New-CuboidPart {
    param(
        [string]$Name,
        [double]$MinX,
        [double]$MinY,
        [double]$MinZ,
        [double]$MaxX,
        [double]$MaxY,
        [double]$MaxZ,
        [hashtable]$Base,
        [hashtable]$Overlay,
        [double]$OverlayInflate = 0.0
    )

    return @{
        Name = [string]$Name
        MinX = [double]$MinX
        MinY = [double]$MinY
        MinZ = [double]$MinZ
        MaxX = [double]$MaxX
        MaxY = [double]$MaxY
        MaxZ = [double]$MaxZ
        Base = $Base
        Overlay = $Overlay
        OverlayInflate = [double]$OverlayInflate
    }
}

function Get-InflatedPart {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Part,
        [double]$Inflate
    )

    if ($Inflate -eq 0) {
        return $Part
    }

    return @{
        Name = $Part.Name
        MinX = [double]$Part.MinX - $Inflate
        MinY = [double]$Part.MinY - $Inflate
        MinZ = [double]$Part.MinZ - $Inflate
        MaxX = [double]$Part.MaxX + $Inflate
        MaxY = [double]$Part.MaxY + $Inflate
        MaxZ = [double]$Part.MaxZ + $Inflate
    }
}

function New-Projection {
    param(
        [double]$YawDegrees = 26.0,
        [double]$PitchDegrees = -11.0,
        [double]$Scale = 1.0,
        [double]$OriginX = 0.0,
        [double]$OriginY = 0.0
    )

    $yaw = Convert-DegreesToRadians $YawDegrees
    $pitch = Convert-DegreesToRadians $PitchDegrees
    return @{
        YawSin = [Math]::Sin($yaw)
        YawCos = [Math]::Cos($yaw)
        PitchSin = [Math]::Sin($pitch)
        PitchCos = [Math]::Cos($pitch)
        Scale = [double]$Scale
        OriginX = [double]$OriginX
        OriginY = [double]$OriginY
    }
}

function Convert-ToCameraPoint {
    param(
        [hashtable]$Projection,
        [double]$X,
        [double]$Y,
        [double]$Z
    )

    $rotatedX = ($X * [double]$Projection.YawCos) + ($Z * [double]$Projection.YawSin)
    $rotatedZ = (-$X * [double]$Projection.YawSin) + ($Z * [double]$Projection.YawCos)
    $rotatedY = ($Y * [double]$Projection.PitchCos) - ($rotatedZ * [double]$Projection.PitchSin)
    $cameraZ = ($Y * [double]$Projection.PitchSin) + ($rotatedZ * [double]$Projection.PitchCos)

    return @{
        X = [double]$rotatedX
        Y = [double]$rotatedY
        Z = [double]$cameraZ
    }
}

function Project-MinecraftPoint {
    param(
        [hashtable]$Projection,
        [hashtable]$Point
    )

    $camera = Convert-ToCameraPoint -Projection $Projection -X $Point.X -Y $Point.Y -Z $Point.Z
    return (New-PointF `
        -X ([double]$Projection.OriginX + ([double]$camera.X * [double]$Projection.Scale)) `
        -Y ([double]$Projection.OriginY + ([double]$camera.Y * [double]$Projection.Scale)))
}

function Get-FaceCorners {
    param(
        [hashtable]$Part,
        [ValidateSet('front', 'back', 'left', 'right', 'top', 'bottom')]
        [string]$FaceName
    )

    $minX = [double]$Part.MinX
    $minY = [double]$Part.MinY
    $minZ = [double]$Part.MinZ
    $maxX = [double]$Part.MaxX
    $maxY = [double]$Part.MaxY
    $maxZ = [double]$Part.MaxZ

    if ($FaceName -eq 'front') {
        return @(
            (New-WorldPoint -X $minX -Y $minY -Z $maxZ),
            (New-WorldPoint -X $maxX -Y $minY -Z $maxZ),
            (New-WorldPoint -X $maxX -Y $maxY -Z $maxZ),
            (New-WorldPoint -X $minX -Y $maxY -Z $maxZ)
        )
    }

    if ($FaceName -eq 'back') {
        return @(
            (New-WorldPoint -X $maxX -Y $minY -Z $minZ),
            (New-WorldPoint -X $minX -Y $minY -Z $minZ),
            (New-WorldPoint -X $minX -Y $maxY -Z $minZ),
            (New-WorldPoint -X $maxX -Y $maxY -Z $minZ)
        )
    }

    if ($FaceName -eq 'left') {
        return @(
            (New-WorldPoint -X $minX -Y $minY -Z $maxZ),
            (New-WorldPoint -X $minX -Y $minY -Z $minZ),
            (New-WorldPoint -X $minX -Y $maxY -Z $minZ),
            (New-WorldPoint -X $minX -Y $maxY -Z $maxZ)
        )
    }

    if ($FaceName -eq 'right') {
        return @(
            (New-WorldPoint -X $maxX -Y $minY -Z $minZ),
            (New-WorldPoint -X $maxX -Y $minY -Z $maxZ),
            (New-WorldPoint -X $maxX -Y $maxY -Z $maxZ),
            (New-WorldPoint -X $maxX -Y $maxY -Z $minZ)
        )
    }

    if ($FaceName -eq 'top') {
        return @(
            (New-WorldPoint -X $minX -Y $minY -Z $minZ),
            (New-WorldPoint -X $maxX -Y $minY -Z $minZ),
            (New-WorldPoint -X $maxX -Y $minY -Z $maxZ),
            (New-WorldPoint -X $minX -Y $minY -Z $maxZ)
        )
    }

    return @(
        (New-WorldPoint -X $minX -Y $maxY -Z $maxZ),
        (New-WorldPoint -X $maxX -Y $maxY -Z $maxZ),
        (New-WorldPoint -X $maxX -Y $maxY -Z $minZ),
        (New-WorldPoint -X $minX -Y $maxY -Z $minZ)
    )
}

function Get-FaceNormal {
    param(
        [ValidateSet('front', 'back', 'left', 'right', 'top', 'bottom')]
        [string]$FaceName
    )

    if ($FaceName -eq 'front') {
        return (New-WorldPoint -X 0 -Y 0 -Z 1)
    }
    if ($FaceName -eq 'back') {
        return (New-WorldPoint -X 0 -Y 0 -Z -1)
    }
    if ($FaceName -eq 'left') {
        return (New-WorldPoint -X -1 -Y 0 -Z 0)
    }
    if ($FaceName -eq 'right') {
        return (New-WorldPoint -X 1 -Y 0 -Z 0)
    }
    if ($FaceName -eq 'top') {
        return (New-WorldPoint -X 0 -Y -1 -Z 0)
    }
    return (New-WorldPoint -X 0 -Y 1 -Z 0)
}

function Get-FaceBrightness {
    param(
        [ValidateSet('front', 'back', 'left', 'right', 'top', 'bottom')]
        [string]$FaceName
    )

    if ($FaceName -eq 'front') {
        return 1.0
    }
    if ($FaceName -eq 'top') {
        return 1.08
    }
    if ($FaceName -eq 'left') {
        return 0.76
    }
    if ($FaceName -eq 'right') {
        return 0.82
    }
    if ($FaceName -eq 'back') {
        return 0.62
    }
    return 0.56
}

function Get-ProjectedBounds {
    param(
        [hashtable[]]$Parts,
        [hashtable]$Projection
    )

    $minX = [double]::PositiveInfinity
    $minY = [double]::PositiveInfinity
    $maxX = [double]::NegativeInfinity
    $maxY = [double]::NegativeInfinity

    foreach ($part in $Parts) {
        $renderPart = Get-InflatedPart -Part $part -Inflate ([double]$part.OverlayInflate)
        foreach ($x in @([double]$renderPart.MinX, [double]$renderPart.MaxX)) {
            foreach ($y in @([double]$renderPart.MinY, [double]$renderPart.MaxY)) {
                foreach ($z in @([double]$renderPart.MinZ, [double]$renderPart.MaxZ)) {
                    $point = Project-MinecraftPoint -Projection $Projection -Point (New-WorldPoint -X $x -Y $y -Z $z)
                    $minX = [Math]::Min($minX, [double]$point.X)
                    $minY = [Math]::Min($minY, [double]$point.Y)
                    $maxX = [Math]::Max($maxX, [double]$point.X)
                    $maxY = [Math]::Max($maxY, [double]$point.Y)
                }
            }
        }
    }

    return @{
        MinX = $minX
        MinY = $minY
        MaxX = $maxX
        MaxY = $maxY
        Width = $maxX - $minX
        Height = $maxY - $minY
    }
}

function New-FittedProjection {
    param(
        [hashtable[]]$Parts,
        [int]$CanvasWidth,
        [int]$CanvasHeight
    )

    $baseProjection = New-Projection -YawDegrees 26.0 -PitchDegrees -11.0 -Scale 1.0 -OriginX 0.0 -OriginY 0.0
    $bounds = Get-ProjectedBounds -Parts $Parts -Projection $baseProjection
    $paddingX = 2.0
    $paddingTop = 2.0
    $paddingBottom = 3.0
    $scaleX = ([double]$CanvasWidth - ($paddingX * 2.0)) / [double]$bounds.Width
    $scaleY = ([double]$CanvasHeight - $paddingTop - $paddingBottom) / [double]$bounds.Height
    $scale = [Math]::Min($scaleX, $scaleY)
    $renderWidth = [double]$bounds.Width * $scale
    $renderHeight = [double]$bounds.Height * $scale
    $originX = (([double]$CanvasWidth - $renderWidth) / 2.0) - ([double]$bounds.MinX * $scale)
    $originY = $paddingTop - ([double]$bounds.MinY * $scale) + ((([double]$CanvasHeight - $paddingTop - $paddingBottom - $renderHeight) / 2.0) * 0.35)

    return New-Projection -YawDegrees 26.0 -PitchDegrees -11.0 -Scale $scale -OriginX $originX -OriginY $originY
}

function New-ProjectedFace {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Part,
        [Parameter(Mandatory = $true)]
        [hashtable]$Projection,
        [Parameter(Mandatory = $true)]
        [hashtable]$Face,
        [ValidateSet('front', 'back', 'left', 'right', 'top', 'bottom')]
        [string]$FaceName,
        [double]$BrightnessBias,
        [int]$LayerOrder
    )

    $normal = Get-FaceNormal -FaceName $FaceName
    $cameraNormal = Convert-ToCameraPoint -Projection $Projection -X $normal.X -Y $normal.Y -Z $normal.Z
    if ([double]$cameraNormal.Z -le 0.001) {
        return $null
    }

    $corners = Get-FaceCorners -Part $Part -FaceName $FaceName
    $points = [System.Drawing.PointF[]]@(
        (Project-MinecraftPoint -Projection $Projection -Point $corners[0]),
        (Project-MinecraftPoint -Projection $Projection -Point $corners[1]),
        (Project-MinecraftPoint -Projection $Projection -Point $corners[3])
    )

    $depth = 0.0
    foreach ($corner in $corners) {
        $camera = Convert-ToCameraPoint -Projection $Projection -X $corner.X -Y $corner.Y -Z $corner.Z
        $depth += [double]$camera.Z
    }
    $depth = $depth / [double]$corners.Count

    return [PSCustomObject]@{
        Face = $Face
        FaceName = $FaceName
        Points = $points
        Brightness = ((Get-FaceBrightness -FaceName $FaceName) * $BrightnessBias)
        Depth = $depth
        LayerOrder = $LayerOrder
    }
}

function Add-CuboidLayerFaces {
    param(
        [System.Collections.ArrayList]$Faces,
        [hashtable]$Part,
        [hashtable]$Projection,
        [hashtable]$Layer,
        [double]$BrightnessBias,
        [int]$LayerOrder
    )

    if ($null -eq $Layer) {
        return
    }

    foreach ($faceName in @('back', 'right', 'left', 'bottom', 'top', 'front')) {
        if (-not $Layer.ContainsKey($faceName)) {
            continue
        }

        $projectedFace = New-ProjectedFace `
            -Part $Part `
            -Projection $Projection `
            -Face $Layer[$faceName] `
            -FaceName $faceName `
            -BrightnessBias $BrightnessBias `
            -LayerOrder $LayerOrder
        if ($null -ne $projectedFace) {
            [void]$Faces.Add($projectedFace)
        }
    }
}

function Draw-ProjectedSkinFace {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Texture,
        [Parameter(Mandatory = $true)]
        [hashtable]$Face,
        [Parameter(Mandatory = $true)]
        [System.Drawing.PointF[]]$Points,
        [double]$Brightness
    )

    $faceBitmap = $null
    try {
        $faceBitmap = New-ShadedFaceBitmap -Texture $Texture -Face $Face -Brightness $Brightness
        $Graphics.DrawImage($faceBitmap, $Points)
    }
    finally {
        if ($null -ne $faceBitmap) {
            $faceBitmap.Dispose()
        }
    }
}

function New-BodyLayer {
    return @{
        top = New-SkinFace -X 20 -Y 16 -Width 8 -Height 4
        bottom = New-SkinFace -X 28 -Y 16 -Width 8 -Height 4
        right = New-SkinFace -X 16 -Y 20 -Width 4 -Height 12
        front = New-SkinFace -X 20 -Y 20 -Width 8 -Height 12
        left = New-SkinFace -X 28 -Y 20 -Width 4 -Height 12
        back = New-SkinFace -X 32 -Y 20 -Width 8 -Height 12
    }
}

function New-BodyOverlayLayer {
    return @{
        top = New-SkinFace -X 20 -Y 32 -Width 8 -Height 4
        bottom = New-SkinFace -X 28 -Y 32 -Width 8 -Height 4
        right = New-SkinFace -X 16 -Y 36 -Width 4 -Height 12
        front = New-SkinFace -X 20 -Y 36 -Width 8 -Height 12
        left = New-SkinFace -X 28 -Y 36 -Width 4 -Height 12
        back = New-SkinFace -X 32 -Y 36 -Width 8 -Height 12
    }
}

function New-HeadLayer {
    param([switch]$Overlay)

    if ($Overlay) {
        return @{
            top = New-SkinFace -X 40 -Y 0 -Width 8 -Height 8
            bottom = New-SkinFace -X 48 -Y 0 -Width 8 -Height 8
            right = New-SkinFace -X 32 -Y 8 -Width 8 -Height 8
            front = New-SkinFace -X 40 -Y 8 -Width 8 -Height 8
            left = New-SkinFace -X 48 -Y 8 -Width 8 -Height 8
            back = New-SkinFace -X 56 -Y 8 -Width 8 -Height 8
        }
    }

    return @{
        top = New-SkinFace -X 8 -Y 0 -Width 8 -Height 8
        bottom = New-SkinFace -X 16 -Y 0 -Width 8 -Height 8
        right = New-SkinFace -X 0 -Y 8 -Width 8 -Height 8
        front = New-SkinFace -X 8 -Y 8 -Width 8 -Height 8
        left = New-SkinFace -X 16 -Y 8 -Width 8 -Height 8
        back = New-SkinFace -X 24 -Y 8 -Width 8 -Height 8
    }
}

function New-ArmLayer {
    param(
        [ValidateSet('right', 'left')]
        [string]$Side,
        [ValidateSet('base', 'overlay')]
        [string]$Layer,
        [int]$ArmWidth
    )

    $rightFaceWidth = 4
    if ($Side -eq 'right') {
        $y = if ($Layer -eq 'overlay') { 36 } else { 20 }
        $topY = if ($Layer -eq 'overlay') { 32 } else { 16 }
        return @{
            top = New-SkinFace -X 44 -Y $topY -Width $ArmWidth -Height 4
            bottom = New-SkinFace -X (44 + $ArmWidth) -Y $topY -Width $ArmWidth -Height 4
            right = New-SkinFace -X 40 -Y $y -Width $rightFaceWidth -Height 12
            front = New-SkinFace -X 44 -Y $y -Width $ArmWidth -Height 12
            left = New-SkinFace -X (44 + $ArmWidth) -Y $y -Width 4 -Height 12
            back = New-SkinFace -X (48 + $ArmWidth) -Y $y -Width $ArmWidth -Height 12
        }
    }

    if ($Layer -eq 'overlay') {
        return @{
            top = New-SkinFace -X 52 -Y 48 -Width $ArmWidth -Height 4
            bottom = New-SkinFace -X (52 + $ArmWidth) -Y 48 -Width $ArmWidth -Height 4
            right = New-SkinFace -X 48 -Y 52 -Width $rightFaceWidth -Height 12
            front = New-SkinFace -X 52 -Y 52 -Width $ArmWidth -Height 12
            left = New-SkinFace -X (52 + $ArmWidth) -Y 52 -Width 4 -Height 12
            back = New-SkinFace -X (56 + $ArmWidth) -Y 52 -Width $ArmWidth -Height 12
        }
    }

    return @{
        top = New-SkinFace -X 36 -Y 48 -Width $ArmWidth -Height 4
        bottom = New-SkinFace -X (36 + $ArmWidth) -Y 48 -Width $ArmWidth -Height 4
        right = New-SkinFace -X 32 -Y 52 -Width $rightFaceWidth -Height 12
        front = New-SkinFace -X 36 -Y 52 -Width $ArmWidth -Height 12
        left = New-SkinFace -X (36 + $ArmWidth) -Y 52 -Width 4 -Height 12
        back = New-SkinFace -X (40 + $ArmWidth) -Y 52 -Width $ArmWidth -Height 12
    }
}

function New-LegLayer {
    param(
        [ValidateSet('right', 'left')]
        [string]$Side,
        [ValidateSet('base', 'overlay')]
        [string]$Layer
    )

    if ($Side -eq 'right') {
        $topY = if ($Layer -eq 'overlay') { 32 } else { 16 }
        $y = if ($Layer -eq 'overlay') { 36 } else { 20 }
        return @{
            top = New-SkinFace -X 4 -Y $topY -Width 4 -Height 4
            bottom = New-SkinFace -X 8 -Y $topY -Width 4 -Height 4
            right = New-SkinFace -X 0 -Y $y -Width 4 -Height 12
            front = New-SkinFace -X 4 -Y $y -Width 4 -Height 12
            left = New-SkinFace -X 8 -Y $y -Width 4 -Height 12
            back = New-SkinFace -X 12 -Y $y -Width 4 -Height 12
        }
    }

    if ($Layer -eq 'overlay') {
        return @{
            top = New-SkinFace -X 4 -Y 48 -Width 4 -Height 4
            bottom = New-SkinFace -X 8 -Y 48 -Width 4 -Height 4
            right = New-SkinFace -X 0 -Y 52 -Width 4 -Height 12
            front = New-SkinFace -X 4 -Y 52 -Width 4 -Height 12
            left = New-SkinFace -X 8 -Y 52 -Width 4 -Height 12
            back = New-SkinFace -X 12 -Y 52 -Width 4 -Height 12
        }
    }

    return @{
        top = New-SkinFace -X 20 -Y 48 -Width 4 -Height 4
        bottom = New-SkinFace -X 24 -Y 48 -Width 4 -Height 4
        right = New-SkinFace -X 16 -Y 52 -Width 4 -Height 12
        front = New-SkinFace -X 20 -Y 52 -Width 4 -Height 12
        left = New-SkinFace -X 24 -Y 52 -Width 4 -Height 12
        back = New-SkinFace -X 28 -Y 52 -Width 4 -Height 12
    }
}

function New-MinecraftBodyParts {
    param(
        [ValidateSet('wide', 'slim')]
        [string]$Model
    )

    $armWidth = if ($Model -eq 'slim') { 3 } else { 4 }
    $armHalfGap = 0.28
    $rightArmMaxX = 4.0 + $armHalfGap + [double]$armWidth
    $leftArmMinX = -4.0 - $armHalfGap - [double]$armWidth

    return @(
        (New-CuboidPart -Name 'leftArm' -MinX $leftArmMinX -MinY 8.35 -MinZ -2 -MaxX (-4.0 - $armHalfGap) -MaxY 20.35 -MaxZ 2 -Base (New-ArmLayer -Side left -Layer base -ArmWidth $armWidth) -Overlay (New-ArmLayer -Side left -Layer overlay -ArmWidth $armWidth) -OverlayInflate 0.22),
        (New-CuboidPart -Name 'leftLeg' -MinX -4.02 -MinY 20 -MinZ -2 -MaxX -0.12 -MaxY 32 -MaxZ 2 -Base (New-LegLayer -Side left -Layer base) -Overlay (New-LegLayer -Side left -Layer overlay) -OverlayInflate 0.18),
        (New-CuboidPart -Name 'rightLeg' -MinX 0.12 -MinY 20 -MinZ -2 -MaxX 4.02 -MaxY 32 -MaxZ 2 -Base (New-LegLayer -Side right -Layer base) -Overlay (New-LegLayer -Side right -Layer overlay) -OverlayInflate 0.18),
        (New-CuboidPart -Name 'body' -MinX -4 -MinY 8 -MinZ -2 -MaxX 4 -MaxY 20 -MaxZ 2 -Base (New-BodyLayer) -Overlay (New-BodyOverlayLayer) -OverlayInflate 0.22),
        (New-CuboidPart -Name 'rightArm' -MinX (4.0 + $armHalfGap) -MinY 8.35 -MinZ -2 -MaxX $rightArmMaxX -MaxY 20.35 -MaxZ 2 -Base (New-ArmLayer -Side right -Layer base -ArmWidth $armWidth) -Overlay (New-ArmLayer -Side right -Layer overlay -ArmWidth $armWidth) -OverlayInflate 0.22),
        (New-CuboidPart -Name 'head' -MinX -4 -MinY -0.15 -MinZ -4 -MaxX 4 -MaxY 7.85 -MaxZ 4 -Base (New-HeadLayer) -Overlay (New-HeadLayer -Overlay) -OverlayInflate 0.52)
    )
}

function Draw-MinecraftBody {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Texture,
        [ValidateSet('wide', 'slim')]
        [string]$Model,
        [int]$CanvasWidth,
        [int]$CanvasHeight
    )

    $parts = New-MinecraftBodyParts -Model $Model
    $projection = New-FittedProjection -Parts $parts -CanvasWidth $CanvasWidth -CanvasHeight $CanvasHeight
    $faces = New-Object System.Collections.ArrayList

    foreach ($part in $parts) {
        Add-CuboidLayerFaces -Faces $faces -Part $part -Projection $projection -Layer $part.Base -BrightnessBias 1.0 -LayerOrder 0
        $overlayPart = Get-InflatedPart -Part $part -Inflate ([double]$part.OverlayInflate)
        Add-CuboidLayerFaces -Faces $faces -Part $overlayPart -Projection $projection -Layer $part.Overlay -BrightnessBias 1.0 -LayerOrder 1
    }

    foreach ($face in ($faces | Sort-Object -Property @{ Expression = { $_.Depth }; Ascending = $true }, @{ Expression = { $_.LayerOrder }; Ascending = $true })) {
        Draw-ProjectedSkinFace `
            -Graphics $Graphics `
            -Texture $Texture `
            -Face $face.Face `
            -Points $face.Points `
            -Brightness $face.Brightness
    }
}

$texture = $null
$bitmap = $null
$graphics = $null
$tempOutputPath = $null

try {
    $resolvedSourcePath = [System.IO.Path]::GetFullPath($SourcePath)
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)

    if (-not [System.IO.File]::Exists($resolvedSourcePath)) {
        throw "Source texture does not exist: $resolvedSourcePath"
    }

    $texture = New-Object System.Drawing.Bitmap($resolvedSourcePath)
    if ($texture.Width -ne 64 -or $texture.Height -ne 64) {
        throw "Minecraft skin texture must be exactly 64x64 pixels. actual=$($texture.Width)x$($texture.Height)"
    }

    $parent = [System.IO.Path]::GetDirectoryName($resolvedOutputPath)
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not [System.IO.Directory]::Exists($parent)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }

    $canvasWidth = 130
    $canvasHeight = 260
    $bitmap = New-Object System.Drawing.Bitmap($canvasWidth, $canvasHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $bitmap.SetResolution(96, 96)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighSpeed
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None

    Draw-MinecraftBody -Graphics $graphics -Texture $texture -Model $Model -CanvasWidth $canvasWidth -CanvasHeight $canvasHeight

    $tempOutputPath = $resolvedOutputPath + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
    $bitmap.Save($tempOutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Move-Item -LiteralPath $tempOutputPath -Destination $resolvedOutputPath -Force
    $tempOutputPath = $null
}
finally {
    if ($null -ne $graphics) {
        $graphics.Dispose()
    }
    if ($null -ne $bitmap) {
        $bitmap.Dispose()
    }
    if ($null -ne $texture) {
        $texture.Dispose()
    }
    if (-not [string]::IsNullOrWhiteSpace($tempOutputPath) -and [System.IO.File]::Exists($tempOutputPath)) {
        Remove-Item -LiteralPath $tempOutputPath -Force -ErrorAction SilentlyContinue
    }
}
