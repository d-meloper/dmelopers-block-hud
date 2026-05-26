function Get-LowSpecSettingsPolicy {
    @(
        [PSCustomObject][ordered]@{
            FieldKey                     = 'lowSpecFreezeInventoryPlayerAnimation'
            VariableName                 = 'LowSpecFreezeInventoryPlayerAnimation'
            DefaultValue                 = '0'
            LegacyEnabledValue          = '1'
            ExpandFromLegacySingleToggle = $true
        }
        [PSCustomObject][ordered]@{
            FieldKey                     = 'lowSpecDisableSlotHoverHighlight'
            VariableName                 = 'LowSpecDisableSlotHoverHighlight'
            DefaultValue                 = '0'
            LegacyEnabledValue          = '1'
            ExpandFromLegacySingleToggle = $true
        }
        [PSCustomObject][ordered]@{
            FieldKey                     = 'lowSpecDisableHoverTextTooltip'
            VariableName                 = 'LowSpecDisableHoverTextTooltip'
            DefaultValue                 = '0'
            LegacyEnabledValue          = '1'
            ExpandFromLegacySingleToggle = $true
        }
    )
}
