Add-Type -AssemblyName System.Drawing

$script:BlockHudMinecraftSkinTuning = $null
$script:BlockHudMinecraftSkinHotOptions = $null

function Set-MinecraftSkinRenderTuning {
    param([string]$Path)

    $script:BlockHudMinecraftSkinTuning = $null
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $script:BlockHudMinecraftSkinTuning = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    Initialize-MinecraftSkinRenderHotOptions
}

function Get-MinecraftSkinRenderTuningValue {
    param(
        [string]$Path,
        $Default
    )

    $value = $script:BlockHudMinecraftSkinTuning
    if ($null -eq $value) {
        return $Default
    }
    foreach ($segment in $Path.Split('.')) {
        $property = $value.PSObject.Properties[$segment]
        if ($null -eq $property -or $null -eq $property.Value) {
            return $Default
        }
        $value = $property.Value
    }
    return $value
}

function Get-MinecraftSkinRenderTuningDouble {
    param([string]$Path, [double]$Default)
    return [double](Get-MinecraftSkinRenderTuningValue -Path $Path -Default $Default)
}

function Get-MinecraftSkinRenderTuningInt {
    param([string]$Path, [int]$Default)
    return [int](Get-MinecraftSkinRenderTuningValue -Path $Path -Default $Default)
}

function Get-MinecraftSkinRenderTuningString {
    param([string]$Path, [string]$Default)
    return [string](Get-MinecraftSkinRenderTuningValue -Path $Path -Default $Default)
}

function Get-MinecraftSkinRenderTuningEnum {
    param([type]$Type, [string]$Path, [string]$Default)
    return [System.Enum]::Parse($Type, (Get-MinecraftSkinRenderTuningString -Path $Path -Default $Default), $true)
}

function Initialize-MinecraftSkinRenderHotOptions {
    $script:BlockHudMinecraftSkinHotOptions = @{
        BodyYawScale = Get-MinecraftSkinRenderTuningDouble '자세.몸통좌우회전_라디안당도' 20.0
        BodyYawOffset = Get-MinecraftSkinRenderTuningDouble '자세.몸통좌우회전_기본오프셋도' 0.0
        HeadYawScale = Get-MinecraftSkinRenderTuningDouble '자세.머리좌우회전_라디안당도' 5.0
        HeadYawOffset = Get-MinecraftSkinRenderTuningDouble '자세.머리좌우회전_기본오프셋도' 0.0
        HeadPitchScale = Get-MinecraftSkinRenderTuningDouble '자세.머리상하회전_라디안당도' -13.0
        HeadPitchOffset = Get-MinecraftSkinRenderTuningDouble '자세.머리상하회전_기본오프셋도' 0.0
        ModelPitchScale = Get-MinecraftSkinRenderTuningDouble '자세.전체몸상하회전_라디안당도' -5.0
        ModelPitchOffset = Get-MinecraftSkinRenderTuningDouble '자세.전체몸상하회전_기본오프셋도' 0.0
        HeadPivotY = Get-MinecraftSkinRenderTuningDouble '자세.머리회전축세로좌표' 8.0
        ModelPivotY = Get-MinecraftSkinRenderTuningDouble '자세.전체몸회전축세로좌표' 16.0
        BrightnessFront = Get-MinecraftSkinRenderTuningDouble '조명.앞면' 1.0
        BrightnessTop = Get-MinecraftSkinRenderTuningDouble '조명.윗면' 1.08
        BrightnessLeft = Get-MinecraftSkinRenderTuningDouble '조명.왼쪽면' 0.76
        BrightnessRight = Get-MinecraftSkinRenderTuningDouble '조명.오른쪽면' 0.82
        BrightnessBack = Get-MinecraftSkinRenderTuningDouble '조명.뒷면' 0.62
        BrightnessBottom = Get-MinecraftSkinRenderTuningDouble '조명.아랫면' 0.56
        CullThreshold = Get-MinecraftSkinRenderTuningDouble '렌더링.뒷면제거임계값' 0.001
        BrightnessCacheDigits = Get-MinecraftSkinRenderTuningInt '렌더링.밝기캐시키소수자리' 5
        BaseBrightnessBias = Get-MinecraftSkinRenderTuningDouble '렌더링.기본레이어밝기배율' 1.0
        BaseLayerOrder = Get-MinecraftSkinRenderTuningInt '렌더링.기본레이어순서' 0
        OverlayBrightnessBias = Get-MinecraftSkinRenderTuningDouble '렌더링.오버레이레이어밝기배율' 1.0
        OverlayLayerOrder = Get-MinecraftSkinRenderTuningInt '렌더링.오버레이레이어순서' 1
    }
}

