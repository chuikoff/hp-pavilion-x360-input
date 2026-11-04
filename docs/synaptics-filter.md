# Клавиатура и тачпад: снятие фильтра SynTP

Инструкция для HP Pavilion x360 Convertible 14-dh0xxx, Windows 11.
Компьютер: `DESKTOP-6U89JI4`.

Это первая из двух правок. Октябрьские повторы после уже снятого фильтра совпали с новыми драйверами Intel ME. Их версии и установка задач описаны в [README](../README.md).

## Симптом

Не работают встроенная клавиатура и тачпад. USB-мышь при этом работает.

Причина: фильтр Synaptics `SynTP` стоял в стеке обоих устройств и не пропускал ввод. USB-мышь идёт мимо этого фильтра.

Рабочий стек после исправления:

- Клавиатура: `kbdclass` → `i8042prt` → ACPI
- Тачпад: `mouclass` → `mouhid` → `mshidkmdf`

## Без командной строки

Те же правки через редактор реестра и диспетчер устройств. Нужны права администратора: Windows спросит подтверждение при открытии редактора реестра.

### 1. Убрать SynTP у клавиатуры

1. Нажать `Win + R`, ввести `regedit`, нажать Enter и подтвердить запрос.
2. Вставить в адресную строку редактора реестра и нажать Enter:

   `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\{4d36e96b-e325-11ce-bfc1-08002be10318}`

3. Справа дважды щёлкнуть параметр `UpperFilters`.
4. В списке две строки: `SynTP` и `kbdclass`. Удалить строку `SynTP`. Строку `kbdclass` оставить.
5. Нажать ОК.

Если удалить `kbdclass`, клавиатура после перезагрузки не поднимется.

### 2. Убрать SynTP у тачпада

1. В том же окне реестра открыть:

   `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\HID\SYNA328B&Col01\5&29f54c&0&0000`

2. Справа найти параметр `UpperFilters`. В нём одна строка: `SynTP`.
3. Щёлкнуть его правой кнопкой → Удалить → Да.

Удалять нужно только параметр `UpperFilters`, не всю папку устройства.

Если такой папки нет, идентификатор сменился после обновления драйвера:

1. `Win + X` → Диспетчер устройств.
2. Раздел «Мыши и иные указывающие устройства» → «Synaptics PrecisionTouchpad Filter Driver».
3. Правой кнопкой → Свойства → вкладка Сведения.
4. В списке выбрать «Путь к экземпляру устройства». Скопировать значение. Оно выглядит как `HID\SYNA328B&COL01\5&…\0&0000`.
5. В реестре открыть `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\` и дальше этот путь: `HID` заменить не нужно, он уже есть в пути. Пример: значение `HID\SYNA328B&COL01\5&29F54C&0&0000` — это ключ `Enum\HID\SYNA328B&Col01\5&29f54c&0&0000`.
6. Удалить параметр `UpperFilters` в найденном ключе, как выше.

### 3. Перезапустить тачпад

1. `Win + X` → Диспетчер устройств.
2. «Мыши и иные указывающие устройства» → «Synaptics PrecisionTouchpad Filter Driver».
3. Правой кнопкой → Отключить устройство → Да.
4. Правой кнопкой по тому же пункту → Включить устройство.
5. Проверить тачпад рукой.

### 4. Перезагрузить компьютер

Клавиатура подхватывает новый список фильтров только после перезагрузки.

Пуск → питание → Перезагрузка.

После входа проверить клавиши и ещё раз тачпад. В реестре у класса клавиатуры в `UpperFilters` должна остаться только строка `kbdclass`. У тачпада параметра `UpperFilters` быть не должно.

## Через PowerShell

Нужен PowerShell от администратора. Пуск → ввести `PowerShell` → «Запуск от имени администратора».

### 1. Убрать SynTP с класса клавиатуры

В разделе фильтров класса должен остаться только `kbdclass`.

```powershell
$kbdClass = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96b-e325-11ce-bfc1-08002be10318}"
Set-ItemProperty -Path $kbdClass -Name UpperFilters -Value ([string[]]@("kbdclass"))
(Get-ItemProperty $kbdClass).UpperFilters
```

Ожидаемый вывод: `kbdclass`.

### 2. Убрать SynTP с устройства тачпада

Ключ этого компьютера:

`HKLM:\SYSTEM\CurrentControlSet\Enum\HID\SYNA328B&Col01\5&29f54c&0&0000`

```powershell
$tpReg = "HKLM:\SYSTEM\CurrentControlSet\Enum\HID\SYNA328B&Col01\5&29f54c&0&0000"
Remove-ItemProperty -Path $tpReg -Name UpperFilters -ErrorAction SilentlyContinue
```

Если после обновления драйвера идентификатор устройства другой, найти ключ так:

```powershell
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\HID" -Recurse -ErrorAction SilentlyContinue |
  Where-Object {
    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    $p.UpperFilters -contains "SynTP" -and $p.Service -eq "mouhid"
  } |
  ForEach-Object { $_.Name }
