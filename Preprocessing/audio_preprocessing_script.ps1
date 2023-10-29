# Függőségek és változók inicializálása
$BASEDIR = "D:\ThesisTest"
$naudioDllPath = "C:\naudio.core.2.2.1\lib\netstandard2.0\NAudio.Core.dll"
$datasetsPath = "D:\Dataset"
$compressedFileNameToSynchronization = "one_second_words.tar.gz"



# Ellenőrzés, hogy a szkript adminisztrátori jogosultsággal fut-e
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "A szkriptet adminisztrátorként kell futtatni."
   
    # Ha nem adminisztrátori jogokkal indult a szkript, akkor új PowerShell ablakban elindítás adminisztrátorként
    Start-Process powershell -ArgumentList " -NoProfile -ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Definition)" -Verb RunAs
   
    # A futtatás jelenlegi példányának leállítása
    exit
}

# Tájékoztatás arról, hogy a szkript sikeresen elindult adminisztrátori jogosultsággal
Write-Host "A szkript adminisztrátorként fut."

# Ellenőrzés, hogy az ffmpeg mappa létezik-e valamelyik meghajtó gyökérkönyvtárában
$ffmpegFolderExists = $false

foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
    $driveLetter = $drive.Name
    $ffmpegFolderPath = "${driveLetter}:\ffmpeg"

    if (Test-Path -Path $ffmpegFolderPath -PathType Container) {
        $ffmpegFolderExists = $true
        break  # Kilépés a ciklusból, ha talál egy meghajtót, ahol létezik az "ffmpeg" mappa
    }
}

if ($ffmpegFolderExists) {
    # Ha az ffmpeg mappa megtalálható valamelyik meghajtó gyökérkönyvtárában, akkor ugrás a további utasításokra
    Write-Host "Az ffmpeg mappa megtalálható valamelyik meghajtó gyökérkönyvtárában."

    # Ellenőrzés, hogy az ffmpeg mappa bin mappája hozzá van-e adva a PATH környezeti változókhoz (user variables és system variables)
    $ffmpegPath = "${driveLetter}:\ffmpeg\bin"  # Az ffmpeg mappa bin mappájának elérési útja

    # Ellenőrizze a user variables PATH változót
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")

    if ($userPath -notlike "*$ffmpegPath*") {
        # Ha az ffmpeg mappa bin mappája nincs hozzáadva a user variables PATH változóhoz, akkor hozzáadás
        [System.Environment]::SetEnvironmentVariable("PATH", "$userPath;$ffmpegPath", "User")
        Write-Host "Az ffmpeg mappa bin mappája hozzáadva a user variables PATH változóhoz."
    }
    else {
        Write-Host "Az ffmpeg mappa bin mappája már hozzá van adva a user variables PATH változóhoz."
    }

    # Ellenőrizze a system variables PATH változót (adminisztrátori jogosultsággal végrehajtható)
    $systemPath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")

    if ($systemPath -notlike "*$ffmpegPath*") {
        # Ha az ffmpeg mappa bin mappája nincs hozzáadva a system variables PATH változóhoz, akkor hozzáadás
        [System.Environment]::SetEnvironmentVariable("PATH", "$systemPath;$ffmpegPath", "Machine")
        Write-Host "Az ffmpeg mappa bin mappája hozzáadva a system variables PATH változóhoz."
    }
    else {
        Write-Host "Az ffmpeg mappa bin mappája már hozzá van adva a system variables PATH változóhoz."
    }

    # Az ffmpeg mappa bin mappája hozzá van adva a PATH változókhoz
    Write-Host "Az ffmpeg mappa bin mappája hozzá van adva a PATH változókhoz."
}
else {
    # Ha az ffmpeg mappa nem található egyik meghajtó gyökérkönyvtárban sem, kivételt dob és leáll a program
    throw "Az ffmpeg mappa nem található egyik meghajtó gyökérkönyvtárban sem."
}