Initialize-MinecraftSkinRenderHotOptions

function New-PointF {
    param(
        [double]$X,
        [double]$Y
    )

    return [System.Drawing.PointF]::new([single]$X, [single]$Y)
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

function New-LookPose {
    param(
        [double]$HorizontalRadians,
        [double]$VerticalRadians
    )

    $options = $script:BlockHudMinecraftSkinHotOptions
    $bodyYawDegrees = ([double]$HorizontalRadians * [double]$options.BodyYawScale) + [double]$options.BodyYawOffset
    $headYawDegrees = ([double]$HorizontalRadians * [double]$options.HeadYawScale) + [double]$options.HeadYawOffset
    $headPitchDegrees = ([double]$VerticalRadians * [double]$options.HeadPitchScale) + [double]$options.HeadPitchOffset
    $modelPitchDegrees = ([double]$VerticalRadians * [double]$options.ModelPitchScale) + [double]$options.ModelPitchOffset
    $bodyYaw = Convert-DegreesToRadians $bodyYawDegrees
    $headYaw = Convert-DegreesToRadians $headYawDegrees
    $headPitch = Convert-DegreesToRadians $headPitchDegrees
    $modelPitch = Convert-DegreesToRadians $modelPitchDegrees
    return @{
        HorizontalRadians = [double]$HorizontalRadians
        VerticalRadians = [double]$VerticalRadians
        BodyYawDegrees = $bodyYawDegrees
        HeadYawDegrees = $headYawDegrees
        HeadPitchDegrees = $headPitchDegrees
        ModelPitchDegrees = $modelPitchDegrees
        BodyYawSin = -[Math]::Sin($bodyYaw)
        BodyYawCos = [Math]::Cos($bodyYaw)
        HeadYawSin = -[Math]::Sin($headYaw)
        HeadYawCos = [Math]::Cos($headYaw)
        HeadPitchSin = -[Math]::Sin($headPitch)
        HeadPitchCos = [Math]::Cos($headPitch)
        ModelPitchSin = -[Math]::Sin($modelPitch)
        ModelPitchCos = [Math]::Cos($modelPitch)
    }
}

function Convert-MinecraftPointForPose {
    param(
        [hashtable]$Point,
        [string]$PartName,
        [AllowNull()][hashtable]$Pose,
        [switch]$Normal
    )

    if ($null -eq $Pose) {
        return $Point
    }

    $x = [double]$Point.X
    $y = [double]$Point.Y
    $z = [double]$Point.Z
    if ($PartName -eq 'head') {
        $headPivotY = if ($Normal) { 0.0 } else { [double]$script:BlockHudMinecraftSkinHotOptions.HeadPivotY }
        $relativeY = $y - $headPivotY
        $rotatedY = $headPivotY + ($relativeY * [double]$Pose.HeadPitchCos) - ($z * [double]$Pose.HeadPitchSin)
        $rotatedZ = ($relativeY * [double]$Pose.HeadPitchSin) + ($z * [double]$Pose.HeadPitchCos)
        $y = $rotatedY
        $z = $rotatedZ

        $rotatedX = ($x * [double]$Pose.HeadYawCos) + ($z * [double]$Pose.HeadYawSin)
        $rotatedZ = (-$x * [double]$Pose.HeadYawSin) + ($z * [double]$Pose.HeadYawCos)
        $x = $rotatedX
        $z = $rotatedZ
    }

    $rotatedX = ($x * [double]$Pose.BodyYawCos) + ($z * [double]$Pose.BodyYawSin)
    $rotatedZ = (-$x * [double]$Pose.BodyYawSin) + ($z * [double]$Pose.BodyYawCos)
    $x = $rotatedX
    $z = $rotatedZ

    $modelPivotY = if ($Normal) { 0.0 } else { [double]$script:BlockHudMinecraftSkinHotOptions.ModelPivotY }
    $relativeY = $y - $modelPivotY
    $rotatedY = $modelPivotY + ($relativeY * [double]$Pose.ModelPitchCos) - ($z * [double]$Pose.ModelPitchSin)
    $rotatedZ = ($relativeY * [double]$Pose.ModelPitchSin) + ($z * [double]$Pose.ModelPitchCos)
    return (New-WorldPoint -X $x -Y $rotatedY -Z $rotatedZ)
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
        [hashtable]$Point,
        [string]$PartName = '',
        [AllowNull()][hashtable]$Pose = $null
    )

    $renderPoint = Convert-MinecraftPointForPose -Point $Point -PartName $PartName -Pose $Pose
    $camera = Convert-ToCameraPoint -Projection $Projection -X $renderPoint.X -Y $renderPoint.Y -Z $renderPoint.Z
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

    $options = $script:BlockHudMinecraftSkinHotOptions
    if ($FaceName -eq 'front') {
        return [double]$options.BrightnessFront
    }
    if ($FaceName -eq 'top') {
        return [double]$options.BrightnessTop
    }
    if ($FaceName -eq 'left') {
        return [double]$options.BrightnessLeft
    }
    if ($FaceName -eq 'right') {
        return [double]$options.BrightnessRight
    }
    if ($FaceName -eq 'back') {
        return [double]$options.BrightnessBack
    }
    return [double]$options.BrightnessBottom
}

