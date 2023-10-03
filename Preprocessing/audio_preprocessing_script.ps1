# Ellenőrizze, hogy az alábbi útvonal a helyes-e, és ahol a NAudio.dll fájl található
$naudioDllPath = "C:\naudio.core.2.2.1\lib\netstandard2.0\NAudio.Core.dll"

# Hozzáadja az NAudio.dll fájlt a PowerShell modulokhoz
Import-Module $naudioDllPath

$BASEDIR = "D:\ThesisTest"

# Hozzon létre egy "ogg" nevű mappát a $BASEDIR mappában
$oggFolderPath = "${BASEDIR}\ogg"
mkdir -Force $oggFolderPath

# Másolja be a .ogg kiterjesztésű fájlokat az "ogg" mappába
Copy-Item -Path "${BASEDIR}\*.ogg" -Destination $oggFolderPath

# Kód a ".ogg" fájlok konvertálásához ".wav"-ra
$oggFiles = Get-ChildItem -Path $oggFolderPath -Filter "*.ogg"

mkdir -Force "${BASEDIR}\wavs"

foreach ($oggFile in $oggFiles) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($oggFile.Name)
    $outputPath = "${BASEDIR}\wavs\$baseName.wav"
    ffmpeg -i $oggFile.FullName -ar 16000 $outputPath
}

# Hozzon létre egy "trimmed_wavs" nevű mappát a $BASEDIR mappában
$trimmedWavsFolderPath = "${BASEDIR}\trimmed_wavs"
mkdir -Force $trimmedWavsFolderPath

# Másolja a ".wav" fájlokat a "wavs" mappából a "trimmed_wavs" mappába
Copy-Item -Path "${BASEDIR}\wavs\*.wav" -Destination $trimmedWavsFolderPath

# Ellenőrizze, hogy a "trimmed_wavs" mappa létezik-e
if (Test-Path -Path $trimmedWavsFolderPath -PathType Container) {
    # Listázza ki a .wav fájlokat a "trimmed_wavs" mappából
    $wavFiles = Get-ChildItem -Path $trimmedWavsFolderPath -Filter "*.wav"

    # Iteráljunk végig a .wav fájlokon
    foreach ($wavFile in $wavFiles) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($wavFile.Name)

        $outputFile = "${BASEDIR}\trimmed_wavs\$baseName"
        
        $audio = [NAudio.Wave.WaveFileReader]::new($wavFile.FullName)
        $totalTime = $audio.TotalTime.TotalSeconds
        $sampleRate = $audio.WaveFormat.SampleRate
        $windowSize = ([Math]::Ceiling($sampleRate * 1.0) * 2)  # Az ablak mérete 1 másodperc
        Write-Host "Winsize: $windowSize"

        # Amplitude változások tárolásához
        $maxAmplitudeChange = 0
        $startMaxAmplitudeChange = 0

        # Ablakon belüli számításhoz
        $tempInsideWindowPosition = 0
        $tempSampleValue = 0

        #Trimmelési számításhoz
        $startSeconds = 0.00
        $trimmDurationSeconds = 0.00

        #Az egy ablakra vonatkozó különbségek kiszámítása        
        $tempListOfSamplesSingleWindow = New-Object 'System.Collections.Generic.List[float]'
        $tempListOfSampleDifferences = New-Object 'System.Collections.Generic.List[float]'

        $biggestDifferenceInTheAudioFile = 0.00000000000000000000
        $windowStartTimeOfTheBiggestDifference = 0

        
        for ($start = 0; ($start + $windowSize) -lt ($audio.SampleCount * 2); $start+=4000) {
            

            # Ablakon belüli minták indexének törlése
            $tempInsideWindowPosition = 0
            
            while($tempInsideWindowPosition -le $windowSize) {

                $audio.Position = ($start + $tempInsideWindowPosition)
                $audio.TryReadFloat([ref]$tempSampleValue)         
                $tempListOfSamplesSingleWindow.Add($tempSampleValue)
                $tempInsideWindowPosition += 2
                Write-Host "Amplitude: $tempSampleValue"
            }

            
            # Ciklus az értékek feldolgozásához
            for ($actualIndex = 1; $actualIndex -lt $tempListOfSamplesSingleWindow.Count; $actualIndex++) {
                $currentValue = $tempListOfSamplesSingleWindow[$actualIndex]
                $previousValue = $tempListOfSamplesSingleWindow[$actualIndex - 1]

                # Különbség számítása
                $difference = $currentValue - $previousValue

                # Az új értéket hozzáadhatod egy másik listához
                $tempListOfSampleDifferences.Add($difference)

                # Egyéb műveletek
                Write-Host "Actual value: $currentValue"
                Write-Host "Previous value: $previousValue"
                Write-Host "Difference value: $difference"
            }

            $tempListOfSamplesSingleWindow.Clear()


            # A lista elemeinek abszolútértékeinek összeadása
            $sumOfAbsoluteDifferences = 0

            foreach ($difference in $tempListOfSampleDifferences) {
                $absoluteDifference = [Math]::Abs($difference)
                $sumOfAbsoluteDifferences += $absoluteDifference
            }

            $tempListOfSampleDifferences.Clear()

            # Eredmény kiíratása
            Write-Host "Az aktuális abszolútértékek összege: $sumOfAbsoluteDifferences"

            # Ha ez az érték nagyobb, mint az eddigi maximális amplitúdóváltozás, frissítse a változókat
            if ($sumOfAbsoluteDifferences -gt $biggestDifferenceInTheAudioFile) {
                $biggestDifferenceInTheAudioFile = $sumOfAbsoluteDifferences
                $windowStartTimeOfTheBiggestDifference = $start
            }

            Write-Host "Ablak kezdetének aktuális értéke: $start"
            Write-Host "Legnagyobb különbségeket tartalmazó ablak kezdete: $windowStartTimeOfTheBiggestDifference"
            Write-Host "Legnagyobb különbség egy ablakban: $biggestDifferenceInTheAudioFile"     
        }
        
        $audio.Close()

        # Trim és mentés az új fájlnevű kimeneti fájlba
        $outputFileTrimmed = "${outputFile}_trimmed.wav"

        $startSeconds = (($windowStartTimeOfTheBiggestDifference / 2) / $sampleRate)
        $trimmDurationSeconds = (($windowSize / 2) / $sampleRate)

        & ffmpeg -ss $startSeconds -t $trimmDurationSeconds -i $wavFile.FullName -y $outputFileTrimmed
    }
}
else {
    Write-Host "A '$trimmedWavsFolderPath' mappa nem található."
}

# Ellenőrizze a .wav fájlok hosszát és törölje a nem 1 másodperceseket
$wavFiles = Get-ChildItem -Path "${BASEDIR}\trimmed_wavs" -Filter "*.wav"
$requiredDuration = "00:00:01.00"

foreach ($wavFile in $wavFiles) {
    $duration = (ffmpeg -i $wavFile.FullName 2>&1 | Select-String "Duration: (\d+:\d+:\d+\.\d+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })
    
    if ($duration -ne $requiredDuration) {
        Write-Host "Törlés: $($wavFile.Name), Hossz: $duration"
        Remove-Item -Path $wavFile.FullName -Force
    }
    else {
        Write-Host "Megfelel: $($wavFile.Name), Hossz: $duration"
    }
}