if (Test-Path -Path $naudioDllPath -PathType Leaf) {
    # Ha az NAudio.dll fájl megtalálható, importálás a PowerShell-be
    Import-Module $naudioDllPath
}
else {
    # Ha az NAudio.dll fájl nem található, kivételt dob és leáll a program
    throw "Az NAudio.dll fájl nem található a következő helyen: $naudioDllPath"
}

# Az NAudio.dll fájl megtalálható és betöltve lett
Write-Host "Az NAudio.dll fájl betöltve."



# Egy "ogg" nevű mappa létrehozása a $BASEDIR mappában
$oggFolderPath = "${BASEDIR}\ogg"
mkdir -Force $oggFolderPath

# Az .ogg kiterjesztésű fájlok áthelyezése az "ogg" mappába
Move-Item -Path "${BASEDIR}\*.ogg" -Destination $oggFolderPath

# A ".ogg" fájlok átkonvertálása ".wav"-ra
$oggFiles = Get-ChildItem -Path $oggFolderPath -Filter "*.ogg"

mkdir -Force "${BASEDIR}\wavs"

foreach ($oggFile in $oggFiles) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($oggFile.Name)
    $outputPath = "${BASEDIR}\wavs\$baseName.wav"
    ffmpeg -i $oggFile.FullName -ar 16000 $outputPath
}



# Egy "trimmed_wavs" nevű mappa létrehozása a $BASEDIR mappában
$trimmedWavsFolderPath = "${BASEDIR}\trimmed_wavs"
mkdir -Force $trimmedWavsFolderPath

# A ".wav" fájlok másolása a "wavs" mappából a "trimmed_wavs" mappába
Copy-Item -Path "${BASEDIR}\wavs\*.wav" -Destination $trimmedWavsFolderPath

# Ellenőrzés, hogy a "trimmed_wavs" mappa létezik-e
if (Test-Path -Path $trimmedWavsFolderPath -PathType Container) {
    # Listázza ki a .wav fájlokat a "trimmed_wavs" mappából
    $wavFiles = Get-ChildItem -Path $trimmedWavsFolderPath -Filter "*.wav"

    # Iteráció a wav fájlokon
    foreach ($wavFile in $wavFiles) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($wavFile.Name)

        $outputFile = "${BASEDIR}\trimmed_wavs\$baseName"
       
        $audio = [NAudio.Wave.WaveFileReader]::new($wavFile.FullName)
        $totalTime = $audio.TotalTime.TotalSeconds
        $sampleRate = $audio.WaveFormat.SampleRate
        $windowSize = ([Math]::Ceiling($sampleRate * 1.0) * 2)  # Az ablak mérete 1 másodperc
        Write-Host "Winsize: $windowSize"

        # Amplitudó változások tárolásához
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

        $biggestDifferenceInTheAudioFile = 0.00
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

                # Az új érték hozzáadása a másik listához
                $tempListOfSampleDifferences.Add($difference)

                # Aktuálisan számított értékek kiíratása
                Write-Host "Actual value: $currentValue"
                Write-Host "Previous value: $previousValue"
                Write-Host "Difference value: $difference"
            }

            $tempListOfSamplesSingleWindow.Clear()


            # A listaelemek abszolútértékeinek összeadása
            $sumOfAbsoluteDifferences = 0

            foreach ($difference in $tempListOfSampleDifferences) {
                $absoluteDifference = [Math]::Abs($difference)
                $sumOfAbsoluteDifferences += $absoluteDifference
            }

            $tempListOfSampleDifferences.Clear()

            # Eredmény kiíratása
            Write-Host "Az aktuális abszolútértékek összege: $sumOfAbsoluteDifferences"

            # Ha ez az érték nagyobb, mint az eddigi maximális amplitúdóváltozás, a változók frissítése
            if ($sumOfAbsoluteDifferences -gt $biggestDifferenceInTheAudioFile) {
                $biggestDifferenceInTheAudioFile = $sumOfAbsoluteDifferences
                $windowStartTimeOfTheBiggestDifference = $start
            }

            # Eredmények kiíratása
            Write-Host "Ablak kezdetének aktuális értéke: $start"
            Write-Host "Legnagyobb különbségeket tartalmazó ablak kezdete: $windowStartTimeOfTheBiggestDifference"
            Write-Host "Legnagyobb különbség egy ablakban: $biggestDifferenceInTheAudioFile"    
        }
       
        $audio.Close()

        # Vágás és mentés új néven egy kimeneti fájlba
        $outputFileTrimmed = "${outputFile}_trimmed.wav"

        $startSeconds = (($windowStartTimeOfTheBiggestDifference / 2) / $sampleRate)
        $trimmDurationSeconds = (($windowSize / 2) / $sampleRate)

        & ffmpeg -ss $startSeconds -t $trimmDurationSeconds -i $wavFile.FullName -y $outputFileTrimmed
    }
}
else {
    throw "A '$trimmedWavsFolderPath' mappa nem található."
}



