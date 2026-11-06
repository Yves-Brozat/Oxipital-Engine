function New-EN16ColorConversion([int]$Component) {
    if($Component -lt 0 -or $Component -gt 2){throw 'Expected an RGB component index.'}
    # Conversion stores explicit links. Unlike Convert To Float's dynamic
    # Extract Component enum, these indices survive rebuilding the input.
    [pscustomobject]@{
        niceName='Extract '+@('Red','Green','Blue')[$Component]
        type='Mega Converter'
        convertedParameters=[pscustomobject]@{items=@([pscustomobject]@{
            niceName='Channel Value';shortName='channelValue';type='Float'
            parameters=@([pscustomobject]@{controlAddress='/defaultValue';value=0.0})
        })}
        links=@([pscustomobject]@{sourceIndex=0;sourceValueIndex=$Component;out='channelValue';outValueIndex=0})
    }
}