```

У найденного ключа удалить значение `UpperFilters` той же командой `Remove-ItemProperty`.

### 3. Перезапустить тачпад

```powershell
Disable-PnpDevice -InstanceId "HID\SYNA328B&COL01\5&29F54C&0&0000" -Confirm:$false
Enable-PnpDevice -InstanceId "HID\SYNA328B&COL01\5&29F54C&0&0000" -Confirm:$false
pnputil /enum-devices /instanceid "HID\SYNA328B&COL01\5&29F54C&0&0000" /stack
```

В стеке не должно быть строки `SynTP`. Должно быть так:

```text
mouclass
mouhid
mshidkmdf
```

### 4. Перезагрузить компьютер

Клавиатура подхватывает новый список фильтров только после перезагрузки. Пока висит незавершённая смена драйвера, `pnputil /restart-device` для клавиатуры отвечает отказом и просит перезагрузку. Это нормально: после перезагрузки устройство `ACPI\HPQ8001` создаётся заново уже без `SynTP`.

Проверка после входа в систему:

```powershell
pnputil /enum-devices /instanceid "ACPI\HPQ8001\5&34135D84&0" /stack
```

Ожидаемый стек:

```text
kbdclass
i8042prt
ACPI
```

Затем проверить клавиши и тачпад руками.

## Если фильтр вернулся

Обновление или переустановка Synaptics снова прописывает `SynTP` в `UpperFilters`. Повторить шаги из раздела «Без командной строки» или из раздела «Через PowerShell».

На этом компьютере фильтр и режим планшета после загрузки и после сна возвращает скрипт `C:\ProgramData\ForceLaptopMode\force-laptop.ps1`. Журнал: `C:\ProgramData\ForceLaptopMode\force-laptop.log`.

Задачи Планировщика, все три запускают этот скрипт:

- `ForceLaptopMode` — через 20 секунд после старта системы
- `ForceLaptopModeLogon` — через 5 секунд после входа
- `ForceLaptopModeWake` — через 8 секунд после выхода из сна

Скрипт не перезапускает клавиатуру и тачпад. Перезапуск клавиатуры командой `pnputil /restart-device` оставлял её выключенной до следующей перезагрузки компьютера. Так она и замолчала 19 октября 2026 в 22:18.

Дополнительно, чтобы сон не гасил ввод:

- у клавиатуры, тачпада и контроллеров I2C запрещено отключение ради экономии питания (`PnPCapabilities` = 24);
- переход из сна в гибернацию выключен и от сети, и от батареи. Обычный сон остаётся.

## Чего не делать

- Не отключать USB-мышь и не менять её параметры питания. К этой поломке она не относится.
- Не возвращать фильтр Cypress `cykbfltr` на клавиатуру. С ним ввод после сна тоже пропадал.
- Не ставить драйвер Synaptics поверх уже рабочего стека без проверки `UpperFilters`.