function Get-ProjectedBounds {
    param(
        [hashtable[]]$Parts,
        [hashtable]$Projection,
        [AllowNull()][hashtable]$Pose = $null
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
                    $point = Project-MinecraftPoint `
                        -Projection $Projection `
                        -Point (New-WorldPoint -X $x -Y $y -Z $z) `
                        -PartName $part.Name `
                        -Pose $Pose
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
        [int]$CanvasHeight,
        [double]$YawDegrees = 26.0,
        [double]$PitchDegrees = -11.0,
        [AllowNull()][hashtable]$Pose = $null
    )

    $YawDegrees = Get-MinecraftSkinRenderTuningDouble '투영.정적이미지.카메라좌우각도' $YawDegrees
    $PitchDegrees = Get-MinecraftSkinRenderTuningDouble '투영.정적이미지.카메라상하각도' $PitchDegrees
    $baseProjection = New-Projection -YawDegrees $YawDegrees -PitchDegrees $PitchDegrees -Scale 1.0 -OriginX 0.0 -OriginY 0.0
    $bounds = Get-ProjectedBounds -Parts $Parts -Projection $baseProjection -Pose $Pose
    $paddingX = Get-MinecraftSkinRenderTuningDouble '투영.정적이미지.좌우여백' 2.0
    $paddingTop = Get-MinecraftSkinRenderTuningDouble '투영.정적이미지.위여백' 2.0
    $paddingBottom = Get-MinecraftSkinRenderTuningDouble '투영.정적이미지.아래여백' 3.0
    $scaleX = ([double]$CanvasWidth - ($paddingX * 2.0)) / [double]$bounds.Width
    $scaleY = ([double]$CanvasHeight - $paddingTop - $paddingBottom) / [double]$bounds.Height
    $scale = [Math]::Min($scaleX, $scaleY) * (Get-MinecraftSkinRenderTuningDouble '투영.정적이미지.크기배율' 1.0)
    $renderWidth = [double]$bounds.Width * $scale
    $renderHeight = [double]$bounds.Height * $scale
    $originX = (([double]$CanvasWidth - $renderWidth) / 2.0) - ([double]$bounds.MinX * $scale) + (Get-MinecraftSkinRenderTuningDouble '투영.정적이미지.가로위치보정' 0.0)
    $originY = $paddingTop - ([double]$bounds.MinY * $scale) + ((([double]$CanvasHeight - $paddingTop - $paddingBottom - $renderHeight) / 2.0) * (Get-MinecraftSkinRenderTuningDouble '투영.정적이미지.세로중심보정' 0.35)) + (Get-MinecraftSkinRenderTuningDouble '투영.정적이미지.세로위치보정' 0.0)

    return New-Projection -YawDegrees $YawDegrees -PitchDegrees $PitchDegrees -Scale $scale -OriginX $originX -OriginY $originY
}

