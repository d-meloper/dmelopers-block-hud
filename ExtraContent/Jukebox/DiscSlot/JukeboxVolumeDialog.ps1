[CmdletBinding()]
param(
    [int]$InitialValue = 100,
    [int]$CenterX = 0,
    [int]$CenterY = 0,
    [string]$Title = 'Volume',
    [string]$LabelText = 'Volume (0-100)',
    [string]$CancelText = 'Cancel',
    [string]$ApplyText = 'Apply'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$form = $null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

function Write-DmelPair {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowNull()][object]$Value
    )

    $text = ''
    if ($null -ne $Value) {
        $text = [string]$Value
    }
    $text = $text -replace "`r", ' ' -replace "`n", ' '
    [Console]::Out.WriteLine(("{0}={1}" -f $Key, $text))
}

function Complete-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [int]$Value = 0,
        [string]$Code = ''
    )

    Write-DmelPair -Key 'DMEL_STATUS' -Value $Status
    Write-DmelPair -Key 'DMEL_VALUE' -Value (Clamp-Volume -Value $Value)
    if (-not [string]::IsNullOrWhiteSpace($Code)) {
        Write-DmelPair -Key 'DMEL_CODE' -Value $Code
    }
}

function Clamp-Volume {
    param([AllowNull()][object]$Value)

    $parsed = 0
    if (-not [int]::TryParse(([string]$Value).Trim(), [ref]$parsed)) {
        $parsed = 0
    }
    if ($parsed -lt 0) {
        return 0
    }
    if ($parsed -gt 100) {
        return 100
    }
    return $parsed
}

function Get-SafeText {
    param(
        [AllowNull()][string]$Value,
        [Parameter(Mandatory = $true)][string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Fallback
    }
    return $Value.Trim()
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $state = [PSCustomObject]@{
        Result = 'CANCEL'
        Value = Clamp-Volume -Value $InitialValue
        UpdatingText = $false
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = Get-SafeText -Value $Title -Fallback 'Volume'
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.ClientSize = New-Object System.Drawing.Size(252, 132)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $label = New-Object System.Windows.Forms.Label
    $label.AutoSize = $false
    $label.Text = Get-SafeText -Value $LabelText -Fallback 'Volume (0-100)'
    $label.Location = New-Object System.Drawing.Point(12, 12)
    $label.Size = New-Object System.Drawing.Size(228, 20)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(12, 40)
    $textBox.Size = New-Object System.Drawing.Size(160, 24)
    $textBox.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Right
    $textBox.Text = [string]$state.Value

    $upButton = New-Object System.Windows.Forms.Button
    $upButton.Location = New-Object System.Drawing.Point(180, 38)
    $upButton.Size = New-Object System.Drawing.Size(28, 24)
    $upButton.Text = [string][char]0x25B2
    $upButton.TabStop = $false

    $downButton = New-Object System.Windows.Forms.Button
    $downButton.Location = New-Object System.Drawing.Point(212, 38)
    $downButton.Size = New-Object System.Drawing.Size(28, 24)
    $downButton.Text = [string][char]0x25BC
    $downButton.TabStop = $false

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(84, 92)
    $cancelButton.Size = New-Object System.Drawing.Size(76, 28)
    $cancelButton.Text = Get-SafeText -Value $CancelText -Fallback 'Cancel'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $applyButton = New-Object System.Windows.Forms.Button
    $applyButton.Location = New-Object System.Drawing.Point(166, 92)
    $applyButton.Size = New-Object System.Drawing.Size(76, 28)
    $applyButton.Text = Get-SafeText -Value $ApplyText -Fallback 'Apply'
    $applyButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $form.Controls.AddRange(@($label, $textBox, $upButton, $downButton, $cancelButton, $applyButton))
    $form.AcceptButton = $applyButton
    $form.CancelButton = $cancelButton

    $syncText = {
        param([int]$Value)
        $state.UpdatingText = $true
        try {
            $state.Value = Clamp-Volume -Value $Value
            $textBox.Text = [string]$state.Value
            $textBox.SelectionStart = $textBox.Text.Length
        }
        finally {
            $state.UpdatingText = $false
        }
    }

    $textBox.Add_KeyPress({
        param($sender, $eventArgs)
        if ([char]::IsControl($eventArgs.KeyChar) -or [char]::IsDigit($eventArgs.KeyChar)) {
            return
        }
        $eventArgs.Handled = $true
    })

    $textBox.Add_TextChanged({
        if ($state.UpdatingText) {
            return
        }
        if ([string]::IsNullOrWhiteSpace($textBox.Text)) {
            return
        }
        $clamped = Clamp-Volume -Value $textBox.Text
        if ($textBox.Text -ne [string]$clamped) {
            & $syncText $clamped
        }
        else {
            $state.Value = $clamped
        }
    })

    $upButton.Add_Click({ & $syncText ($state.Value + 1) })
    $downButton.Add_Click({ & $syncText ($state.Value - 1) })

    $applyButton.Add_Click({
        & $syncText (Clamp-Volume -Value $textBox.Text)
        $state.Result = 'OK'
    })

    $cancelButton.Add_Click({
        $state.Result = 'CANCEL'
    })

    $form.Add_Shown({
        $point = New-Object System.Drawing.Point($CenterX, $CenterY)
        $screen = [System.Windows.Forms.Screen]::FromPoint($point)
        $area = $screen.WorkingArea
        $x = [Math]::Round($CenterX - ($form.Width / 2))
        $y = [Math]::Round($CenterY - ($form.Height / 2))
        $x = [Math]::Max($area.Left, [Math]::Min($x, $area.Right - $form.Width))
        $y = [Math]::Max($area.Top, [Math]::Min($y, $area.Bottom - $form.Height))
        $form.Location = New-Object System.Drawing.Point([int]$x, [int]$y)
        $textBox.SelectAll()
        $textBox.Focus()
        $form.TopMost = $true
        $form.BringToFront()
        $form.Activate()
    })

    $dialogResult = $form.ShowDialog()
    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK -and $state.Result -eq 'OK') {
        Complete-Result -Status 'OK' -Value $state.Value
    }
    else {
        Complete-Result -Status 'CANCEL' -Value $state.Value
    }
}
catch {
    Complete-Result -Status 'ERROR' -Value $InitialValue -Code 'VOLUME_DIALOG_FAILED'
}
finally {
    if ($form -ne $null) {
        $form.Dispose()
    }
}
