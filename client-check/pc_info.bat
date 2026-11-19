@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: ============================================================================
:: ИНИЦИАЛИЗАЦИЯ ПЕРЕМЕННЫХ И ПУТЕЙ
:: ============================================================================
set "REPORT_FILE=%~dp0pc_report.txt"
set "TEMP_APPS=%TEMP%\apps_list_%RANDOM%.txt"
set "TEMP_RAW=%TEMP%\apps_raw_%RANDOM%.txt"

set /a CHECKED_BASE=0
set /a REC_COUNT=0

:: Очистка старого файла отчета перед началом
if exist "%REPORT_FILE%" del /f /q "%REPORT_FILE%"

echo [*] Запуск аудита рабочего места...
echo [*] Идет сбор сведений об оборудовании и ОС...

:: ============================================================================
:: ЗАГОЛОВОК ОТЧЕТА С ВРЕМЕННОЙ МЕТКОЙ
:: ============================================================================
call :log "======================================================================"
call :log "ОТЧЕТ АУДИТА РАБОЧЕГО МЕСТА"
call :log "Дата и время формирования: %DATE% %TIME%"
call :log "Имя компьютера: %COMPUTERNAME% | Пользователь: %USERNAME%"
call :log "======================================================================"
call :log ""

:: ============================================================================
:: БЛОК 1. СБОР ДАННЫХ ОБ ОС, ПРОЦЕССОРЕ, ПАМЯТИ И ДИСКЕ (С ЗАЩИТОЙ ОТ СБОЕВ)
:: ============================================================================
call :log "[1. АППАРАТНАЯ И СИСТЕМНАЯ КОНФИГУРАЦИЯ]"

:: --- Операционная система ---
set "OS_NAME="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).Caption" 2^>nul`) do set "OS_NAME=%%I"
if defined OS_NAME (
    call :log "Операционная система: %OS_NAME%"
) else (
    call :log "Операционная система: [Не удалось получить данные]"
)

:: --- Процессор ---
set "CPU_NAME="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "(Get-CimInstance Win32_Processor | Select-Object -First 1).Name" 2^>nul`) do set "CPU_NAME=%%I"
if defined CPU_NAME (
    call :log "Процессор: %CPU_NAME%"
) else (
    call :log "Процессор: [Не удалось получить данные]"
)

:: --- Оперативная память (расчет в ГБ через PowerShell без переполнения) ---
set "RAM_GB="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)" 2^>nul`) do set "RAM_GB=%%I"
if defined RAM_GB (
    call :log "Оперативная память: %RAM_GB% ГБ"
) else (
    call :log "Оперативная память: [Не удалось получить данные]"
)