function New-LookAtlasProjection {
    param(
        [hashtable[]]$Parts,
        [hashtable[]]$Poses,
        [int]$CanvasWidth,
        [int]$CanvasHeight
    )

    $lookYawDegrees = Get-MinecraftSkinRenderTuningDouble '투영.커서추적.카메라좌우각도' 0.0
    $lookPitchDegrees = Get-MinecraftSkinRenderTuningDouble '투영.커서추적.카메라상하각도' 0.0
    $baseProjection = New-Projection -YawDegrees $lookYawDegrees -PitchDegrees $lookPitchDegrees -Scale 1.0 -OriginX 0.0 -OriginY 0.0
    $minX = [double]::PositiveInfinity
    $minY = [double]::PositiveInfinity
    $maxX = [double]::NegativeInfinity
    $maxY = [double]::NegativeInfinity
    foreach ($pose in $Poses) {
        $bounds = Get-ProjectedBounds -Parts $Parts -Projection $baseProjection -Pose $pose
        $minX = [Math]::Min($minX, [double]$bounds.MinX)
        $minY = [Math]::Min($minY, [double]$bounds.MinY)
        $maxX = [Math]::Max($maxX, [double]$bounds.MaxX)
        $maxY = [Math]::Max($maxY, [double]$bounds.MaxY)
    }

    $paddingX = Get-MinecraftSkinRenderTuningDouble '투영.커서추적.좌우여백' 2.0
    $paddingTop = Get-MinecraftSkinRenderTuningDouble '투영.커서추적.위여백' 2.0
    $paddingBottom = Get-MinecraftSkinRenderTuningDouble '투영.커서추적.아래여백' 3.0
    $boundsWidth = $maxX - $minX
    $boundsHeight = $maxY - $minY
    $scaleX = ([double]$CanvasWidth - ($paddingX * 2.0)) / $boundsWidth
    $scaleY = ([double]$CanvasHeight - $paddingTop - $paddingBottom) / $boundsHeight
    $scale = [Math]::Min($scaleX, $scaleY) * (Get-MinecraftSkinRenderTuningDouble '투영.커서추적.크기배율' 1.0)
    $renderWidth = $boundsWidth * $scale
    $renderHeight = $boundsHeight * $scale
    $originX = (([double]$CanvasWidth - $renderWidth) / 2.0) - ($minX * $scale) + (Get-MinecraftSkinRenderTuningDouble '투영.커서추적.가로위치보정' 0.0)
    $originY = $paddingTop - ($minY * $scale) + ((([double]$CanvasHeight - $paddingTop - $paddingBottom - $renderHeight) / 2.0) * (Get-MinecraftSkinRenderTuningDouble '투영.커서추적.세로중심보정' 0.35)) + (Get-MinecraftSkinRenderTuningDouble '투영.커서추적.세로위치보정' 0.0)
    return New-Projection -YawDegrees $lookYawDegrees -PitchDegrees $lookPitchDegrees -Scale $scale -OriginX $originX -OriginY $originY
}

