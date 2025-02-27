<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Данные из OpenVPN лога</title>
    <style>
        /* Стили для страницы */
        body {
            font-family: Arial, sans-serif;
            background-color: #f9f9f9;
            margin: 0;
            padding: 20px;
        }
        h1 {
            color: #333;
        }
        h2 {
            color: #555;
            margin-top: 30px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
            background-color: #fff;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }
        th, td {
            padding: 12px;
            border: 1px solid #ddd;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
            font-weight: bold;
            color: #333;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        tr:hover {
            background-color: #f1f1f1;
        }
        .error {
            color: red;
            font-weight: bold;
        }
        .user-select, .date-range {
            margin-bottom: 20px;
        }
        .user-select label, .date-range label {
            font-weight: bold;
            margin-right: 10px;
        }
        .user-select select, .date-range input {
            padding: 5px;
            font-size: 16px;
        }
    </style>
</head>
<body>
    <h1>Данные из OpenVPN лога</h1>
    <?php
    // Функция для чтения файла и группировки данных по третьей колонке (пользователю)
    function groupByThirdColumn($filename) {
        $data = []; // Массив для хранения сгруппированных данных
        if (file_exists($filename)) {
            // Читаем все строки из файла
            $lines = file($filename, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                // Разделяем строку на колонки по пробелам
                $columns = preg_split('/\s+/', $line, 8); // Увеличиваем лимит до 8 колонок
                if (count($columns) >= 6) { // Проверяем, что колонок достаточно
                    $key = $columns[2]; // Третья колонка (пользователь) используется как ключ для группировки
                    $data[$key][] = $line; // Группируем строки по значению третьей колонки
                }
            }
        } else {
            // Если файл не найден, выводим сообщение об ошибке
            echo "<p class='error'>Ошибка: Файл не найден по пути $filename.</p>";
        }
        return $data; // Возвращаем сгруппированные данные
    }

    // Путь к файлу лога OpenVPN
    $logFile = '/var/log/openvpn/client-connect.log';

    // Читаем файл и группируем данные
    $groupedData = groupByThirdColumn($logFile);

    // Обрабатываем выбор диапазона дат
    $startDate = $_GET['start_date'] ?? null;
    $endDate = $_GET['end_date'] ?? null;

    // Фильтруем данные по диапазону дат, если они указаны
    if ($startDate && $endDate) {
        foreach ($groupedData as $user => $lines) {
            $filteredLines = [];
            foreach ($lines as $line) {
                $columns = preg_split('/\s+/', $line, 8);
                $logDate = $columns[0]; // Первая колонка — дата
                if ($logDate >= $startDate && $logDate <= $endDate) {
                    $filteredLines[] = $line; // Сохраняем строку, если она попадает в диапазон
                }
            }
            $groupedData[$user] = $filteredLines; // Обновляем данные для пользователя
        }
    }

    // Сортируем пользователей по возрастанию
    if (!empty($groupedData)) {
        ksort($groupedData);

        // Получаем список пользователей
        $users = array_keys($groupedData);

        // Обрабатываем выбор пользователя из выпадающего списка
        $selectedUser = $_GET['user'] ?? null;

        // Выводим форму для выбора диапазона дат
        echo "<div class='date-range'>";
        echo "<form method='GET' action=''>";
        echo "<label for='start_date'>Начальная дата:</label>";
        echo "<input type='date' id='start_date' name='start_date' value='$startDate'>";
        echo "<label for='end_date'>Конечная дата:</label>";
        echo "<input type='date' id='end_date' name='end_date' value='$endDate'>";
        echo "<button type='submit'>Применить</button>";
        echo "</form>";
        echo "</div>";

        // Выводим выпадающий список для выбора пользователя
        echo "<div class='user-select'>";
        echo "<label for='user'>Выберите пользователя:</label>";
        echo "<select id='user' name='user' onchange='location = this.value;'>";
        echo "<option value=''>-- Выберите пользователя --</option>";
        echo "<option value='?user=all&start_date=$startDate&end_date=$endDate'" . ($selectedUser === 'all' ? ' selected' : '') . ">-- Все пользователи --</option>";
        echo "<option value='?user=online&start_date=$startDate&end_date=$endDate'" . ($selectedUser === 'online' ? ' selected' : '') . ">-- Онлайн пользователи --</option>";
        foreach ($users as $user) {
            $selected = ($user === $selectedUser) ? 'selected' : '';
            echo "<option value='?user=$user&start_date=$startDate&end_date=$endDate' $selected>$user</option>";
        }
        echo "</select>";
        echo "</div>";

        // Выводим данные в зависимости от выбора
        if ($selectedUser) {
            if ($selectedUser === 'all') {
                // Показываем данные для всех пользователей
                foreach ($groupedData as $user => $lines) {
                    if (!empty($lines)) { // Пропускаем пустые данные
                        echo "<h2>Пользователь: $user</h2>";
                        echo "<table>";
                        echo "<tr><th>Дата</th><th>Время</th><th>Пользователь</th><th>IP Источник</th><th>Направление</th><th>IP Назначение</th><th>Статус</th><th>Дополнительно</th></tr>";
                        foreach ($lines as $line) {
                            // Разделяем строку на колонки для отображения
                            $columns = preg_split('/\s+/', $line, 8);
                            echo "<tr>";
                            foreach ($columns as $column) {
                                echo "<td>$column</td>";
                            }
                            echo "</tr>";
                        }
                        echo "</table>";
                    }
                }
            } elseif ($selectedUser === 'online') {
                // Фильтруем пользователей, у которых последняя строка имеет статус UP (онлайн)
                $onlineUsers = [];
                foreach ($groupedData as $user => $lines) {
                    if (!empty($lines)) {
                        $lastLine = end($lines); // Получаем последнюю строку для пользователя
                        $columns = preg_split('/\s+/', $lastLine, 8); // Разделяем строку на колонки
                        if (isset($columns[6]) && trim($columns[6]) === 'UP') { // Проверяем статус
                            $onlineUsers[$user] = $lastLine; // Добавляем пользователя в список онлайн
                        }
                    }
                }

                // Выводим таблицу с онлайн пользователями
                if (!empty($onlineUsers)) {
                    echo "<h2>Пользователи онлайн</h2>";
                    echo "<table>";
                    echo "<tr><th>Пользователь</th><th>Последнее подключение</th><th>IP Источник</th><th>Направление</th><th>IP Назначение</th><th>Статус</th></tr>";
                    foreach ($onlineUsers as $user => $line) {
                        $columns = preg_split('/\s+/', $line, 8); // Разделяем строку на колонки
                        echo "<tr>";
                        echo "<td>$user</td>";
                        echo "<td>{$columns[0]} {$columns[1]}</td>"; // Дата и время
                        echo "<td>{$columns[3]}</td>"; // IP Источник
                        echo "<td>{$columns[4]}</td>"; // Направление
                        echo "<td>{$columns[5]}</td>"; // IP Назначение
                        echo "<td>{$columns[6]}</td>"; // Статус
                        echo "</tr>";
                    }
                    echo "</table>";
                } else {
                    echo "<p>Нет пользователей онлайн.</p>";
                }
            } elseif (isset($groupedData[$selectedUser])) {
                // Показываем данные для выбранного пользователя
                if (!empty($groupedData[$selectedUser])) {
                    echo "<h2>Пользователь: $selectedUser</h2>";
                    echo "<table>";
                    echo "<tr><th>Дата</th><th>Время</th><th>Пользователь</th><th>IP Источник</th><th>Направление</th><th>IP Назначение</th><th>Статус</th><th>Дополнительно</th></tr>";
                    foreach ($groupedData[$selectedUser] as $line) {
                        // Разделяем строку на колонки для отображения
                        $columns = preg_split('/\s+/', $line, 8);
                        echo "<tr>";
                        foreach ($columns as $column) {
                            echo "<td>$column</td>";
                        }
                        echo "</tr>";
                    }
                    echo "</table>";
                } else {
                    echo "<p>Данные для выбранного пользователя не найдены.</p>";
                }
            }
        }
    } else {
        // Если данные не найдены или файл не удалось прочитать
        echo "<p>Данные не найдены или файл не удалось прочитать.</p>";
    }
    ?>
</body>
</html>