:: --- Свободное место на системном диске C: ---
set "DISK_FREE="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "[math]::Round((Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='C:'\").FreeSpace / 1GB, 2)" 2^>nul`) do set "DISK_FREE=%%I"
if defined DISK_FREE (
    call :log "Свободно на диске C:: %DISK_FREE% ГБ"
) else (
    call :log "Свободно на диске C:: [Не удалось получить данные]"
)
call :log ""

:: ============================================================================
:: БЛОК 2. ФОРМИРОВАНИЕ СПИСКА УСТАНОВЛЕННОГО ПО ИЗ РЕЕСТРА (64 И 32 БИТА)
:: ============================================================================
echo [*] Идет опрос реестра установленных программ (может занять несколько секунд)...

if exist "%TEMP_RAW%" del /f /q "%TEMP_RAW%"
if exist "%TEMP_APPS%" del /f /q "%TEMP_APPS%"

:: Опрос 64-битной ветки реестра
for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /v DisplayName 2^>nul ^| findstr /i "DisplayName"') do (
    echo %%B>>"%TEMP_RAW%"
)

:: Опрос 32-битной ветки реестра (WOW6432Node)
for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" /s /v DisplayName 2^>nul ^| findstr /i "DisplayName"') do (
    echo %%B>>"%TEMP_RAW%"
)

:: Опрос программ текущего пользователя
for /f "tokens=2*" %%A in ('reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /v DisplayName 2^>nul ^| findstr /i "DisplayName"') do (
    echo %%B>>"%TEMP_RAW%"
)

:: Сортировка и удаление дубликатов через PowerShell
if exist "%TEMP_RAW%" (
    powershell -NoProfile -Command "Get-Content '%TEMP_RAW%' -Encoding Default | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | Sort-Object -Unique | Set-Content '%TEMP_APPS%' -Encoding UTF8"
) else (
    type nul > "%TEMP_APPS%"
)

:: ============================================================================
:: БЛОК 3. АНАЛИЗ БАЗОВОГО ОФИСНОГО ПО
:: ============================================================================
echo [*] Анализ наличия базового офисного ПО...
call :log "[2. РЕКОМЕНДАЦИИ ПО БАЗОВОМУ ОФИСНОМУ ПО]"
call :log "Эталонный стандарт: офисный пакет, архиватор, PDF-ридер, браузер, антивирус."
call :log ""

:: 1. Офисный пакет
call :check_base "Офисный пакет" "Office|LibreOffice|OpenOffice|МойОфис|Р7-Офис" "Не обнаружен офисный пакет. Для работы с документами и таблицами рекомендуется установить LibreOffice или Р7-Офис."

:: 2. Архиватор
call :check_base "Архиватор" "7-Zip|WinRAR|WinZip|PeaZip" "Не обнаружен архиватор. Для работы с вложениями в почте рекомендуется установить 7-Zip или WinRAR."

:: 3. Программа для чтения PDF
call :check_base "Просмотр PDF" "Acrobat|Foxit|SumatraPDF|PDF-XChange" "Не обнаружена специализированная программа для чтения PDF. Рекомендуется установить SumatraPDF или Adobe Acrobat Reader."

:: 4. Браузер (отдельная проверка на системный Edge)
set /a CHECKED_BASE+=1
set "FOUND_ALT_BROWSER="
for /f "usebackq delims=" %%P in (`findstr /i /r "Chrome Firefox Яндекс Yandex Opera" "%TEMP_APPS%" 2^>nul`) do (
    if not defined FOUND_ALT_BROWSER set "FOUND_ALT_BROWSER=%%P"
)
if defined FOUND_ALT_BROWSER (
    call :log "[OK] Браузер: требование выполнено (обнаружено: !FOUND_ALT_BROWSER!)."
) else (
    findstr /i "Edge" "%TEMP_APPS%" >nul 2>&1
    if !errorlevel! equ 0 (
        call :log "[ВНИМАНИЕ] Браузер: обнаружен только встроенный компонент системы Microsoft Edge. Рекомендуется проверить, требуется ли установка корпоративного браузера (Яндекс.Браузер или Chrome)."
        set /a REC_COUNT+=1
    ) else (
        call :log "[РЕКОМЕНДАЦИЯ] Не обнаружен сторонний браузер. Рекомендуется установить Яндекс.Браузер или Google Chrome."
        set /a REC_COUNT+=1
    )
)

:: 5. Антивирусная защита (проверка реестра + службы Защитника Windows)
set /a CHECKED_BASE+=1
set "FOUND_AV="
for /f "usebackq delims=" %%P in (`findstr /i /r "Kaspersky ESET Dr.Web Avast AVG Bitdefender" "%TEMP_APPS%" 2^>nul`) do (
    if not defined FOUND_AV set "FOUND_AV=%%P"
)
if defined FOUND_AV (
    call :log "[OK] Антивирус: требование выполнено (обнаружено: !FOUND_AV!)."
) else (
    sc query WinDefend | findstr /i "RUNNING" >nul 2>&1
    if !errorlevel! equ 0 (
        call :log "[OK] Антивирус: активен встроенный компонент системы Microsoft Defender."
    ) else (
        call :log "[РЕКОМЕНДАЦИЯ] Не обнаружен активный антивирус. Рекомендуется включить Microsoft Defender или установить корпоративный антивирус (Kaspersky / Dr.Web)."
        set /a REC_COUNT+=1
    )
)
call :log ""

:: ============================================================================
:: БЛОК 4. АНАЛИЗ ИЗЛИШНЕГО / НЕПРОФИЛЬНОГО ПО
:: ============================================================================
echo [*] Проверка на наличие непрофильного ПО...
call :log "[3. ПРОВЕРКА НА НАЛИЧИЕ НЕПРОФИЛЬНОГО ПО]"
call :log "ПРИМЕЧАНИЕ: Данный раздел носит рекомендательный характер. Наличие программы в списке"
call :log "означает, что она не относится к базовым офисным задачам и подлежит проверке администратором."
call :log ""

call :check_extra "Группа 1: Игровое ПО и платформы" "Steam|Epic Games|GOG|Origin|Ubisoft Connect|Battle\.net|Riot|game|gaming"
call :check_extra "Группа 2: Торрент-клиенты и файлообменники" "torrent|uTorrent|BitTorrent|qBittorrent|Vuze|Zona"
call :check_extra "Группа 3: Мессенджеры (проверка соответствия регламенту)" "Discord|Telegram|WhatsApp|Viber|Skype"
call :check_extra "Группа 4: Развлечения, стриминг и мультимедиа" "Wallpaper Engine|OBS|Soundpad|VLC|AIMP|PotPlayer|Media Player Classic"

:: ============================================================================
:: ИТОГИ И ОЧИСТКА ВРЕМЕННЫХ ФАЙЛОВ
:: ============================================================================
call :log "======================================================================"
call :log "ИТОГИ АУДИТА:"
call :log "- Проверено категорий базового ПО: %CHECKED_BASE%"
call :log "- Сформировано рекомендаций и замечаний: %REC_COUNT%"
call :log "- Полный путь к файлу отчета: %REPORT_FILE%"
call :log "======================================================================"

:: Удаление временных файлов
if exist "%TEMP_RAW%" del /f /q "%TEMP_RAW%"
if exist "%TEMP_APPS%" del /f /q "%TEMP_APPS%"

echo.
echo [ГОТОВО] Аудит успешно завершен.
echo Отчет сохранен по пути: %REPORT_FILE%
echo.
pause
exit /b 0

:: ============================================================================
:: ПОДПРОГРАММЫ
:: ============================================================================

:: Подпрограмма :log — единая точка вывода на экран и в файл отчета
:log
set "MSG=%~1"
if "%MSG%"=="" (
    echo(
    echo(>>"%REPORT_FILE%"
) else (
    echo(!MSG!
    echo(!MSG!>>"%REPORT_FILE%"
)
exit /b

:: Подпрограмма :check_base — проверка наличия программы из эталонной категории
:check_base
set "CAT_NAME=%~1"
set "PATTERNS=%~2"
set "ADVICE=%~3"
set /a CHECKED_BASE+=1
set "FOUND_ITEM="

for /f "usebackq delims=" %%P in (`findstr /i /r "%PATTERNS%" "%TEMP_APPS%" 2^>nul`) do (
    if not defined FOUND_ITEM set "FOUND_ITEM=%%P"
)

if defined FOUND_ITEM (
    call :log "[OK] %CAT_NAME%: требование выполнено (обнаружено: !FOUND_ITEM!)."
) else (
    call :log "[РЕКОМЕНДАЦИЯ] %ADVICE%"
    set /a REC_COUNT+=1
)
exit /b

:: Подпрограмма :check_extra — поиск программ из групп риска
:check_extra
set "GROUP_TITLE=%~1"
set "PATTERNS=%~2"
set "HAS_MATCH=0"
call :log "--- %GROUP_TITLE% ---"
for /f "usebackq delims=" %%P in (findstr /i /r "%PATTERNS%" "%TEMP_APPS%" 2^>nul) do (
call :log "  [!] Подлежит проверке: %%P"
set "HAS_MATCH=1"
set /a REC_COUNT+=1
)
if "!HAS_MATCH!"=="0" (
call :log "  Программ данной группы не обнаружено."
)
call :log ""
exit /b