function Add-ProjectionOffset {
    param(
        [hashtable]$Projection,
        [double]$OffsetX,
        [double]$OffsetY
    )

    return @{
        YawSin = [double]$Projection.YawSin
        YawCos = [double]$Projection.YawCos
        PitchSin = [double]$Projection.PitchSin
        PitchCos = [double]$Projection.PitchCos
        Scale = [double]$Projection.Scale
        OriginX = [double]$Projection.OriginX + $OffsetX
        OriginY = [double]$Projection.OriginY + $OffsetY
    }
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
        [int]$LayerOrder,
        [AllowNull()][hashtable]$Pose = $null
    )

    $normal = Get-FaceNormal -FaceName $FaceName
    $normal = Convert-MinecraftPointForPose -Point $normal -PartName $Part.Name -Pose $Pose -Normal
    $cameraNormal = Convert-ToCameraPoint -Projection $Projection -X $normal.X -Y $normal.Y -Z $normal.Z
    if ([double]$cameraNormal.Z -le [double]$script:BlockHudMinecraftSkinHotOptions.CullThreshold) {
        return $null
    }

    $corners = Get-FaceCorners -Part $Part -FaceName $FaceName
    $cameraCorners = [object[]]::new($corners.Count)
    for ($cornerIndex = 0; $cornerIndex -lt $corners.Count; $cornerIndex++) {
        $corner = $corners[$cornerIndex]
        $renderCorner = Convert-MinecraftPointForPose -Point $corner -PartName $Part.Name -Pose $Pose
        $cameraCorners[$cornerIndex] = Convert-ToCameraPoint -Projection $Projection -X $renderCorner.X -Y $renderCorner.Y -Z $renderCorner.Z
    }
    $points = [System.Drawing.PointF[]]@(
        (New-PointF -X ([double]$Projection.OriginX + ([double]$cameraCorners[0].X * [double]$Projection.Scale)) -Y ([double]$Projection.OriginY + ([double]$cameraCorners[0].Y * [double]$Projection.Scale))),
        (New-PointF -X ([double]$Projection.OriginX + ([double]$cameraCorners[1].X * [double]$Projection.Scale)) -Y ([double]$Projection.OriginY + ([double]$cameraCorners[1].Y * [double]$Projection.Scale))),
        (New-PointF -X ([double]$Projection.OriginX + ([double]$cameraCorners[3].X * [double]$Projection.Scale)) -Y ([double]$Projection.OriginY + ([double]$cameraCorners[3].Y * [double]$Projection.Scale)))
    )

    $depth = 0.0
    foreach ($cameraCorner in $cameraCorners) {
        $depth += [double]$cameraCorner.Z
    }
    $depth = $depth / [double]$corners.Count

    return @{
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
        [int]$LayerOrder,
        [AllowNull()][hashtable]$Pose = $null
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
            -LayerOrder $LayerOrder `
            -Pose $Pose
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
        [double]$Brightness,
        [AllowNull()][hashtable]$FaceBitmapCache = $null
    )

    $faceBitmap = $null
    $ownsFaceBitmap = $true
    try {
        if ($null -ne $FaceBitmapCache) {
            $cacheKey = '{0},{1},{2},{3},{4}' -f $Face.X, $Face.Y, $Face.Width, $Face.Height, ([Math]::Round($Brightness, [int]$script:BlockHudMinecraftSkinHotOptions.BrightnessCacheDigits))
            if (-not $FaceBitmapCache.ContainsKey($cacheKey)) {
                $FaceBitmapCache[$cacheKey] = New-ShadedFaceBitmap -Texture $Texture -Face $Face -Brightness $Brightness
            }
            $faceBitmap = $FaceBitmapCache[$cacheKey]
            $ownsFaceBitmap = $false
        }
        else {
            $faceBitmap = New-ShadedFaceBitmap -Texture $Texture -Face $Face -Brightness $Brightness
        }
        $Graphics.DrawImage($faceBitmap, $Points)
    }
    finally {
        if ($ownsFaceBitmap -and $null -ne $faceBitmap) {
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

    $armWidth = if ($Model -eq 'slim') {
        Get-MinecraftSkinRenderTuningInt '형상.슬림팔텍스처너비' 3
    } else {
        Get-MinecraftSkinRenderTuningInt '형상.일반팔텍스처너비' 4
    }
    $leftArmMinX = if ($Model -eq 'slim') {
        Get-MinecraftSkinRenderTuningDouble '형상.부위.왼팔.최소가로_슬림' -7.28
    } else {
        Get-MinecraftSkinRenderTuningDouble '형상.부위.왼팔.최소가로_일반' -8.28
    }
    $rightArmMaxX = if ($Model -eq 'slim') {
        Get-MinecraftSkinRenderTuningDouble '형상.부위.오른팔.최대가로_슬림' 7.28
    } else {
        Get-MinecraftSkinRenderTuningDouble '형상.부위.오른팔.최대가로_일반' 8.28
    }

    return @(
        (New-CuboidPart -Name 'leftArm' -MinX $leftArmMinX -MinY (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼팔.최소세로' 8.35) -MinZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼팔.최소깊이' -2.0) -MaxX (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼팔.최대가로' -4.28) -MaxY (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼팔.최대세로' 20.35) -MaxZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼팔.최대깊이' 2.0) -Base (New-ArmLayer -Side left -Layer base -ArmWidth $armWidth) -Overlay (New-ArmLayer -Side left -Layer overlay -ArmWidth $armWidth) -OverlayInflate (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼팔.오버레이팽창' 0.22)),
        (New-CuboidPart -Name 'leftLeg' -MinX (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼다리.최소가로' -4.02) -MinY (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼다리.최소세로' 20.0) -MinZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼다리.최소깊이' -2.0) -MaxX (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼다리.최대가로' -0.12) -MaxY (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼다리.최대세로' 32.0) -MaxZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼다리.최대깊이' 2.0) -Base (New-LegLayer -Side left -Layer base) -Overlay (New-LegLayer -Side left -Layer overlay) -OverlayInflate (Get-MinecraftSkinRenderTuningDouble '형상.부위.왼다리.오버레이팽창' 0.18)),
        (New-CuboidPart -Name 'rightLeg' -MinX (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른다리.최소가로' 0.12) -MinY (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른다리.최소세로' 20.0) -MinZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른다리.최소깊이' -2.0) -MaxX (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른다리.최대가로' 4.02) -MaxY (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른다리.최대세로' 32.0) -MaxZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른다리.최대깊이' 2.0) -Base (New-LegLayer -Side right -Layer base) -Overlay (New-LegLayer -Side right -Layer overlay) -OverlayInflate (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른다리.오버레이팽창' 0.18)),
        (New-CuboidPart -Name 'body' -MinX (Get-MinecraftSkinRenderTuningDouble '형상.부위.몸통.최소가로' -4.2) -MinY (Get-MinecraftSkinRenderTuningDouble '형상.부위.몸통.최소세로' 8.0) -MinZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.몸통.최소깊이' -2.0) -MaxX (Get-MinecraftSkinRenderTuningDouble '형상.부위.몸통.최대가로' 4.2) -MaxY (Get-MinecraftSkinRenderTuningDouble '형상.부위.몸통.최대세로' 20.0) -MaxZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.몸통.최대깊이' 2.0) -Base (New-BodyLayer) -Overlay (New-BodyOverlayLayer) -OverlayInflate (Get-MinecraftSkinRenderTuningDouble '형상.부위.몸통.오버레이팽창' 0.22)),
        (New-CuboidPart -Name 'rightArm' -MinX (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른팔.최소가로' 4.28) -MinY (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른팔.최소세로' 8.35) -MinZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른팔.최소깊이' -2.0) -MaxX $rightArmMaxX -MaxY (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른팔.최대세로' 20.35) -MaxZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른팔.최대깊이' 2.0) -Base (New-ArmLayer -Side right -Layer base -ArmWidth $armWidth) -Overlay (New-ArmLayer -Side right -Layer overlay -ArmWidth $armWidth) -OverlayInflate (Get-MinecraftSkinRenderTuningDouble '형상.부위.오른팔.오버레이팽창' 0.22)),
        (New-CuboidPart -Name 'head' -MinX (Get-MinecraftSkinRenderTuningDouble '형상.부위.머리.최소가로' -4.0) -MinY (Get-MinecraftSkinRenderTuningDouble '형상.부위.머리.최소세로' -0.15) -MinZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.머리.최소깊이' -4.0) -MaxX (Get-MinecraftSkinRenderTuningDouble '형상.부위.머리.최대가로' 4.0) -MaxY (Get-MinecraftSkinRenderTuningDouble '형상.부위.머리.최대세로' 7.85) -MaxZ (Get-MinecraftSkinRenderTuningDouble '형상.부위.머리.최대깊이' 4.0) -Base (New-HeadLayer) -Overlay (New-HeadLayer -Overlay) -OverlayInflate (Get-MinecraftSkinRenderTuningDouble '형상.부위.머리.오버레이팽창' 0.52))
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
        [int]$CanvasHeight,
        [AllowNull()][hashtable]$Projection = $null,
        [AllowNull()][hashtable]$Pose = $null,
        [AllowNull()][hashtable]$FaceBitmapCache = $null,
        [AllowNull()][hashtable[]]$Parts = $null
    )

    if ($null -eq $Parts) {
        $Parts = New-MinecraftBodyParts -Model $Model
    }
    if ($null -eq $Projection) {
        $Projection = New-FittedProjection -Parts $Parts -CanvasWidth $CanvasWidth -CanvasHeight $CanvasHeight
    }
    $faces = [System.Collections.ArrayList]::new(24)
    $options = $script:BlockHudMinecraftSkinHotOptions

    foreach ($part in $Parts) {
        Add-CuboidLayerFaces -Faces $faces -Part $part -Projection $Projection -Layer $part.Base -BrightnessBias ([double]$options.BaseBrightnessBias) -LayerOrder ([int]$options.BaseLayerOrder) -Pose $Pose
        $overlayPart = Get-InflatedPart -Part $part -Inflate ([double]$part.OverlayInflate)
        Add-CuboidLayerFaces -Faces $faces -Part $overlayPart -Projection $Projection -Layer $part.Overlay -BrightnessBias ([double]$options.OverlayBrightnessBias) -LayerOrder ([int]$options.OverlayLayerOrder) -Pose $Pose
    }

    foreach ($face in ($faces | Sort-Object -Property @{ Expression = { $_.Depth }; Ascending = $true }, @{ Expression = { $_.LayerOrder }; Ascending = $true })) {
        Draw-ProjectedSkinFace `
            -Graphics $Graphics `
            -Texture $Texture `
            -Face $face.Face `
            -Points $face.Points `
            -Brightness $face.Brightness `
            -FaceBitmapCache $FaceBitmapCache
    }
}

function New-LookAtlasPoses {
    $poses = New-Object System.Collections.ArrayList
    $horizontalRange = Get-MinecraftSkinRenderTuningDouble '아틀라스.좌우최대입력라디안' ([Math]::PI / 2.0)
    $verticalRange = Get-MinecraftSkinRenderTuningDouble '아틀라스.상하최대입력라디안' ([Math]::PI / 2.0)
    $horizontalFactors = @(Get-MinecraftSkinRenderTuningValue '아틀라스.좌우셀배율' @(-1.0, -0.833333333333333, -0.666666666666667, -0.5, -0.333333333333333, -0.166666666666667, 0.0, 0.166666666666667, 0.333333333333333, 0.5, 0.666666666666667, 0.833333333333333, 1.0))
    $verticalFactors = @(Get-MinecraftSkinRenderTuningValue '아틀라스.상하셀배율' @(-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 0.75, 1.0))
    for ($row = 0; $row -lt 9; $row++) {
        $verticalRadians = [double]$verticalFactors[$row] * $verticalRange
        for ($column = 0; $column -lt 13; $column++) {
            $horizontalRadians = [double]$horizontalFactors[$column] * $horizontalRange
            [void]$poses.Add((New-LookPose -HorizontalRadians $horizontalRadians -VerticalRadians $verticalRadians))
        }
    }
    return [hashtable[]]$poses.ToArray()
}

function Get-MinecraftLookAtlasProgressPercent {
    param(
        [int]$CompletedFrames,
        [int]$TotalFrames = 117
    )

    if ($TotalFrames -le 0 -or $CompletedFrames -le 0) { return 0 }
    if ($CompletedFrames -ge $TotalFrames) { return 100 }
    return [int]([Math]::Floor((($CompletedFrames * 100.0) / $TotalFrames) / 5.0) * 5)
}

function Draw-MinecraftLookAtlas {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Texture,
        [ValidateSet('wide', 'slim')]
        [string]$Model,
        [int]$CanvasWidth,
        [int]$CanvasHeight,
        [AllowNull()][scriptblock]$ProgressCallback = $null
    )

    $faceBitmapCache = @{}
    try {
        $lastProgress = -1
        if ($null -ne $ProgressCallback) {
            & $ProgressCallback 0
            $lastProgress = 0
        }
        $parts = New-MinecraftBodyParts -Model $Model
        $poses = New-LookAtlasPoses
        $baseProjection = New-LookAtlasProjection -Parts $parts -Poses $poses -CanvasWidth $CanvasWidth -CanvasHeight $CanvasHeight
        for ($row = 0; $row -lt 9; $row++) {
            for ($column = 0; $column -lt 13; $column++) {
                $poseIndex = ($row * 13) + $column
                $projection = Add-ProjectionOffset `
                    -Projection $baseProjection `
                    -OffsetX ([double]($column * $CanvasWidth)) `
                    -OffsetY ([double]($row * $CanvasHeight))
                Draw-MinecraftBody `
                    -Graphics $Graphics `
                    -Texture $Texture `
                    -Model $Model `
                    -CanvasWidth $CanvasWidth `
                    -CanvasHeight $CanvasHeight `
                    -Projection $projection `
                    -Pose $poses[$poseIndex] `
                    -FaceBitmapCache $faceBitmapCache `
                    -Parts $parts
                if ($null -ne $ProgressCallback) {
                    $completedFrames = $poseIndex + 1
                    $progress = Get-MinecraftLookAtlasProgressPercent -CompletedFrames $completedFrames -TotalFrames 117
                    if ($progress -gt $lastProgress) {
                        & $ProgressCallback ([int]$progress)
                        $lastProgress = [int]$progress
                    }
                }
            }
        }
    }
    finally {
        foreach ($cachedBitmap in $faceBitmapCache.Values) {
            if ($null -ne $cachedBitmap) {
                $cachedBitmap.Dispose()
            }
        }
    }
}

function Complete-AtomicPngWrite {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemporaryPath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if ([System.IO.File]::Exists($DestinationPath)) {
        $backupPath = $TemporaryPath + '.bak'
        [System.IO.File]::Replace($TemporaryPath, $DestinationPath, $backupPath, $true)
        try {
            if ([System.IO.File]::Exists($backupPath)) {
                [System.IO.File]::Delete($backupPath)
            }
        }
        catch {
            Write-Verbose ("Committed PNG replacement left backup '{0}': {1}" -f $backupPath, [string]$_.Exception.Message)
        }
    }
    else {
        [System.IO.File]::Move($TemporaryPath, $DestinationPath)
    }
}

function ConvertTo-WpfOptimizedPng {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    $resolvedSourcePath = [System.IO.Path]::GetFullPath($SourcePath)
    $optimizedPath = $resolvedSourcePath + '.wpf'
    $inputStream = $null
    $outputStream = $null
    $completed = $false

    try {
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        $inputStream = [System.IO.File]::Open(
            $resolvedSourcePath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        $decoder = [System.Windows.Media.Imaging.PngBitmapDecoder]::new(
            $inputStream,
            [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
            [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        )
        $frame = $decoder.Frames[0]
        $inputStream.Dispose()
        $inputStream = $null

        $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
        [void]$encoder.Frames.Add($frame)
        $outputStream = [System.IO.File]::Open(
            $optimizedPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $encoder.Save($outputStream)
        $outputStream.Dispose()
        $outputStream = $null

        if ((-not [System.IO.File]::Exists($optimizedPath)) -or ([System.IO.FileInfo]::new($optimizedPath).Length -le 0)) {
            throw 'WPF PNG encoder did not produce a non-empty output file.'
        }

        $completed = $true
        return $optimizedPath
    }
    catch {
        Write-Verbose ("WPF PNG optimization skipped for '{0}': {1}" -f $resolvedSourcePath, [string]$_.Exception.Message)
        return $null
    }
    finally {
        if ($null -ne $inputStream) {
            $inputStream.Dispose()
        }
        if ($null -ne $outputStream) {
            $outputStream.Dispose()
        }
        if (-not $completed -and [System.IO.File]::Exists($optimizedPath)) {
            Remove-Item -LiteralPath $optimizedPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-MinecraftSkinRender {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [ValidateSet('wide', 'slim')]
        [string]$Model = 'wide',
        [ValidateSet('Static', 'LookAtlas')]
        [string]$RenderMode = 'Static',
        [ValidateRange(1, 1024)]
        [int]$FrameWidth = 130,
        [ValidateRange(1, 1024)]
        [int]$FrameHeight = 260,
        [string]$TuningPath = '',
        [AllowNull()][scriptblock]$ProgressCallback = $null
    )

    $texture = $null
    $bitmap = $null
    $graphics = $null
    $tempOutputPath = $null
    $optimizedTempOutputPath = $null

    try {
    Set-MinecraftSkinRenderTuning -Path $TuningPath
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

    $canvasWidth = if ($RenderMode -eq 'LookAtlas') { $FrameWidth * 13 } else { $FrameWidth }
    $canvasHeight = if ($RenderMode -eq 'LookAtlas') { $FrameHeight * 9 } else { $FrameHeight }
    $pixelFormat = Get-MinecraftSkinRenderTuningEnum ([System.Drawing.Imaging.PixelFormat]) '래스터.픽셀형식' 'Format32bppPArgb'
    $bitmap = New-Object System.Drawing.Bitmap($canvasWidth, $canvasHeight, $pixelFormat)
    $bitmap.SetResolution((Get-MinecraftSkinRenderTuningDouble '래스터.가로점밀도' 96.0), (Get-MinecraftSkinRenderTuningDouble '래스터.세로점밀도' 96.0))
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::FromArgb((Get-MinecraftSkinRenderTuningInt '래스터.배경색정수' 0)))
    $graphics.CompositingMode = Get-MinecraftSkinRenderTuningEnum ([System.Drawing.Drawing2D.CompositingMode]) '래스터.합성모드' 'SourceOver'
    $graphics.CompositingQuality = Get-MinecraftSkinRenderTuningEnum ([System.Drawing.Drawing2D.CompositingQuality]) '래스터.합성품질' 'HighSpeed'
    $graphics.InterpolationMode = Get-MinecraftSkinRenderTuningEnum ([System.Drawing.Drawing2D.InterpolationMode]) '래스터.보간모드' 'NearestNeighbor'
    $graphics.PixelOffsetMode = Get-MinecraftSkinRenderTuningEnum ([System.Drawing.Drawing2D.PixelOffsetMode]) '래스터.픽셀오프셋모드' 'Half'
    $graphics.SmoothingMode = Get-MinecraftSkinRenderTuningEnum ([System.Drawing.Drawing2D.SmoothingMode]) '래스터.스무딩모드' 'None'

    if ($RenderMode -eq 'LookAtlas') {
        Draw-MinecraftLookAtlas -Graphics $graphics -Texture $texture -Model $Model -CanvasWidth $FrameWidth -CanvasHeight $FrameHeight -ProgressCallback $ProgressCallback
    }
    else {
        Draw-MinecraftBody -Graphics $graphics -Texture $texture -Model $Model -CanvasWidth $FrameWidth -CanvasHeight $FrameHeight
    }

    $tempOutputPath = $resolvedOutputPath + '.' + [System.Guid]::NewGuid().ToString('N') + '.tmp'
    $bitmap.Save($tempOutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $graphics = $null
    $bitmap.Dispose()
    $bitmap = $null
    if ($RenderMode -eq 'LookAtlas') {
        $optimizedTempOutputPath = ConvertTo-WpfOptimizedPng -SourcePath $tempOutputPath
    }
    if (-not [string]::IsNullOrWhiteSpace($optimizedTempOutputPath)) {
        Complete-AtomicPngWrite -TemporaryPath $optimizedTempOutputPath -DestinationPath $resolvedOutputPath
        $optimizedTempOutputPath = $null
    }
    else {
        Complete-AtomicPngWrite -TemporaryPath $tempOutputPath -DestinationPath $resolvedOutputPath
        $tempOutputPath = $null
    }
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
        if (-not [string]::IsNullOrWhiteSpace($optimizedTempOutputPath) -and [System.IO.File]::Exists($optimizedTempOutputPath)) {
            Remove-Item -LiteralPath $optimizedTempOutputPath -Force -ErrorAction SilentlyContinue
        }
    }
}