# A .wav fájlok hosszának ellenőrzése és a nem 1 másodperc hosszúságúak törlése
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

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($wavFile.Name)

        # Fájlnév kiolvasása: az OpenSpeechCommands a szavak jelentése után _ karakterrel választja el a sorszámot
        $firstWord = $baseName.Split('_')[0]

        # A kiolvasott szavak számára mappa létrehozása
        $outputFolder = Join-Path -Path ${BASEDIR} -ChildPath $firstWord
        mkdir -Force $outputFolder

        # Fájl rendezése a megfelelő mappába
        $outputPath = Join-Path -Path $outputFolder -ChildPath "$baseName.wav"
        Move-Item -Path $wavFile.FullName -Destination $outputPath
    }
}



# "ogg" mappa eltakarítása
if (Test-Path -Path $oggFolderPath -PathType Container) {
    Remove-Item -Path $oggFolderPath -Recurse -Force
    Write-Host "Az 'ogg' mappa és annak tartalma törölve."
}
else {
    Write-Host "Az 'ogg' mappa nem található."
}

# "wavs" mappa eltakarítása
if (Test-Path -Path "${BASEDIR}\wavs" -PathType Container) {
    Remove-Item -Path "${BASEDIR}\wavs" -Recurse -Force
    Write-Host "A 'wavs' mappa és annak tartalma törölve."
}
else {
    Write-Host "A 'wavs' mappa nem található."
}

# "trimmed_wavs" mappa eltakarítása
if (Test-Path -Path $trimmedWavsFolderPath -PathType Container) {
    Remove-Item -Path $trimmedWavsFolderPath -Recurse -Force
    Write-Host "A 'trimmed_wavs' mappa és annak tartalma törölve."
}
else {
    Write-Host "A 'trimmed_wavs' mappa nem található."
}

# Ellenőrzés, hogy az adatkészletet tartalmazó mappa létezik-e, ha nem, akkor létrehozás
if (-not (Test-Path -Path $datasetsPath -PathType Container)) {
    New-Item -Path $datasetsPath -ItemType Directory
    Write-Host "A $datasetsPath mappa nem található, ezért új mappaként létrehozva."
}
else {
    Write-Host "A $datasetsPath mappa megtalálva."
}

# Ellenőrzés, hogy az adatkészlet kezelhető, tömörítetlen fájljait tartalmazó mappa létezik-e, ha nem, akkor létrehozás
$filesPath = Join-Path -Path $datasetsPath -ChildPath "Files"
if (-not (Test-Path -Path $filesPath -PathType Container)) {
    New-Item -Path $filesPath -ItemType Directory
    Write-Host "A $filesPath mappa nem található, ezért új mappaként létrehozva."
}
else {
    Write-Host "A $filesPath mappa megtalálva."
}

