# Snima UART ispis ploce u fajl. Ne treba nikakav dodatni program --
# koristi .NET SerialPort koji PowerShell vec ima.
#
#   powershell -File uart_log.ps1 -Port COM6 -Seconds 60 -Out uart.txt
#
# Baud 115200 je izveden iz ps7_init.tcl (CD=0x7C=124, BDIV=6, UART_CLK=100 MHz
# -> 100e6/(124*7) = 115207), nije pretpostavljen.
param(
    [string]$Port    = "COM6",
    [int]   $Baud    = 115200,
    [int]   $Seconds = 60,
    [string]$Out     = "uart.txt"
)

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.ReadTimeout  = 500
$sp.NewLine      = "`n"
# DTR/RTS ostaju na podrazumevanom -- Zybo UART ih ne koristi za kontrolu toka.

try {
    $sp.Open()
} catch {
    "GRESKA: ne mogu da otvorim $Port -- $($_.Exception.Message)"
    "Ako je port zauzet, zatvori drugi terminal koji ga drzi."
    exit 1
}

"### slusam $Port na $Baud, $Seconds s -> $Out"
$deadline = (Get-Date).AddSeconds($Seconds)
$sb = New-Object System.Text.StringBuilder

while ((Get-Date) -lt $deadline) {
    try {
        $chunk = $sp.ReadExisting()
        if ($chunk.Length -gt 0) {
            [void]$sb.Append($chunk)
            Write-Host -NoNewline $chunk
        } else {
            Start-Sleep -Milliseconds 50
        }
    } catch {
        Start-Sleep -Milliseconds 50
    }
}

$sp.Close()
[IO.File]::WriteAllText($Out, $sb.ToString())
"`n### zavrseno, $($sb.Length) znakova upisano u $Out"