# Ellenőrzés, hogy az adatkészlet tömörített fájljait tartalmazó mappa létezik-e, ha nem, akkor létrehozás
$compressedPath = Join-Path -Path $datasetsPath -ChildPath "Compressed"
if (-not (Test-Path -Path $compressedPath -PathType Container)) {
    New-Item -Path $compressedPath -ItemType Directory
    Write-Host "A $compressedPath mappa nem található, ezért új mappaként létrehozva."
}
else {
    Write-Host "A $compressedPath mappa megtalálva."
}

# Ellenőrzés, hogy a különböző szavakat tartalmazó mappa létezik-e, ha nem, akkor létrehozás
$oneSecondWordsPath = Join-Path -Path $filesPath -ChildPath "one_second_words"
# Ellenőrzi, hogy a mappa létezik.
if (-not (Test-Path -Path $oneSecondWordsPath -PathType Container)) {
    New-Item -Path $oneSecondWordsPath -ItemType Directory
    Write-Host "A $oneSecondWordsPath mappa nem található, ezért új mappaként létrehozva."
}
else {
    Write-Host "A $oneSecondWordsPath mappa megtalálva."
}

# Ellenőrzés, hogy a különböző szavakat tartalmazó mappában vannak-e fájlok, ha üres, vagy csak kevés, akkor letöltés az internetről
$filesInFolder = Get-ChildItem -Path $oneSecondWordsPath
if ($filesInFolder.Count -le 5) {
    Write-Host "A $oneSecondWordsPath mappa üres vagy nem tartalmaz elegendő fájlt. Adatkészlet letöltésének elindítása."
    $downloadURL = "https://storage.googleapis.com/download.tensorflow.org/data/speech_commands_v0.02.tar.gz"
    $downloadedFile = Join-Path -Path $filesPath -ChildPath "speech_commands_v0.02.tar.gz"
    Invoke-WebRequest -Uri $downloadURL -OutFile $downloadedFile

    # A letöltött adatok kicsomagolása
    tar -xzvf $downloadedFile -C $oneSecondWordsPath

    # Letöltött, tömörített fájl törlése
    Remove-Item -Path $downloadedFile
    Write-Host "Adatkészlet letöltve és kicsomagolva a $oneSecondWordsPath mappába."
}
else {
    Write-Host "A $oneSecondWordsPath mappa tartalmaz korábbi fájlokat."
}

# $BASEDIR mappa ellenőrzése, a rendezett fájlok másolása a különböző szavakat tartalmazó mappába, majd a $BASEDIR kiürítése
if (Test-Path -Path $BASEDIR -PathType Container) {
    Get-ChildItem -Path $BASEDIR -Directory | ForEach-Object {
        $destinationPath = Join-Path -Path $oneSecondWordsPath -ChildPath $_.Name
        Copy-Item -Path $_.FullName -Destination $destinationPath -Recurse
        Remove-Item -Path $_.FullName -Recurse -Force
    }

    Write-Host "Adatkészlet fájlstruktúra előkészítve a felhőoldali integrációhoz. Tömörítés elindítása."
}
else {
    throw "Nem található a megvágott hangokat tartalmazó mappa a $BASEDIR helyen."
}

# A vegyes adatkészletet tartalmazó mappa tömörítése, majd másolása a tömörített fájlnak és a felhőszinkronizációnak kijelölt mappába
$CompressedFileRespresentation = Join-Path -Path $compressedPath -ChildPath $compressedFileNameToSynchronization
if (Test-Path $oneSecondWordsPath -PathType Container) {
    tar -cvzf $CompressedFileRespresentation -C $oneSecondWordsPath .
    Write-Host "Adathalmaz sikeresen tömörítve: $CompressedFileRespresentation."
    Write-Host "A szinkronizációt követően a hangfájlok felhasználhatóvá válnak a felhőből."
    }
else {
    throw "Tömörítés nem lehetséges, mert a $oneSecondWordsPath mappa nem található."
}